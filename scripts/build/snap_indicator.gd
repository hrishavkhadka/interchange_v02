class_name SnapIndicator
extends Node3D

const RING_INNER: float = 0.9
const RING_OUTER: float = 1.3
const LIFT: float = 0.06
const MIN_SCALE: float = 0.6
const MAX_SCALE: float = 3.5
const REF_DISTANCE: float = 80.0

var _mesh: MeshInstance3D

func _ready() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = RING_INNER
	torus.outer_radius = RING_OUTER
	torus.rings = 24
	torus.ring_segments = 6
	_mesh = MeshInstance3D.new()
	_mesh.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.78, 0.20)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false
	_mesh.material_override = mat
	add_child(_mesh)
	visible = false

func show_at(p: Vector3) -> void:
	position = p + Vector3(0.0, LIFT, 0.0)
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		var d: float = cam.global_position.distance_to(p)
		var s: float = clampf(d / REF_DISTANCE, MIN_SCALE, MAX_SCALE)
		scale = Vector3(s, s, s)
	visible = true

func hide_indicator() -> void:
	visible = false
