class_name DotNpcAiScheduler
extends Node

## Opt-in level-of-detail time-slicer for NPC brains: a brain asks [method admit] before each think.
## Tier comes from distance to the nearest player, visibility and target; tier 3 sleeps, phases come from the NPC seed.
## [method advance] must run before the brains it gates ([member auto_advance]); disabled, nothing changes.

const CHANNEL := "npc.ai.sched"

## The name the scheduler registers under, and brains look up.
const SERVICE := &"npc_ai_scheduler"

## The number of tiers, 0 (full rate) to this minus one (asleep).
const TIERS := 4

## Drive [method advance] from this node's physics frame. Turn off to call it yourself.
@export var auto_advance: bool = true

## Every number, from [DotNpcAiSchedulerConfig].
var config: DotNpcAiSchedulerConfig = DotNpcAiSchedulerConfig.new()

## Returns the players' positions as an Array of Vector3. Empty means the [member DotNpcAiSchedulerConfig.player_group].
var players_source: Callable = Callable()

## Called with a position, returns whether any player can see it. Unset means everything counts as seen.
var visibility_source: Callable = Callable()

## Returns microseconds. Replaced in tests with a fake clock.
var clock: Callable = Callable()

## Ticks advanced so far.
var tick: int = 0

## Frame totals since the start, for [method describe].
var stats := {
	"thinks": 0, "skipped": 0, "deferred": 0, "overruns": 0,
	"paths_granted": 0, "paths_denied": 0, "los_hits": 0, "los_blocked": 0, "cache_hits": 0,
}

## True when the last [method cached_path] call was refused for want of allowance and had nothing cached.
var path_denied: bool = false

## The most microseconds any one frame's admitted brains spent.
var peak_used_us: int = 0

## Microseconds spent by the brains admitted this frame, and how many they were.
var used_us: int = 0
var admitted: int = 0

var _time: float = 0.0
var _slots: Array[Slot] = []
var _by_id: Dictionary = {}
var _by_npc: Dictionary = {}
var _owed: Array[Slot] = []
var _owed_head: int = 0
var _est_cost_us: float = 100.0
var _paths_used: int = 0
var _serial: int = 0
var _los_cache: Dictionary = {}
var _path_cache: Dictionary = {}
var _players: Array = []
var _player_buf: Array = []
var _group_players: Callable = _positions_from_group
var _players_tick: int = -1
var _active_from: float = 0.0
var _was_enabled: bool = false


class Slot extends RefCounted:
	var brain: Object = null
	var npc: Object = null
	var mix: int = 0
	var tier: int = -1
	var interval: int = 1
	var last_time: float = 0.0
	var started_us: int = -1
	var go_tick: int = -1
	var owed: bool = false
	var live: bool = true
	var has_alive: bool = false
	var alert_until: int = -1
	var index: int = 0
	var thinks: int = 0


func _init() -> void:
	process_physics_priority = -100


func _ready() -> void:
	DotLog.info(CHANNEL, "npc ai scheduler placed", {
		"enabled": config.enabled, "budget_ms": config.budget_ms,
	})


func _physics_process(delta: float) -> void:
	if auto_advance:
		advance(delta)


## The scheduler registered under [constant SERVICE], or null.
static func find() -> Object:
	return DotRegistry.get_service(SERVICE)


## Registers this scheduler so brains can find it.
func register_service() -> void:
	DotRegistry.register(SERVICE, self)


## Sets the config, taking the cost estimate from it.
func apply_config(p_config: DotNpcAiSchedulerConfig) -> void:
	config = p_config
	_est_cost_us = config.initial_cost_us


