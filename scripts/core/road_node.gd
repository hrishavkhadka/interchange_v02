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
# Set by the user (via the junction editor) to force this node to be treated
# as a full junction even if its current geometry would classify it as a
# pass-through.
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
		if seg == null:
			return false
		
		var length := seg.curve.get_baked_length()
		if length < 0.1:
			return false
			
		var d: Vector3
		if e["is_start"]:
			# Tangent pointing OUT of the segment at the start
			d = seg.curve.sample_baked(minf(length, 0.1)) - position
		else:
			# Tangent pointing OUT of the segment at the end
			d = position - seg.curve.sample_baked(maxf(0.0, length - 0.1))
			
		d.y = 0.0
		if d.length_squared() < 0.01:
			return false
		dirs.append(d.normalized())
		
	var ang: float = dirs[0].angle_to(dirs[1])
	return ang > deg_to_rad(PASS_THROUGH_ANGLE_DEG)

func total_demand() -> int:
	var s := 0
	for v in demand.values():
		s += int(v)
	return s
