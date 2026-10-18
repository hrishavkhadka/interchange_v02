extends Node

signal lanes_changed

var debug_lane_arcs: bool = false

var arcs: Array = []
var arcs_by_from_lane: Dictionary = {}
var arcs_by_node: Dictionary = {}
var conflicting_lanes: Dictionary = {}

var lanes: Array[Lane] = []

func _ready() -> void:
	RoadGraph.graph_changed.connect(_rebuild)
	ArcOverrides.overrides_changed.connect(_rebuild)

func _rebuild() -> void:
	ArcOverrides.refresh_indices()
	lanes.clear()
	arcs.clear()
	arcs_by_from_lane.clear()
	arcs_by_node.clear()
	conflicting_lanes.clear()

	var trims := _compute_node_trims()

	for seg in RoadGraph.segments:
		if seg.road_type == null or seg.curve == null:
			continue
		if seg.start_node == null or seg.end_node == null:
			continue
		var start_trim: float = trims.get(seg.start_node.id, 0.0)
		var end_trim: float = trims.get(seg.end_node.id, 0.0)
		var layout: LaneLayout = seg.road_type.layout()
		for i in layout.size():
			var dir: String = layout.lanes[i]
			var lane := _make_lane(seg, i, dir, start_trim, end_trim)
			if lane != null:
				lanes.append(lane)

	_build_arcs()
	_build_connections_from_arcs()
	_build_adjacency()
	_build_lane_conflicts()
	_build_arc_conflicts()

	lanes_changed.emit()

func _compute_node_trims() -> Dictionary:
	var trims: Dictionary = {}
	for node in RoadGraph.nodes:
		if node.is_pass_through():
			trims[node.id] = 0.0
			continue
		var ends: Array = node.segment_ends
		if ends.size() < 2:
			trims[node.id] = 0.0
			continue
		var min_angle: float = PI
		for i in ends.size():
			for j in range(i + 1, ends.size()):
				var e1: Dictionary = ends[i]
				var e2: Dictionary = ends[j]
				var s1: RoadSegment = e1["segment"]
				var s2: RoadSegment = e2["segment"]
				var d1: Vector3 = _outward_dir(s1, e1["is_start"], node)
				var d2: Vector3 = _outward_dir(s2, e2["is_start"], node)
				if d1.length_squared() < 0.01 or d2.length_squared() < 0.01:
					continue
				var ang: float = d1.angle_to(d2)
				if ang < min_angle:
					min_angle = ang
		var factor: float = LaneBuilder.trim_factor_for_angle(min_angle)
		var max_half_width: float = 0.0
		for e in ends:
			var s: RoadSegment = e["segment"]
			if s.road_type == null:
				continue
			var hw: float = s.road_type.total_width() * 0.5
			if hw > max_half_width:
				max_half_width = hw
		trims[node.id] = factor * max_half_width
	return trims

static func _outward_dir(seg: RoadSegment, is_start: bool, node: RoadNode) -> Vector3:
	var other: RoadNode
	if is_start:
		other = seg.end_node
	else:
		other = seg.start_node
	if other == null:
		return Vector3.ZERO
	var d: Vector3 = other.position - node.position
	d.y = 0.0
	if d.length_squared() < 0.01:
		return Vector3.ZERO
	return d.normalized()

func _make_lane(seg: RoadSegment, lane_index: int, direction: String, start_trim: float, end_trim: float) -> Lane:
	var curve := LaneBuilder.build_lane_curve(seg.curve, seg.road_type, lane_index, direction, start_trim, end_trim)
	if curve == null:
		return null
	var lane := Lane.new()
	lane.segment = seg
	lane.lane_index = lane_index
	lane.direction = direction
	lane.curve = curve
	lane.length = curve.get_baked_length()
	if direction == "F":
		lane.from_node = seg.start_node
		lane.to_node = seg.end_node
	else:
		lane.from_node = seg.end_node
		lane.to_node = seg.start_node
	lane.speed_limit = seg.road_type.speed_limit_kmh / 3.6
	return lane

