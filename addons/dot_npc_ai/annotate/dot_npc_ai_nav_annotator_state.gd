extends DotJob

## The settings, state and measuring queries of [DotNpcAiNavAnnotator], split out so the annotator file
## holds the phases only. Not a public class: extend [DotNpcAiNavAnnotator], never this.

const CHANNEL := "npc.ai.annotate"

const CVAR_JUMP_UP := "npc_nav_jump_up"
const CVAR_DROP := "npc_nav_drop"
const CVAR_GAP := "npc_nav_gap"
const CVAR_SPOT_SPACING := "npc_nav_spot_spacing"

## The cvars [method bind_cvars] registers, and the field each sets.
const CVARS := [
	{"name": CVAR_JUMP_UP, "field": "jump_up", "value": 1.0, "min": 0.0, "max": 4.0,
		"description": "Highest ledge (metres) the map's bots and NPCs are linked to jump up onto."},
	{"name": CVAR_DROP, "field": "drop_max", "value": 6.0, "min": 0.0, "max": 30.0,
		"description": "Deepest drop (metres) linked as a way down; deeper is a fall nobody takes on purpose."},
	{"name": CVAR_GAP, "field": "gap_max", "value": 3.0, "min": 0.0, "max": 12.0,
		"description": "Widest gap (metres) linked as a running jump across."},
	{"name": CVAR_SPOT_SPACING, "field": "spot_spacing", "value": 2.5, "min": 0.5, "max": 20.0,
		"description": "Least distance (metres) between two of a map's chosen hiding spots."},
]

## The body the mesh was baked for, metres.
var agent_radius: float = 0.35
var stand_height: float = 1.8
var crouch_height: float = 0.9
var eye_height: float = 1.6
## The highest step the bake climbed; a drop no deeper than this is a step, not a link.
var climb: float = 0.4

## Highest ledge linked as a jump up ([constant CVAR_JUMP_UP]).
var jump_up: float = 1.0
## Deepest drop linked ([constant CVAR_DROP]).
var drop_max: float = 6.0
## Widest gap linked as a jump ([constant CVAR_GAP]).
var gap_max: float = 3.0
## Metres between samples of the mesh's outline.
var sample_spacing: float = 1.0
## Least distance between two links of one kind at both ends.
var link_spacing: float = 2.0
## Least distance between two chosen hiding spots ([constant CVAR_SPOT_SPACING]).
var spot_spacing: float = 2.5
## Most hiding spots chosen.
var max_hiding: int = 200
## Most wall samples measured as spots; more are thinned evenly, seeded.
var max_candidates: int = 1500
## Places across the walkable floor, at an eye, that a spot's exposure is measured from.
var watchers: int = 96
## A watcher further than this from a spot does not count for or against it.
var reach: float = 30.0
## Random routes walked to find where traffic crowds.
var routes: int = 48
## The widest walkable passage (metres across, on the mesh) that counts as a chokepoint.
var choke_width: float = 3.0
## The least share of the routes that must pass a chokepoint.
var choke_traffic: float = 0.15
## The physics layers that are walls, floors and sight blockers.
var collision_mask: int = 0xFFFFFFFF
## Bodies the rays ignore.
var exclude: Array[RID] = []
## Seed of the watcher and route draws.
var random_seed: int = 1
## Where bodies start (spawns and teleport destinations), on or just above the mesh. Islands
## of the mesh are kept for spots, watchers and routes when a body can get there from one
## through the mesh and the links; otherwise, unless [member reach_only], when a link touches
## them or they are at least [member min_island_area]. When the seeds (or, with none, the
## largest island) are under a roof, islands open to the sky are dropped: on a sealed map
## they are the top of its shell. What a bake leaves inside a solid brush is small and
## linkless, and dropped.
var seeds: PackedVector3Array = PackedVector3Array()
## Keep only what [member seeds] reach. Off by default, because a map crossed by surfing or
## a lift is joined by ride links a game declares, and without them most of it is unreached.
var reach_only: bool = false
## Square metres an island no link touches needs to be kept.
var min_island_area: float = 6.0
## Items per [method _step].
var slice: int = 24
## Milliseconds one [method _step] may run before it hands the frame back, whatever [member slice]
## says: the items of a dense map cost ten times those of a sparse one (a 24-sample slice was
## 40 ms on a large surf map), so a count alone is no budget. A step finishes the item it is on,
## so it can overrun by one item. Zero turns it off. It changes only where a step ends, never
## the result, so it is not part of the cache key.
var slice_ms: float = 4.0

