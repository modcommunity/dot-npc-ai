class_name DotNpcAiNavAnnotator
extends "dot_npc_ai_nav_annotator_islands.gd"

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

	var began := Time.get_ticks_usec()
	_step_began_us = began
	var ran := _phase
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
		Phase.FINISH:
			_step_finish()
	var took := (Time.get_ticks_usec() - began) / 1000.0
	if took > _slowest_ms:
		_slowest_ms = took
		_slowest_phase = Phase.keys()[ran].to_lower()
	if _phase == Phase.DONE:
		_complete()
		return false
	return true


## The last phase, in pieces: hashing the mesh for the key (the dearest, it is every polygon),
## then counting the links that join islands. [method _complete] only assembles.
func _step_finish() -> void:
	if _finish_stage == 0:
		if _cursor == 0:
			_key_ctx = _key_begin(_mesh)
		var end := mini(_cursor + slice * 40, _mesh.get_polygon_count())
		_key_polygons(_key_ctx, _mesh, _cursor, end)
		_cursor = end
		if _cursor >= _mesh.get_polygon_count():
			_finish_stage = 1
			_cursor = 0
			annotations.links.append_array(_declared)
		return
	var end := mini(_cursor + maxi(1, slice / 2), annotations.links.size())
	for k in range(_cursor, end):
		var link := annotations.links[k]
		var a := _poly_under(link["from"], 1.0)
		var b := _poly_under(link["to"], 1.0)
		if a >= 0 and b >= 0 and _find(a) != _find(b):
			_joining += 1
		if _out_of_time():
			end = k + 1
			break
	_cursor = end
	if _cursor >= annotations.links.size():
		_next_phase()


func _complete() -> void:
	annotations.key = _key_end(_key_ctx, settings())
	_key_ctx = null
	var ms := (Time.get_ticks_usec() - _started_us) / 1000.0
	var joining := _joining
	annotations.stats = {
		"ms": snappedf(ms, 0.1), "phases_ms": _phase_us,
		"slowest_slice_ms": snappedf(_slowest_ms, 0.1), "slowest_slice_phase": _slowest_phase, "polygons": _mesh.get_polygon_count(),
		"outline": _border.size(), "samples": _samples.size(), "wall_samples": _wall_samples.size(),
		"islands": _island_count(), "islands_kept": _kept.size(), "links_joining_islands": joining, "routes": _routes_done,
	}
	DotLog.info(CHANNEL, "annotated a map", {
		"links": annotations.link_counts(), "spots": annotations.spots.size(), "hiding": annotations.hiding.size(),
		"chokepoints": annotations.chokepoints.size(), "ms": snappedf(ms, 0.1), "key": annotations.key.left(12),
	})
	_finish(DotResult.success(annotations))


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


func _step_border() -> void:
	var end := mini(_cursor + slice, _samples.size())
	for i in range(_cursor, end):
		var sample: Array = _samples[i]
		_classify(sample[0], sample[1], int(sample[2]))
		if _out_of_time():
			end = i + 1
			break
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
		if _out_of_time():
			end = i + 1
			break
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
		if _out_of_time():
			end = _i + 1
			break
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
