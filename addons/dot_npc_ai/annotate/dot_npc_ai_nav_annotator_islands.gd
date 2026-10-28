extends "dot_npc_ai_nav_annotator_state.gd"


## The islands phase of [DotNpcAiNavAnnotator]: which islands of the mesh are kept. Not a public class.


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
## against the whole map, the dearest per item here), then keeps islands in slices too
## ([method _step_keep]); on a 7000-polygon map that was one 80 ms step.
func _step_islands() -> void:
	if _keep_stage == KEEP_ASK:
		if _cursor == 0:
			var roots := {}
			for i in range(_island_parent.size()):
				roots[_find(i)] = true
			_island_roots = roots.keys()
		var end := mini(_cursor + maxi(1, slice / 4), _island_roots.size())
		for k in range(_cursor, end):
			_open_to_sky(int(_island_roots[k]))
			if _out_of_time():
				end = k + 1
				break
		_cursor = end
		if _cursor >= _island_roots.size():
			_keep_stage = KEEP_AREA
			_cursor = 0
			_island_area = {}
		return
	if _step_keep():
		_keep_stage = KEEP_ASK
		_next_phase()


## Fills [member _kept], the islands spots, watchers and routes are drawn from, and drops links that start elsewhere.
## Every stage walks a list in order and keeps its state in members, so slicing cannot change the answer (float sums keep their order). Returns true when done.
func _step_keep() -> bool:
	match _keep_stage:
		KEEP_AREA:
			_keep_sum_areas()
		KEEP_LINKS:
			_keep_scan_links()
		KEEP_REACH:
			_keep_walk_reach()
		KEEP_DECIDE:
			_keep_decide()
		KEEP_USABLE:
			_keep_filter_links()
		KEEP_TABLE:
			return _keep_build_table()
	return false


## Area per island, summed in triangle order.
func _keep_sum_areas() -> void:
	var end := mini(_cursor + slice * 40, _tris.size())
	for i in range(_cursor, end):
		var root := _find(int(_tris[i][3]))
		var prev := _tri_area[i - 1] if i > 0 else 0.0
		_island_area[root] = float(_island_area.get(root, 0.0)) + _tri_area[i] - prev
	_cursor = end
	if _cursor >= _tris.size():
		_keep_stage = KEEP_LINKS
		_cursor = 0
		_keep_all_links = annotations.links.duplicate()
		_keep_all_links.append_array(_declared)
		_keep_touched = {}
		_keep_out = {}


## Which islands a link touches or leaves.
func _keep_scan_links() -> void:
	var end := mini(_cursor + maxi(1, slice / 2), _keep_all_links.size())
	for k in range(_cursor, end):
		var link := _keep_all_links[k]
		var a := _poly_under((link["from"] as Vector3) + Vector3.UP * 0.2, 0.6)
		var b := _poly_under((link["to"] as Vector3) + Vector3.UP * 0.2, 0.6)
		if a >= 0:
			_keep_touched[_find(a)] = true
		if b >= 0:
			_keep_touched[_find(b)] = true
		if a >= 0 and b >= 0 and _find(a) != _find(b):
			if not _keep_out.has(_find(a)):
				_keep_out[_find(a)] = []
			(_keep_out[_find(a)] as Array).append(_find(b))
	_cursor = end
	if _cursor >= _keep_all_links.size():
		_keep_stage = KEEP_REACH
		_cursor = 0


## Small: seeds and a walk over the islands the links join.
func _keep_walk_reach() -> void:
	var seeded := {}
	for seed_at in seeds:
		var poly := _poly_under(seed_at + Vector3.UP * 0.2, 1.5)
		if poly >= 0:
			seeded[_find(poly)] = true
	var largest := -1
	for root: int in _island_area:
		if largest < 0 or float(_island_area[root]) > float(_island_area[largest]):
			largest = root
	var reached := seeded.duplicate()
	var queue: Array = seeded.keys()
	while not queue.is_empty():
		var root: int = queue.pop_back()
		for next: int in _keep_out.get(root, []):
			if not reached.has(next):
				reached[next] = true
				queue.append(next)
	# A map whose bodies start under a roof is sealed, and a floor open to the sky is the top of
	# its shell: walkable to the bake, outside the map to everybody else.
	var reference: Array = seeded.keys() if not seeded.is_empty() else ([largest] if largest >= 0 else [])
	_keep_roofed = false
	for root: int in reference:
		if not _open_to_sky(root):
			_keep_roofed = true
			break
	_keep_seeded_empty = seeded.is_empty()
	_keep_largest = largest
	_keep_reached = reached
	_keep_roots = _island_area.keys()
	_kept = {}
	_keep_stage = KEEP_DECIDE


## Which islands are kept.
func _keep_decide() -> void:
	var end := mini(_cursor + slice * 8, _keep_roots.size())
	for k in range(_cursor, end):
		var root: int = _keep_roots[k]
		if _keep_reached.has(root):
			_kept[root] = true
		elif reach_only and not _keep_seeded_empty:
			continue
		elif _solid.has(root):
			continue
		elif _keep_roofed and _open_to_sky(root):
			continue
		elif _keep_touched.has(root) or float(_island_area[root]) >= min_island_area or (_keep_seeded_empty and root == _keep_largest):
			_kept[root] = true
	_cursor = end
	if _cursor >= _keep_roots.size():
		_keep_stage = KEEP_USABLE
		_cursor = 0
		_keep_usable = []


## A link that starts where nobody can be is no use to anybody.
func _keep_filter_links() -> void:
	var end := mini(_cursor + maxi(1, slice / 2), annotations.links.size())
	for k in range(_cursor, end):
		var link := annotations.links[k]
		var a := _poly_under((link["from"] as Vector3) + Vector3.UP * 0.2, 0.6)
		if a >= 0 and _kept.has(_find(a)):
			_keep_usable.append(link)
	_cursor = end
	if _cursor >= annotations.links.size():
		var usable: Array[Dictionary] = []
		usable.assign(_keep_usable)
		annotations.links = usable
		# Random points from here on are drawn from the kept floor only.
		_kept_tris = PackedInt32Array()
		_kept_area = PackedFloat32Array()
		_keep_total = 0.0
		_keep_stage = KEEP_TABLE
		_cursor = 0


## The area table random points are drawn from; true when done.
func _keep_build_table() -> bool:
	var end := mini(_cursor + slice * 40, _tris.size())
	for i in range(_cursor, end):
		if _kept.has(_find(int(_tris[i][3]))):
			_keep_total += _tri_area[i] - (_tri_area[i - 1] if i > 0 else 0.0)
			_kept_tris.append(i)
			_kept_area.append(_keep_total)
	_cursor = end
	if _cursor >= _tris.size():
		_keep_all_links = []
		_keep_touched = {}
		_keep_out = {}
		_keep_reached = {}
		_keep_usable = []
		return true
	return false


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

