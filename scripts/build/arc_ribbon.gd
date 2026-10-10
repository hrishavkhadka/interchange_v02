class_name ArcRibbon
extends Node3D

const LIFT: float = 0.20
const HALF_WIDTH_ENABLED: float = 0.14
const SAMPLES_ENABLED: int = 40
const SAMPLES_DISABLED: int = 24

var arc: LaneArc
var _mesh: MeshInstance3D
var _material: StandardMaterial3D

func setup(a: LaneArc) -> void:
	arc = a
	_mesh = MeshInstance3D.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	rebuild()

func rebuild() -> void:
	if arc == null or arc.curve == null:
		return
	var c: Curve3D = arc.curve
	var length: float = c.get_baked_length()
	if length < 0.1:
		_mesh.mesh = null
		_update_color()
		return
	if arc.enabled:
		_build_ribbon(c, length)
	else:
		_build_thin_line(c, length)
	_update_color()

func _build_ribbon(c: Curve3D, length: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var samples: int = maxi(8, SAMPLES_ENABLED)
	var prev_l: Vector3 = Vector3.ZERO
	var prev_r: Vector3 = Vector3.ZERO
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var along: float = t * length
		var p: Vector3 = c.sample_baked(along)
		var right: Vector3 = _right_at(c, along, length)
		var l: Vector3 = p - right * HALF_WIDTH_ENABLED + Vector3(0.0, LIFT, 0.0)
		var r: Vector3 = p + right * HALF_WIDTH_ENABLED + Vector3(0.0, LIFT, 0.0)
		if i > 0:
			_tri(st, prev_l, prev_r, l)
			_tri(st, prev_r, r, l)
		prev_l = l
		prev_r = r
	_mesh.mesh = st.commit()

func _build_thin_line(c: Curve3D, length: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var samples: int = maxi(8, SAMPLES_DISABLED)
	var prev: Vector3 = c.sample_baked(0.0) + Vector3(0.0, LIFT, 0.0)
	for i in range(1, samples + 1):
		var t: float = float(i) / float(samples)
		var p: Vector3 = c.sample_baked(t * length) + Vector3(0.0, LIFT, 0.0)
		st.add_vertex(prev)
		st.add_vertex(p)
		prev = p
	_mesh.mesh = st.commit()

func _right_at(c: Curve3D, along: float, length: float) -> Vector3:
	var ahead_d: float = minf(along + 0.2, length)
	var behind_d: float = maxf(along - 0.2, 0.0)
	var ahead: Vector3 = c.sample_baked(ahead_d)
	var behind: Vector3 = c.sample_baked(behind_d)
	var tangent: Vector3 = ahead - behind
	tangent.y = 0.0
	if tangent.length_squared() < 0.0001:
		tangent = Vector3.FORWARD
	tangent = tangent.normalized()
	var right: Vector3 = tangent.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		right = Vector3.RIGHT
	return right.normalized()

func _update_color() -> void:
	if _material == null:
		return
	if arc != null and arc.enabled:
		_material.albedo_color = Color(0.25, 0.95, 0.35, 0.9)
	else:
		_material.albedo_color = Color(0.95, 0.25, 0.25, 0.9)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)

func distance_to_point(p: Vector3) -> float:
	if arc == null or arc.curve == null:
		return INF
	var c: Curve3D = arc.curve
	var length: float = c.get_baked_length()
	if length < 0.1:
		return INF
	var samples: int = maxi(4, 32)
	var best: float = INF
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var q: Vector3 = c.sample_baked(t * length)
		var d: float = Vector2(q.x - p.x, q.z - p.z).length()
		if d < best:
			best = d
	return best
