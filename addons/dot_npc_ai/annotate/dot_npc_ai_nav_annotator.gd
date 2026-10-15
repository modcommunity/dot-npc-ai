class_name DotNpcAiNavAnnotator
extends DotJob

## Works out a map's [DotNpcAiNavAnnotations] from a baked [NavigationMesh] and the colliders
## it was baked from: links where a body can drop, jump up or jump across, spots beside walls
## scored for cover and for being out of sight, and the chokepoints routes crowd through.
##
## [b]Any map, no authoring.[/b] Imported maps come with brushes and nothing else, and a
## bot that only has the walkable mesh walks to the edge of a balcony and stops, because the
## mesh has no polygon in the air between the balcony and the floor. Everything here is
## measured from two things every map has once it is loaded: the mesh (where a body stands)
## and the physics space (what a ray hits).
##
## [b]Where the links come from.[/b] The mesh's outline is every edge only one polygon has.
## Each is sampled about every [member sample_spacing] metres and asked one question with a
## ray: is there a wall just past it? If so the sample is a place beside a wall, and a hiding
## or cover candidate. If not it is a ledge, and a ray straight down past it finds what is
## below: a floor on the mesh within [member drop_max] is a drop (and, when it is no higher
## than [member jump_up], a jump up the other way); nothing, or nothing on the mesh, is a gap,
## and points further out to [member gap_max] are tried for a landing a jump would reach with
## a clear arc. A link a short walk already covers is dropped, and links along one stretch of
## edge are thinned to one per [member link_spacing].
##
## [b]Why not the navigation server's own links or a jump-link baker.[/b] The engine bakes
## no off-mesh links, and a link it is handed is all it knows; the question of where one
## belongs is geometric, and asking it of the colliders with rays works on any map, a code
## built one or an imported one, with no editor step.
##
## [b]A job, so it never stops a frame.[/b] It is stepped in slices of [member slice] items,
## so a [DotScheduler] runs it inside its frame budget on the main thread, which is the only
## place a physics query may be made and the only place there is in a browser without threads.
## [method DotJob.run_to_completion] runs it in one go for tools and tests. It is
## deterministic: the same mesh, colliders, settings and [member random_seed] give the same
## annotations, so a cached file and a fresh run agree.
##
## [codeblock]
## var job := DotNpcAiNavAnnotator.new(nav.mesh, map.get_world_3d())
## job.agent_radius = 0.35
## var cached := DotNpcAiNavAnnotations.load_file("user://nav/%s.json" % job.cache_key(), job.cache_key())
## if cached.ok:
##     annotations = cached.value
## else:
##     scheduler.submit(job)
##     var res: DotResult = await job.finished
##     if res.ok:
##         annotations = res.value
##         annotations.save("user://nav/%s.json" % annotations.key)
## [/codeblock]
##
## [b]Subclass or assign.[/b] [member los_fn] replaces the line of sight (a game whose glass
## or foliage blocks sight but not rays); [method _keep_link] and [method _hide_score] are the
## two judgements worth overriding; [method declare] adds the links geometry cannot see
## (ladders, teleports, ride edges).

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

# --- Settings -----------------------------------------------------------------

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

## `(from: Vector3, to: Vector3) -> bool`, true when nothing blocks the sight line. Unset,
## a ray against [member collision_mask].
var los_fn: Callable = Callable()

## What this job is making. Filled as it runs; the job's result once it finishes.
var annotations: DotNpcAiNavAnnotations = DotNpcAiNavAnnotations.new()

# --- State --------------------------------------------------------------------

enum Phase { POLYGONS, EDGES, BORDER, ISLANDS, WATCHERS, SPOTS, PICK, ROUTES, CHOKEPOINTS, DONE }

var _mesh: NavigationMesh = null
var _world: World3D = null
var _phase: int = Phase.POLYGONS
var _cursor: int = 0
var _started_us: int = 0
var _phase_us: Dictionary = {}
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
var _thin_kept: Array = []
var _thin_cells: Dictionary = {}


