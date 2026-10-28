extends SceneTree

## Bakes a map's navigation mesh, annotates it, prints what it found and, with a renderer (xvfb-run), photographs it to `--out PREFIX` (_top, _zoom, _corner_a, _corner_b .png and PREFIX.json). Source: `--toy`, or `--source map.res` (NavigationMeshSourceGeometryData3D a game saved; never commit it here).
## `--meta FILE.json` gives spawns and teleports (`{"spawns": [[x,y,z]], "teleports": [{"min":..,"max":..,"to":..}]}`), which become seeds and declared links. Options: `--radius --height --climb --jump --drop --gap --slice`.
## Run: `godot --path . --script res://tools/annotate_map.gd -- --toy --out /tmp/toy`. The slowest slice is printed, since a frame would pay it.

const Toy := preload("res://fixtures/nav_toy_level.gd")

var _args: Dictionary = {}
var _level: Node3D = null
var _mesh: NavigationMesh = null
var _frames: int = 0


func _init() -> void:
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var k := raw[i].trim_prefix("--")
		if i + 1 < raw.size() and not raw[i + 1].begins_with("--"):
			_args[k] = raw[i + 1]
			i += 2
		else:
			_args[k] = "true"
			i += 1
	process_frame.connect(_go, CONNECT_ONE_SHOT)


func _num(k: String, d: float) -> float:
	return float(_args.get(k, str(d)))


func _go() -> void:
	DotLog.set_level(DotLog.Level.WARN)
	var source := NavigationMeshSourceGeometryData3D.new()
	_level = Node3D.new()
	get_root().add_child(_level)
	if _args.has("source"):
		var loaded: Variant = load(String(_args["source"]))
		if not (loaded is NavigationMeshSourceGeometryData3D):
			print("not source geometry: %s" % _args["source"])
			quit(2)
			return
		source = loaded
		_level.add_child(_level_from_source(source))
	else:
		var toy := Toy.build()
		_level.add_child(toy)
		var probe := NavigationMesh.new()
		probe.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		NavigationServer3D.parse_source_geometry_data(probe, source, toy)

	_mesh = bake(source, _num("radius", 0.35), _num("height", 1.8), _num("climb", 0.4))
	print("baked %d polygons from %d triangles" % [_mesh.get_polygon_count(), source.get_indices().size() / 3])
	# Rays see a body only after the physics server has stepped once with it in.
	for _k in range(3):
		await physics_frame
	_annotate()


## The mesh dot-bot's DotBotNav would bake for this body, from [param source].
static func bake(source: NavigationMeshSourceGeometryData3D, radius: float, height: float, step: float) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.175
	mesh.cell_height = 0.1
	mesh.agent_radius = ceilf(radius / 0.175 - 0.001) * 0.175
	mesh.agent_height = ceilf(height / 0.1 - 0.001) * 0.1
	mesh.agent_max_climb = floorf(step / 0.1 + 0.001) * 0.1
	mesh.agent_max_slope = 46.0
	mesh.region_min_size = 2.0
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	return mesh


## One trimesh body (and a grey mesh to draw) from source geometry.
static func _level_from_source(source: NavigationMeshSourceGeometryData3D) -> Node3D:
	var flat := source.get_vertices()
	var indices := source.get_indices()
	var faces := PackedVector3Array()
	faces.resize(indices.size())
	for i in range(indices.size()):
		var v := indices[i] * 3
		faces[i] = Vector3(flat[v], flat[v + 1], flat[v + 2])
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var trimesh := ConcavePolygonShape3D.new()
	trimesh.backface_collision = true
	trimesh.set_faces(faces)
	shape.shape = trimesh
	body.add_child(shape)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The parser winds faces for the baker; drawn both sides, so the order does not matter.
	for f in faces:
		st.add_vertex(f)
	st.generate_normals()
	var view := MeshInstance3D.new()
	view.mesh = st.commit()
	body.add_child(view)
	return body