## Starts gating [param brain]; its [code]npc[/code] gives position, seed and target.
func register(brain: Object) -> void:
	var id := brain.get_instance_id()
	if _by_id.has(id):
		return

	var slot := Slot.new()
	slot.brain = brain
	slot.npc = brain.get(&"npc")
	slot.has_alive = slot.npc != null and slot.npc.has_method(&"is_alive")
	_serial += 1
	var seed_value := 0
	if slot.npc != null:
		seed_value = int(slot.npc.get(&"seed"))
	if seed_value <= 0:
		seed_value = _serial
	var h := seed_value * 0x1E3779B97F4A7C15
	h = (h ^ (h >> 32)) * 0x3F58476D1CE4E5B9
	slot.mix = (h ^ (h >> 29)) & 0x7FFFFFFFFFFF
	slot.last_time = _time
	if _players_tick != tick:
		_players = _read_players()
		_players_tick = tick
	slot.index = _slots.size()
	_slots.append(slot)
	_by_id[id] = slot
	if slot.npc != null:
		_by_npc[slot.npc.get_instance_id()] = slot
	_retier(slot)


## Stops gating [param brain].
func unregister(brain: Object) -> void:
	var id := brain.get_instance_id()
	var slot: Slot = _by_id.get(id)
	if slot == null:
		return
	_by_id.erase(id)
	if slot.npc != null:
		_by_npc.erase(slot.npc.get_instance_id())
	slot.live = false
	if slot.owed:
		slot.owed = false
		var at := _owed.find(slot)
		if at >= 0:
			_owed.remove_at(at)
			if at < _owed_head:
				_owed_head -= 1
	var last := _slots.pop_back() as Slot
	if last != slot:
		_slots[slot.index] = last
		last.index = slot.index


## Call once per frame before any brain thinks: moves the clock, retiers some brains, picks who thinks now.
func advance(delta: float) -> void:
	tick += 1
	_time += delta
	peak_used_us = maxi(peak_used_us, used_us)
	used_us = 0
	admitted = 0
	_paths_used = 0

	if tick % 120 == 0:
		_prune_caches()

	if not config.enabled:
		_was_enabled = false
		for owed in _owed:
			owed.owed = false
		_owed.clear()
		_owed_head = 0
		return

	if not _was_enabled:
		# Time that passed while off is not owed to anyone.
		_was_enabled = true
		_active_from = _time - delta

	_players = _read_players()
	_players_tick = tick
	var allowance := _allowance()
	var retier_every := config.retier_interval

	# Owed brains first: ones deferred earlier must not starve behind ones that happen to come first.
	while _owed_head < _owed.size() and allowance > 0:
		var owed := _owed[_owed_head]
		_owed_head += 1
		if owed.live and owed.owed:
			owed.owed = false
			if _thinks(owed):
				owed.go_tick = tick
				allowance -= 1
	if _owed_head >= _owed.size():
		_owed.clear()
		_owed_head = 0

	for slot in _slots:
		var phase := tick + slot.mix
		if phase % retier_every == 0:
			_retier(slot)
		# A grant stays until the brain asks, so a host ticking slower than this loop starves nobody.
		if slot.owed or slot.go_tick >= 0:
			continue
		if slot.interval == 0 or phase % slot.interval != 0:
			stats["skipped"] += 1
			continue
		if not _thinks(slot):
			continue
		if allowance > 0:
			slot.go_tick = tick
			allowance -= 1
		else:
			slot.owed = true
			_owed.append(slot)
			stats["deferred"] += 1


## The delta [param brain] should think with this tick, or -1.0 to skip it. Pass its own delta; call [method finish] after.
func admit(brain: Object, delta: float) -> float:
	if not config.enabled:
		return delta

	var slot: Slot = _by_id.get(brain.get_instance_id())
	if slot == null:
		return delta
	if slot.go_tick < 0:
		return -1.0

	slot.go_tick = -1
	if float(used_us) + _est_cost_us > config.budget_ms * 1000.0 and admitted > 0:
		slot.owed = true
		_owed.append(slot)
		stats["deferred"] += 1
		return -1.0

	var dt := minf(_time - maxf(slot.last_time, _active_from), config.max_catchup_s)
	slot.last_time = _time
	slot.started_us = _now_us()
	admitted += 1
	return dt if dt > 0.0 else delta