func _init(mesh: NavigationMesh = null, world: World3D = null) -> void:
	_mesh = mesh
	_world = world
	name = "nav annotations"


## Physics queries are main-thread only.
func is_thread_safe() -> bool:
	return false


## Adds a link the geometry cannot show (a ladder, a teleport, a ride edge), kept in the
## result whatever the measurement finds. Call before the job runs or after it finished.
func declare(from: Vector3, to: Vector3, kind: int, cost: float = 1.0) -> void:
	var link := {"from": from, "to": to, "kind": kind, "cost": cost}
	_declared.append(link)
	if _phase == Phase.DONE:
		annotations.links.append(link)


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
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("dot_npc_ai_nav_annotations/%d|" % DotNpcAiNavAnnotations.VERSION).to_utf8_buffer())
	if mesh != null:
		ctx.update(mesh.get_vertices().to_byte_array())
		for i in range(mesh.get_polygon_count()):
			ctx.update(mesh.get_polygon(i).to_byte_array())
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


# --- The job ------------------------------------------------------------------

func _setup() -> void:
	_started_us = Time.get_ticks_usec()
	_phase_started_us = _started_us
	_rng = DotRandomStream.new(random_seed, &"nav_annotate")
	annotations = DotNpcAiNavAnnotations.new()


func _progress() -> float:
	return float(_phase) / float(Phase.DONE)


func _step() -> bool:
	if _mesh == null or _mesh.get_polygon_count() == 0:
		_finish(DotResult.fail(DotError.CODE_INVALID, "nothing to annotate: the mesh is empty"))
		return false
	if _world == null or _world.direct_space_state == null:
		_finish(DotResult.fail(DotError.CODE_STATE, "nothing to measure against: no physics space"))
		return false

	match _phase:
		Phase.POLYGONS:
			_step_polygons()
		Phase.EDGES:
			_step_edges()
		Phase.BORDER:
			_step_border()
		Phase.ISLANDS:
			_step_islands()
		Phase.WATCHERS:
			_step_watchers()
		Phase.SPOTS:
			_step_spots()
		Phase.PICK:
			_step_pick()
		Phase.ROUTES:
			_step_routes()
		Phase.CHOKEPOINTS:
			_step_chokepoints()
	if _phase == Phase.DONE:
		_complete()
		return false
	return true


func _next_phase() -> void:
	var now := Time.get_ticks_usec()
	_phase_us[Phase.keys()[_phase].to_lower()] = snappedf((now - _phase_started_us) / 1000.0, 0.1)
	_phase_started_us = now
	_phase += 1
	_cursor = 0


func _complete() -> void:
	annotations.links.append_array(_declared)
	annotations.key = cache_key()
	var ms := (Time.get_ticks_usec() - _started_us) / 1000.0
	var joining := 0
	for link in annotations.links:
		var a := _poly_under(link["from"], 1.0)
		var b := _poly_under(link["to"], 1.0)
		if a >= 0 and b >= 0 and _find(a) != _find(b):
			joining += 1
	annotations.stats = {
		"ms": snappedf(ms, 0.1), "phases_ms": _phase_us, "polygons": _mesh.get_polygon_count(),
		"outline": _border.size(), "samples": _samples.size(), "wall_samples": _wall_samples.size(),
		"islands": _island_count(), "islands_kept": _kept.size(), "links_joining_islands": joining, "routes": _routes_done,
	}
	DotLog.info(CHANNEL, "annotated a map", {
		"links": annotations.link_counts(), "spots": annotations.spots.size(), "hiding": annotations.hiding.size(),
		"chokepoints": annotations.chokepoints.size(), "ms": snappedf(ms, 0.1), "key": annotations.key.left(12),
	})
	_finish(DotResult.success(annotations))


# --- Phase: polygons ------------------------------------------------------------