## `(from: Vector3, to: Vector3) -> bool`, true when nothing blocks the sight line. Unset,
## a ray against [member collision_mask].
var los_fn: Callable = Callable()

## What this job is making. Filled as it runs; the job's result once it finishes.
var annotations: DotNpcAiNavAnnotations = DotNpcAiNavAnnotations.new()

enum Phase { POLYGONS, EDGES, BORDER, ISLANDS, WATCHERS, SPOTS, PICK, ROUTES, CHOKEPOINTS, FINISH, DONE }

var _mesh: NavigationMesh = null
var _world: World3D = null
var _phase: int = Phase.POLYGONS
var _cursor: int = 0
var _started_us: int = 0
var _phase_us: Dictionary = {}
var _finish_stage: int = 0
var _key_ctx: HashingContext = null
var _joining: int = 0
var _step_began_us: int = 0
## The longest single [method _step] so far and the phase it ran: what one frame would pay.
var _slowest_ms: float = 0.0
var _slowest_phase: String = ""
var _phase_started_us: int = 0
var _rng: DotRandomStream = null

var _vertices: PackedVector3Array = PackedVector3Array()
var _centres: PackedVector3Array = PackedVector3Array()
## Triangles as [a, b, c, polygon].
var _tris: Array = []
var _tri_area: PackedFloat32Array = PackedFloat32Array()
var _total_area: float = 0.0
## Vector2i XZ cell -> triangle indices.
var _tri_grid: Dictionary = {}
const GRID := 2.0
## Edge key -> [polygon, from vertex, to vertex], or the portal once two polygons share it.
var _edges: Dictionary = {}
var _edge_keys: Array = []
var _graph: AStar3D = AStar3D.new()
var _island_parent: PackedInt32Array = PackedInt32Array()
## Outline segments as [a, b], and their XZ grid.
var _border: Array = []
var _border_grid: Dictionary = {}
## Outline samples: [point, outward normal].
var _samples: Array = []
var _wall_samples: Array = []
var _watchers: PackedVector3Array = PackedVector3Array()
## Portal midpoints between adjacent polygons: Vector2i(a, b) with a < b -> Vector3.
var _portals: Dictionary = {}
## Cell -> {"count", "at", "width"}.
var _traffic: Dictionary = {}
var _routes_done: int = 0
var _last_height: float = 0.0
var _declared: Array[Dictionary] = []
## Island roots kept (see [member seeds]); empty until the watchers phase.
var _kept: Dictionary = {}
var _kept_tris: PackedInt32Array = PackedInt32Array()
var _kept_area: PackedFloat32Array = PackedFloat32Array()
var _sky: Dictionary = {}
var _solid: Dictionary = {}
var _island_roots: Array = []
# The island-keeping stages of the islands phase, and what they carry between slices.
enum { KEEP_ASK, KEEP_AREA, KEEP_LINKS, KEEP_REACH, KEEP_DECIDE, KEEP_USABLE, KEEP_TABLE }
var _keep_stage: int = KEEP_ASK
var _island_area: Dictionary = {}
var _keep_all_links: Array[Dictionary] = []
var _keep_touched: Dictionary = {}
var _keep_out: Dictionary = {}
var _keep_reached: Dictionary = {}
var _keep_roots: Array = []
var _keep_roofed: bool = false
var _keep_seeded_empty: bool = true
var _keep_largest: int = -1
var _keep_usable: Array = []
var _keep_total: float = 0.0
var _thin_kept: Array = []
var _thin_cells: Dictionary = {}


