class_name JunctionEditor
extends Node3D

const NODE_PICK_RADIUS: float = 6.0
const DOT_PICK_PIXELS: float = 35.0
const RIBBON_PICK_RADIUS: float = 2.5
const DOT_RADIUS: float = 0.55
const DOT_LIFT: float = 0.35

var active: bool = false
var _node: RoadNode = null

var _ribbons: Array[ArcRibbon] = []
var _entry_dots: Array[MeshInstance3D] = []
var _exit_dots: Array[MeshInstance3D] = []
var _entry_lanes: Array[Lane] = []
var _exit_lanes: Array[Lane] = []

var _entry_mat: StandardMaterial3D
var _exit_mat: StandardMaterial3D
var _sel_mat: StandardMaterial3D
var _entry_dot_mesh: SphereMesh
var _exit_dot_mesh: SphereMesh

var _selected_entry_lane: Lane = null
var _selected_entry_dot: MeshInstance3D = null

var _panel: PanelContainer
var _panel_title: Label

func _ready() -> void:
	_entry_mat = StandardMaterial3D.new()
	_entry_mat.albedo_color = Color(0.30, 0.70, 1.0)
	_entry_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_exit_mat = StandardMaterial3D.new()
	_exit_mat.albedo_color = Color(1.0, 0.80, 0.20)
	_exit_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sel_mat = StandardMaterial3D.new()
	_sel_mat.albedo_color = Color(1.0, 0.35, 1.0)
	_sel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_entry_dot_mesh = SphereMesh.new()
	_entry_dot_mesh.radius = DOT_RADIUS
	_entry_dot_mesh.height = DOT_RADIUS * 2.0
	_exit_dot_mesh = SphereMesh.new()
	_exit_dot_mesh.radius = DOT_RADIUS
	_exit_dot_mesh.height = DOT_RADIUS * 2.0
	_build_panel()

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.visible = false
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 0.0
	_panel.offset_left = -180
	_panel.offset_right = 180
	_panel.offset_top = 16
	_panel.offset_bottom = 104
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_panel.add_child(vbox)

	_panel_title = Label.new()
	_panel_title.text = "Junction"
	vbox.add_child(_panel_title)

	var hint := Label.new()
	hint.text = "Drag entry to exit dot to toggle. Click a ribbon to disable."
	hint.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	hint.add_theme_font_size_override("font_size", 11)
	vbox.add_child(hint)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	vbox.add_child(btn_row)

	var clear_btn := Button.new()
	clear_btn.text = "Clear all arcs"
	clear_btn.pressed.connect(_on_clear_all)
	btn_row.add_child(clear_btn)

	var reset_btn := Button.new()
	reset_btn.text = "Reset to default"
	reset_btn.pressed.connect(_on_reset_default)
	btn_row.add_child(reset_btn)

func set_active(on: bool) -> void:
	active = on
	if not active:
		_close()

func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if not GameState.is_build():
		_close()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_left_click(mb.shift_pressed)
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_close()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_ESCAPE:
			_close()
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

func _on_left_click(shift: bool) -> void:
	var dot := _pick_dot()
	if not dot.is_empty():
		_handle_dot_click(dot)
		return
	var rib := _pick_ribbon()
	if rib != null:
		_toggle_arc(rib.arc)
		return
	if _selected_entry_lane != null:
		_deselect_entry()
		return
	var pos_raw: Variant = _ground_hit()
	if pos_raw == null:
		return
	var hit: Vector3 = pos_raw
	var node := _node_at(hit)
	if node == null:
		return
	if node.is_pass_through():
		if shift:
			node.forced_junction = true
			RoadGraph.graph_changed.emit()
			_open(node)
		return
	_open(node)

func _pick_dot() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var mouse := get_viewport().get_mouse_position()
	var best_d := DOT_PICK_PIXELS
	var best_kind := ""
	var best_idx := -1
	for i in _entry_dots.size():
		var dot: MeshInstance3D = _entry_dots[i]
		if not is_instance_valid(dot):
			continue
		var sp := cam.unproject_position(dot.global_position)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best_kind = "entry"
			best_idx = i
	for i in _exit_dots.size():
		var dot: MeshInstance3D = _exit_dots[i]
		if not is_instance_valid(dot):
			continue
		var sp := cam.unproject_position(dot.global_position)
		var d := sp.distance_to(mouse)
		if d < best_d:
			best_d = d
			best_kind = "exit"
			best_idx = i
	if best_idx < 0:
		return {}
	return { "kind": best_kind, "idx": best_idx }

