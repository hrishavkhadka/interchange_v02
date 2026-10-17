class_name Vehicle
extends Node3D

signal despawned

const LATERAL_SAMPLES: int = 16
const AVOID_SECONDS: float = 8.0
const STUCK_SPEED: float = 0.2
const STUCK_TIME: float = 2.5

var path: Array[PathStep] = []
var step_index: int = 0
var distance_on_step: float = 0.0
var speed: float = 0.0
var target_node: RoadNode
var length: float = 4.5
var color_seed: int = 0
var cooldown: float = 0.0
var avoid_lane: Lane = null
var avoid_timer: float = 0.0
var yield_timer: float = 0.0

var lateral_target_lane: Lane = null
var lateral_occupancy_start: float = 0.0
var lateral_occupancy_end: float = 0.0

var _saved_path: Array[PathStep] = []
var _saved_step_index: int = 0
var _saved_distance: float = 0.0
var _saved_avoid_lane: Lane = null
var _saved_avoid_timer: float = 0.0
var stuck_timer: float = 0.0

var _mesh: MeshInstance3D

func current_curve() -> Curve3D:
	if path.is_empty() or step_index >= path.size():
		return null
	return path[step_index].curve

func current_step_length() -> float:
	if path.is_empty() or step_index >= path.size():
		return 0.0
	return path[step_index].length

func current_lane() -> Lane:
	if path.is_empty() or step_index >= path.size():
		return null
	var s: PathStep = path[step_index]
	if not s.is_lane:
		return null
	return s.lane_ref

func current_step_is_lane() -> bool:
	if path.is_empty() or step_index >= path.size():
		return false
	return path[step_index].is_lane

func current_step_is_lateral() -> bool:
	if path.is_empty() or step_index >= path.size():
		return false
	var s: PathStep = path[step_index]
	return (not s.is_lane) and (s.arc_ref == null)

func desired_speed() -> float:
	if path.is_empty() or step_index >= path.size():
		return 0.0
	return path[step_index].speed

static func make_color(seed_value: int) -> Color:
	var palette: Array[Color] = [
		Color(0.85, 0.20, 0.20),
		Color(0.20, 0.45, 0.85),
		Color(0.95, 0.85, 0.20),
		Color(0.30, 0.75, 0.35),
		Color(0.85, 0.55, 0.20),
		Color(0.80, 0.80, 0.85),
		Color(0.30, 0.30, 0.35),
	]
	return palette[seed_value % palette.size()]

func setup(steps: Array[PathStep], t: RoadNode, seed_value: int, v0: float) -> void:
	path = steps
	target_node = t
	step_index = 0
	distance_on_step = path[0].start_dist
	speed = v0
	color_seed = seed_value
	cooldown = 0.0
	avoid_lane = null
	avoid_timer = 0.0
	yield_timer = 0.0
	lateral_target_lane = null
	lateral_occupancy_start = 0.0
	lateral_occupancy_end = 0.0
	_saved_path = []
	stuck_timer = 0.0

	_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.8, 1.4, 4.2)
	_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = make_color(seed_value)
	mat.roughness = 0.7
	_mesh.material_override = mat
	add_child(_mesh)

	_update_transform()

func occupancy_entries() -> Array:
	var result: Array = []
	var c := current_curve()
	if c != null:
		result.append({ "curve": c, "dist": distance_on_step })
	if lateral_target_lane != null:
		var f: float = 0.0
		var L: float = current_step_length()
		if L > 0.01:
			f = clampf(distance_on_step / L, 0.0, 1.0)
		var d: float = lateral_occupancy_start + f * (lateral_occupancy_end - lateral_occupancy_start)
		result.append({ "curve": lateral_target_lane.curve, "dist": d })
	return result

