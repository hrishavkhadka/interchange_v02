class_name CurveMath
extends RefCounted

static func slice(curve: Curve3D, start_dist: float, end_dist: float) -> Curve3D:
	var total_len := curve.get_baked_length()
	start_dist = clampf(start_dist, 0.0, total_len)
	end_dist = clampf(end_dist, 0.0, total_len)
	
	var new_curve := Curve3D.new()
	if end_dist <= start_dist:
		return new_curve
		
	var p_start = curve.sample_baked(start_dist)
	var p_end = curve.sample_baked(end_dist)
	
	var dt = minf(0.1, (end_dist - start_dist) * 0.1)
	var p_start_forward = curve.sample_baked(minf(start_dist + dt, total_len))
	var p_end_backward = curve.sample_baked(maxf(end_dist - dt, 0.0))
	
	var tangent_start = (p_start_forward - p_start).normalized()
	var tangent_end = (p_end - p_end_backward).normalized()
	
	var slice_len = end_dist - start_dist
	var handle_start = tangent_start * slice_len / 3.0
	var handle_end = -tangent_end * slice_len / 3.0
	
	new_curve.add_point(p_start, Vector3.ZERO, handle_start)
	new_curve.add_point(p_end, handle_end, Vector3.ZERO)
	return new_curve
