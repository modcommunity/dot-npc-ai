class_name DotNpcAiAvoidance
extends Node

## Local avoidance for NPC crowds: a safe velocity from the one an NPC wants.
##
## Opt-in. Place one, set [member config] (enabled), register it with [method register_service]; a brain finds it
## and passes its steering through [method steer]. Two backends behind one call: the navigation server's RVO
## where [method rvo_supported] says it exists, and an own velocity-obstacle pass (a grid, the nearest few
## neighbours, a sidestep per predicted collision) where it does not. Walls are the physics world's job.
## NPCs in a calm scheduler tier skip it, so far crowds cost nothing.

const CHANNEL := "npc.ai.avoid"

## The name the node registers under, and brains look up.
const SERVICE := &"npc_ai_avoidance"

const _TABLE := 4096

## Drive [method advance] from this node's physics frame. Turn off to call it yourself.
@export var auto_advance: bool = true

## Every number, from [DotNpcAiAvoidanceConfig].
var config: DotNpcAiAvoidanceConfig = DotNpcAiAvoidanceConfig.new()

## Replaces the capability probe in tests; returns whether the RVO backend may be used.
var rvo_probe: Callable = Callable()

## Ticks advanced so far.
var tick: int = 0

## Counters since the start, for [method describe].
var n_steered: int = 0
var n_skipped: int = 0
var n_reused: int = 0
var n_scanned: int = 0
var n_avoided: int = 0
var n_pushed: int = 0

## Microseconds spent in the last [method advance] plus every [method steer] since it, and the worst such frame.
var used_us: int = 0
var peak_us: int = 0

var _backend: StringName = &""
var _agents: Array[Agent] = []
var _by_key: Dictionary = {}
var _heads := PackedInt32Array()
var _next := PackedInt32Array()
var _px := PackedFloat32Array()
var _pz := PackedFloat32Array()
var _vx := PackedFloat32Array()
var _vz := PackedFloat32Array()
var _rr := PackedFloat32Array()
var _kd := PackedFloat32Array()
var _ki := PackedInt32Array()
var _kn: int = 0
var _map: RID = RID()
var _own_map: bool = false
static var _rvo_cache: int = -1


class Agent extends RefCounted:
	var key: Variant = null
	var source: Object = null
	var pos := Vector3.ZERO
	var prev := Vector3.ZERO
	var vel := Vector3.ZERO
	var radius: float = 0.45
	var seen: int = 0
	var out_tick: int = -1000
	var out := Vector3.ZERO
	var rid: RID = RID()
	var safe := Vector3.ZERO
	var has_safe: bool = false
	var speed: float = -1.0
	var index: int = 0

	func on_safe(v: Vector3) -> void:
		safe = v
		has_safe = true


func _init() -> void:
	process_physics_priority = -90
	_heads.resize(_TABLE)
	_heads.fill(-1)
	_kd.resize(32)
	_ki.resize(32)


func _ready() -> void:
	DotLog.info(CHANNEL, "npc ai avoidance placed", {"enabled": config.enabled, "backend": String(backend())})


func _physics_process(delta: float) -> void:
	if auto_advance:
		advance(delta)


func _exit_tree() -> void:
	_release_all()


## The avoidance node registered under [constant SERVICE], or null.
static func find() -> Object:
	return DotRegistry.get_service(SERVICE)


## Whether the navigation server can run RVO agents here (asked of the server, never of the platform name).
static func rvo_supported() -> bool:
	if _rvo_cache < 0:
		_rvo_cache = 0
		if ClassDB.class_exists(&"NavigationServer3D"):
			var m := NavigationServer3D.map_create()
			var a := NavigationServer3D.agent_create()
			if m.is_valid() and a.is_valid():
				_rvo_cache = 1
			if a.is_valid():
				NavigationServer3D.free_rid(a)
			if m.is_valid():
				NavigationServer3D.free_rid(m)
	return _rvo_cache == 1


