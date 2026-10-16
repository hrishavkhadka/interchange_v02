class_name VehicleManager
extends Node3D

@export var spawn_interval: float = 0.5
@export var spawn_clear_distance: float = 10.0
@export var max_vehicles: int = 200
@export var enable_lane_changes: bool = true

var debug_lane_changes: bool = false
var debug_vehicle_seed: int = -1
var _debug_tick: int = 0

const RNG_SEED: int = 987654321
const MAX_LEADER_LOOKAHEAD_STEPS: int = 4

const MAX_SPEED: float = 14.0
const ACCEL: float = 7.0
const DECEL: float = 7.0

const DF_C1: float = 0.5
const DF_C2: float = 0.5
const DF_C3: float = 1.0
const DF_BAND: float = 1.0
const TARGET_MARGIN: float = 2.0

const LC_BACK_C1: float = 0.7
const LC_BACK_C2: float = 5.0
const LC_FWD_C1: float = 0.7
const LC_FWD_C2: float = 6.0
const LC_COOLDOWN_RETURN: float = 3.0
const LC_COOLDOWN_ONWARD: float = 0.2
const LC_FORWARD_MIN: float = 9.0
const LC_FORWARD_TIME: float = 0.7

const APPROACH_DIST: float = 15.0
const COMMIT_DIST: float = 3.0
const CLEARANCE: float = 8.0
const JUNC_APPROACH_SPEED: float = 14.0
const STUCK_TIME: float = 8.0
const STUCK_NUDGE_SPEED: float = 2.0
const NUDGE_CLEAR_GAP: float = 5.0
const JUNCTION_ARRIVAL_COOLDOWN: float = 0.1

var _timer: float = 0.0
var _color_seed: int = 0
var _rng := RandomNumberGenerator.new()
var _vehicles: Array[Vehicle] = []
var _arc_claims: Dictionary = {}

# Spawn plan built at play start.
# entries: Array of { entry: RoadNode, exit: RoadNode, remaining: int }
var _spawn_plan: Array = []
var _used_marked_plan: bool = false

func _ready() -> void:
	_rng.seed = RNG_SEED
	LaneGraph.lanes_changed.connect(_on_lanes_changed)
	GameState.state_changed.connect(_on_state_changed)

func _on_lanes_changed() -> void:
	_clear_all_vehicles()

func _on_state_changed(s: int) -> void:
	if GameState.is_build():
		_clear_all_vehicles()
		_timer = 0.0
		_rng.seed = RNG_SEED
		_color_seed = 0
		_spawn_plan.clear()
		_used_marked_plan = false
	elif s == GameState.State.PLAYING and _spawn_plan.is_empty():
		# Fresh play start.
		_build_spawn_plan()

func _build_spawn_plan() -> void:
	_spawn_plan.clear()
	_used_marked_plan = false
	var entries: Array = []
	var exits: Array = []
	for n in RoadGraph.nodes:
		if n.segment_ends.size() != 1:
			continue
		if n.is_entry:
			entries.append(n)
		if n.is_exit:
			exits.append(n)
	if entries.is_empty():
		# Fallback: no explicit entries, spawn randomly until GameState.target_count.
		return
	_used_marked_plan = true
	var total: int = 0
	for e in entries:
		var entry: RoadNode = e
		for exit_id in entry.demand:
			var exit_node := _find_node_by_id(int(exit_id))
			if exit_node == null:
				continue
			if not exit_node.is_exit:
				continue
			var count: int = int(entry.demand[exit_id])
			if count <= 0:
				continue
			_spawn_plan.append({ "entry": entry, "exit": exit_node, "remaining": count })
			total += count
	if total <= 0:
		# Entries marked but no demand. Fall back to random exits.
		_used_marked_plan = false
		_spawn_plan.clear()
		return
	GameState.set_target(total)

func _find_node_by_id(nid: int) -> RoadNode:
	for n in RoadGraph.nodes:
		if n.id == nid:
			return n
	return null

func _clear_all_vehicles() -> void:
	for v in _vehicles:
		if is_instance_valid(v):
			v.queue_free()
	_vehicles.clear()
	_arc_claims.clear()

