extends RefCounted

## A small level built in code with one of everything [DotNpcAiNavAnnotator] looks for, at known places, for the suite and tools/annotate_map.
## A 40 by 30 floor split by a wall with one doorway (a chokepoint). West: a low platform (jump up, drop), a high balcony (drop only), a low wall (cover crouched, not standing).
## East: two platforms two metres apart (a jump across) and a closed room with one door (where to hide).

const FLOOR_TOP := 0.0
const LOW_TOP := 0.9
const BALCONY_TOP := 3.0
const GAP_TOP := 2.0
const WALL := 3.0

## Where things are, for the checks.
const DOORWAY := Vector3(0.0, 0.0, 0.0)
const LOW_PLATFORM := AABB(Vector3(-16, 0, -12), Vector3(5, LOW_TOP, 5))
const BALCONY := AABB(Vector3(-16, 0, 6), Vector3(5, BALCONY_TOP, 6))
const GAP_WEST := AABB(Vector3(4, 0, -12), Vector3(5, GAP_TOP, 5))
const GAP_EAST := AABB(Vector3(11, 0, -12), Vector3(5, GAP_TOP, 5))
const LOW_WALL := AABB(Vector3(-6.15, 0, -3), Vector3(0.3, 0.8, 6))
const ROOM := AABB(Vector3(8, 0, 4), Vector3(8, WALL, 8))


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "NavToyLevel"
	_box(root, AABB(Vector3(-20, -1, -15), Vector3(40, 1, 30)))
	# The outside walls.
	_box(root, AABB(Vector3(-20.4, 0, -15.4), Vector3(40.8, WALL, 0.4)))
	_box(root, AABB(Vector3(-20.4, 0, 15), Vector3(40.8, WALL, 0.4)))
	_box(root, AABB(Vector3(-20.4, 0, -15), Vector3(0.4, WALL, 30)))
	_box(root, AABB(Vector3(20, 0, -15), Vector3(0.4, WALL, 30)))
	# The dividing wall, with a doorway 1.6 m wide at z = 0.
	_box(root, AABB(Vector3(-0.2, 0, -15), Vector3(0.4, WALL, 14.2)))
	_box(root, AABB(Vector3(-0.2, 0, 0.8), Vector3(0.4, WALL, 14.2)))
	_box(root, LOW_PLATFORM)
	_box(root, BALCONY)
	_box(root, LOW_WALL)
	_box(root, GAP_WEST)
	_box(root, GAP_EAST)
	# The room: four walls, a door 1.4 m wide in the west one.
	var r := ROOM
	_box(root, AABB(Vector3(r.position.x, 0, r.position.z), Vector3(r.size.x, WALL, 0.3)))
	_box(root, AABB(Vector3(r.position.x, 0, r.end.z - 0.3), Vector3(r.size.x, WALL, 0.3)))
	_box(root, AABB(Vector3(r.end.x - 0.3, 0, r.position.z), Vector3(0.3, WALL, r.size.z)))
	_box(root, AABB(Vector3(r.position.x, 0, r.position.z), Vector3(0.3, WALL, 3.3)))
	_box(root, AABB(Vector3(r.position.x, 0, r.position.z + 4.7), Vector3(0.3, WALL, 3.3)))
	return root


## A large level for timing: a [param cells] by [param cells] field of 5 m blocks, 8 m apart, each 0.9 to 3.6 m high (drops, jump ups and gaps all round) on a walled floor.
## Thousands of polygons and hundreds of islands: what a surf or bhop map is to the annotator, without owning one.
static func build_large(cells: int = 12) -> Node3D:
	var root := Node3D.new()
	root.name = "NavLargeLevel"
	var span := float(cells) * 8.0 + 8.0
	_box(root, AABB(Vector3(-4, -1, -4), Vector3(span, 1, span)))
	_box(root, AABB(Vector3(-4.4, 0, -4.4), Vector3(span + 0.8, WALL, 0.4)))
	_box(root, AABB(Vector3(-4.4, 0, span - 4), Vector3(span + 0.8, WALL, 0.4)))
	_box(root, AABB(Vector3(-4.4, 0, -4), Vector3(0.4, WALL, span)))
	_box(root, AABB(Vector3(span - 4, 0, -4), Vector3(0.4, WALL, span)))
	for ix in range(cells):
		for iz in range(cells):
			var h := 0.9 + float((ix * 7 + iz * 13) % 10) * 0.3
			_box(root, AABB(Vector3(float(ix) * 8.0, 0, float(iz) * 8.0), Vector3(5, h, 5)))
	return root


## The mesh dot-bot's DotBotNav bakes for a body of [param radius] and [param height] that steps [param step], from [param root]'s static colliders (root in the tree).
## Same numbers as DotBotNav (cell 0.175 by 0.1, body rounded to whole cells), so the suite annotates what a game would.
static func bake(root: Node3D, radius: float = 0.35, height: float = 1.8, step: float = 0.4) -> NavigationMesh:
	var source := NavigationMeshSourceGeometryData3D.new()
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.cell_size = 0.175
	mesh.cell_height = 0.1
	mesh.agent_radius = ceilf(radius / 0.175 - 0.001) * 0.175
	mesh.agent_height = ceilf(height / 0.1 - 0.001) * 0.1
	mesh.agent_max_climb = floorf(step / 0.1 + 0.001) * 0.1
	mesh.agent_max_slope = 46.0
	mesh.region_min_size = 2.0
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	return mesh


static func _box(root: Node3D, box: AABB) -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = box.size
	shape.shape = b
	body.position = box.get_center()
	body.add_child(shape)
	var view := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = box.size
	view.mesh = m
	body.add_child(view)
	root.add_child(body)