## The settings that change the result, as one dictionary (what [method cache_key] digests).
func settings() -> Dictionary:
	return {
		"radius": agent_radius, "stand": stand_height, "crouch": crouch_height, "eye": eye_height, "climb": climb,
		"jump_up": jump_up, "drop_max": drop_max, "gap_max": gap_max, "sample_spacing": sample_spacing,
		"link_spacing": link_spacing, "spot_spacing": spot_spacing, "max_hiding": max_hiding,
		"max_candidates": max_candidates, "watchers": watchers, "reach": reach, "routes": routes,
		"choke_width": choke_width, "choke_traffic": choke_traffic, "mask": collision_mask, "seed": random_seed, "reach_only": reach_only, "min_island_area": min_island_area,
		"declared": _declared.map(func(l: Dictionary) -> String: return "%s>%s:%d" % [l["from"], l["to"], l["kind"]]),
		"seeds": Array(seeds).map(func(v: Vector3) -> String: return "%.2f,%.2f,%.2f" % [v.x, v.y, v.z]),
	}


## The digest the result will carry: the mesh, [method settings] and the annotations'
## VERSION. The same map baked the same way has the same key on every machine. The colliders
## are not in it: the mesh was baked from them, so a changed wall is a changed mesh.
func cache_key() -> String:
	return key_for(_mesh, settings())


static func key_for(mesh: NavigationMesh, with: Dictionary) -> String:
	var ctx := _key_begin(mesh)
	if mesh != null:
		_key_polygons(ctx, mesh, 0, mesh.get_polygon_count())
	return _key_end(ctx, with)


# The key in three parts, so the job can hash a large mesh a slice at a time and get the very
# digest [method key_for] gives.
static func _key_begin(mesh: NavigationMesh) -> HashingContext:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("dot_npc_ai_nav_annotations/%d|" % DotNpcAiNavAnnotations.VERSION).to_utf8_buffer())
	if mesh != null:
		ctx.update(mesh.get_vertices().to_byte_array())
	return ctx


static func _key_polygons(ctx: HashingContext, mesh: NavigationMesh, from: int, to: int) -> void:
	for i in range(from, to):
		ctx.update(mesh.get_polygon(i).to_byte_array())


static func _key_end(ctx: HashingContext, with: Dictionary) -> String:
	var keys := with.keys()
	keys.sort()
	for k: Variant in keys:
		ctx.update(("%s=%s;" % [str(k), str(with[k])]).to_utf8_buffer())
	return ctx.finish().hex_encode()


## Registers [constant CVARS] through [param add] (`(name, value, description, flags) ->
## cvar`, a server's or a console's), returning the cvars made; [method read_cvars] takes
## their values into an annotator before it runs. A static method, so nothing per map is
## bound to the console.
static func bind_cvars(add: Callable, flags: int = 0) -> Array:
	var made: Array = []
	for spec: Dictionary in CVARS:
		var cv: Variant = add.call(String(spec["name"]), str(spec["value"]), String(spec["description"]), flags)
		if not (cv is Object) or cv == null:
			continue
		if (cv as Object).has_method(&"with_range"):
			(cv as Object).call(&"with_range", float(spec["min"]), float(spec["max"]))
		made.append(cv)
	return made


## Sets the fields [constant CVARS] name from [param cvars] (what [method bind_cvars]
## returned), each clamped to its range.
func read_cvars(cvars: Array) -> void:
	for cv: Variant in cvars:
		if not (cv is Object) or not (cv as Object).has_method(&"get_string"):
			continue
		var cv_name := str((cv as Object).get(&"name"))
		for spec: Dictionary in CVARS:
			if String(spec["name"]) == cv_name:
				var text := str((cv as Object).call(&"get_string"))
				if text.is_valid_float():
					set(String(spec["field"]), clampf(text.to_float(), float(spec["min"]), float(spec["max"])))


func _next_phase() -> void:
	var now := Time.get_ticks_usec()
	_phase_us[Phase.keys()[_phase].to_lower()] = snappedf((now - _phase_started_us) / 1000.0, 0.1)
	_phase_started_us = now
	_phase += 1
	_cursor = 0