func _process(delta: float) -> void:
	if not GameState.is_playing():
		return
	_prune_dead()
	if GameState.spawned_count >= GameState.target_count:
		return
	if _vehicles.size() >= max_vehicles:
		return
	_timer += delta * GameState.speed_multiplier
	if _timer >= spawn_interval:
		_timer = 0.0
		_try_spawn()

func _physics_process(delta: float) -> void:
	if not GameState.is_playing():
		return
	var scaled: float = delta * GameState.speed_multiplier
	_prune_dead()
	var occ := _build_occupancy()
	_compute_arc_claims(occ)
	_debug_tick += 1
	for v in _vehicles:
		_step_vehicle(v, occ, scaled)
	for v in _vehicles:
		if is_instance_valid(v):
			v._update_transform()
	if debug_lane_changes and (_debug_tick % 120) == 0:
		_print_debug_summary()

func _print_debug_summary() -> void:
	var n_active: int = 0
	var n_lane: int = 0
	var n_arc: int = 0
	var n_lat: int = 0
	for v in _vehicles:
		if not is_instance_valid(v):
			continue
		n_active += 1
		if v.current_step_is_lateral():
			n_lat += 1
		elif v.current_lane() != null:
			n_lane += 1
		else:
			n_arc += 1
	print("[sim] active=%d lane_steps=%d arcs=%d lateral=%d claims=%d" % [
		n_active, n_lane, n_arc, n_lat, _arc_claims.size()])

func _prune_dead() -> void:
	var alive: Array[Vehicle] = []
	for v in _vehicles:
		if is_instance_valid(v):
			alive.append(v)
	_vehicles = alive

func _build_occupancy() -> Dictionary:
	var occ: Dictionary = {}
	for v in _vehicles:
		if not is_instance_valid(v):
			continue
		var entries: Array = v.occupancy_entries()
		for e in entries:
			var ed: Dictionary = e
			var curve: Curve3D = ed["curve"]
			var dist: float = ed["dist"]
			if not occ.has(curve):
				occ[curve] = []
			occ[curve].append({ "vehicle": v, "dist": dist })
	for k in occ:
		var arr: Array = occ[k]
		arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return a["dist"] < b["dist"])
	return occ

func _compute_arc_claims(occ: Dictionary) -> void:
	_arc_claims.clear()
	for v in _vehicles:
		if not is_instance_valid(v):
			continue
		var cur_arc := _current_arc(v)
		if cur_arc != null:
			_arc_claims[cur_arc] = cur_arc.from_lane
			continue
		if not v.current_step_is_lane():
			continue
		var room: float = v.current_step_length() - v.distance_on_step
		if room > COMMIT_DIST:
			continue
		var nxt := _next_arc(v)
		if nxt == null:
			continue
		if not _lane_l_clear(nxt.to_lane, occ):
			continue
		var blocked: bool = false
		for other in nxt.conflicting_arcs:
			if _arc_claims.has(other):
				blocked = true
				break
		if blocked:
			var alt := _find_alternate_arc(v, nxt, occ)
			if alt != null:
				_splice_alternate_arc(v, alt)
				nxt = alt
			else:
				continue
		_arc_claims[nxt] = nxt.from_lane

func _current_arc(v: Vehicle) -> LaneArc:
	if v.step_index >= v.path.size():
		return null
	var step: PathStep = v.path[v.step_index]
	if step.arc_ref != null:
		return step.arc_ref
	return null

func _next_arc(v: Vehicle) -> LaneArc:
	if v.step_index + 1 >= v.path.size():
		return null
	var step: PathStep = v.path[v.step_index + 1]
	if step.arc_ref != null:
		return step.arc_ref
	return null

func _lane_l_clear(lane: Lane, occ: Dictionary) -> bool:
	var lst: Array = occ.get(lane.curve, [])
	for e in lst:
		var ed: Dictionary = e
		var d: float = ed["dist"]
		if d < CLEARANCE:
			return false
	return true

func _find_alternate_arc(v: Vehicle, blocked_arc: LaneArc, occ: Dictionary) -> LaneArc:
	var from_lane: Lane = blocked_arc.from_lane
	var dest_segment = blocked_arc.to_lane.segment
	var dest_dir: String = blocked_arc.to_lane.direction
	for next_lane_v in from_lane.next_arcs:
		var next_lane: Lane = next_lane_v
		if next_lane == blocked_arc.to_lane:
			continue
		if next_lane.segment != dest_segment:
			continue
		if next_lane.direction != dest_dir:
			continue
		var alt: LaneArc = from_lane.next_arcs[next_lane]
		if alt == null or alt.length < 0.05 or not alt.enabled:
			continue
		if not _lane_l_clear(next_lane, occ):
			continue
		var alt_blocked: bool = false
		for other in alt.conflicting_arcs:
			if _arc_claims.has(other):
				alt_blocked = true
				break
		if alt_blocked:
			continue
		return alt
	return null