func _step_polygons() -> void:
	if _cursor == 0:
		_vertices = _mesh.get_vertices()
		_island_parent.resize(_mesh.get_polygon_count())
	var end := mini(_cursor + slice * 8, _mesh.get_polygon_count())
	for i in range(_cursor, end):
		_island_parent[i] = i
		var polygon := _mesh.get_polygon(i)
		var centre := Vector3.ZERO
		for v in polygon:
			centre += _vertices[v]
		centre /= float(maxi(polygon.size(), 1))
		_centres.append(centre)
		_graph.add_point(i, centre)
		for k in range(1, polygon.size() - 1):
			_add_triangle(_vertices[polygon[0]], _vertices[polygon[k]], _vertices[polygon[k + 1]], i)
		for k in range(polygon.size()):
			var a := polygon[k]
			var b := polygon[(k + 1) % polygon.size()]
			var key := _edge_key(_vertices[a], _vertices[b])
			if _edges.has(key):
				var other: Array = _edges[key]
				other.append(i)
			else:
				_edges[key] = [i, a, b]
	_cursor = end
	if _cursor >= _mesh.get_polygon_count():
		_edge_keys = _edges.keys()
		_next_phase()


func _add_triangle(a: Vector3, b: Vector3, c: Vector3, polygon: int) -> void:
	var index := _tris.size()
	_tris.append([a, b, c, polygon])
	_total_area += (b - a).cross(c - a).length() * 0.5
	_tri_area.append(_total_area)
	var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.z, minf(b.z, c.z)))
	var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.z, maxf(b.z, c.z)))
	for cx in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
		for cz in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
			var cell := Vector2i(cx, cz)
			if not _tri_grid.has(cell):
				_tri_grid[cell] = PackedInt32Array()
			var bucket: PackedInt32Array = _tri_grid[cell]
			bucket.append(index)
			# A packed array in a dictionary is a copy when read out; write it back.
			_tri_grid[cell] = bucket


# --- Phase: edges -----------------------------------------------------------------

func _step_edges() -> void:
	var end := mini(_cursor + slice * 8, _edge_keys.size())
	for i in range(_cursor, end):
		var entry: Array = _edges[_edge_keys[i]]
		var a: Vector3 = _vertices[entry[1]]
		var b: Vector3 = _vertices[entry[2]]
		if entry.size() == 3:
			_add_border(a, b, int(entry[0]))
			continue
		# Shared: a portal. Joined both ways in the route graph.
		var p := int(entry[0])
		var q := int(entry[3])
		if p == q:
			continue
		if not _graph.are_points_connected(p, q):
			_graph.connect_points(p, q, true)
		_union(p, q)
		_portals[Vector2i(mini(p, q), maxi(p, q))] = (a + b) * 0.5
	_cursor = end
	if _cursor >= _edge_keys.size():
		_next_phase()


func _add_border(a: Vector3, b: Vector3, polygon: int) -> void:
	var index := _border.size()
	_border.append([a, b])
	var lo := Vector2(minf(a.x, b.x), minf(a.z, b.z))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.z, b.z))
	for cx in range(floori(lo.x / GRID), floori(hi.x / GRID) + 1):
		for cz in range(floori(lo.y / GRID), floori(hi.y / GRID) + 1):
			var cell := Vector2i(cx, cz)
			var bucket: PackedInt32Array = _border_grid.get(cell, PackedInt32Array())
			bucket.append(index)
			_border_grid[cell] = bucket
	# Samples along it, each with the normal pointing out of its polygon.
	var along := b - a
	along.y = 0.0
	var length := along.length()
	if length < 0.05:
		return
	var normal := Vector3(along.z, 0.0, -along.x) / length
	var mid := (a + b) * 0.5
	var inward := _centres[polygon] - mid
	if normal.dot(Vector3(inward.x, 0.0, inward.z)) > 0.0:
		normal = -normal
	var count := maxi(1, roundi(length / sample_spacing))
	for k in range(count):
		var t := (float(k) + 0.5) / float(count)
		_samples.append([a.lerp(b, t), normal, polygon])


# --- Phase: the outline -----------------------------------------------------------

