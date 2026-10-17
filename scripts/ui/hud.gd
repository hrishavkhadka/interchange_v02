class_name HUD
extends CanvasLayer

signal save_requested()
signal load_requested()

var _cost_label: Label
var _road_type_label: Label
var _hint_label: Label

var _time_label: Label
var _counters_label: Label
var _play_button: Button
var _pause_button: Button
var _stop_button: Button
var _restart_button: Button
var _speed_buttons: Array[Button] = []

var _fail_popup: Control
var _pass_popup: Control

func _ready() -> void:
	layer = 2
	_build_bottom_left()
	_build_top_right()
	_build_popups()

	GameState.timer_tick.connect(_on_timer)
	GameState.counters_changed.connect(_on_counters)
	GameState.state_changed.connect(_on_state)
	GameState.failed.connect(_show_fail)
	GameState.passed.connect(_show_pass)

	_on_timer(GameState.time_remaining)
	_on_counters(0, 0, GameState.target_count)
	_on_state(GameState.state)

func _build_bottom_left() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.modulate = Color(1, 1, 1, 0.72)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	_cost_label = Label.new()
	_cost_label.text = "Spent: 0"
	_cost_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_cost_label)

	_road_type_label = Label.new()
	_road_type_label.text = "Road: 2-lane two-way"
	_road_type_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_road_type_label)

	_hint_label = Label.new()
	_hint_label.text = "LMB: place / act\nRMB/Esc: cancel\n1-9/0: road type  L: lanes\nSpace: play/pause\nF9: save  F10: load"
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
	vbox.add_child(_hint_label)

func _build_top_right() -> void:
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left = -520
	panel.offset_right = -16
	panel.offset_top = 16
	panel.offset_bottom = 108
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	vbox.add_child(top_row)

	_time_label = Label.new()
	_time_label.text = "1:30"
	_time_label.add_theme_font_size_override("font_size", 22)
	_time_label.custom_minimum_size = Vector2(80, 0)
	top_row.add_child(_time_label)

	_counters_label = Label.new()
	_counters_label.text = "Spawned 0 / Cleared 0 / Target 40"
	_counters_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	top_row.add_child(_counters_label)

	var ctrl_row := HBoxContainer.new()
	ctrl_row.add_theme_constant_override("separation", 4)
	vbox.add_child(ctrl_row)

	_play_button = _mk_ctrl("▶", "Play / Resume")
	_play_button.pressed.connect(func() -> void: GameState.start_play())
	ctrl_row.add_child(_play_button)

	_pause_button = _mk_ctrl("⏸", "Pause / Resume")
	_pause_button.pressed.connect(func() -> void: GameState.toggle_pause())
	ctrl_row.add_child(_pause_button)

	_stop_button = _mk_ctrl("■", "Stop and clear vehicles")
	_stop_button.pressed.connect(func() -> void: GameState.stop())
	ctrl_row.add_child(_stop_button)

	_restart_button = _mk_ctrl("↺", "Restart")
	_restart_button.pressed.connect(func() -> void: GameState.restart())
	ctrl_row.add_child(_restart_button)

	var sep := VSeparator.new()
	ctrl_row.add_child(sep)

	var save_button := Button.new()
	save_button.text = "Save"
	save_button.tooltip_text = "Save level"
	save_button.custom_minimum_size = Vector2(56, 28)
	save_button.pressed.connect(func() -> void: save_requested.emit())
	ctrl_row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "Load"
	load_button.tooltip_text = "Load level"
	load_button.custom_minimum_size = Vector2(56, 28)
	load_button.pressed.connect(func() -> void: load_requested.emit())
	ctrl_row.add_child(load_button)

	var sep2 := VSeparator.new()
	ctrl_row.add_child(sep2)

	var speeds: Array = [0.5, 1.0, 2.0, 4.0]
	for m_v in speeds:
		var m: float = m_v
		var b := Button.new()
		if m == 0.5:
			b.text = "0.5x"
		elif m == 1.0:
			b.text = "1x"
		elif m == 2.0:
			b.text = "2x"
		else:
			b.text = "4x"
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(38, 28)
		b.pressed.connect(func() -> void:
			GameState.set_speed(m)
			_refresh_speed_buttons())
		ctrl_row.add_child(b)
		_speed_buttons.append(b)
	_refresh_speed_buttons()

func _mk_ctrl(label: String, tip: String) -> Button:
	var b := Button.new()
	b.text = label
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(36, 28)
	return b

func _refresh_speed_buttons() -> void:
	var speeds: Array = [0.5, 1.0, 2.0, 4.0]
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(absf(speeds[i] - GameState.speed_multiplier) < 0.01)

func _build_popups() -> void:
	_fail_popup = _make_popup("Time's up", "The timer has run out. Vehicles are still moving.", Color(0.85, 0.25, 0.25))
	add_child(_fail_popup)
	_pass_popup = _make_popup("Passed", "All vehicles cleared.", Color(0.30, 0.85, 0.40))
	add_child(_pass_popup)

func _make_popup(title: String, message: String, accent: Color) -> Control:
	var root := CenterContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	root.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(360, 140)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", accent)
	vbox.add_child(t)

	var m := Label.new()
	m.text = message
	m.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(m)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	vbox.add_child(row)

	var keep := Button.new()
	keep.text = "Keep watching"
	keep.pressed.connect(func() -> void: root.visible = false)
	row.add_child(keep)

	var stop := Button.new()
	stop.text = "Stop"
	stop.pressed.connect(func() -> void:
		root.visible = false
		GameState.stop())
	row.add_child(stop)

	return root

func _on_timer(remaining: float) -> void:
	var m: int = int(remaining) / 60
	var s: int = int(remaining) % 60
	_time_label.text = "%d:%02d" % [m, s]
	if GameState.state == GameState.State.FAILED_PLAYING:
		_time_label.add_theme_color_override("font_color", Color(0.95, 0.30, 0.30))
	else:
		_time_label.add_theme_color_override("font_color", Color(1, 1, 1))

func _on_counters(spawned: int, cleared: int, target: int) -> void:
	_counters_label.text = "Spawned %d / Cleared %d / Target %d" % [spawned, cleared, target]

func _on_state(s: int) -> void:
	var in_build: bool = s == GameState.State.BUILD
	var in_pause: bool = s == GameState.State.PAUSED
	_play_button.disabled = not (in_build or in_pause)
	_pause_button.disabled = in_build
	_stop_button.disabled = in_build
	_restart_button.disabled = in_build
	for b in _speed_buttons:
		b.disabled = in_build

func _show_fail() -> void:
	_fail_popup.visible = true

func _show_pass() -> void:
	_pass_popup.visible = true

func set_cost(v: float) -> void:
	if _cost_label != null:
		_cost_label.text = "Spent: %.0f" % v

func set_road_type(name: String) -> void:
	if _road_type_label != null:
		_road_type_label.text = "Road: " + name
