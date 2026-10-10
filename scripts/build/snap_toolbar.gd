class_name SnapToolbar
extends CanvasLayer

signal settings_changed

var _settings: BuildSettings
var _all_button: CheckButton
var _snap_buttons: Array[CheckButton] = []
var _snap_props: Array[String] = ["snap_node", "snap_segment", "snap_guide", "snap_length", "snap_angle"]

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
	panel.offset_top = -320
	panel.offset_bottom = -76
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Snapping"
	vbox.add_child(title)

	_all_button = CheckButton.new()
	_all_button.text = "All"
	_all_button.button_pressed = true
	_all_button.tooltip_text = "Toggle every snap on or off"
	_all_button.toggled.connect(_on_all_toggled)
	vbox.add_child(_all_button)

	var sep := HSeparator.new()
	vbox.add_child(sep)

	for prop in _snap_props:
		_add_toggle(vbox, prop)

func set_expanded(on: bool) -> void:
	visible = on

func _add_toggle(parent: Control, prop: String) -> void:
	var labels := {
		"snap_node": "Node",
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
	_snap_buttons.append(b)

func _on_all_toggled(on: bool) -> void:
	for prop in _snap_props:
		_settings.set(prop, on)
	for b in _snap_buttons:
		b.set_pressed_no_signal(on)
	settings_changed.emit()

func _refresh_all_state() -> void:
	var all_on := true
	for prop in _snap_props:
		if not _settings.get(prop):
			all_on = false
			break
	_all_button.set_pressed_no_signal(all_on)