func _step_border() -> void:
	var end := mini(_cursor + slice, _samples.size())
	for i in range(_cursor, end):
		var sample: Array = _samples[i]
		_classify(sample[0], sample[1], int(sample[2]))
	_cursor = end
	if _cursor >= _samples.size():
		_next_phase()


## One outline sample: beside a wall (a spot candidate) or a ledge (a drop, a jump up or a gap).
func _classify(p: Vector3, n: Vector3, polygon: int) -> void:
	var knee := Vector3(0.0, minf(0.5, stand_height * 0.3), 0.0)
	var probe := agent_radius + 0.45
	if _ray(p + knee, p + knee + n * probe).size() > 0:
		_wall_samples.append([p, n, polygon])
		return

	# A ledge, unless the floor just past it is at about this height: a lip the bake left out
	# or a rounded corner, where there is neither a link nor anything to hide against.
	var past := p + n * (agent_radius + 0.3)
	var hit := _ray(past + Vector3.UP * 0.3, past + Vector3.DOWN * (drop_max + 0.3))
	if not hit.is_empty() and p.y - (hit["position"] as Vector3).y <= climb + 0.25:
		return
	# A floor at about this height a jump away comes first (a gap is a better way over than
	# down and back up), then what is under the air just past the edge.
	_try_gap(p, n)
	if hit.is_empty():
		return
	var land := _landing(hit["position"], n)
	if is_nan(land.x):
		return
	# Measured between the two floors of the mesh, which both sit the same way above what
	# they were baked from.
	var depth := p.y - land.y
	if depth <= climb + 0.1:
		return
	_offer_link(p, land, DotNpcAiNavAnnotations.LINK_DROP, 1.0 + depth * 0.15)
	if depth <= jump_up:
		_offer_link(land, p, DotNpcAiNavAnnotations.LINK_JUMP_UP, 1.5 + depth)


## The point on the mesh nearest below [param ground] going on along [param n], or NAN.
func _landing(ground: Vector3, n: Vector3) -> Vector3:
	for k in [0.0, agent_radius + 0.15, agent_radius * 2.0 + 0.3]:
		var at := ground + n * float(k)
		if _poly_under(at + Vector3.UP * 0.2, 0.5) >= 0:
			return Vector3(at.x, _last_height, at.z)
	return Vector3(NAN, NAN, NAN)


## A landing at about the height of [param p], further out along [param n] than a step and
## no further than [member gap_max], with a clear line for the jump; linked when found.
func _try_gap(p: Vector3, n: Vector3) -> void:
	if gap_max <= 0.0:
		return
	var lift := Vector3.UP * minf(stand_height * 0.5, 0.9)
	var dist := agent_radius + 0.6
	while dist <= gap_max + agent_radius:
		var t := p + n * dist
		# Only near-level landings: a floor far below is a drop, and found as one.
		var hit := _ray(t + Vector3.UP * (jump_up * 0.6 + 0.3), t + Vector3.DOWN * 1.0)
		if not hit.is_empty():
			var land := _landing(hit["position"], n)
			if not is_nan(land.x) and _ray(p + lift, land + lift).is_empty():
				_offer_link(p, land, DotNpcAiNavAnnotations.LINK_JUMP_GAP, 1.5 + dist * 0.3)
				return
			# Something at this height that is not a landing (a wall top, a rail): no gap.
			if is_nan(land.x):
				return
		dist += 0.5


## Adds a link unless one like it is near both its ends or [method _keep_link] says a walk
## already covers it.
func _offer_link(from: Vector3, to: Vector3, kind: int, cost: float) -> void:
	for link in annotations.links:
		if int(link["kind"]) == kind and (link["from"] as Vector3).distance_to(from) < link_spacing and (link["to"] as Vector3).distance_to(to) < link_spacing:
			return
	if not _keep_link(from, to, kind):
		return
	annotations.links.append({"from": from, "to": to, "kind": kind, "cost": cost})


