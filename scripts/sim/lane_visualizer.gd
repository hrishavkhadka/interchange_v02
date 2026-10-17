class_name LaneVisualizer
extends Node3D

const LIFT: float = 0.10
const LANE_SAMPLES: int = 20
const ARC_SAMPLES: int = 10

var _visible: bool = false
var _mesh: MeshInstance3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.90, 1.0, 0.85)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = mat
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.visible = false
	add_child(_mesh)
	LaneGraph.lanes_changed.connect(_rebuild)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and not ke.echo and ke.keycode == KEY_L:
			_visible = not _visible
			_mesh.visible = _visible
			if _visible:
				_rebuild()

func _rebuild() -> void:
	if not _visible:
		_mesh.mesh = null
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for lane in LaneGraph.lanes:
		_draw_curve(st, lane.curve, lane.length, LANE_SAMPLES)
	for arc in LaneGraph.arcs:
		if not arc.enabled:
			continue
		_draw_curve(st, arc.curve, arc.length, ARC_SAMPLES)
	_mesh.mesh = st.commit()

func _draw_curve(st: SurfaceTool, c: Curve3D, length: float, count: int) -> void:
	if c == null or length < 0.05:
		return
	var prev: Vector3 = c.sample_baked(0.0) + Vector3(0.0, LIFT, 0.0)
	for i in range(1, count + 1):
		var t: float = float(i) / float(count)
		var p: Vector3 = c.sample_baked(t * length) + Vector3(0.0, LIFT, 0.0)
		st.add_vertex(prev)
		st.add_vertex(p)
		prev = p
