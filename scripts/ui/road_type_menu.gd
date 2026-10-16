class_name RoadTypeMenu
extends CanvasLayer

signal type_selected(index: int, name: String)

var _buttons: Array[Button] = []

func _ready() -> void:
	layer = 2
	visible = false

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_right = 0.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16
	panel.offset_right = 236
	panel.offset_top = -540
	panel.offset_bottom = -76
	add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Road Type"
	vbox.add_child(title)

	for i in RoadBuilder.ROAD_TYPE_DEFS.size():
		var d: Dictionary = RoadBuilder.ROAD_TYPE_DEFS[i]
		var b := Button.new()
		b.text = "%s  (%s)" % [d["name"], d["layout"]]
		b.toggle_mode = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(200, 0)
		b.pressed.connect(func() -> void: _select(i))
		vbox.add_child(b)
		_buttons.append(b)

func set_expanded(on: bool) -> void:
	visible = on

func set_selected(i: int) -> void:
	for k in _buttons.size():
		_buttons[k].set_pressed_no_signal(k == i)

func _select(i: int) -> void:
	set_selected(i)
	var d: Dictionary = RoadBuilder.ROAD_TYPE_DEFS[i]
	type_selected.emit(i, d["name"])