## Whether a link from [param from] to [param to] is worth having: false when walking there
## on the mesh is not much longer (within half again its length and three metres). Override
## for a game that wants every edge linked, or none of a kind.
func _keep_link(from: Vector3, to: Vector3, _kind: int) -> bool:
	var a := _poly_under(from + Vector3.UP * 0.2, 0.6)
	var b := _poly_under(to + Vector3.UP * 0.2, 0.6)
	if a < 0 or b < 0 or a == b:
		return a != b
	if _find(a) != _find(b):
		return true
	var walk := _walk_length(a, b)
	return walk > from.distance_to(to) * 1.5 + 3.0


func _walk_length(a: int, b: int) -> float:
	var ids := _graph.get_id_path(a, b)
	if ids.size() < 2:
		return INF
	var total := 0.0
	for i in range(1, ids.size()):
		total += _centres[ids[i - 1]].distance_to(_centres[ids[i]])
	return total


# --- Phase: watchers and spots ----------------------------------------------------

func _step_watchers() -> void:
	if _cursor == 0:
		for _i in range(watchers):
			_watchers.append(_random_point() + Vector3(0.0, eye_height, 0.0))
		_thin_kept = []
		_thin_cells = {}
	# Thin the wall samples to under half the spot spacing apart, against a grid of the ones
	# kept so it stays linear on a map with thousands, then to max_candidates evenly.
	var apart := spot_spacing * 0.4
	var end := mini(_cursor + slice * 4, _wall_samples.size())
	for i in range(_cursor, end):
		var sample: Array = _wall_samples[i]
		if not _kept.has(_find(int(sample[2]))):
			continue
		var at: Vector3 = sample[0]
		var c := Vector3i(floori(at.x / apart), floori(at.y / apart), floori(at.z / apart))
		var near := false
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var bucket: Variant = _thin_cells.get(c + Vector3i(dx, dy, dz))
					if bucket == null:
						continue
					for other: Vector3 in bucket:
						if other.distance_to(at) < apart:
							near = true
		if not near:
			_thin_kept.append(sample)
			if not _thin_cells.has(c):
				_thin_cells[c] = []
			(_thin_cells[c] as Array).append(at)
	_cursor = end
	if _cursor < _wall_samples.size():
		return
	var kept := _thin_kept
	if kept.size() > max_candidates:
		var thinned: Array = []
		var stride := float(kept.size()) / float(max_candidates)
		var f := _rng.next_unit() * stride
		while int(f) < kept.size() and thinned.size() < max_candidates:
			thinned.append(kept[int(f)])
			f += stride
		kept = thinned
	_wall_samples = kept
	_thin_kept = []
	_thin_cells = {}
	_next_phase()


func _step_spots() -> void:
	var end := mini(_cursor + maxi(1, slice / 4), _wall_samples.size())
	var head := Vector3(0.0, crouch_height * 0.85, 0.0)
	var low := Vector3(0.0, crouch_height * 0.6, 0.0)
	var high := Vector3(0.0, stand_height * 0.72, 0.0)
	for i in range(_cursor, end):
		var sample: Array = _wall_samples[i]
		var at: Vector3 = sample[0]
		# Heights from the floor itself: the mesh floats up to a cell above what it was baked
		# from, and a crouched head over a waist-high wall is a matter of centimetres.
		var ground := _ray(at + Vector3.UP * 0.3, at + Vector3.DOWN * 0.6)
		if not ground.is_empty():
			at.y = (ground["position"] as Vector3).y
		var target := at + head
		var near := 0
		var seen := 0
		for eye in _watchers:
			var d := eye.distance_to(target)
			if d > reach or d < 1.0:
				continue
			near += 1
			if _clear(eye, target):
				seen += 1
		var blocked := 0
		for k in range(16):
			var a := float(k) * TAU / 16.0
			if _ray(target, target + Vector3(cos(a), 0.0, sin(a)) * 2.0).size() > 0:
				blocked += 1
		var low_mask := 0
		var high_mask := 0
		for k in range(DotNpcAiNavAnnotations.COVER_DIRECTIONS):
			var dir := DotNpcAiNavAnnotations.direction(k)
			if _ray(at + low, at + low + dir * (agent_radius + 0.9)).size() > 0:
				low_mask |= 1 << k
			if _ray(at + high, at + high + dir * (agent_radius + 0.9)).size() > 0:
				high_mask |= 1 << k
		annotations.spots.append({
			# On the mesh, as every other point here; the normal away from the wall.
			"at": sample[0], "normal": -(sample[1] as Vector3),
			# Nobody within reach: as hidden as it is unvisited, so counted as seen by half.
			"exposure": float(seen) / float(near) if near > 0 else 0.5,
			"seen_by": seen, "enclosure": float(blocked) / 16.0, "low": low_mask, "high": high_mask,
		})
	_cursor = end
	if _cursor >= _wall_samples.size():
		_next_phase()


