class_name RoadNode
extends RefCounted

const PASS_THROUGH_ANGLE_DEG: float = 150.0

var id: int
var position: Vector3
var is_waypoint: bool = false
var is_entry: bool = false
var is_exit: bool = false
var map_label: String = ""
var demand: Dictionary = {}
var segment_ends: Array = []
var forced_junction: bool = false

func _init(p_position: Vector3, p_id: int) -> void:
	position = p_position
	id = p_id

func degree() -> int:
	return segment_ends.size()

func add_segment_end(seg: RoadSegment, is_start: bool) -> void:
	segment_ends.append({ "segment": seg, "is_start": is_start })

func is_pass_through() -> bool:
	if forced_junction:
		return false
	if segment_ends.size() != 2:
		return false
	var dirs: Array[Vector3] = []
	for entry in segment_ends:
		var e: Dictionary = entry
		var seg: RoadSegment = e["segment"]
		if seg == null or seg.curve == null:
			return false
		
		var d: Vector3
		if e["is_start"]:
			d = _get_tangent_at_start(seg.curve)
		else:
			d = -_get_tangent_at_end(seg.curve)
			
		d.y = 0.0
		if d.length_squared() < 0.01:
			return false
		dirs.append(d.normalized())
		
	var ang: float = dirs[0].angle_to(dirs[1])
	return ang > deg_to_rad(PASS_THROUGH_ANGLE_DEG)

static func _get_tangent_at_start(curve: Curve3D) -> Vector3:
	var out = curve.get_point_out(0)
	if out.length_squared() > 0.001:
		return out.normalized()
	if curve.point_count > 1:
		return (curve.get_point_position(1) - curve.get_point_position(0)).normalized()
	return Vector3.FORWARD

static func _get_tangent_at_end(curve: Curve3D) -> Vector3:
	var last = curve.point_count - 1
	if last < 0:
		return Vector3.FORWARD
	var in_h = curve.get_point_in(last)
	if in_h.length_squared() > 0.001:
		return -in_h.normalized()
	if last > 0:
		return (curve.get_point_position(last) - curve.get_point_position(last - 1)).normalized()
	return Vector3.FORWARD

func total_demand() -> int:
	var s := 0
	for v in demand.values():
		s += int(v)
	return s