func _splice_alternate_arc(v: Vehicle, new_arc: LaneArc) -> void:
	var new_route: Array = LanePathfinder.find_path(new_arc.to_lane, v.target_node)
	if new_route.is_empty():
		return
	var kept: Array[PathStep] = []
	for i in range(v.step_index + 1):
		kept.append(v.path[i])
	var arc_speed: float = minf(new_arc.from_lane.speed_limit, new_arc.to_lane.speed_limit)
	var route_steps := _build_steps(new_route)
	var result: Array[PathStep] = []
	for s in kept:
		result.append(s)
	result.append(PathStep.make(new_arc.curve, arc_speed, false, null, 0.0, new_arc))
	for s in route_steps:
		result.append(s)
	v.path = result

func _step_vehicle(v: Vehicle, occ: Dictionary, delta: float) -> void:
	if not is_instance_valid(v):
		return

	if v.speed < Vehicle.STUCK_SPEED:
		v.stuck_timer += delta
		if v.current_step_is_lateral():
			if v.stuck_timer > Vehicle.STUCK_TIME:
				v.abort_lane_change()
				v.stuck_timer = 0.0
		else:
			if v.stuck_timer > STUCK_TIME:
				var nudge_leader: Variant = _find_leader(v, occ)
				if nudge_leader == null or nudge_leader["gap"] > NUDGE_CLEAR_GAP:
					v.speed = maxf(v.speed, STUCK_NUDGE_SPEED)
				v.stuck_timer = 0.0
	else:
		v.stuck_timer = 0.0

	v.cooldown = maxf(0.0, v.cooldown - delta)
	if v.avoid_timer > 0.0:
		v.avoid_timer = maxf(0.0, v.avoid_timer - delta)
		if v.avoid_timer <= 0.0:
			v.avoid_lane = null

	if enable_lane_changes and v.cooldown <= 0.0 and v.current_lane() != null:
		_maybe_lane_change(v, occ)

	var leader: Variant = _find_leader(v, occ)
	var target_from_leader: float = _compute_car_following_target(v, leader)
	var junc_cap: float = _junction_cap(v, occ)
	var target_speed: float = minf(target_from_leader, junc_cap)

	var accel: float = 0.0
	if target_speed > v.speed:
		accel = ACCEL
	elif target_speed < v.speed:
		accel = -DECEL
	v.speed = clampf(v.speed + accel * delta, 0.0, MAX_SPEED)

	_advance(v, v.speed * delta)

func _compute_car_following_target(v: Vehicle, leader: Variant) -> float:
	if leader == null:
		return MAX_SPEED
	var info: Dictionary = leader
	var lv: Vehicle = info["vehicle"]
	var gap: float = info["gap"]
	var self_speed: float = v.speed
	var lead_speed: float = lv.speed
	var df: float = (self_speed - lead_speed) * DF_C1 \
		+ maxf(self_speed, lead_speed) * DF_C2 \
		+ DF_C3
	if gap > df + DF_BAND:
		return MAX_SPEED
	if gap < df - DF_BAND:
		return maxf(0.0, lead_speed - TARGET_MARGIN)
	return lead_speed

func _junction_cap(v: Vehicle, occ: Dictionary) -> float:
	if not v.current_step_is_lane():
		return MAX_SPEED
	var room: float = v.current_step_length() - v.distance_on_step
	if room > APPROACH_DIST:
		return MAX_SPEED
	var nxt := _next_arc(v)
	if nxt == null:
		return MAX_SPEED
	if _arc_claims.has(nxt) and _arc_claims[nxt] == v.current_lane():
		return MAX_SPEED
	for other in nxt.conflicting_arcs:
		if _arc_claims.has(other):
			return 0.0
	if not _lane_l_clear(nxt.to_lane, occ):
		return 0.0
	if nxt.conflicting_arcs.size() > 0:
		return JUNC_APPROACH_SPEED
	return MAX_SPEED