## Ends a think that [method admit] allowed, charging its time to the frame.
func finish(brain: Object) -> void:
	if not config.enabled:
		return

	var slot: Slot = _by_id.get(brain.get_instance_id())
	if slot == null or slot.started_us < 0:
		return

	var cost := _now_us() - slot.started_us
	slot.started_us = -1
	used_us += cost
	stats["thinks"] += 1
	slot.thinks += 1
	_est_cost_us = lerpf(_est_cost_us, float(cost), 0.1)
	if float(used_us) > config.budget_ms * 1000.0:
		stats["overruns"] += 1


## Retiers [param brain] now and lets it think this tick: it was hurt or found a target and must not wait for a sweep.
func wake(brain: Object) -> void:
	if not config.enabled:
		return
	var slot: Slot = _by_id.get(brain.get_instance_id())
	if slot == null:
		return
	if _players_tick != tick:
		_players = _read_players()
		_players_tick = tick
	slot.alert_until = tick + config.alert_ticks
	_retier(slot)
	if slot.interval != 0 and not slot.owed and slot.go_tick < 0:
		slot.go_tick = tick


## Wakes the brain of [param npc] when [param target] is not empty. Connect a spawner's `target_changed` to this.
func notice_target(npc: Object, target: StringName) -> void:
	var slot: Slot = _by_npc.get(npc.get_instance_id()) if npc != null else null
	if slot != null and target != &"":
		wake(slot.brain)


## The tier [param brain] is in, 0 to [constant TIERS] - 1; 0 when it is not registered.
func tier_of(brain: Object) -> int:
	var slot: Slot = _by_id.get(brain.get_instance_id())
	return slot.tier if slot != null else 0


## How many times [param brain] has been allowed to think since it registered.
func thinks_of(brain: Object) -> int:
	var slot: Slot = _by_id.get(brain.get_instance_id())
	return slot.thinks if slot != null else 0


## How many registered brains are in each tier.
func tier_counts() -> PackedInt32Array:
	var out := PackedInt32Array([0, 0, 0, 0])
	for slot in _slots:
		out[slot.tier] += 1
	return out


## Whether [param brain] may test line of sight at all this tick.
func los_allowed(brain: Object) -> bool:
	if not config.enabled:
		return true
	return tier_of(brain) <= config.los_max_tier


## A line-of-sight answer for [param key], reused for a few ticks; [param compute] takes no arguments, returns bool.
func cached_los(brain: Object, key: Variant, compute: Callable) -> bool:
	if not config.enabled:
		return compute.call()

	if not los_allowed(brain):
		stats["los_blocked"] += 1
		return false

	var hit: Array = _los_cache.get(key, [])
	if not hit.is_empty() and hit[0] > tick:
		stats["cache_hits"] += 1
		return hit[1]

	var value: bool = compute.call()
	_los_cache[key] = [tick + config.los_cache_ticks, value]
	stats["los_hits"] += 1
	return value


## A path for [param key], reused for a few ticks; null when this frame's path requests are used up and none is cached.
func cached_path(key: Variant, compute: Callable) -> Variant:
	if not config.enabled:
		return compute.call()

	var hit: Array = _path_cache.get(key, [])
	path_denied = false
	if not hit.is_empty() and hit[0] > tick:
		stats["cache_hits"] += 1
		return hit[1]
	if _paths_used >= config.max_paths_per_frame:
		stats["paths_denied"] += 1
		path_denied = hit.is_empty()
		return hit[1] if not hit.is_empty() else null

	_paths_used += 1
	stats["paths_granted"] += 1
	var value: Variant = compute.call()
	_path_cache[key] = [tick + config.path_cache_ticks, value]
	return value


## Spends one of this frame's path computations; false when they are used up. For a caller that keeps its own cache.
func take_path_slot() -> bool:
	if not config.enabled:
		return true
	if _paths_used >= config.max_paths_per_frame:
		stats["paths_denied"] += 1
		return false
	_paths_used += 1
	stats["paths_granted"] += 1
	return true