## Whether this step has used its [member slice_ms].
func _out_of_time() -> bool:
	return slice_ms > 0.0 and (Time.get_ticks_usec() - _step_began_us) / 1000.0 >= slice_ms


func _ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, collision_mask, exclude)
	return _world.direct_space_state.intersect_ray(query)


func _clear(from: Vector3, to: Vector3) -> bool:
	if los_fn.is_valid():
		return bool(los_fn.call(from, to))
	return _ray(from, to).is_empty()


## The polygon whose surface is under or over [param at] within [param reach] metres, nearest
## in height, or -1; its height there is left in [member _last_height].
func _poly_under(at: Vector3, reach_y: float) -> int:
	var bucket: PackedInt32Array = _tri_grid.get(Vector2i(floori(at.x / GRID), floori(at.z / GRID)), PackedInt32Array())
	var best := -1
	var best_dy := INF
	for index in bucket:
		var tri: Array = _tris[index]
		var h := _height_in(at, tri[0], tri[1], tri[2])
		if is_nan(h):
			continue
		var dy := absf(at.y - h)
		if dy <= reach_y and dy < best_dy:
			best_dy = dy
			best = int(tri[3])
			_last_height = h
	return best


## A point on the mesh, weighted by area, from the job's own stream: on a kept island once
## those are known.
func _random_point() -> Vector3:
	var table := _tri_area
	if not _kept_tris.is_empty():
		table = _kept_area
	var pick := _rng.next_range_f(0.0, table[table.size() - 1])
	var lo := 0
	var hi := table.size() - 1
	while lo < hi:
		var mid := (lo + hi) / 2
		if table[mid] < pick:
			lo = mid + 1
		else:
			hi = mid
	var tri: Array = _tris[_kept_tris[lo] if not _kept_tris.is_empty() else lo]
	var u := _rng.next_unit()
	var v := _rng.next_unit()
	if u + v > 1.0:
		u = 1.0 - u
		v = 1.0 - v
	var a: Vector3 = tri[0]
	return a + ((tri[1] as Vector3) - a) * u + ((tri[2] as Vector3) - a) * v


static func _height_in(at: Vector3, a: Vector3, b: Vector3, c: Vector3) -> float:
	var v0 := Vector2(c.x - a.x, c.z - a.z)
	var v1 := Vector2(b.x - a.x, b.z - a.z)
	var v2 := Vector2(at.x - a.x, at.z - a.z)
	var d00 := v0.dot(v0)
	var d01 := v0.dot(v1)
	var d11 := v1.dot(v1)
	var d20 := v2.dot(v0)
	var d21 := v2.dot(v1)
	var denom := d00 * d11 - d01 * d01
	if absf(denom) < 1e-9:
		return NAN
	var u := (d11 * d20 - d01 * d21) / denom
	var v := (d00 * d21 - d01 * d20) / denom
	if u < -0.001 or v < -0.001 or u + v > 1.001:
		return NAN
	return a.y + u * (c.y - a.y) + v * (b.y - a.y)


static func _edge_key(a: Vector3, b: Vector3) -> String:
	# Quantised to a centimetre and ordered, so the two polygons either side agree.
	var ka := Vector3i(roundi(a.x * 100.0), roundi(a.y * 100.0), roundi(a.z * 100.0))
	var kb := Vector3i(roundi(b.x * 100.0), roundi(b.y * 100.0), roundi(b.z * 100.0))
	if kb < ka:
		var t := ka
		ka = kb
		kb = t
	return "%d,%d,%d|%d,%d,%d" % [ka.x, ka.y, ka.z, kb.x, kb.y, kb.z]


func _find(i: int) -> int:
	while _island_parent[i] != i:
		_island_parent[i] = _island_parent[_island_parent[i]]
		i = _island_parent[i]
	return i


func _union(a: int, b: int) -> void:
	var ra := _find(a)
	var rb := _find(b)
	if ra != rb:
		_island_parent[maxi(ra, rb)] = mini(ra, rb)


func _island_count() -> int:
	var roots := {}
	for i in range(_island_parent.size()):
		roots[_find(i)] = true
	return roots.size()