func _advance(v: Vehicle, move: float) -> void:
	var safety: int = 0
	while move > 0.0 and safety < 8:
		safety += 1
		if v.step_index >= v.path.size():
			_despawn(v)
			return
		var step: PathStep = v.path[v.step_index]
		var remaining: float = step.length - v.distance_on_step
		if move < remaining:
			v.distance_on_step += move
			move = 0.0
		else:
			move -= remaining
			v.step_index += 1
			if v.step_index >= v.path.size():
				_despawn(v)
				return
			var new_step: PathStep = v.path[v.step_index]
			v.distance_on_step = new_step.start_dist
			if new_step.is_lane:
				v.complete_lane_change()
				v.cooldown = maxf(v.cooldown, JUNCTION_ARRIVAL_COOLDOWN)

func _despawn(v: Vehicle) -> void:
	if not is_instance_valid(v):
		return
	GameState.register_cleared()
	v._despawn()

func _maybe_lane_change(v: Vehicle, occ: Dictionary) -> void:
	var current: Lane = v.current_lane()
	if current == null:
		return
	var room: float = v.current_step_length() - v.distance_on_step
	if room < APPROACH_DIST:
		return
	if not _is_constrained(v, occ):
		return
	var next_lane: Variant = _next_route_lane(v)
	var eligible: Array = _eligible_lanes(current, next_lane)
	if eligible.size() < 2:
		return
	for lane_v in eligible:
		var target: Lane = lane_v
		if target == current:
			continue
		if target == v.avoid_lane:
			continue
		if _change_ok(v, target, occ):
			_execute_lane_change(v, target)
			return

func _is_constrained(v: Vehicle, occ: Dictionary) -> bool:
	var leader: Variant = _find_leader(v, occ)
	if leader == null:
		return false
	var info: Dictionary = leader
	var lv: Vehicle = info["vehicle"]
	var gap: float = info["gap"]
	var df: float = (v.speed - lv.speed) * DF_C1 \
		+ maxf(v.speed, lv.speed) * DF_C2 \
		+ DF_C3
	return gap < df + DF_BAND

func _eligible_lanes(current: Lane, next_lane: Variant) -> Array:
	var result: Array = []
	for lane in LaneGraph.lanes:
		if lane.segment != current.segment:
			continue
		if lane.direction != current.direction:
			continue
		if next_lane != null:
			var nl: Lane = next_lane
			if not lane.next_arcs.has(nl):
				continue
			var arc: LaneArc = lane.next_arcs[nl]
			if not arc.enabled:
				continue
		result.append(lane)
	return result

func _next_route_lane(v: Vehicle) -> Variant:
	for i in range(v.step_index + 1, v.path.size()):
		var step: PathStep = v.path[i]
		if step.arc_ref != null:
			if i + 1 < v.path.size():
				var ns: PathStep = v.path[i + 1]
				if ns.is_lane:
					return ns.lane_ref
			return null
	return null

func _change_ok(v: Vehicle, target: Lane, occ: Dictionary) -> bool:
	var p_par: float = _project_onto_lane(v.global_position, target)
	var lead: Variant = _leader_on_lane_at(target, p_par, occ)
	var lead_speed: float = 0.0
	if lead != null:
		var li: Dictionary = lead
		var lv: Vehicle = li["vehicle"]
		lead_speed = lv.speed
		var fwd_required: float = maxf(v.speed, lead_speed) * LC_FWD_C1 + LC_FWD_C2
		if li["gap"] < fwd_required:
			return false
	var fol: Variant = _follower_on_lane_at(target, p_par, occ)
	if fol != null:
		var fi: Dictionary = fol
		var fv: Vehicle = fi["vehicle"]
		var back_required: float = maxf(0.0, fv.speed - v.speed) * LC_BACK_C1 + LC_BACK_C2
		if fi["gap"] < back_required:
			return false
	return true