## State for logs and the console.
func describe() -> Dictionary:
	return {
		"enabled": config.enabled, "brains": _slots.size(), "tick": tick,
		"tiers": Array(tier_counts()), "budget_ms": config.budget_ms,
		"used_us": used_us, "peak_used_us": peak_used_us, "est_cost_us": snappedf(_est_cost_us, 0.1),
		"owed": _owed.size() - _owed_head, "stats": stats.duplicate(),
	}


## [method describe] as lines.
func describe_lines() -> PackedStringArray:
	var out := PackedStringArray()
	var d := describe()
	out.append("npc ai scheduler: %s, %d brains, tick %d" % [
		"on" if d["enabled"] else "off", d["brains"], d["tick"]])
	out.append("tiers %s, owed %d" % [str(d["tiers"]), d["owed"]])
	out.append("frame %d us of %d, peak %d, one think about %s us" % [
		d["used_us"], int(config.budget_ms * 1000.0), d["peak_used_us"], d["est_cost_us"]])
	out.append("thinks %d, skipped %d, deferred %d, overruns %d" % [
		stats["thinks"], stats["skipped"], stats["deferred"], stats["overruns"]])
	out.append("paths %d granted / %d denied, los %d tested / %d blocked, cache hits %d" % [
		stats["paths_granted"], stats["paths_denied"], stats["los_hits"], stats["los_blocked"], stats["cache_hits"]])
	return out


func _allowance() -> int:
	return maxi(1, int(config.budget_ms * 1000.0 / maxf(_est_cost_us, 1.0)))


func _thinks(slot: Slot) -> bool:
	if not is_instance_valid(slot.brain):
		return false
	if slot.has_alive and (not is_instance_valid(slot.npc) or not slot.npc.call(&"is_alive")):
		return false
	return true


func _now_us() -> int:
	if clock.is_valid():
		return int(clock.call())
	return Time.get_ticks_usec()


func _read_players() -> Array:
	if players_source.is_valid():
		return players_source.call()
	return _group_players.call()


## Player positions from the group; a Callable so the once-per-tick scan is not a per-frame call.
func _positions_from_group() -> Array:
	_player_buf.clear()
	if is_inside_tree():
		for node in get_tree().get_nodes_in_group(config.player_group):
			if node is Node3D:
				_player_buf.append((node as Node3D).global_position)
	return _player_buf


func _retier(slot: Slot) -> void:
	var tier := config.idle_tier
	var at := Vector3.ZERO

	if slot.npc != null:
		at = slot.npc.call(&"position")

	if not _players.is_empty():
		var nearest := INF
		for p in _players:
			nearest = minf(nearest, at.distance_to(p))
		tier = _tier_for(nearest, slot.tier)

		if config.unseen_penalty > 0 and visibility_source.is_valid() and not visibility_source.call(at):
			tier = mini(tier + config.unseen_penalty, TIERS - 1)

	if tick < slot.alert_until or (slot.npc != null and slot.npc.call(&"has_target")):
		tier = mini(tier, config.engaged_max_tier)

	slot.tier = tier
	match tier:
		0: slot.interval = 1
		1: slot.interval = config.tier1_interval
		2: slot.interval = config.tier2_interval
		_: slot.interval = config.tier3_interval


func _tier_for(distance: float, current: int) -> int:
	var raw := TIERS - 1
	if distance < config.full_range:
		raw = 0
	elif distance < config.mid_range:
		raw = 1
	elif distance < config.far_range:
		raw = 2
	# Calmer only once clear of the edge by the margin.
	if current >= 0 and raw > current and current < TIERS - 1 and distance < _edge(current) + config.hysteresis:
		return current
	return raw


func _edge(i: int) -> float:
	match i:
		0: return config.full_range
		1: return config.mid_range
		_: return config.far_range


func _prune_caches() -> void:
	for cache in [_los_cache, _path_cache]:
		for key in cache.keys():
			if cache[key][0] + 120 < tick:
				cache.erase(key)