func _pick_ribbon() -> ArcRibbon:
	var pos_raw: Variant = _ground_hit()
	if pos_raw == null:
		return null
	var hit: Vector3 = pos_raw
	var best: ArcRibbon = null
	var best_d: float = RIBBON_PICK_RADIUS
	for r in _ribbons:
		if not is_instance_valid(r):
			continue
		var d: float = r.distance_to_point(hit)
		if d < best_d:
			best_d = d
			best = r
	return best

func _handle_dot_click(hit: Dictionary) -> void:
	var kind: String = hit["kind"]
	var idx: int = hit["idx"]
	if kind == "entry":
		var lane: Lane = _entry_lanes[idx]
		if _selected_entry_lane == lane:
			_deselect_entry()
			return
		_select_entry(lane, _entry_dots[idx])
		return
	if _selected_entry_lane == null:
		return
	var to_lane: Lane = _exit_lanes[idx]
	_toggle_arc_between(_selected_entry_lane, to_lane)
	_deselect_entry()

func _select_entry(lane: Lane, dot: MeshInstance3D) -> void:
	_deselect_entry()
	_selected_entry_lane = lane
	_selected_entry_dot = dot
	if is_instance_valid(dot):
		dot.material_override = _sel_mat

func _deselect_entry() -> void:
	if _selected_entry_dot != null and is_instance_valid(_selected_entry_dot):
		_selected_entry_dot.material_override = _entry_mat
	_selected_entry_lane = null
	_selected_entry_dot = null

func _toggle_arc_between(from_lane: Lane, to_lane: Lane) -> void:
	if _node == null:
		return
	var arc: LaneArc = from_lane.next_arcs.get(to_lane, null)
	if arc == null:
		return
	_toggle_arc(arc)

func _toggle_arc(arc: LaneArc) -> void:
	if arc == null or arc.node == null or arc.from_lane == null or arc.to_lane == null:
		return
	var node: RoadNode = arc.node
	var was_enabled: bool = arc.enabled
	var new_override: int = -1 if was_enabled else 1
	ArcOverrides.set_override(node, arc.from_lane, arc.to_lane, new_override)
	_open(node)

func _on_clear_all() -> void:
	if _node == null:
		return
	var node_arcs: Array = LaneGraph.arcs_by_node.get(_node.id, [])
	for a_v in node_arcs:
		var arc: LaneArc = a_v
		if arc.from_lane == null or arc.to_lane == null:
			continue
		ArcOverrides.set_override(_node, arc.from_lane, arc.to_lane, -1)
	_open(_node)

func _on_reset_default() -> void:
	if _node == null:
		return
	ArcOverrides.clear_node_overrides(_node)
	_open(_node)

func _open(node: RoadNode) -> void:
	_close()
	if node == null:
		return
	var node_arcs: Array = LaneGraph.arcs_by_node.get(node.id, [])
	if node_arcs.is_empty():
		return
	_node = node
	_panel.visible = true
	_panel_title.text = "Junction %d" % node.id

	for a in node_arcs:
		var arc: LaneArc = a
		if not arc.enabled:
			continue
		var r := ArcRibbon.new()
		r.setup(arc)
		add_child(r)
		_ribbons.append(r)

	for lane in LaneGraph.lanes:
		if lane.to_node == node:
			var pos: Vector3 = lane.curve.sample_baked(lane.length) + Vector3(0.0, DOT_LIFT, 0.0)
			var mi := MeshInstance3D.new()
			mi.mesh = _entry_dot_mesh
			mi.material_override = _entry_mat
			mi.position = pos
			add_child(mi)
			_entry_dots.append(mi)
			_entry_lanes.append(lane)
		if lane.from_node == node:
			var pos2: Vector3 = lane.curve.sample_baked(0.0) + Vector3(0.0, DOT_LIFT, 0.0)
			var mi2 := MeshInstance3D.new()
			mi2.mesh = _exit_dot_mesh
			mi2.material_override = _exit_mat
			mi2.position = pos2
			add_child(mi2)
			_exit_dots.append(mi2)
			_exit_lanes.append(lane)

func _close() -> void:
	for r in _ribbons:
		if is_instance_valid(r):
			r.queue_free()
	_ribbons.clear()
	for d in _entry_dots:
		if is_instance_valid(d):
			d.queue_free()
	_entry_dots.clear()
	_entry_lanes.clear()
	for d in _exit_dots:
		if is_instance_valid(d):
			d.queue_free()
	_exit_dots.clear()
	_exit_lanes.clear()
	_selected_entry_lane = null
	_selected_entry_dot = null
	_node = null
	if _panel != null:
		_panel.visible = false