## Registers this node so brains can find it.
func register_service() -> void:
	DotRegistry.register(SERVICE, self)


## Sets the config and picks the backend again.
func apply_config(p_config: DotNpcAiAvoidanceConfig) -> void:
	_release_all()
	config = p_config
	_backend = &""


## The backend in use, [code]&"rvo"[/code] or [code]&"separation"[/code].
func backend() -> StringName:
	if _backend == &"":
		var rvo_ok: bool = bool(rvo_probe.call()) if rvo_probe.is_valid() else rvo_supported()
		var wants_rvo := config.backend == "auto" or config.backend == "rvo"
		_backend = &"rvo" if wants_rvo and rvo_ok else &"separation"
		DotLog.debug(CHANNEL, "backend chosen", {"asked": config.backend, "using": String(_backend)})
	return _backend


## How many agents are known.
func agent_count() -> int:
	return _agents.size()


## Per-tick upkeep: refreshes positions and velocities, forgets agents not steered lately, rebuilds the grid.
func advance(delta: float) -> void:
	if not config.enabled:
		return
	var t0 := Time.get_ticks_usec()
	tick += 1
	var rvo := backend() == &"rvo"
	if rvo and not _map.is_valid():
		_make_map()
	var i := 0
	var inv := 1.0 / maxf(delta, 0.0001)
	while i < _agents.size():
		var a := _agents[i]
		if tick - a.seen > config.forget_ticks or not is_instance_valid(a.source):
			_remove_at(i)
			continue
		var p: Vector3 = a.source.call(&"position")
		a.prev = a.pos
		a.pos = p
		a.vel = (p - a.prev) * inv
		_px[i] = p.x
		_pz[i] = p.z
		_vx[i] = a.vel.x
		_vz[i] = a.vel.z
		if rvo:
			NavigationServer3D.agent_set_position(a.rid, p)
		i += 1
	if not rvo:
		_rebuild_grid()
	used_us = Time.get_ticks_usec() - t0


## The velocity [param key]'s NPC should use instead of [param want]; [param source] has [code]position()[/code], [param tier] is its scheduler tier.
func steer(key: Variant, source: Object, want: Vector3, tier: int = 0, radius: float = -1.0) -> Vector3:
	if not config.enabled:
		return want
	var t0 := Time.get_ticks_usec()
	var a: Agent = _by_key.get(key)
	if a == null:
		a = _add(key, source, radius if radius > 0.0 else config.radius)
	a.seen = tick
	var result := want
	if tier > config.max_tier:
		n_skipped += 1
	elif tier > 0 and tick - a.out_tick < config.calm_interval and a.out.dot(want) > 0.0:
		n_reused += 1
		result = a.out
	else:
		n_steered += 1
		result = _steer_rvo(a, want) if backend() == &"rvo" else _steer_own(a, want)
		a.out = result
		a.out_tick = tick
	used_us += Time.get_ticks_usec() - t0
	peak_us = maxi(peak_us, used_us)
	return result


## State for logs and the console.
func describe() -> Dictionary:
	return {
		"enabled": config.enabled, "backend": String(backend()), "agents": _agents.size(), "tick": tick,
		"used_us": used_us, "peak_us": peak_us, "stats": {
			"steered": n_steered, "skipped": n_skipped, "reused": n_reused,
			"scanned": n_scanned, "avoided": n_avoided, "pushed": n_pushed,
		},
	}


## [method describe] as lines.
func describe_lines() -> PackedStringArray:
	var d := describe()
	var s: Dictionary = d["stats"]
	return PackedStringArray([
		"npc ai avoidance: %s, backend %s, %d agents, tick %d" % [
			"on" if d["enabled"] else "off", d["backend"], d["agents"], d["tick"]],
		"frame %d us, peak %d" % [d["used_us"], d["peak_us"]],
		"steered %d, reused %d, skipped %d (calm tier), avoided %d, pushed apart %d, scanned %d" % [
			s["steered"], s["reused"], s["skipped"], s["avoided"], s["pushed"], s["scanned"]],
	])


