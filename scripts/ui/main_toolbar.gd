class_name MainToolbar
extends CanvasLayer

signal mode_requested(mode: int)
signal snapping_toggled(on: bool)
signal road_type_menu_toggled(on: bool)
signal level_data_toggled(on: bool)

const BTN_SIZE: Vector2 = Vector2(36, 36)

var _mode: int = 1
var _buttons: Array[Button] = []
var _snapping_button: Button
var _road_type_button: Button
var _level_data_button: Button
var _interactive: bool = true

func _ready() -> void:
	layer = 3

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_right = 506
	panel.offset_top = -56
	panel.offset_bottom = -16
	add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)

	_add_mode_button(row, "▶", 0, "Pointer mode")
	_add_mode_button(row, "≡", 1, "Road building")
	_add_mode_button(row, "✖", 2, "Demolish")
	_add_mode_button(row, "⇄", 3, "Reverse direction")
	_add_mode_button(row, "◇", 4, "Edit lane connections")
	_add_mode_button(row, "⚑", 5, "Mark entries and exits")
	_add_mode_button(row, "⇅", 6, "Update road type")

	var sep := VSeparator.new()
	row.add_child(sep)

	_road_type_button = Button.new()
	_road_type_button.text = "▦"
	_road_type_button.toggle_mode = true
	_road_type_button.tooltip_text = "Road types"
	_road_type_button.custom_minimum_size = BTN_SIZE
	_road_type_button.toggled.connect(func(on: bool) -> void:
		road_type_menu_toggled.emit(on))
	row.add_child(_road_type_button)

	_snapping_button = Button.new()
	_snapping_button.text = "▤"
	_snapping_button.toggle_mode = true
	_snapping_button.tooltip_text = "Snapping options"
	_snapping_button.custom_minimum_size = BTN_SIZE
	_snapping_button.toggled.connect(func(on: bool) -> void:
		snapping_toggled.emit(on))
	row.add_child(_snapping_button)

	_level_data_button = Button.new()
	_level_data_button.text = "⚙"
	_level_data_button.toggle_mode = true
	_level_data_button.tooltip_text = "Level data (entries, demand)"
	_level_data_button.custom_minimum_size = BTN_SIZE
	_level_data_button.toggled.connect(func(on: bool) -> void:
		level_data_toggled.emit(on))
	row.add_child(_level_data_button)

	_set_mode_visual(_mode)

func get_mode() -> int:
	return _mode

func set_interactive(on: bool) -> void:
	_interactive = on
	for b in _buttons:
		b.disabled = not on
	_road_type_button.disabled = not on
	_snapping_button.disabled = not on
	_level_data_button.disabled = not on

func _add_mode_button(parent: Control, label_text: String, mode_id: int, tip: String) -> void:
	var b := Button.new()
	b.text = label_text
	b.toggle_mode = true
	b.tooltip_text = tip
	b.custom_minimum_size = BTN_SIZE
	b.pressed.connect(func() -> void: _request(mode_id))
	parent.add_child(b)
	_buttons.append(b)

func _request(m: int) -> void:
	if not _interactive:
		_set_mode_visual(_mode)
		return
	if m == _mode:
		_set_mode_visual(_mode)
		return
	_mode = m
	_set_mode_visual(_mode)
	mode_requested.emit(_mode)

func _set_mode_visual(m: int) -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == m)
