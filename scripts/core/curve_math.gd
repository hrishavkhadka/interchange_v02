class_name CurveMath
extends RefCounted

# Slices a Curve3D between two baked distances (0.0 to length) and returns a new Curve3D.
static func slice(curve: Curve3D, start_dist: float, end_dist: float) -> Curve3D:
	var total_len := curve.get_baked_length()
	start_dist = clampf(start_dist, 0.0, total_len)
	end_dist = clampf(end_dist, 0.0, total_len)
	
	var new_curve := Curve3D.new()
	if end_dist <= start_dist:
		return new_curve
		
	# If the curve is a simple 2-point cubic Bezier (our base curves), use De Casteljau
	# to slice it perfectly into smaller cubic curves.
	if curve.point_count == 2:
		var p0 = curve.get_point_position(0)
		var p1 = p0 + curve.get_point_out(0)
		var p2 = curve.get_point_position(1) + curve.get_point_in(1)
		var p3 = curve.get_point_position(1)
		
		# Approximate t for the given distances (binary search)
		var t_start = _find_t_for_dist(curve, start_dist, total_len)
		var t_end = _find_t_for_dist(curve, end_dist, total_len)
		
		# 1. Split the curve at t_start
		var a = _de_casteljau(p0, p1, p2, p3, t_start)
		# The right half (a[4..7]) is the new sub-curve
		var b0 = a[4]
		var b1 = a[5]
		var b2 = a[6]
		var b3 = a[7]
		
		# 2. Normalize t_end relative to the new right half
		# (Note: t_end from original curve won't map perfectly 1:1 due to arc length distortion,
		# but for small segments, this is visually perfect. We re-approximate for precision).
		var t_sub_end = _find_t_for_dist_in_bezier(b0, b1, b2, b3, end_dist - start_dist)
		
		# 3. Split the right half at t_sub_end
		var b = _de_casteljau(b0, b1, b2, b3, t_sub_end)
		# The left half (b[0..3]) is our final slice
		new_curve.add_point(b[0], Vector3.ZERO, b[1] - b[0])
		new_curve.add_point(b[3], b[2] - b[3], Vector3.ZERO)
		return new_curve
		
	# Fallback for polylines (e.g. if a curve was already sampled)
	var slice_len := end_dist - start_dist
	var steps := maxi(4, int(slice_len / 2.0))
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var d := start_dist + t * slice_len
		var p := curve.sample_baked(d)
		if i == 0 or new_curve.point_count == 0 or p.distance_to(new_curve.get_point_position(new_curve.point_count - 1)) > 0.1:
			new_curve.add_point(p)
	return new_curve

static func _de_casteljau(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Array[Vector3]:
	var a0 = p0.lerp(p1, t)
	var a1 = p1.lerp(p2, t)
	var a2 = p2.lerp(p3, t)
	var b0 = a0.lerp(a1, t)
	var b1 = a1.lerp(a2, t)
	var c0 = b0.lerp(b1, t)
	return [p0, a0, b0, c0, c0, b1, a2, p3]

static func _find_t_for_dist(curve: Curve3D, dist: float, total_len: float) -> float:
	if dist <= 0.0: return 0.0
	if dist >= total_len: return 1.0
	# Simple binary search
	var lo := 0.0
	var hi := 1.0
	for _i in range(12):
		var mid := (lo + hi) * 0.5
		if curve.sample_baked(mid * total_len).distance_to(curve.sample_baked(dist)) < 0.01:
			break
		if curve.sample_baked(mid * total_len).distance_squared_to(curve.sample_baked(0)) < dist * dist:
			lo = mid
		else:
			hi = mid
	return (lo + hi) * 0.5

static func _find_t_for_dist_in_bezier(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, target_dist: float) -> float:
	var temp := Curve3D.new()
	temp.add_point(p0, Vector3.ZERO, p1 - p0)
	temp.add_point(p3, p2 - p3, Vector3.ZERO)
	return _find_t_for_dist(temp, target_dist, temp.get_baked_length())