## How good a hiding spot [param spot] is; higher is better. Out of sight first, then tucked
## in. Override for a game that hides differently (in the open among props, high up).
func _hide_score(spot: Dictionary) -> float:
	return (1.0 - float(spot["exposure"])) * 2.0 + float(spot["enclosure"]) * 1.5


func _step_pick() -> void:
	var order: Array = []
	for i in range(annotations.spots.size()):
		order.append([_hide_score(annotations.spots[i]), i])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	# The better third, or anything seen by under a third of its watchers, whichever is more.
	var cutoff := maxi(1, order.size() / 3)
	var chosen: Array[Vector3] = []
	for rank in range(order.size()):
		if annotations.hiding.size() >= max_hiding:
			break
		var index: int = order[rank][1]
		var spot := annotations.spots[index]
		if rank >= cutoff and float(spot["exposure"]) > 0.33:
			continue
		var at: Vector3 = spot["at"]
		var crowded := false
		for other in chosen:
			if other.distance_to(at) < spot_spacing:
				crowded = true
				break
		if crowded:
			continue
		chosen.append(at)
		annotations.hiding.append(index)
	_next_phase()


# --- Phase: routes and chokepoints -------------------------------------------------

func _step_routes() -> void:
	var end := mini(_cursor + maxi(1, slice / 8), routes)
	for _i in range(_cursor, end):
		var a := _poly_under(_random_point() + Vector3.UP * 0.2, 0.5)
		var b := _poly_under(_random_point() + Vector3.UP * 0.2, 0.5)
		if a < 0 or b < 0 or a == b or _find(a) != _find(b) or not _kept.has(_find(a)):
			continue
		var ids := _graph.get_id_path(a, b)
		if ids.size() < 2:
			continue
		_routes_done += 1
		var passed := {}
		for k in range(1, ids.size()):
			var p := ids[k - 1]
			var q := ids[k]
			var mid: Vector3 = _portals.get(Vector2i(mini(p, q), maxi(p, q)), (_centres[p] + _centres[q]) * 0.5)
			var cell := Vector3i(floori(mid.x / GRID), floori(mid.y / GRID), floori(mid.z / GRID))
			if passed.has(cell):
				continue
			passed[cell] = true
			var travel := _centres[q] - _centres[p]
			var entry: Dictionary = _traffic.get(cell, {"count": 0, "at": mid, "width": INF})
			entry["count"] = int(entry["count"]) + 1
			var width := _width_across(mid, travel)
			if width < float(entry["width"]):
				entry["width"] = width
				entry["at"] = mid
			_traffic[cell] = entry
	_cursor = end
	if _cursor >= routes:
		_next_phase()


## Walkable metres across the mesh at [param at], square to [param travel]: the distance to
## the outline on each side, added.
func _width_across(at: Vector3, travel: Vector3) -> float:
	var side := Vector3(-travel.z, 0.0, travel.x)
	if side.length() < 0.001:
		return INF
	side = side.normalized()
	var limit := choke_width * 2.0
	return _to_outline(at, side, limit) + _to_outline(at, -side, limit)