func begin_lane_change(
		target_lane: Lane,
		p_par: float,
		target_offset: float,
		subsequent: Array[PathStep],
		cooldown_seconds: float) -> void:
	var c_cur: Curve3D = current_curve()
	if c_cur == null:
		return
	var old_lane: Lane = current_lane()

	_saved_path = path.duplicate()
	_saved_step_index = step_index
	_saved_distance = distance_on_step
	_saved_avoid_lane = avoid_lane
	_saved_avoid_timer = avoid_timer

	var start_p: Vector3 = c_cur.sample_baked(distance_on_step)
	var t_off: float = clampf(target_offset, 0.0, target_lane.length)
	var end_p: Vector3 = target_lane.curve.sample_baked(t_off)

	var ahead_d: float = minf(distance_on_step + 2.0, current_step_length())
	var ahead_p: Vector3 = c_cur.sample_baked(ahead_d)
	var start_t: Vector3 = ahead_p - start_p
	start_t.y = 0.0
	if start_t.length_squared() < 0.001:
		start_t = Vector3.FORWARD
	start_t = start_t.normalized()

	var t_ahead_d: float = minf(t_off + 2.0, target_lane.length)
	var t_ahead_p: Vector3 = target_lane.curve.sample_baked(t_ahead_d)
	var end_t: Vector3 = t_ahead_p - end_p
	end_t.y = 0.0
	if end_t.length_squared() < 0.001:
		end_t = start_t
	end_t = end_t.normalized()

	var dist: float = start_p.distance_to(end_p)
	var handle: float = maxf(dist / 3.0, 2.0)
	var p1: Vector3 = start_p + start_t * handle
	var p2: Vector3 = end_p - end_t * handle

	var lat_curve := Curve3D.new()
	for i in range(LATERAL_SAMPLES + 1):
		var t: float = float(i) / float(LATERAL_SAMPLES)
		var p: Vector3 = _bezier3(start_p, p1, p2, end_p, t)
		lat_curve.add_point(p)

	var lat_step := PathStep.make(lat_curve, target_lane.speed_limit, false)

	var new_path: Array[PathStep] = []
	for i in range(step_index):
		new_path.append(path[i])
	new_path.append(lat_step)
	new_path.append_array(subsequent)
	path = new_path
	distance_on_step = 0.0
	cooldown = cooldown_seconds
	if old_lane != null:
		avoid_lane = old_lane
		avoid_timer = AVOID_SECONDS

	lateral_target_lane = target_lane
	lateral_occupancy_start = p_par
	lateral_occupancy_end = t_off
	stuck_timer = 0.0

func abort_lane_change() -> void:
	if _saved_path.is_empty():
		return
	path = _saved_path
	step_index = _saved_step_index
	distance_on_step = _saved_distance
	avoid_lane = _saved_avoid_lane
	avoid_timer = _saved_avoid_timer
	lateral_target_lane = null
	_saved_path = []
	stuck_timer = 0.0
	cooldown = 3.0

func complete_lane_change() -> void:
	_saved_path = []
	lateral_target_lane = null

func _despawn() -> void:
	despawned.emit()
	queue_free()

static func _bezier3(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return u*u*u*p0 + 3.0*u*u*t*p1 + 3.0*u*t*t*p2 + t*t*t*p3

func _update_transform() -> void:
	var c := current_curve()
	if c == null:
		return
	var L := current_step_length()
	var d: float = clampf(distance_on_step, 0.0, L)
	var p: Vector3 = c.sample_baked(d)
	var ahead_d: float = minf(d + 0.5, L)
	var ahead: Vector3 = c.sample_baked(ahead_d)
	global_position = p + Vector3(0.0, 0.75, 0.0)
	var dir: Vector3 = ahead - p
	dir.y = 0.0
	if dir.length_squared() > 0.01:
		look_at(global_position + dir.normalized(), Vector3.UP)
	else:
		print("[vehicle] v%d zero direction on step %d (curve len %.3f, dist %.3f)" % [
			color_seed, step_index, current_step_length(), distance_on_step])
