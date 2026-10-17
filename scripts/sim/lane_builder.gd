class_name LaneBuilder
extends RefCounted

const DELTA: float = 0.2
const MIN_ANGLE_DEG: float = 30.0
const BASE_TRIM_FACTOR: float = 1.5
const MAX_TRIM_FACTOR: float = 5.0

static func trim_factor_for_angle(interior_angle: float) -> float:
	var a: float = interior_angle
	var min_a: float = deg_to_rad(MIN_ANGLE_DEG)
	if a < min_a:
		a = min_a
	if a > PI - 0.001:
		a = PI - 0.001
	var f: float = 1.0 / tan(a * 0.5) + BASE_TRIM_FACTOR
	return clampf(f, 1.5, MAX_TRIM_FACTOR)

static func build_lane_curve(
		segment_curve: Curve3D,
		rt: RoadType,
		lane_index: int,
		direction: String,
		start_trim: float,
		end_trim: float) -> Curve3D:
	var total_length: float = segment_curve.get_baked_length()
	if total_length < 0.1:
		return null

	var max_trim: float = total_length * 0.45
	var trim_start: float = minf(start_trim, max_trim)
	var trim_end: float = minf(end_trim, max_trim)
	var usable: float = total_length - trim_start - trim_end
	if usable < 1.0:
		trim_start = 0.0
		trim_end = 0.0
		usable = total_length
	if usable < 0.1:
		return null

	var samples: int = maxi(6, int(usable * 0.5))
	var offset: float = rt.lane_right_offset(lane_index)

	var points: Array[Vector3] = []
	points.resize(samples + 1)
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var along: float = trim_start + t * usable
		var p: Vector3 = segment_curve.sample_baked(along)

		var prev_along: float = maxf(along - DELTA, 0.0)
		var next_along: float = minf(along + DELTA, total_length)
		var prev_p: Vector3 = segment_curve.sample_baked(prev_along)
		var next_p: Vector3 = segment_curve.sample_baked(next_along)

		var tangent: Vector3 = next_p - prev_p
		tangent.y = 0.0
		if tangent.length_squared() < 0.0001:
			tangent = next_p - p
			tangent.y = 0.0
		if tangent.length_squared() < 0.0001:
			tangent = p - prev_p
			tangent.y = 0.0
		if tangent.length_squared() < 0.0001:
			tangent = Vector3.FORWARD
		tangent = tangent.normalized()

		var right: Vector3 = tangent.cross(Vector3.UP)
		if right.length_squared() < 0.0001:
			right = Vector3.RIGHT
		right = right.normalized()

		points[i] = p + right * offset

	if direction == "B":
		points.reverse()

	var curve := Curve3D.new()
	for p in points:
		curve.add_point(p)
	return curve