func _build_arcs() -> void:
	for lane in lanes:
		lane.next_arcs.clear()
		lane.prev_arcs.clear()

	for node in RoadGraph.nodes:
		if node.segment_ends.size() < 2:
			continue
		var pairs: Array = LaneArcBuilder.build(node, lanes, debug_lane_arcs)
		for p_v in pairs:
			var p: Dictionary = p_v
			var from_lane: Lane = p["from_lane"]
			var to_lane: Lane = p["to_lane"]
			var default_enabled: bool = bool(p["default_enabled"])
			if from_lane == null or to_lane == null:
				continue
			if from_lane.next_arcs.has(to_lane):
				continue
			var curve := _make_transition(from_lane, to_lane)
			if curve == null:
				continue
			var arc := LaneArc.make(from_lane, to_lane, node, curve)

			var enabled: bool = default_enabled
			if node.is_pass_through():
				enabled = true
			else:
				var override: int = ArcOverrides.get_override(node, from_lane, to_lane)
				if override == 1:
					enabled = true
				elif override == -1:
					enabled = false

			arc.enabled = enabled
			from_lane.next_arcs[to_lane] = arc
			to_lane.prev_arcs[from_lane] = arc
			arcs.append(arc)
			if not arcs_by_from_lane.has(from_lane):
				arcs_by_from_lane[from_lane] = []
			arcs_by_from_lane[from_lane].append(arc)
			if not arcs_by_node.has(node.id):
				arcs_by_node[node.id] = []
			arcs_by_node[node.id].append(arc)

func _build_connections_from_arcs() -> void:
	for lane in lanes:
		lane.next_lanes.clear()
		lane.prev_lanes.clear()
	for lane in lanes:
		for to_lane in lane.next_arcs:
			var arc: LaneArc = lane.next_arcs[to_lane]
			if arc.enabled:
				lane.next_lanes.append(to_lane)
				to_lane.prev_lanes.append(lane)

func _make_transition(from_lane: Lane, to_lane: Lane) -> Curve3D:
	var start_p: Vector3 = from_lane.curve.sample_baked(from_lane.length)
	var end_p: Vector3 = to_lane.curve.sample_baked(0.0)
	var dist: float = start_p.distance_to(end_p)
	if dist < 0.1:
		var straight := Curve3D.new()
		straight.add_point(start_p)
		straight.add_point(end_p)
		return straight
	var start_t: Vector3 = _end_tangent(from_lane.curve, from_lane.length)
	var end_t: Vector3 = _start_tangent(to_lane.curve)
	var handle_len: float = dist / 3.0
	var p1: Vector3 = start_p + start_t * handle_len
	var p2: Vector3 = end_p - end_t * handle_len
	var samples: int = maxi(6, int(dist * 1.5))
	var curve := Curve3D.new()
	if debug_lane_arcs:
		var turn_deg: float = rad_to_deg(start_t.angle_to(end_t))
		if turn_deg > 90.0:
			print("[transition] sharp turn %.1f deg, from lane %d to lane %d, dist %.2f" % [
				turn_deg, from_lane.lane_index, to_lane.lane_index, dist])
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		curve.add_point(_bezier3(start_p, p1, p2, end_p, t))
	return curve

static func _end_tangent(c: Curve3D, length: float) -> Vector3:
	var p_end: Vector3 = c.sample_baked(length)
	var p_before: Vector3 = c.sample_baked(maxf(length - 0.3, 0.0))
	var t: Vector3 = p_end - p_before
	t.y = 0.0
	if t.length_squared() < 0.0001:
		return Vector3.FORWARD
	return t.normalized()

static func _start_tangent(c: Curve3D) -> Vector3:
	var length: float = c.get_baked_length()
	var p_start: Vector3 = c.sample_baked(0.0)
	var p_after: Vector3 = c.sample_baked(minf(0.3, length))
	var t: Vector3 = p_after - p_start
	t.y = 0.0
	if t.length_squared() < 0.0001:
		return Vector3.FORWARD
	return t.normalized()

static func _bezier3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3