func _to_outline(at: Vector3, dir: Vector3, limit: float) -> float:
	var o := Vector2(at.x, at.z)
	var d := Vector2(dir.x, dir.z)
	var best := limit
	var seen := {}
	var steps := ceili(limit / GRID) + 1
	for s in range(steps + 1):
		var probe := o + d * float(s) * GRID
		for dx in range(-1, 2):
			for dz in range(-1, 2):
				var cell := Vector2i(floori(probe.x / GRID) + dx, floori(probe.y / GRID) + dz)
				for index: int in _border_grid.get(cell, PackedInt32Array()):
					if seen.has(index):
						continue
					seen[index] = true
					var seg: Array = _border[index]
					var a: Vector3 = seg[0]
					var b: Vector3 = seg[1]
					if absf((a.y + b.y) * 0.5 - at.y) > 1.5:
						continue
					var hit: Variant = Geometry2D.segment_intersects_segment(o, o + d * limit, Vector2(a.x, a.z), Vector2(b.x, b.z))
					if hit is Vector2:
						best = minf(best, o.distance_to(hit))
	return best


func _step_chokepoints() -> void:
	var found: Array = []
	var floor_count := maxi(3, ceili(float(_routes_done) * choke_traffic))
	for cell: Vector3i in _traffic:
		var entry: Dictionary = _traffic[cell]
		if int(entry["count"]) >= floor_count and float(entry["width"]) <= choke_width:
			found.append(entry)
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["count"]) > int(b["count"]) or (int(a["count"]) == int(b["count"]) and float(a["width"]) < float(b["width"])))
	for entry: Dictionary in found:
		var at: Vector3 = entry["at"]
		var crowded := false
		for choke in annotations.chokepoints:
			if (choke["at"] as Vector3).distance_to(at) < 5.0:
				crowded = true
				break
		if not crowded:
			annotations.chokepoints.append({"at": at, "width": float(entry["width"]),
				"traffic": float(entry["count"]) / float(maxi(_routes_done, 1))})
	_next_phase()


## The mesh's polygons on islands a body can reach (see [member seeds]), once the job has run:
## where a game should draw random points from, and what [DotNpcAiNavDebug] draws.
func kept_polygons() -> PackedInt32Array:
	var out := PackedInt32Array()
	if _kept.is_empty():
		return out
	for i in range(_island_parent.size()):
		if _kept.has(_find(i)):
			out.append(i)
	return out


## Asks of a slice of islands whether each is inside a solid or open to the sky (rays
## against the whole map, the dearest per item here), then keeps islands once all are asked.
func _step_islands() -> void:
	if _cursor == 0:
		var roots := {}
		for i in range(_island_parent.size()):
			roots[_find(i)] = true
		_island_roots = roots.keys()
	var end := mini(_cursor + maxi(1, slice / 4), _island_roots.size())
	for k in range(_cursor, end):
		_open_to_sky(int(_island_roots[k]))
	_cursor = end
	if _cursor >= _island_roots.size():
		_keep_islands()
		_next_phase()


