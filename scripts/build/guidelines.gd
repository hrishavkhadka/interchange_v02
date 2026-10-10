class_name Guidelines
extends Node3D

const LINE_WIDTH: float = 0.08
const TICK_HALF: float = 0.55
const MAX_TICKS: int = 10
const NEAR_RAY_RADIUS: float = 15.0
const LIFT: float = 0.05

var _mesh: MeshInstance3D
var _material: StandardMaterial3D

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_material = StandardMaterial3D.new()
	_material.albedo_color = Color(1.0, 0.85, 0.35, 0.55)
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)

func clear() -> void:
	_mesh.mesh = null

func update(cursor: Vector3, road_type: RoadType) -> void:
	if road_type == null:
		_mesh.mesh = null
		return
	var lane_w: float = road_type.lane_width
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for node in RoadGraph.nodes:
		for entry in node.segment_ends:
			var e: Dictionary = entry
			var seg_v: Variant = e["segment"]
			if seg_v == null:
				continue
			var seg: RoadSegment = seg_v
			if seg.road_type == null:
				continue
			var is_start: bool = e["is_start"]
			var other: Vector3
			if is_start:
				if seg.end_node == null:
					continue
				other = seg.end_node.position
			else:
				if seg.start_node == null:
					continue
				other = seg.start_node.position

			var dir: Vector3 = other - node.position
			dir.y = 0.0
			if dir.length_squared() < 0.0001:
				continue
			dir = dir.normalized()
			var perp := Vector3(-dir.z, 0.0, dir.x)

			# Straight guideline points OUTWARD (away from the segment body).
			_add_ray(st, node.position, -dir, lane_w, cursor)
			_add_ray(st, node.position, perp, lane_w, cursor)
			_add_ray(st, node.position, -perp, lane_w, cursor)

	_mesh.mesh = st.commit()

func _add_ray(st: SurfaceTool, origin: Vector3, dir: Vector3, lane_w: float, cursor: Vector3) -> void:
	if _dist_to_ray_xz(cursor, origin, dir, lane_w * float(MAX_TICKS)) > NEAR_RAY_RADIUS:
		return
	var perp := Vector3(-dir.z, 0.0, dir.x)
	var full_len: float = lane_w * float(MAX_TICKS)
	var base := origin + Vector3(0.0, LIFT, 0.0)
	var tip := origin + dir * full_len + Vector3(0.0, LIFT, 0.0)
	_quad(st, base, tip, LINE_WIDTH, perp)

	for i in range(1, MAX_TICKS + 1):
		var t: Vector3 = origin + dir * (lane_w * float(i)) + Vector3(0.0, LIFT, 0.0)
		var a: Vector3 = t + perp * TICK_HALF
		var b: Vector3 = t - perp * TICK_HALF
		_quad(st, a, b, LINE_WIDTH, dir)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, width: float, perp_dir: Vector3) -> void:
	var hw: float = width * 0.5
	var p0: Vector3 = a + perp_dir * hw
	var p1: Vector3 = a - perp_dir * hw
	var p2: Vector3 = b - perp_dir * hw
	var p3: Vector3 = b + perp_dir * hw
	_tri(st, p0, p1, p2)
	_tri(st, p0, p2, p3)

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.set_normal(Vector3.UP)
	st.add_vertex(a)
	st.set_normal(Vector3.UP)
	st.add_vertex(b)
	st.set_normal(Vector3.UP)
	st.add_vertex(c)

func _dist_to_ray_xz(p: Vector3, origin: Vector3, dir: Vector3, max_len: float) -> float:
	var d: Vector3 = p - origin
	d.y = 0.0
	var proj: float = d.dot(dir)
	if proj < 0.0:
		return Vector2(p.x - origin.x, p.z - origin.z).length()
	if proj > max_len:
		proj = max_len
	var on_ray: Vector3 = origin + dir * proj
	return Vector2(p.x - on_ray.x, p.z - on_ray.z).length()
