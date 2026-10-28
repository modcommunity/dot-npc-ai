class_name DotNpcAiNavDebug
extends Node3D

## Draws a map's [DotNpcAiNavAnnotations] (and the mesh, if given): links as arrows by kind, hiding spots as tall markers, other spots small, chokepoints as bars as wide as the passage.
## [b]Looked at, because no assertion reaches it:[/b] a link on the wrong floor passes every count. Unshaded and over the geometry ([member through_walls]); built once in [method show_annotations].

# No log channel: it draws.

const LINK_COLOURS := {
	DotNpcAiNavAnnotations.LINK_DROP: Color(1.0, 0.25, 0.2),
	DotNpcAiNavAnnotations.LINK_JUMP_UP: Color(0.25, 1.0, 0.3),
	DotNpcAiNavAnnotations.LINK_JUMP_GAP: Color(1.0, 0.9, 0.15),
	DotNpcAiNavAnnotations.LINK_LADDER: Color(0.75, 0.4, 1.0),
	DotNpcAiNavAnnotations.LINK_TELEPORT: Color(1.0, 0.4, 0.9),
	DotNpcAiNavAnnotations.LINK_RIDE: Color(0.2, 0.9, 1.0),
}
const HIDING_COLOUR := Color(0.2, 0.45, 1.0)
const SPOT_COLOUR := Color(0.55, 0.85, 1.0, 0.8)
const CHOKE_COLOUR := Color(1.0, 0.55, 0.0)
const MESH_COLOUR := Color(0.2, 0.75, 0.35, 0.35)

## Drawn over the geometry.
@export var through_walls: bool = true
## Metres a marker stands above the floor.
@export var marker_height: float = 1.2
## Whether spots that are not hiding spots are drawn.
@export var draw_all_spots: bool = true


## Clears and draws [param a], and [param mesh] under it when given: only [param polygons]
## of it when that is not empty ([method DotNpcAiNavAnnotator.kept_polygons], so a roof the
## bake walked on is not drawn over the map).
func show_annotations(a: DotNpcAiNavAnnotations, mesh: NavigationMesh = null, polygons: PackedInt32Array = PackedInt32Array()) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	if mesh != null:
		add_child(_mesh_faces(mesh, polygons))
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES, _material(Color.WHITE, true))
	for link in a.links:
		_arrow(lines, link["from"], link["to"], LINK_COLOURS.get(int(link["kind"]), Color.WHITE))
	var hidden := {}
	for i in a.hiding:
		hidden[i] = true
	for i in range(a.spots.size()):
		var spot := a.spots[i]
		var at: Vector3 = spot["at"]
		if hidden.has(i):
			_marker(lines, at, marker_height, 0.35, HIDING_COLOUR)
		elif draw_all_spots:
			_marker(lines, at, marker_height * 0.3, 0.15, SPOT_COLOUR)
	for choke in a.chokepoints:
		var at: Vector3 = choke["at"]
		var half := float(choke["width"]) * 0.5 + 0.3
		for dy in [0.3, 1.5, 2.7]:
			lines.surface_set_color(CHOKE_COLOUR)
			lines.surface_add_vertex(at + Vector3(-half, dy, 0.0))
			lines.surface_add_vertex(at + Vector3(half, dy, 0.0))
			lines.surface_add_vertex(at + Vector3(0.0, dy, -half))
			lines.surface_add_vertex(at + Vector3(0.0, dy, half))
		lines.surface_add_vertex(at)
		lines.surface_add_vertex(at + Vector3(0.0, 3.0, 0.0))
	lines.surface_end()
	var view := MeshInstance3D.new()
	view.name = "Annotations"
	view.mesh = lines
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(view)


func _arrow(lines: ImmediateMesh, from: Vector3, to: Vector3, colour: Color) -> void:
	var lift := Vector3(0.0, 0.25, 0.0)
	var a := from + lift
	var b := to + lift
	# A drop or a jump drawn as a bent line (up and over), so it reads as a move, not a wall.
	var top := Vector3((a.x + b.x) * 0.5, maxf(a.y, b.y) + 0.6, (a.z + b.z) * 0.5)
	for seg in [[a, top], [top, b]]:
		lines.surface_set_color(colour)
		lines.surface_add_vertex(seg[0])
		lines.surface_set_color(colour)
		lines.surface_add_vertex(seg[1])
	var back := (top - b).normalized() * 0.5
	var side := back.cross(Vector3.UP).normalized() * 0.25
	for tip in [b + back + side, b + back - side]:
		lines.surface_set_color(colour)
		lines.surface_add_vertex(b)
		lines.surface_set_color(colour)
		lines.surface_add_vertex(tip)
	# A small foot at the start, so which end is which reads without the arrowhead.
	lines.surface_set_color(colour)
	lines.surface_add_vertex(a)
	lines.surface_set_color(colour)
	lines.surface_add_vertex(from)


func _marker(lines: ImmediateMesh, at: Vector3, height: float, size: float, colour: Color) -> void:
	lines.surface_set_color(colour)
	lines.surface_add_vertex(at)
	lines.surface_set_color(colour)
	lines.surface_add_vertex(at + Vector3(0.0, height, 0.0))
	var top := at + Vector3(0.0, height, 0.0)
	for d in [Vector3(size, 0, 0), Vector3(0, 0, size)]:
		lines.surface_set_color(colour)
		lines.surface_add_vertex(top - d)
		lines.surface_set_color(colour)
		lines.surface_add_vertex(top + d)


func _mesh_faces(mesh: NavigationMesh, polygons: PackedInt32Array) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices := mesh.get_vertices()
	var lift := Vector3(0.0, 0.05, 0.0)
	var which := polygons
	if which.is_empty():
		which = PackedInt32Array(range(mesh.get_polygon_count()))
	for i in which:
		var polygon := mesh.get_polygon(i)
		for k in range(1, polygon.size() - 1):
			st.add_vertex(vertices[polygon[0]] + lift)
			st.add_vertex(vertices[polygon[k]] + lift)
			st.add_vertex(vertices[polygon[k + 1]] + lift)
	var view := MeshInstance3D.new()
	view.name = "NavMesh"
	view.mesh = st.commit()
	view.material_override = _material(MESH_COLOUR, false)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return view


func _material(colour: Color, vertex_colours: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = colour
	m.vertex_color_use_as_albedo = vertex_colours
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if colour.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = through_walls and vertex_colours
	return m
