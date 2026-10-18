class_name SnapToolbar
extends CanvasLayer

signal settings_changed

var _settings: BuildSettings
var _angle_options: Array[float] = [15.0, 30.0, 45.0, 90.0]

func setup(s: BuildSettings) -> void:
	_settings = s

func _ready() -> void:
	layer = 2
	visible = false

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_right = 176
	panel.offset_top = -360
	panel.offset_bottom = -76
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Snapping"
	vbox.add_child(title)

	var _all_button = CheckButton.new()
	_all_button.text = "All"
	_all_button.button_pressed = true
	_all_button.tooltip_text = "Toggle every snap on or off"
	_all_button.toggled.connect(_on_all_toggled)
	vbox.add_child(_all_button)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	_add_toggle(vbox, "snap_node")
	_add_toggle(vbox, "snap_lane")
	_add_toggle(vbox, "snap_segment")
	_add_toggle(vbox, "snap_guide")
	_add_toggle(vbox, "snap_length")
	_add_toggle(vbox, "snap_angle")

func set_expanded(on: bool) -> void:
	visible = on

func _add_toggle(parent: Control, prop: String) -> void:
	var labels := {
		"snap_node": "Node",
		"snap_lane": "Lane",
		"snap_segment": "Segment",
		"snap_guide": "Guideline",
		"snap_length": "Length",
		"snap_angle": "Angle",
	}
	var b := CheckButton.new()
	b.text = labels.get(prop, prop)
	b.button_pressed = _settings.get(prop)
	b.toggled.connect(func(on: bool) -> void:
		_settings.set(prop, on)
		_refresh_all_state()
		settings_changed.emit())
	parent.add_child(b)
	if prop != "snap_node":
		pass # we don't store an array of buttons anymore, handled by name lookup in _on_all_toggled

func _on_all_toggled(on: bool) -> void:
	var _props := ["snap_node", "snap_lane", "snap_segment", "snap_guide", "snap_length", "snap_angle"]
	for prop in _props:
		_settings.set(prop, on)
	for child in get_node("PanelContainer/VBoxContainer").get_children():
		if child is CheckButton and child.text != "All":
			child.set_pressed_no_signal(on)
	settings_changed.emit()

func _refresh_all_state() -> void:
	var _props := ["snap_node", "snap_lane", "snap_segment", "snap_guide", "snap_length", "snap_angle"]
	var all_on := true
	for prop in _props:
		if not _settings.get(prop):
			all_on = false
			break
	for child in get_node("PanelContainer/VBoxContainer").get_children():
		if child is CheckButton and child.text == "All":
			child.set_pressed_no_signal(all_on)
			break
