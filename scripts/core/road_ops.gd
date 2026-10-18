class_name RoadOps
extends RefCounted

static func find_crossings(start: Vector3, end: Vector3) -> Array:
	var result: Array = []
	var a_start := Vector2(start.x, start.z)
	var a_end := Vector2(end.x, end.z)

	for seg in RoadGraph.segments:
		if seg.start_node == null or seg.end_node == null:
			continue
		var b_start3: Vector3 = seg.start_node.position
		var b_end3: Vector3 = seg.end_node.position

		if _near(b_start3, start) or _near(b_start3, end):
			continue
		if _near(b_end3, start) or _near(b_end3, end):
			continue

		var b_start := Vector2(b_start3.x, b_start3.z)
		var b_end := Vector2(b_end3.x, b_end3.z)

		var hit_raw: Variant = _seg_intersect_2d(a_start, a_end, b_start, b_end)
		if hit_raw == null:
			continue
		var hp: Vector2 = hit_raw
		var p3 := Vector3(hp.x, 0.0, hp.y)
		result.append({
			"point": p3,
			"segment": seg,
			"distance": a_start.distance_to(hp),
		})

	result.sort_custom(func(a, b): return a["distance"] < b["distance"])
	return result

static func find_segment_under_point(pos: Vector3) -> Variant:
	var best_dist := INF
	var best: Variant = null
	for seg in RoadGraph.segments:
		if seg.start_node == null or seg.end_node == null:
			continue
		if seg.road_type == null:
			continue
		var a := seg.start_node.position
		var b := seg.end_node.position
		if absf(a.y - pos.y) > 0.5 or absf(b.y - pos.y) > 0.5:
			continue
		var proj := _project_to_segment_xz(pos, a, b)
		var flat_dist := Vector2(proj.x - pos.x, proj.z - pos.z).length()
		var half_w := seg.road_type.total_width() * 0.5
		if flat_dist <= half_w and flat_dist < best_dist:
			best_dist = flat_dist
			best = { "segment": seg, "point": proj }
	return best

static func find_nearest_segment(pos: Vector3, radius: float) -> Variant:
	var best: Variant = null
	var best_dist := radius
	for seg in RoadGraph.segments:
		if seg.start_node == null or seg.end_node == null:
			continue
		if seg.road_type == null:
			continue
		var a := seg.start_node.position
		var b := seg.end_node.position
		if absf(a.y - pos.y) > 0.5 or absf(b.y - pos.y) > 0.5:
			continue
		var proj := _project_to_segment_xz(pos, a, b)
		var d := Vector2(proj.x - pos.x, proj.z - pos.z).length()
		if d < best_dist:
			best_dist = d
			best = { "segment": seg, "point": proj, "distance": d }
	return best

static func is_placement_valid(
		start: Vector3, end: Vector3,
		new_half_width: float,
		t_segments: Array,
		sharing_nodes: Array) -> bool:
	if start.distance_to(end) < 0.5:
		return false
	var a0 := Vector2(start.x, start.z)
	var a1 := Vector2(end.x, end.z)
	for seg in RoadGraph.segments:
		if seg.start_node == null or seg.end_node == null:
			continue
		if seg in t_segments:
			continue
		if seg.start_node in sharing_nodes or seg.end_node in sharing_nodes:
			continue
		var b_hw: float = seg.road_type.total_width() * 0.5
		var sa := seg.start_node.position
		var sb := seg.end_node.position
		var d := _seg_seg_min_dist_2d(
			a0, a1, Vector2(sa.x, sa.z), Vector2(sb.x, sb.z))
		if d < new_half_width + b_hw - 0.01:
			return false
	return true

static func _seg_seg_min_dist_2d(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if _seg_intersect_2d(a0, a1, b0, b1) != null:
		return 0.0
	var d1 := _point_seg_dist_2d(a0, b0, b1)
	var d2 := _point_seg_dist_2d(a1, b0, b1)
	var d3 := _point_seg_dist_2d(b0, a0, a1)
	var d4 := _point_seg_dist_2d(b1, a0, a1)
	return min(min(d1, d2), min(d3, d4))

static func _point_seg_dist_2d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_to(a + ab * t)

static func _project_to_segment_xz(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var pa := Vector2(a.x, a.z)
	var pb := Vector2(b.x, b.z)
	var pp := Vector2(p.x, p.z)
	var ab := pb - pa
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return a
	var t := clampf((pp - pa).dot(ab) / len_sq, 0.0, 1.0)
	var hit := pa + ab * t
	return Vector3(hit.x, a.y, hit.y)

static func _near(a: Vector3, b: Vector3, eps: float = 0.01) -> bool:
	return a.distance_to(b) < eps

static func _seg_intersect_2d(p1: Vector2, p2: Vector2, p3: Vector2, p4: Vector2) -> Variant:
	var d1 := p2 - p1
	var d2 := p4 - p3
	var denom := d1.x * d2.y - d1.y * d2.x
	if absf(denom) < 0.0001:
		return null
	var diff := p3 - p1
	var t := (diff.x * d2.y - diff.y * d2.x) / denom
	var u := (diff.x * d1.y - diff.y * d1.x) / denom
	if t < 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return null
	return p1 + d1 * t
	
static func find_lane_under_point(pos: Vector3) -> Variant:
	var best_dist := INF
	var best: Variant = null
	for lane in LaneGraph.lanes:
		if lane.length < 0.1:
			continue
		var proj := _project_to_curve_xz(pos, lane.curve, lane.length)
		var dist := Vector2(proj.x - pos.x, proj.z - pos.z).length()
		var half_w := lane.segment.road_type.lane_width * 0.5
		if dist <= half_w and dist < best_dist:
			best_dist = dist
			best = { "lane": lane, "segment": lane.segment, "point": proj }
	return best

static func _project_to_curve_xz(p: Vector3, curve: Curve3D, length: float) -> Vector3:
	var samples := 16
	var best_d := INF
	var best_t := 0.0
	for i in range(samples + 1):
		var t := float(i) / float(samples)
		var q := curve.sample_baked(t * length)
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < best_d:
			best_d = d
			best_t = t
	var step := 1.0 / float(samples)
	var lo := maxf(best_t - step, 0.0)
	var hi := minf(best_t + step, 1.0)
	for _i in range(8):
		var m1 := lerpf(lo, hi, 1.0 / 3.0)
		var m2 := lerpf(lo, hi, 2.0 / 3.0)
		var p1 := curve.sample_baked(m1 * length)
		var p2 := curve.sample_baked(m2 * length)
		var d1 := Vector2(p1.x - p.x, p1.z - p.z).length_squared()
		var d2 := Vector2(p2.x - p.x, p2.z - p.z).length_squared()
		if d1 < d2:
			hi = m2
		else:
			lo = m1
	return curve.sample_baked(((lo + hi) * 0.5) * length)
