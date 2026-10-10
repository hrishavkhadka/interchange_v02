class_name SnapResolver
extends RefCounted

const NODE_SNAP_RADIUS: float = 5.0
const WAYPOINT_SNAP_RADIUS: float = 2.0
const ANGLE_TOLERANCE_DEG: float = 9.0
const GUIDE_SNAP_RADIUS: float = 2.5

static func resolve_position(raw: Vector3, settings: BuildSettings, road_type: RoadType) -> Dictionary:
	if settings.snap_node:
		var n := RoadGraph.find_nearest(raw, NODE_SNAP_RADIUS)
		if n != null:
			var effective: float = WAYPOINT_SNAP_RADIUS if n.is_pass_through() else NODE_SNAP_RADIUS
			if n.position.distance_to(raw) <= effective:
				return { "point": n.position, "kind": "node", "t_segment": null, "guide_dir": null }

	if settings.snap_segment:
		var s: Variant = RoadOps.find_segment_under_point(raw)
		if s != null:
			var seg: RoadSegment = s["segment"]
			var p: Vector3 = s["point"]
			if p.distance_to(seg.start_node.position) > 1.0 \
					and p.distance_to(seg.end_node.position) > 1.0:
				return { "point": p, "kind": "segment", "t_segment": seg, "guide_dir": null }

	if settings.snap_guide and road_type != null:
		var snap_ticks: bool = settings.snap_length
		var gp: Variant = _try_guide_snap(raw, road_type.lane_width, snap_ticks)
		if gp != null:
			var g: Dictionary = gp
			var gpp: Vector3 = g["point"]
			var gd: Vector3 = g["dir"]
			return { "point": gpp, "kind": "guide", "t_segment": null, "guide_dir": gd }

	return { "point": raw, "kind": "free", "t_segment": null, "guide_dir": null }

static func _try_guide_snap(raw: Vector3, lane_w: float, snap_to_ticks: bool) -> Variant:
	var max_len: float = lane_w * 10.0
	var best_origin := Vector3.ZERO
	var best_dir := Vector3.ZERO
	var best_t: float = 0.0
	var best_dist: float = GUIDE_SNAP_RADIUS
	var found := false

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

			var dirs: Array[Vector3] = [-dir, perp, -perp]
			for dv in dirs:
				var dirv: Vector3 = dv
				var v: Vector3 = raw - node.position
				v.y = 0.0
				var t: float = v.dot(dirv)
				if t < 0.0:
					continue
				if t > max_len:
					t = max_len
				var pt: Vector3 = node.position + dirv * t
				var dist: float = Vector2(pt.x - raw.x, pt.z - raw.z).length()
				if dist < best_dist:
					best_dist = dist
					best_origin = node.position
					best_dir = dirv
					best_t = t
					found = true

	if not found:
		return null

	if snap_to_ticks:
		var snapped_t: float = roundf(best_t / lane_w) * lane_w
		if snapped_t < lane_w * 0.5:
			snapped_t = lane_w
		if snapped_t > max_len:
			snapped_t = max_len
		return { "point": best_origin + best_dir * snapped_t, "dir": best_dir }

	return { "point": best_origin + best_dir * best_t, "dir": best_dir }

static func resolve_direction(start: Vector3, end: Vector3, start_t_segment: Variant, start_guide_dir: Variant, settings: BuildSettings) -> Dictionary:
	var dir: Vector3 = end - start
	dir.y = 0.0
	if dir.length_squared() < 0.01:
		return { "point": end, "kind": "" }
	var length: float = dir.length()
	dir = dir.normalized()

	if settings.snap_angle:
		var ref_v: Variant = _angle_reference(start, start_t_segment, start_guide_dir, dir)
		var ref: Vector3 = ref_v
		var ref_angle: float = atan2(ref.z, ref.x)
		var step: float = deg_to_rad(settings.angle_step_deg)
		var current_angle: float = atan2(dir.z, dir.x)
		var rel: float = current_angle - ref_angle
		var snapped_rel: float = roundf(rel / step) * step
		var snapped_a: float = ref_angle + snapped_rel
		var ad: Vector3 = Vector3(cos(snapped_a), 0.0, sin(snapped_a))
		var dot: float = clampf(dir.dot(ad), -1.0, 1.0)
		var diff: float = rad_to_deg(acos(dot))
		if diff <= ANGLE_TOLERANCE_DEG:
			return { "point": start + ad * length, "kind": "angle" }

	return { "point": end, "kind": "" }

static func _angle_reference(start: Vector3, start_t_segment: Variant, start_guide_dir: Variant, drag_dir: Vector3) -> Variant:
	if start_t_segment != null:
		var d: Variant = _segment_dir(start_t_segment)
		if d != null:
			return d
	if start_guide_dir != null:
		var gd: Vector3 = start_guide_dir
		if gd.length_squared() > 0.5:
			return gd
	var node := RoadGraph.find_nearest(start, 1.0)
	if node != null and node.segment_ends.size() > 0:
		var best: Vector3 = Vector3.ZERO
		var best_dot: float = -2.0
		for entry in node.segment_ends:
			var e: Dictionary = entry
			var sv: Variant = e["segment"]
			if sv == null:
				continue
			var sdir: Variant = _segment_dir(sv)
			if sdir == null:
				continue
			var v: Vector3 = sdir
			var dot: float = absf(v.dot(drag_dir))
			if dot > best_dot:
				best_dot = dot
				best = v
		if best.length_squared() > 0.5:
			return best
	return Vector3(1.0, 0.0, 0.0)

static func _segment_dir(seg: Variant) -> Variant:
	if seg == null:
		return null
	var s: RoadSegment = seg
	if s.start_node == null or s.end_node == null:
		return null
	var d: Vector3 = s.end_node.position - s.start_node.position
	d.y = 0.0
	if d.length_squared() < 0.0001:
		return null
	return d.normalized()