func _add(key: Variant, source: Object, radius: float) -> Agent:
	var a := Agent.new()
	a.key = key
	a.source = source
	a.radius = radius
	a.pos = source.call(&"position")
	a.prev = a.pos
	a.seen = tick
	a.index = _agents.size()
	_agents.append(a)
	_by_key[key] = a
	if _next.size() < _agents.size():
		var cap := _agents.size() * 2
		_next.resize(cap)
		_px.resize(cap)
		_pz.resize(cap)
		_vx.resize(cap)
		_vz.resize(cap)
		_rr.resize(cap)
	_px[a.index] = a.pos.x
	_pz[a.index] = a.pos.z
	_vx[a.index] = 0.0
	_vz[a.index] = 0.0
	_rr[a.index] = radius
	if backend() == &"rvo":
		_make_agent(a)
	return a


func _remove_at(i: int) -> void:
	var a := _agents[i]
	_by_key.erase(a.key)
	if a.rid.is_valid():
		NavigationServer3D.free_rid(a.rid)
	var last := _agents.size() - 1
	_agents[i] = _agents[last]
	_agents[i].index = i
	_px[i] = _px[last]
	_pz[i] = _pz[last]
	_vx[i] = _vx[last]
	_vz[i] = _vz[last]
	_rr[i] = _rr[last]
	_agents.resize(last)


func _release_all() -> void:
	for a in _agents:
		if a.rid.is_valid():
			NavigationServer3D.free_rid(a.rid)
	_agents.clear()
	_by_key.clear()
	if _own_map and _map.is_valid():
		NavigationServer3D.free_rid(_map)
	_map = RID()
	_own_map = false


func _make_map() -> void:
	if is_inside_tree() and get_viewport() != null and get_viewport().world_3d != null:
		_map = get_viewport().world_3d.navigation_map
		return
	_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(_map, true)
	_own_map = true


func _make_agent(a: Agent) -> void:
	if not _map.is_valid():
		_make_map()
	a.rid = NavigationServer3D.agent_create()
	NavigationServer3D.agent_set_map(a.rid, _map)
	NavigationServer3D.agent_set_radius(a.rid, a.radius)
	NavigationServer3D.agent_set_neighbor_distance(a.rid, config.neighbour_range)
	NavigationServer3D.agent_set_max_neighbors(a.rid, config.max_neighbours)
	NavigationServer3D.agent_set_time_horizon_agents(a.rid, config.horizon)
	NavigationServer3D.agent_set_use_3d_avoidance(a.rid, false)
	NavigationServer3D.agent_set_avoidance_enabled(a.rid, true)
	NavigationServer3D.agent_set_position(a.rid, a.pos)
	NavigationServer3D.agent_set_avoidance_callback(a.rid, a.on_safe)


func _steer_rvo(a: Agent, want: Vector3) -> Vector3:
	if not a.rid.is_valid():
		_make_agent(a)
	var s := Vector2(want.x, want.z).length()
	if absf(s - a.speed) > 0.05:
		a.speed = s
		NavigationServer3D.agent_set_max_speed(a.rid, maxf(s, 0.01))
	NavigationServer3D.agent_set_velocity(a.rid, want)
	if not a.has_safe:
		return want
	n_avoided += 1
	return Vector3(a.safe.x, want.y, a.safe.z)


func _cell(cx: int, cz: int) -> int:
	return ((cx * 73856093) ^ (cz * 19349663)) & (_TABLE - 1)


func _rebuild_grid() -> void:
	_heads.fill(-1)
	var inv := 1.0 / config.cell_size
	for i in _agents.size():
		var c := _cell(floori(_px[i] * inv), floori(_pz[i] * inv))
		_next[i] = _heads[c]
		_heads[c] = i