func _annotate() -> void:
	var job := DotNpcAiNavAnnotator.new(_mesh, _level.get_world_3d())
	job.agent_radius = _num("radius", 0.35)
	job.stand_height = _num("height", 1.8)
	job.climb = _num("climb", 0.4)
	job.jump_up = _num("jump", 1.0)
	job.drop_max = _num("drop", 6.0)
	job.gap_max = _num("gap", 3.0)
	job.slice = int(_num("slice", 24))
	if _args.has("meta"):
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(String(_args["meta"])))
		if meta is Dictionary:
			var seeds := PackedVector3Array()
			for p: Array in meta.get("spawns", []):
				seeds.append(Vector3(p[0], p[1], p[2]))
			for t: Dictionary in meta.get("teleports", []):
				var lo := Vector3(t["min"][0], t["min"][1], t["min"][2])
				var hi := Vector3(t["max"][0], t["max"][1], t["max"][2])
				var to := Vector3(t["to"][0], t["to"][1], t["to"][2])
				seeds.append(to)
				job.declare(Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5), to, DotNpcAiNavAnnotations.LINK_TELEPORT, 1.0)
			job.seeds = seeds
			print("meta: %d seeds, %d teleports" % [seeds.size(), (meta.get("teleports", []) as Array).size()])
	var slowest := 0.0
	var steps := 0
	while true:
		var t := Time.get_ticks_usec()
		var more := job.step()
		slowest = maxf(slowest, (Time.get_ticks_usec() - t) / 1000.0)
		steps += 1
		if not more:
			break
	var res: DotResult = job.result
	if not res.ok:
		print("annotation failed: %s" % res.error.message)
		quit(1)
		return
	var a: DotNpcAiNavAnnotations = res.value
	for line in a.describe_lines():
		print(line)
	print("stats %s" % JSON.stringify(a.stats))
	print("%d slices, the slowest %.1f ms" % [steps, slowest])
	if _args.has("out"):
		var saved := a.save(String(_args["out"]) + ".json")
		print("saved %s" % saved.value if saved.ok else "not saved: %s" % saved.error.message)
	if DisplayServer.get_name() == "headless" or not _args.has("out"):
		quit(0)
		return
	await _photograph(a, job.kept_polygons())
	quit(0)


func _photograph(a: DotNpcAiNavAnnotations, polygons: PackedInt32Array) -> void:
	var debug := DotNpcAiNavDebug.new()
	_level.add_child(debug)
	debug.show_annotations(a, _mesh, polygons)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.08, 0.1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	_level.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	_level.add_child(sun)

	# Framed on what is drawn: the kept polygons, not a roof or a skybox floor.
	var verts := _mesh.get_vertices()
	var box := AABB(verts[_mesh.get_polygon(polygons[0] if not polygons.is_empty() else 0)[0]], Vector3.ZERO)
	for i in (polygons if not polygons.is_empty() else PackedInt32Array(range(_mesh.get_polygon_count()))):
		for v in _mesh.get_polygon(i):
			box = box.expand(verts[v])
	var centre := box.get_center()
	var span := maxf(box.size.x, box.size.z)
	var cam := Camera3D.new()
	_level.add_child(cam)
	cam.current = true
	cam.far = span * 6.0 + 500.0

	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = span * 1.05
	cam.position = centre + Vector3(0, box.size.y + span, 0)
	cam.look_at(centre, Vector3.FORWARD)
	# From above with the level hidden: a map is usually roofed, and the roof is all a camera
	# above it would see.
	var level_views: Array[Node] = _level.find_children("*", "MeshInstance3D", true, false).filter(
		func(n: Node) -> bool: return not debug.is_ancestor_of(n))
	for n: Node in level_views:
		(n as MeshInstance3D).visible = false
	await _save("top")

	# And close up, on the busiest stretch of the map (most links and hiding spots in a 16 m
	# square), since a whole map from above shows that there are links and not whether they
	# are right.
	var busy := _busiest(a, 16.0)
	cam.size = 16.0
	cam.position = busy + Vector3(0, 40.0, 0)
	cam.look_at(busy, Vector3.FORWARD)
	await _save("zoom")
	print("zoom on %s" % busy)
	for n: Node in level_views:
		(n as MeshInstance3D).visible = true

	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 60.0
	for corner: Array in [["corner_a", Vector3(-1, 0.8, -1)], ["corner_b", Vector3(1, 0.8, 1)]]:
		cam.position = centre + (corner[1] as Vector3).normalized() * span * 0.75
		cam.look_at(centre, Vector3.UP)
		await _save(String(corner[0]))


static func _busiest(a: DotNpcAiNavAnnotations, cell: float) -> Vector3:
	var counts := {}
	var sums := {}
	var points: Array[Vector3] = []
	for link in a.links:
		if int(link["kind"]) != DotNpcAiNavAnnotations.LINK_TELEPORT:
			points.append(link["from"])
	for spot in a.hiding_spots():
		points.append(spot["at"])
	var best := Vector2i.ZERO
	for p in points:
		var c := Vector2i(floori(p.x / cell), floori(p.z / cell))
		counts[c] = int(counts.get(c, 0)) + 1
		sums[c] = (sums.get(c, Vector3.ZERO) as Vector3) + p
		if int(counts[c]) > int(counts.get(best, 0)):
			best = c
	if not counts.has(best):
		return Vector3.ZERO
	return (sums[best] as Vector3) / float(counts[best])


func _save(suffix: String) -> void:
	for _k in range(4):
		await process_frame
	var path := "%s_%s.png" % [_args["out"], suffix]
	get_root().get_texture().get_image().save_png(path)
	print("wrote %s" % path)