func _build_adjacency() -> void:
	for lane in lanes:
		lane.adjacent_lanes.clear()
	var by_segment: Dictionary = {}
	for lane in lanes:
		var key: int = lane.segment.get_instance_id()
		if not by_segment.has(key):
			by_segment[key] = []
		by_segment[key].append(lane)
	for key in by_segment:
		var group: Array = by_segment[key]
		for i in group.size():
			for j in range(i + 1, group.size()):
				var a: Lane = group[i]
				var b: Lane = group[j]
				if a.direction != b.direction:
					continue
				if absi(a.lane_index - b.lane_index) != 1:
					continue
				a.adjacent_lanes.append(b)
				b.adjacent_lanes.append(a)

const CONFLICT_DIST: float = 3.5
const CONFLICT_SAMPLES: int = 30

func _build_lane_conflicts() -> void:
	var by_node: Dictionary = {}
	for lane in lanes:
		if lane.to_node == null:
			continue
		if lane.to_node.is_pass_through():
			continue
		var key: int = lane.to_node.id
		if not by_node.has(key):
			by_node[key] = []
		by_node[key].append(lane)
	for key in by_node:
		var incoming: Array = by_node[key]
		for i in incoming.size():
			var la: Lane = incoming[i]
			if not conflicting_lanes.has(la):
				conflicting_lanes[la] = []
			for j in range(i + 1, incoming.size()):
				var lb: Lane = incoming[j]
				if _lanes_conflict(la, lb):
					conflicting_lanes[la].append(lb)
					if not conflicting_lanes.has(lb):
						conflicting_lanes[lb] = []
					conflicting_lanes[lb].append(la)

func _lanes_conflict(a: Lane, b: Lane) -> bool:
	for da in a.next_arcs:
		var arc_a: LaneArc = a.next_arcs[da]
		if not arc_a.enabled:
			continue
		for db in b.next_arcs:
			var arc_b: LaneArc = b.next_arcs[db]
			if not arc_b.enabled:
				continue
			if _arc_curves_conflict(arc_a.curve, arc_b.curve):
				return true
	return false

func _build_arc_conflicts() -> void:
	for arc in arcs:
		arc.conflicting_arcs.clear()
	for nid in arcs_by_node:
		var node_arcs: Array = arcs_by_node[nid]
		if node_arcs.is_empty():
			continue
		var first: LaneArc = node_arcs[0]
		if first.node != null and first.node.is_pass_through():
			continue
		for i in node_arcs.size():
			for j in range(i + 1, node_arcs.size()):
				var a: LaneArc = node_arcs[i]
				var b: LaneArc = node_arcs[j]
				if not a.enabled or not b.enabled:
					continue
				if a.from_lane == b.from_lane:
					continue
				if _arc_curves_conflict(a.curve, b.curve):
					a.conflicting_arcs.append(b)
					b.conflicting_arcs.append(a)

func _arc_curves_conflict(ca: Curve3D, cb: Curve3D) -> bool:
	var la: float = ca.get_baked_length()
	var lb: float = cb.get_baked_length()
	if la < 0.1 or lb < 0.1:
		return false
	var pts_a: Array[Vector3] = []
	for i in range(CONFLICT_SAMPLES + 1):
		var t: float = float(i) / float(CONFLICT_SAMPLES)
		pts_a.append(ca.sample_baked(t * la))
	for i in range(CONFLICT_SAMPLES + 1):
		var t: float = float(i) / float(CONFLICT_SAMPLES)
		var p: Vector3 = cb.sample_baked(t * lb)
		for q in pts_a:
			var d: float = Vector2(p.x - q.x, p.z - q.z).length()
			if d < CONFLICT_DIST:
				return true
	return false

func lanes_departing_from(node: RoadNode) -> Array[Lane]:
	var result: Array[Lane] = []
	for lane in lanes:
		if lane.from_node == node:
			result.append(lane)
	return result

func lanes_arriving_at(node: RoadNode) -> Array[Lane]:
	var result: Array[Lane] = []
	for lane in lanes:
		if lane.to_node == node:
			result.append(lane)
	return result
