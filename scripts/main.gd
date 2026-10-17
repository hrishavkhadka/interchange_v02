extends Node3D

var _builder: RoadBuilder
var _vehicles: VehicleManager
var _junction_editor: JunctionEditor
var _marker_editor: MarkerEditor
var _snap_toolbar: SnapToolbar
var _road_type_menu: RoadTypeMenu
var _level_data_panel: LevelDataPanel
var _main_toolbar: MainToolbar
var _save_dialog: ConfirmationDialog
var _save_field: LineEdit
var _load_dialog: ConfirmationDialog
var _load_field: LineEdit

func _toolbar_to_builder_mode(tm: int) -> int:
	if tm == 4 or tm == 5:
		return 0
	if tm == 6:
		return 4
	return tm

func _ready() -> void:
	_setup_environment()
	_setup_light()
	_setup_ground()
	var camera := _setup_camera()

	_builder = _setup_builder(camera)

	var hud := _setup_hud()
	_builder.cost_changed.connect(hud.set_cost)
	hud.save_requested.connect(popup_save)
	hud.load_requested.connect(popup_load)

	_road_type_menu = RoadTypeMenu.new()
	_road_type_menu.name = "RoadTypeMenu"
	add_child(_road_type_menu)
	_road_type_menu.type_selected.connect(func(idx: int, name: String) -> void:
		_builder.set_road_type_index(idx)
		hud.set_road_type(name))

	_builder.road_type_changed.connect(func(idx: int, name: String) -> void:
		hud.set_road_type(name)
		_road_type_menu.set_selected(idx))

	_builder.set_road_type_index(0)
	hud.set_road_type("2-lane two-way")
	_road_type_menu.set_selected(0)

	var visualizer := RoadGraphVisualizer.new()
	visualizer.name = "RoadGraphVisualizer"
	add_child(visualizer)

	var junctions := JunctionRenderer.new()
	junctions.name = "JunctionRenderer"
	add_child(junctions)

	var transitions := TransitionMesh.new()
	transitions.name = "TransitionMesh"
	add_child(transitions)

	var lane_vis := LaneVisualizer.new()
	lane_vis.name = "LaneVisualizer"
	add_child(lane_vis)

	_marker_editor = MarkerEditor.new()
	_marker_editor.name = "MarkerEditor"
	add_child(_marker_editor)

	_vehicles = VehicleManager.new()
	_vehicles.name = "VehicleManager"
	add_child(_vehicles)

	_junction_editor = JunctionEditor.new()
	_junction_editor.name = "JunctionEditor"
	add_child(_junction_editor)

	_snap_toolbar = SnapToolbar.new()
	_snap_toolbar.name = "SnapToolbar"
	_snap_toolbar.setup(_builder.settings)
	add_child(_snap_toolbar)

	_level_data_panel = LevelDataPanel.new()
	_level_data_panel.name = "LevelDataPanel"
	add_child(_level_data_panel)

	_main_toolbar = MainToolbar.new()
	_main_toolbar.name = "MainToolbar"
	add_child(_main_toolbar)

	_build_dialogs()

	var snap_expanded: bool = false
	var road_menu_expanded: bool = false
	var level_data_expanded: bool = false

	_main_toolbar.mode_requested.connect(func(m: int) -> void:
		_junction_editor.set_active(false)
		_marker_editor.set_active(false)
		if m == 4:
			_builder.set_mode(0)
			_junction_editor.set_active(true)
		elif m == 5:
			_builder.set_mode(0)
			_marker_editor.set_active(true)
		elif m == 6:
			_builder.set_mode(4)
		else:
			_builder.set_mode(m)
		_snap_toolbar.set_expanded(snap_expanded and (m == 1))
		_road_type_menu.set_expanded(road_menu_expanded and (m == 1 or m == 6)))

	_main_toolbar.snapping_toggled.connect(func(on: bool) -> void:
		snap_expanded = on
		_snap_toolbar.set_expanded(on and (_main_toolbar.get_mode() == 1)))

	_main_toolbar.road_type_menu_toggled.connect(func(on: bool) -> void:
		road_menu_expanded = on
		var tm: int = _main_toolbar.get_mode()
		_road_type_menu.set_expanded(on and (tm == 1 or tm == 6)))

	_main_toolbar.level_data_toggled.connect(func(on: bool) -> void:
		level_data_expanded = on
		_level_data_panel.set_expanded(on and GameState.is_build()))

	_builder.set_mode(_toolbar_to_builder_mode(_main_toolbar.get_mode()))

	GameState.state_changed.connect(func(s: int) -> void:
		var build: bool = s == GameState.State.BUILD
		_main_toolbar.set_interactive(build)
		if build:
			_builder.set_mode(_toolbar_to_builder_mode(_main_toolbar.get_mode()))
		else:
			_builder.set_mode(0)
			_junction_editor.set_active(false)
			_marker_editor.set_active(false)
		_snap_toolbar.visible = build and snap_expanded
		_road_type_menu.visible = build and road_menu_expanded
		_level_data_panel.visible = build and level_data_expanded)