func _steer_own(a: Agent, want: Vector3) -> Vector3:
	var s := sqrt(want.x * want.x + want.z * want.z)
	if s < 0.01:
		return want
	var dx := want.x / s
	var dz := want.z / s
	_collect(a)
	var px := 0.0
	var pz := 0.0
	var cap := config.horizon
	var touching := false
	for n in _kn:
		var j := _ki[n]
		var rx := _px[j] - a.pos.x
		var rz := _pz[j] - a.pos.z
		var big_r := a.radius + _rr[j]
		var d2 := rx * rx + rz * rz
		if d2 < big_r * big_r:
			var d := sqrt(d2)
			var nx := -rx / d if d > 0.01 else dz
			var nz := -rz / d if d > 0.01 else -dx
			var k := (big_r - d) / big_r * 3.0
			px += nx * k
			pz += nz * k
			n_pushed += 1
			touching = true
			continue
		var ux := want.x - _vx[j]
		var uz := want.z - _vz[j]
		var uu := ux * ux + uz * uz
		if uu < 0.000001:
			continue
		var b := rx * ux + rz * uz
		if b <= 0.0:
			continue
		var disc := b * b - uu * (d2 - big_r * big_r)
		if disc < 0.0:
			continue
		var t := (b - sqrt(disc)) / uu
		if t > cap:
			continue
		var urgency := 1.0 - t / cap
		var d_len := sqrt(d2)
		var cross := rx * uz - rz * ux
		var lx := 0.0
		var lz := 0.0
		if absf(cross) > 0.05 * d_len * sqrt(uu):
			var sign_ := 1.0 if cross > 0.0 else -1.0
			lx = -rz / d_len * sign_
			lz = rx / d_len * sign_
		else:
			lx = dz
			lz = -dx
		px += lx * urgency
		pz += lz * urgency
		n_avoided += 1
	var plen := sqrt(px * px + pz * pz)
	if plen < 0.0001:
		return want
	if plen > 2.0:
		px *= 2.0 / plen
		pz *= 2.0 / plen
	var vx := want.x + px * s
	var vz := want.z + pz * s
	var lat_x := vx - (vx * dx + vz * dz) * dx
	var lat_z := vz - (vx * dx + vz * dz) * dz
	var lat := sqrt(lat_x * lat_x + lat_z * lat_z)
	var mf := 0.0 if touching else config.min_forward
	var lat_max := s * sqrt(1.0 - mf * mf)
	if lat > lat_max:
		lat_x *= lat_max / lat
		lat_z *= lat_max / lat
		lat = lat_max
	var fwd := sqrt(maxf(s * s - lat * lat, 0.0))
	return Vector3(fwd * dx + lat_x, want.y, fwd * dz + lat_z)


## Fills the nearest-first neighbour list of [param a] from the grid, scanning at most max_scan candidates.
func _collect(a: Agent) -> void:
	_kn = 0
	var k := mini(config.max_neighbours, 32)
	var inv := 1.0 / config.cell_size
	var cx := floori(a.pos.x * inv)
	var cz := floori(a.pos.z * inv)
	var span := ceili(config.neighbour_range * inv)
	var range2 := config.neighbour_range * config.neighbour_range
	var scanned := 0
	for gx in range(cx - span, cx + span + 1):
		for gz in range(cz - span, cz + span + 1):
			var j := _heads[_cell(gx, gz)]
			while j >= 0:
				if j != a.index:
					scanned += 1
					var ex := _px[j] - a.pos.x
					var ez := _pz[j] - a.pos.z
					var d2 := ex * ex + ez * ez
					if d2 <= range2:
						_insert(j, d2, k)
					if scanned >= config.max_scan:
						n_scanned += scanned
						return
				j = _next[j]
	n_scanned += scanned


func _insert(j: int, d2: float, k: int) -> void:
	var at := _kn
	if _kn == k:
		if d2 >= _kd[k - 1]:
			return
		at = k - 1
	else:
		_kn += 1
	while at > 0 and _kd[at - 1] > d2:
		_kd[at] = _kd[at - 1]
		_ki[at] = _ki[at - 1]
		at -= 1
	_kd[at] = d2
	_ki[at] = j