func _execute_lane_change(v: Vehicle, target_lane: Lane) -> void:
	var p_par: float = _project_onto_lane(v.global_position, target_lane)
	var lc_len: float = maxf(LC_FORWARD_MIN, v.speed * LC_FORWARD_TIME)
	var max_off: float = target_lane.length - 2.0
	if p_par + lc_len > max_off:
		lc_len = max_off - p_par
	if lc_len < 6.0:
		return
	var target_off: float = p_par + lc_len
	var remaining: Array = _remaining_lanes(v)
	if remaining.is_empty():
		return
	remaining[0] = target_lane
	var new_steps: Array[PathStep] = _build_steps_from_offset(remaining, target_off)
	if new_steps.is_empty():
		return
	v.begin_lane_change(target_lane, p_par, target_off, new_steps, LC_COOLDOWN_ONWARD)
	v.avoid_timer = LC_COOLDOWN_RETURN

func _remaining_lanes(v: Vehicle) -> Array:
	var result: Array = []
	for i in range(v.step_index, v.path.size()):
		var step: PathStep = v.path[i]
		if step.is_lane and step.lane_ref != null:
			result.append(step.lane_ref)
	return result

func _build_steps_from_offset(lanes: Array, offset: float) -> Array[PathStep]:
	var steps: Array[PathStep] = []
	for i in range(lanes.size()):
		var lane: Lane = lanes[i]
		if i == 0:
			var sd: float = clampf(offset, 0.0, lane.length - 0.5)
			if sd < 0.0:
				sd = 0.0
			steps.append(PathStep.make(lane.curve, lane.speed_limit, true, lane, sd))
		else:
			steps.append(PathStep.make(lane.curve, lane.speed_limit, true, lane))
		if i + 1 < lanes.size():
			var nxt: Lane = lanes[i + 1]
			if lane.next_arcs.has(nxt):
				var arc: LaneArc = lane.next_arcs[nxt]
				if arc != null and arc.enabled:
					var sp: float = minf(lane.speed_limit, nxt.speed_limit)
					steps.append(PathStep.make(arc.curve, sp, false, null, 0.0, arc))
	return steps

func _find_leader(v: Vehicle, occ: Dictionary) -> Variant:
	var c := v.current_curve()
	if c == null:
		return null
	var list: Array = occ.get(c, [])
	var idx: int = _binary_search_gt(list, v.distance_on_step)
	for k in range(idx, list.size()):
		var e: Dictionary = list[k]
		var other: Vehicle = e["vehicle"]
		if not is_instance_valid(other) or other == v:
			continue
		var d: float = e["dist"]
		var gap: float = (d - v.distance_on_step) - (v.length + other.length) * 0.5
		if gap < 0.0:
			gap = 0.0
		return { "vehicle": other, "gap": gap }
	var accum: float = v.current_step_length() - v.distance_on_step
	var max_walk: int = mini(v.step_index + MAX_LEADER_LOOKAHEAD_STEPS, v.path.size())
	for i in range(v.step_index + 1, max_walk):
		var step: PathStep = v.path[i]
		var lst: Array = occ.get(step.curve, [])
		for e2 in lst:
			var e2d: Dictionary = e2
			var other2: Vehicle = e2d["vehicle"]
			if not is_instance_valid(other2) or other2 == v:
				continue
			var d2: float = e2d["dist"]
			if d2 < step.start_dist:
				continue
			var gap2: float = accum + (d2 - step.start_dist) - (v.length + other2.length) * 0.5
			if gap2 < 0.0:
				gap2 = 0.0
			return { "vehicle": other2, "gap": gap2 }
		accum += step.length - step.start_dist
	return null

func _binary_search_gt(list: Array, dist: float) -> int:
	var lo: int = 0
	var hi: int = list.size()
	while lo < hi:
		var mid: int = (lo + hi) / 2
		var e: Dictionary = list[mid]
		if e["dist"] <= dist:
			lo = mid + 1
		else:
			hi = mid
	return lo

func _leader_on_lane_at(lane: Lane, dist: float, occ: Dictionary) -> Variant:
	var lst: Array = occ.get(lane.curve, [])
	for e in lst:
		var ed: Dictionary = e
		var ov: Vehicle = ed["vehicle"]
		if not is_instance_valid(ov):
			continue
		var d: float = ed["dist"]
		if d >= dist:
			var gap: float = d - dist - (ov.length + 4.5) * 0.5
			if gap < 0.0:
				gap = 0.0
			return { "vehicle": ov, "gap": gap }
	return null