func _build_dialogs() -> void:
	_save_dialog = ConfirmationDialog.new()
	_save_dialog.title = "Save Level (F9 or button)"
	_save_dialog.ok_button_text = "Save"
	_save_field = LineEdit.new()
	_save_field.text = "level_01"
	_save_dialog.add_child(_save_field)
	_save_dialog.confirmed.connect(func() -> void:
		var path: String = LevelIO.save_level(_save_field.text)
		print("[level] saved to ", path))
	add_child(_save_dialog)

	_load_dialog = ConfirmationDialog.new()
	_load_dialog.title = "Load Level (F10 or button)"
	_load_dialog.ok_button_text = "Load"
	_load_field = LineEdit.new()
	_load_field.text = "level_01"
	_load_dialog.add_child(_load_field)
	_load_dialog.confirmed.connect(func() -> void:
		var ok: bool = LevelIO.load_level(_load_field.text)
		print("[level] load result: ", ok))
	add_child(_load_dialog)

func popup_save() -> void:
	if _save_dialog != null:
		_save_dialog.popup_centered()
		_save_field.grab_focus()

func popup_load() -> void:
	if _load_dialog != null:
		_load_dialog.popup_centered()
		_load_field.grab_focus()

func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		if ke.keycode == KEY_F9:
			var save_path: String = LevelIO.save_level("quick_save")
			print("[level] quick-saved to ", save_path)
			get_viewport().set_input_as_handled()
			return
		if ke.keycode == KEY_F10:
			var ok: bool = LevelIO.load_level("quick_save")
			print("[level] quick-load result: ", ok)
			get_viewport().set_input_as_handled()
			return
		if GameState.is_build():
			match ke.keycode:
				KEY_1: _builder.set_road_type_index(0)
				KEY_2: _builder.set_road_type_index(1)
				KEY_3: _builder.set_road_type_index(2)
				KEY_4: _builder.set_road_type_index(3)
				KEY_5: _builder.set_road_type_index(4)
				KEY_6: _builder.set_road_type_index(5)
				KEY_7: _builder.set_road_type_index(6)
				KEY_8: _builder.set_road_type_index(7)
				KEY_9: _builder.set_road_type_index(8)
				KEY_0: _builder.set_road_type_index(9)
				KEY_K:
					_vehicles.debug_lane_changes = not _vehicles.debug_lane_changes
					print("[debug] lane-change logging = ", _vehicles.debug_lane_changes)
				KEY_J:
					LaneGraph.debug_lane_arcs = not LaneGraph.debug_lane_arcs
					print("[debug] lane-arc debug = ", LaneGraph.debug_lane_arcs)
		match ke.keycode:
			KEY_SPACE:
				if GameState.is_build():
					GameState.start_play()
				else:
					GameState.toggle_pause()

func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.13)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

func _setup_light() -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -40, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	add_child(light)

func _setup_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(300, 300)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0, -0.15, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.34, 0.28)
	mat.roughness = 1.0
	mi.material_override = mat
	add_child(mi)

func _setup_camera() -> OrbitCamera:
	var root := Node3D.new()
	root.set_script(preload("res://scripts/camera/orbit_camera.gd"))
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	cam.far = 4000.0
	root.add_child(cam)
	add_child(root)
	return root

func _setup_builder(_camera: OrbitCamera) -> RoadBuilder:
	var builder := Node3D.new()
	builder.set_script(preload("res://scripts/build/road_builder.gd"))
	builder.name = "RoadBuilder"

	var preview_root := Node3D.new()
	preview_root.name = "PreviewRoot"
	builder.add_child(preview_root)

	var segments_root := Node3D.new()
	segments_root.name = "SegmentsRoot"
	builder.add_child(segments_root)

	add_child(builder)
	return builder

func _setup_hud() -> HUD:
	var hud := HUD.new()
	add_child(hud)
	return hud
