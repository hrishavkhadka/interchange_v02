class_name MarkerEditor
extends Node3D

const NODE_PICK_RADIUS: float = 6.0
const RING_INNER: float = 1.4
const RING_OUTER: float = 1.75
const RING_LIFT: float = 0.12
const LABEL_LIFT: float = 3.6

var active: bool = false
var _ring_mesh: TorusMesh
var _ring_meshes: Array[MeshInstance3D] = []
var _label_nodes: Array[Label3D] = []

func _ready() -> void:
	_ring_mesh = TorusMesh.new()
	_ring_mesh.inner_radius = RING_INNER
	_ring_mesh.outer_radius = RING_OUTER
	_ring_mesh.rings = 24
	_ring_mesh.ring_segments = 8
	RoadGraph.graph_changed.connect(_rebuild)
	_rebuild()

func set_active(on: bool) -> void:
	active = on

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if not GameState.is_build():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(false)
			get_viewport().set_input_as_handled()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_click(true)
			get_viewport().set_input_as_handled()

func _ground_hit() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var m := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(m)
	var dir := cam.project_ray_normal(m)
	var plane := Plane(Vector3.UP, 0.0)
	return plane.intersects_ray(from, dir)

func _node_at(hit: Vector3) -> RoadNode:
	var best: RoadNode = null
	var best_d: float = NODE_PICK_RADIUS
	for n in RoadGraph.nodes:
		var d: float = Vector2(n.position.x - hit.x, n.position.z - hit.z).length()
		if d < best_d:
			best_d = d
			best = n
	return best

func _on_click(is_exit: bool) -> void:
	var pos_raw: Variant = _ground_hit()
	if pos_raw == null:
		return
	var hit: Vector3 = pos_raw
	var node := _node_at(hit)
	if node == null:
		return
	if node.segment_ends.size() != 1:
		return
	if is_exit:
		if node.is_exit:
			node.is_exit = false
			node.map_label = ""
		else:
			node.is_exit = true
			node.map_label = _next_label("X")
			_clear_demand_to(node)
	else:
		if node.is_entry:
			node.is_entry = false
			node.map_label = ""
			node.demand.clear()
		else:
			node.is_entry = true
			node.map_label = _next_label("E")
	_rebuild()

func _next_label(prefix: String) -> String:
	var max_n: int = 0
	for n in RoadGraph.nodes:
		if n.map_label.begins_with(prefix):
			var num := int(n.map_label.substr(prefix.length()))
			if num > max_n:
				max_n = num
	return "%s%d" % [prefix, max_n + 1]

# When an exit's flag clears, no entry should keep demand pointing at its id.
func _clear_demand_to(exit_node: RoadNode) -> void:
	for n in RoadGraph.nodes:
		if n.is_entry:
			n.demand.erase(exit_node.id)

func _rebuild() -> void:
	for m in _ring_meshes:
		if is_instance_valid(m):
			m.queue_free()
	_ring_meshes.clear()
	for l in _label_nodes:
		if is_instance_valid(l):
			l.queue_free()
	_label_nodes.clear()
	for node in RoadGraph.nodes:
		if not (node.is_entry or node.is_exit):
			continue
		var ring_color := Color(0.30, 0.95, 0.35)
		var label_color := Color(0.35, 1.0, 0.40)
		if node.is_entry and node.is_exit:
			ring_color = Color(0.75, 0.35, 0.95)
			label_color = Color(0.80, 0.40, 1.0)
		elif node.is_exit:
			ring_color = Color(0.95, 0.30, 0.30)
			label_color = Color(1.0, 0.35, 0.35)
		_add_ring(node.position, ring_color)
		if node.map_label != "":
			_add_label(node.position, node.map_label, label_color)

func _add_ring(pos: Vector3, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = _ring_mesh
	mi.material_override = mat
	mi.position = pos + Vector3(0.0, RING_LIFT, 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_ring_meshes.append(mi)

func _add_label(pos: Vector3, text: String, color: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.font_size = 96
	lbl.outline_size = 24
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.modulate = color
	lbl.pixel_size = 0.0008
	lbl.position = pos + Vector3(0.0, LABEL_LIFT, 0.0)
	add_child(lbl)
	_label_nodes.append(lbl)