func _follower_on_lane_at(lane: Lane, dist: float, occ: Dictionary) -> Variant:
	var lst: Array = occ.get(lane.curve, [])
	var best: Vehicle = null
	var best_d: float = -INF
	for e in lst:
		var ed: Dictionary = e
		var ov: Vehicle = ed["vehicle"]
		if not is_instance_valid(ov):
			continue
		var d: float = ed["dist"]
		if d < dist and d > best_d:
			best_d = d
			best = ov
	if best == null:
		return null
	var gap: float = dist - best_d - (best.length + 4.5) * 0.5
	if gap < 0.0:
		gap = 0.0
	return { "vehicle": best, "gap": gap }

static func _project_onto_lane(pos: Vector3, lane: Lane) -> float:
	var L: float = lane.length
	if L < 0.1:
		return 0.0
	var samples: int = 16
	var best_d: float = INF
	var best_t: float = 0.0
	for i in range(samples + 1):
		var t: float = float(i) / float(samples)
		var p: Vector3 = lane.curve.sample_baked(t * L)
		var d: float = Vector2(p.x - pos.x, p.z - pos.z).length_squared()
		if d < best_d:
			best_d = d
			best_t = t
	var step: float = 1.0 / float(samples)
	var lo: float = maxf(best_t - step, 0.0)
	var hi: float = minf(best_t + step, 1.0)
	for _i in range(8):
		var m1: float = lerpf(lo, hi, 1.0 / 3.0)
		var m2: float = lerpf(lo, hi, 2.0 / 3.0)
		var p1: Vector3 = lane.curve.sample_baked(m1 * L)
		var p2: Vector3 = lane.curve.sample_baked(m2 * L)
		var d1: float = Vector2(p1.x - pos.x, p1.z - pos.z).length_squared()
		var d2: float = Vector2(p2.x - pos.x, p2.z - pos.z).length_squared()
		if d1 < d2:
			hi = m2
		else:
			lo = m1
	return clampf(((lo + hi) * 0.5) * L, 0.0, L)

func _align_exit_lane(route: Array, target: RoadNode, pref_idx: int) -> Array:
	if route.size() < 2:
		return route
	var last: Lane = route[route.size() - 1]
	if last.lane_index == pref_idx:
		return route
	var second_last: Lane = route[route.size() - 2]
	for lane in LaneGraph.lanes:
		if lane.segment != last.segment:
			continue
		if lane.direction != last.direction:
			continue
		if lane.to_node != target:
			continue
		if lane.lane_index != pref_idx:
			continue
		if not second_last.next_arcs.has(lane):
			continue
		var new_route: Array = route.duplicate()
		new_route[new_route.size() - 1] = lane
		return new_route
	return route

func _dead_end_nodes() -> Dictionary:
	var all_dead: Array = []
	var entries: Array = []
	var exits: Array = []
	for node in RoadGraph.nodes:
		if node.segment_ends.size() != 1:
			continue
		all_dead.append(node)
		if node.is_entry:
			entries.append(node)
		if node.is_exit:
			exits.append(node)
	return { "all": all_dead, "entries": entries, "exits": exits }

func _try_spawn() -> void:
	if LaneGraph.lanes.is_empty():
		return
	if _vehicles.size() >= max_vehicles:
		return
	if _used_marked_plan:
		_try_spawn_from_plan()
	else:
		_try_spawn_fallback()

