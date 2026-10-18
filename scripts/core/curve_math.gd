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
		
	var slice_len := end_dist - start_dist
	# Sample every ~2 meters. Godot's Curve3D uses cubic interpolation between points,
	# so dense points perfectly recreate the original curve's shape.
	var steps := maxi(4, int(slice_len / 2.0))
	
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var d := start_dist + t * slice_len
		var p := curve.sample_baked(d)
		
		# We only need to add points. Godot will smooth it automatically.
		if i == 0 or new_curve.point_count == 0 or p.distance_to(new_curve.get_point_position(new_curve.point_count - 1)) > 0.1:
			new_curve.add_point(p)
			
	return new_curve
