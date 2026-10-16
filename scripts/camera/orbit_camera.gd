class_name OrbitCamera
extends Node3D

@export var pan_speed: float = 1.0
@export var orbit_speed: float = 0.005
@export var zoom_factor: float = 1.15
@export var min_distance: float = 8.0
@export var max_distance: float = 800.0

const KEY_PAN_SPEED: float = 80.0
const KEY_ROTATE_SPEED: float = 1.6
const KEY_ZOOM_SPEED: float = 2.0

var _pivot := Vector3.ZERO
var _yaw := 0.6
var _pitch := -0.9
var _distance := 120.0

var _panning := false

@onready var _camera: Camera3D = $Camera3D

func _ready() -> void:
	_apply()

func _process(delta: float) -> void:
	if _camera == null:
		return

	# Skip all keyboard camera controls while any modifier is held. That
	# leaves Ctrl+S, Ctrl+O, Shift+X, and similar combos for other systems.
	if Input.is_key_pressed(KEY_CTRL) or Input.is_key_pressed(KEY_SHIFT) or Input.is_key_pressed(KEY_ALT):
		return

	var fwd: Vector3 = -_camera.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() > 0.0001:
		fwd = fwd.normalized()
	var right: Vector3 = _camera.global_transform.basis.x
	right.y = 0.0
	if right.length_squared() > 0.0001:
		right = right.normalized()

	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		pan += fwd
	if Input.is_key_pressed(KEY_S):
		pan -= fwd
	if Input.is_key_pressed(KEY_A):
		pan -= right
	if Input.is_key_pressed(KEY_D):
		pan += right
	if pan.length_squared() > 0.0001:
		_pivot += pan.normalized() * KEY_PAN_SPEED * delta
		_apply()

	var yaw_delta := 0.0
	if Input.is_key_pressed(KEY_Q):
		yaw_delta -= KEY_ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_E):
		yaw_delta += KEY_ROTATE_SPEED * delta

	var pitch_delta := 0.0
	if Input.is_key_pressed(KEY_R):
		pitch_delta -= KEY_ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_F):
		pitch_delta += KEY_ROTATE_SPEED * delta

	if yaw_delta != 0.0 or pitch_delta != 0.0:
		_yaw += yaw_delta
		_pitch = clampf(_pitch + pitch_delta, -1.5, -0.1)
		_apply()

	var zoom_dir := 0.0
	if Input.is_key_pressed(KEY_T):
		zoom_dir -= 1.0
	if Input.is_key_pressed(KEY_G):
		zoom_dir += 1.0
	if zoom_dir != 0.0:
		var factor: float = 1.0 + KEY_ZOOM_SPEED * delta * zoom_dir
		_distance = clampf(_distance * factor, min_distance, max_distance)
		_apply()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_distance = clampf(_distance / zoom_factor, min_distance, max_distance)
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_distance = clampf(_distance * zoom_factor, min_distance, max_distance)
					_apply()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			var right: Vector3 = _camera.global_transform.basis.x
			var forward: Vector3 = -_camera.global_transform.basis.z
			forward.y = 0.0
			forward = forward.normalized()
			var move: Vector3 = (-right * mm.relative.x + forward * mm.relative.y) * _distance * 0.001 * pan_speed
			_pivot += move
			_apply()

func _apply() -> void:
	if _camera == null:
		return
	var offset := Vector3(
		cos(_pitch) * sin(_yaw),
		-sin(_pitch),
		cos(_pitch) * cos(_yaw)
	) * _distance
	_camera.global_position = _pivot + offset
	_camera.look_at(_pivot, Vector3.UP)