func _try_spawn_from_plan() -> void:
	# Pick a random pair with remaining > 0 and try to spawn.
	if _spawn_plan.is_empty():
		return
	# Build list of indices with remaining > 0.
	var valid: Array = []
	for i in _spawn_plan.size():
		var p: Dictionary = _spawn_plan[i]
		if p["remaining"] > 0:
			valid.append(i)
	if valid.is_empty():
		return
	# Shuffle so blocked pairs don't starve spawn.
	for i in range(valid.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var tmp = valid[i]
		valid[i] = valid[j]
		valid[j] = tmp
	for idx_v in valid:
		var idx: int = idx_v
		var pair: Dictionary = _spawn_plan[idx]
		var entry: RoadNode = pair["entry"]
		var exit_node: RoadNode = pair["exit"]
		if _try_spawn_pair(entry, exit_node):
			pair["remaining"] = int(pair["remaining"]) - 1
			return

func _try_spawn_pair(entry: RoadNode, exit_node: RoadNode) -> bool:
	var source_lanes: Array = LaneGraph.lanes_departing_from(entry)
	if source_lanes.is_empty():
		return false
	var best_lane: Lane = null
	var best_route: Array = []
	var best_count: int = 999999
	for lane_v in source_lanes:
		var lane: Lane = lane_v
		var r: Array = LanePathfinder.find_path(lane, exit_node)
		if r.is_empty():
			continue
		var c: int = _count_at_lane_start(lane)
		if c < best_count:
			best_count = c
			best_lane = lane
			best_route = r
	if best_lane == null:
		return false
	if not _start_lane_is_clear(best_lane):
		return false
	best_route = _align_exit_lane(best_route, exit_node, best_lane.lane_index)
	var steps: Array[PathStep] = _build_steps(best_route)
	if steps.is_empty():
		return false
	var v := Vehicle.new()
	add_child(v)
	v.setup(steps, exit_node, _color_seed, 0.0)
	_vehicles.append(v)
	_color_seed += 1
	GameState.register_spawn()
	return true

func _try_spawn_fallback() -> void:
	var de := _dead_end_nodes()
	var all_dead: Array = de["all"]
	var entries: Array = de["entries"]
	var exits: Array = de["exits"]
	if all_dead.size() < 2:
		return
	var sources: Array = entries if entries.size() > 0 else all_dead
	var targets: Array = exits if exits.size() > 0 else all_dead
	if sources.is_empty() or targets.is_empty():
		return
	var source: RoadNode = sources[_rng.randi_range(0, sources.size() - 1)]
	var valid_targets: Array = []
	for t in targets:
		if t != source:
			valid_targets.append(t)
	if valid_targets.is_empty():
		return
	var target: RoadNode = valid_targets[_rng.randi_range(0, valid_targets.size() - 1)]

	var source_lanes: Array = LaneGraph.lanes_departing_from(source)
	if source_lanes.is_empty():
		return

	var best_lane: Lane = null
	var best_route: Array = []
	var best_count: int = 999999
	for lane_v in source_lanes:
		var lane: Lane = lane_v
		var r: Array = LanePathfinder.find_path(lane, target)
		if r.is_empty():
			continue
		var c: int = _count_at_lane_start(lane)
		if c < best_count:
			best_count = c
			best_lane = lane
			best_route = r

	if best_lane == null:
		return
	if not _start_lane_is_clear(best_lane):
		return
	best_route = _align_exit_lane(best_route, target, best_lane.lane_index)

	var steps: Array[PathStep] = _build_steps(best_route)
	if steps.is_empty():
		return

	var v := Vehicle.new()
	add_child(v)
	v.setup(steps, target, _color_seed, 0.0)
	_vehicles.append(v)
	_color_seed += 1
	GameState.register_spawn()

func _count_at_lane_start(lane: Lane) -> int:
	var count: int = 0
	for v in _vehicles:
		if not is_instance_valid(v):
			continue
		if v.current_curve() != lane.curve:
			continue
		count += 1
	return count

func _start_lane_is_clear(lane: Lane) -> bool:
	for v in _vehicles:
		if not is_instance_valid(v):
			continue
		var c := v.current_curve()
		if c != lane.curve:
			continue
		if v.distance_on_step < spawn_clear_distance:
			return false
	return true

func _build_steps(lanes: Array) -> Array[PathStep]:
	if debug_lane_changes:
		for i in range(lanes.size()):
			var lane: Lane = lanes[i]
			if i + 1 < lanes.size():
				var nxt: Lane = lanes[i + 1]
				if lane.next_arcs.has(nxt):
					var arc: LaneArc = lane.next_arcs[nxt]
					if arc != null and arc.enabled and arc.length < 1.0:
						print("[path] arc %d->%d is only %.3f m long" % [
							lane.lane_index, nxt.lane_index, arc.length])
	var steps: Array[PathStep] = []
	for i in range(lanes.size()):
		var lane: Lane = lanes[i]
		steps.append(PathStep.make(lane.curve, lane.speed_limit, true, lane))
		if i + 1 < lanes.size():
			var nxt: Lane = lanes[i + 1]
			if lane.next_arcs.has(nxt):
				var arc: LaneArc = lane.next_arcs[nxt]
				if arc != null and arc.enabled:
					var sp: float = minf(lane.speed_limit, nxt.speed_limit)
					steps.append(PathStep.make(arc.curve, sp, false, null, 0.0, arc))
	return steps