## Fills [member _kept], the islands spots, watchers and routes are drawn from (see
## [member seeds], [member reach_only], [member min_island_area]), and drops the links that
## start anywhere else.
func _keep_islands() -> void:
	_kept = {}
	var area := {}
	for i in range(_tris.size()):
		var root := _find(int(_tris[i][3]))
		var prev := _tri_area[i - 1] if i > 0 else 0.0
		area[root] = float(area.get(root, 0.0)) + _tri_area[i] - prev
	var all_links: Array[Dictionary] = annotations.links.duplicate()
	all_links.append_array(_declared)
	var touched := {}
	var out := {}
	for link in all_links:
		var a := _poly_under((link["from"] as Vector3) + Vector3.UP * 0.2, 0.6)
		var b := _poly_under((link["to"] as Vector3) + Vector3.UP * 0.2, 0.6)
		if a >= 0:
			touched[_find(a)] = true
		if b >= 0:
			touched[_find(b)] = true
		if a >= 0 and b >= 0 and _find(a) != _find(b):
			if not out.has(_find(a)):
				out[_find(a)] = []
			(out[_find(a)] as Array).append(_find(b))
	var seeded := {}
	for seed_at in seeds:
		var poly := _poly_under(seed_at + Vector3.UP * 0.2, 1.5)
		if poly >= 0:
			seeded[_find(poly)] = true
	var largest := -1
	for root: int in area:
		if largest < 0 or float(area[root]) > float(area[largest]):
			largest = root
	var reached := seeded.duplicate()
	var queue: Array = seeded.keys()
	while not queue.is_empty():
		var root: int = queue.pop_back()
		for next: int in out.get(root, []):
			if not reached.has(next):
				reached[next] = true
				queue.append(next)
	# A map whose bodies start under a roof is sealed, and a floor open to the sky is the top of
	# its shell: walkable to the bake, outside the map to everybody else.
	var reference: Array = seeded.keys() if not seeded.is_empty() else ([largest] if largest >= 0 else [])
	var roofed := false
	for root: int in reference:
		if not _open_to_sky(root):
			roofed = true
			break
	for root: int in area:
		if reached.has(root):
			_kept[root] = true
		elif reach_only and not seeded.is_empty():
			continue
		elif _solid.has(root):
			continue
		elif roofed and _open_to_sky(root):
			continue
		elif touched.has(root) or float(area[root]) >= min_island_area or (seeded.is_empty() and root == largest):
			_kept[root] = true
	# A link that starts where nobody can be is no use to anybody.
	var usable: Array[Dictionary] = []
	for link in annotations.links:
		var a := _poly_under((link["from"] as Vector3) + Vector3.UP * 0.2, 0.6)
		if a >= 0 and _kept.has(_find(a)):
			usable.append(link)
	annotations.links = usable
	# Random points from here on are drawn from the kept floor only.
	_kept_tris = PackedInt32Array()
	_kept_area = PackedFloat32Array()
	var total := 0.0
	for i in range(_tris.size()):
		if _kept.has(_find(int(_tris[i][3]))):
			total += _tri_area[i] - (_tri_area[i - 1] if i > 0 else 0.0)
			_kept_tris.append(i)
			_kept_area.append(total)


## Whether nothing is over [param root]'s island: a ray up from its centre and from up to
## four more of its polygons, most of them escaping.
func _open_to_sky(root: int) -> bool:
	if _sky.has(root):
		return bool(_sky[root])
	var tried := 0
	var open := 0
	var inside := 0
	var i := root
	while i < _island_parent.size() and tried < 5:
		if _find(i) == root:
			tried += 1
			var c := _centres[i] + Vector3.UP * 0.5
			# A ray that starts in a convex solid hits where it starts: a floor the bake found
			# inside a box, a wall's own top under another, which nobody stands on.
			var query := PhysicsRayQueryParameters3D.create(c, c + Vector3.UP * 2000.0, collision_mask, exclude)
			query.hit_from_inside = true
			var hit := _world.direct_space_state.intersect_ray(query)
			if hit.is_empty():
				open += 1
			elif (hit["position"] as Vector3).distance_to(c) < 0.01:
				inside += 1
		i += maxi(1, _island_parent.size() / 64)
	if inside * 2 > tried:
		_solid[root] = true
	_sky[root] = open * 2 > tried
	return bool(_sky[root])


# --- Queries ------------------------------------------------------------------------

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


func describe() -> Dictionary:
	return {
		"phase": Phase.keys()[_phase].to_lower(),
		"polygons": _mesh.get_polygon_count() if _mesh != null else 0,
		"samples": _samples.size(),
		"links": annotations.links.size(),
		"spots": annotations.spots.size(),
		"key": cache_key().left(12) if _mesh != null else "",
	}


func describe_lines() -> PackedStringArray:
	var d := describe()
	return PackedStringArray(["nav annotator %s: %d polygons, %d outline samples, %d links, %d spots" % [
		d["phase"], d["polygons"], d["samples"], d["links"], d["spots"]]])
