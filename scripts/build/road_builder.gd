class_name RoadBuilder
extends Node3D

signal cost_changed(total_cost: float)
signal road_type_changed(index: int, name: String)

enum Mode { POINTER = 0, ROAD = 1, DEMOLISH = 2, REVERSE = 3, UPDATE = 4, MOVE = 7 }
enum BuildStage { NONE, STRAIGHT_END, CURVE_MID, CURVE_END, SCURVE_MID1, SCURVE_MID2, SCURVE_END }

const MIN_BEND_DOT: float = 0.87
const WAYPOINT_SPACING_LANES: float = 30.0
const DEMOLISH_PICK_RADIUS: float = 3.5
const WAYPOINT_ABSORB_RADIUS: float = 5.0

const ROAD_TYPE_DEFS := [
	{ "id": "f",        "name": "1-lane one-way",  "layout": "F" },
	{ "id": "ff",       "name": "2-lane one-way",  "layout": "FF" },
	{ "id": "fff",      "name": "3-lane one-way",  "layout": "FFF" },
	{ "id": "ffff",     "name": "4-lane one-way",  "layout": "FFFF" },
	{ "id": "fffff",    "name": "5-lane one-way",  "layout": "FFFFF" },
	{ "id": "ffffff",   "name": "6-lane one-way",  "layout": "FFFFFF" },
	{ "id": "fb",       "name": "1+1 two-way",     "layout": "FB" },
	{ "id": "ffb",      "name": "2+1",             "layout": "FFB" },
	{ "id": "fffb",     "name": "3+1",             "layout": "FFFB" },
	{ "id": "ffffb",    "name": "4+1",             "layout": "FFFFB" },
	{ "id": "ffbb",     "name": "2+2",             "layout": "FFBB" },
	{ "id": "fffbb",    "name": "3+2",             "layout": "FFFBB" },
	{ "id": "ffffbb",   "name": "4+2",             "layout": "FFFFBB" },
	{ "id": "fffbbb",   "name": "3+3",             "layout": "FFFBBB" },
	{ "id": "ffffbbb",  "name": "4+3",             "layout": "FFFFBBB" },
	{ "id": "fffffbb",  "name": "5+2",             "layout": "FFFFFBB" },
]

@export var road_type: RoadType
@export var level_half_size: float = 150.0

var settings: BuildSettings = BuildSettings.new()
var mode: int = Mode.ROAD

var _stage: BuildStage = BuildStage.NONE
var _p_start := Vector3.ZERO
var _p_end := Vector3.ZERO
var _p_mid1 := Vector3.ZERO
var _p_mid2 := Vector3.ZERO
var _start_t_segment: Variant = null
var _start_guide_dir: Variant = null
var _end_t_segment: Variant = null

var _preview: RoadSegment
var _segments: Array[RoadSegment] = []
var _snap_indicator: SnapIndicator
var _start_indicator: SnapIndicator
var _guidelines: Guidelines

var _hovered_segment: RoadSegment = null

var _move_selected_node: RoadNode = null
var _move_selected_segment: RoadSegment = null
var _move_is_dragging: bool = false
var _move_drag_target: String = "" # "node", "handle", "segment"
var _move_drag_segment: RoadSegment = null
var _move_drag_node_side: bool = false # true if start, false if end
var _move_drag_start_mouse: Vector3 = Vector3.ZERO
var _move_drag_start_node_pos: Vector3 = Vector3.ZERO
var _move_drag_start_handles: Dictionary = {}

var _move_backup_curves: Dictionary = {}
var _move_backup_nodes: Dictionary = {}
var _move_gizmos: Array[MeshInstance3D] = []

@onready var _preview_root: Node3D = $PreviewRoot
@onready var _segments_root: Node3D = $SegmentsRoot

func _ready() -> void:
	_snap_indicator = SnapIndicator.new()
	_snap_indicator.name = "SnapIndicator"
	add_child(_snap_indicator)
	_start_indicator = SnapIndicator.new()
	_start_indicator.name = "StartIndicator"
	add_child(_start_indicator)
	_guidelines = Guidelines.new()
	_guidelines.name = "Guidelines"
	add_child(_guidelines)

func set_road_type_index(i: int) -> void:
	if i < 0 or i >= ROAD_TYPE_DEFS.size():
		return
	var d: Dictionary = ROAD_TYPE_DEFS[i]
	var rt := RoadType.new()
	rt.id = d["id"]
	rt.display_name = d["name"]
	rt.lane_layout_string = d["layout"]
	rt.lane_width = 3.2
	rt.speed_limit_kmh = 50.0
	road_type = rt
	road_type_changed.emit(i, d["name"])

func set_mode(m: int) -> void:
	if m == mode:
		return
	if _stage != BuildStage.NONE:
		_cancel()
	_exit_hover_mode()
	mode = m
	if mode != Mode.ROAD:
		if _snap_indicator != null: _snap_indicator.hide_indicator()
		if _start_indicator != null: _start_indicator.hide_indicator()
		if _guidelines != null: _guidelines.clear()
	if mode == Mode.MOVE:
		_move_is_dragging = false
		_move_selected_node = null
		_move_selected_segment = null
		_update_move_gizmos()
	else:
		_clear_move_gizmos()

func _process(_dt: float) -> void:
	if not GameState.is_build(): return
	if mode == Mode.ROAD:
		if _stage != BuildStage.NONE: _update()
		else: _update_hover()
	elif mode == Mode.MOVE:
		if not _move_is_dragging: _move_hover()
	elif mode in [Mode.DEMOLISH, Mode.REVERSE, Mode.UPDATE]:
		_demolish_hover()

func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_build(): return
	
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mode == Mode.ROAD: _handle_left_click()
				elif mode == Mode.DEMOLISH: _demolish_click()
				elif mode == Mode.REVERSE: _reverse_click()
				elif mode == Mode.UPDATE: _update_click()
				elif mode == Mode.MOVE: _move_click_pressed()
			else:
				if mode == Mode.MOVE: _move_click_released()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode == Mode.MOVE:
				_move_selected_node = null
				_move_selected_segment = null
				_update_move_gizmos()
			elif _stage != BuildStage.NONE:
				_cancel()
	elif event is InputEventMouseMotion and mode == Mode.MOVE and _move_is_dragging:
		_move_drag_update()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE:
			if mode == Mode.MOVE:
				_move_selected_node = null
				_move_selected_segment = null
				_update_move_gizmos()
			elif _stage != BuildStage.NONE:
				_cancel()

func _handle_left_click() -> void:
	if _stage == BuildStage.NONE:
		_start_drag()
	elif _stage == BuildStage.STRAIGHT_END:
		_click_end_straight()
	elif _stage == BuildStage.CURVE_MID:
		_click_curve_mid()
	elif _stage == BuildStage.CURVE_END:
		_click_curve_end()
	elif _stage == BuildStage.SCURVE_MID1:
		_click_scurve_mid1()
	elif _stage == BuildStage.SCURVE_MID2:
		_click_scurve_mid2()
	elif _stage == BuildStage.SCURVE_END:
		_commit_scurve_preview()

func total_cost() -> float:
	var t := 0.0
	for s in RoadGraph.segments:
		if is_instance_valid(s): t += s.cost()
	return t

# ---------------------------------------------------------------- states

func _start_drag() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	var r := SnapResolver.resolve_position(hit, settings, road_type)
	
	_p_start = r["point"]
	_start_t_segment = r["t_segment"]
	_start_guide_dir = r["guide_dir"] if r.has("guide_dir") else null
	_end_t_segment = null
	
	if settings.road_shape == BuildSettings.RoadShape.STRAIGHT:
		_stage = BuildStage.STRAIGHT_END
	elif settings.road_shape == BuildSettings.RoadShape.CURVE:
		_stage = BuildStage.CURVE_MID
	else:
		_stage = BuildStage.SCURVE_MID1
		
	_start_indicator.show_at(_p_start)
	_preview = RoadSegment.new()
	_preview_root.add_child(_preview)
	_preview.visible = false

func _click_end_straight() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var r := _resolve_end(hit_raw, _p_start, _start_t_segment, _start_guide_dir)
	_p_end = r["point"]
	_end_t_segment = r["t_segment"]
	
	if _p_start.distance_to(_p_end) < road_type.lane_width: return
	var curve := _two_point_curve(_p_start, _p_end)
	if not _is_placement_valid(_p_start, _p_end, _start_t_segment, _end_t_segment, curve): return
	
	_stage = BuildStage.NONE
	_destroy_preview()
	_snap_indicator.hide_indicator()
	_start_indicator.hide_indicator()
	_guidelines.clear()
	
	if _start_t_segment != null:
		var seg_after_start: Variant = _absorb_chain(_start_t_segment, _p_start)
		if seg_after_start != null: _split_existing_segment(seg_after_start, _p_start)
		
	var end_seg: Variant = null
	var reloc: Variant = RoadOps.find_segment_under_point(_p_end)
	if reloc != null: end_seg = reloc["segment"]
	if end_seg != null:
		var seg_after_end: Variant = _absorb_chain(end_seg, _p_end)
		if seg_after_end != null: _split_existing_segment(seg_after_end, _p_end)

	var start_node := RoadGraph.get_or_create(_p_start)
	var end_node := RoadGraph.get_or_create(_p_end)
	_start_t_segment = null
	_start_guide_dir = null
	if start_node == end_node: return
	_create_chain(start_node, end_node, road_type)
	cost_changed.emit(total_cost())

func _click_curve_mid() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	var r := _resolve_end(hit, _p_start, _start_t_segment, _start_guide_dir)
	_p_mid1 = r["point"]
	
	if _p_start.distance_to(_p_mid1) < road_type.lane_width: return
	_stage = BuildStage.CURVE_END

func _click_curve_end() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var r := _resolve_end(hit_raw, _p_mid1, null, null)
	_p_end = r["point"]
	_end_t_segment = r["t_segment"]
	
	if _p_start.distance_to(_p_end) < road_type.lane_width: return
	var curve := _build_c_curve(_p_start, _p_mid1, _p_end)
	if not _is_placement_valid(_p_start, _p_end, _start_t_segment, _end_t_segment, curve): return
	
	var t_targets: Array = []
	if _start_t_segment != null: t_targets.append(_start_t_segment)
	if _end_t_segment != null: t_targets.append(_end_t_segment)
	var sharing := _sharing_nodes(_p_start, _p_end, t_targets)
	_commit_curve_data(curve, _p_start, _p_end, t_targets, sharing, false)

func _click_scurve_mid1() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	var r := _resolve_end(hit, _p_start, _start_t_segment, _start_guide_dir)
	_p_mid1 = r["point"]
	_stage = BuildStage.SCURVE_MID2

func _click_scurve_mid2() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	var r := _resolve_end(hit, _p_mid1, null, null)
	_p_mid2 = r["point"]
	_stage = BuildStage.SCURVE_END

func _commit_scurve_preview() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var r := _resolve_end(hit_raw, _p_mid2, null, null)
	_p_end = r["point"]
	_end_t_segment = r["t_segment"]
	
	if _p_start.distance_to(_p_end) < road_type.lane_width: return
	var curve := _build_s_curve(_p_start, _p_mid1, _p_mid2, _p_end)
	if not _is_placement_valid(_p_start, _p_end, _start_t_segment, _end_t_segment, curve): return
	
	var t_targets: Array = []
	if _start_t_segment != null: t_targets.append(_start_t_segment)
	if _end_t_segment != null: t_targets.append(_end_t_segment)
	var sharing := _sharing_nodes(_p_start, _p_end, t_targets)
	_commit_curve_data(curve, _p_start, _p_end, t_targets, sharing, true)

func _commit_curve_data(curve: Curve3D, start_pos: Vector3, end_pos: Vector3, t_targets: Array, sharing: Array, is_s_curve: bool) -> void:
	_stage = BuildStage.NONE
	_destroy_preview()
	_snap_indicator.hide_indicator()
	_start_indicator.hide_indicator()
	_guidelines.clear()
	
	if _start_t_segment != null:
		var seg_after_start: Variant = _absorb_chain(_start_t_segment, start_pos)
		if seg_after_start != null: _split_existing_segment(seg_after_start, start_pos)
		
	var end_seg: Variant = null
	var reloc: Variant = RoadOps.find_segment_under_point(end_pos)
	if reloc != null: end_seg = reloc["segment"]
	if end_seg != null:
		var seg_after_end: Variant = _absorb_chain(end_seg, end_pos)
		if seg_after_end != null: _split_existing_segment(seg_after_end, end_pos)

	var start_node := RoadGraph.get_or_create(start_pos)
	var end_node := RoadGraph.get_or_create(end_pos)
	_start_t_segment = null
	_start_guide_dir = null
	if start_node == end_node: return
	
	# Rebuild the curve using the exact snapped node positions.
	# This guarantees the mesh perfectly aligns with the nodes (Fixes A1/A2/A3).
	if is_s_curve:
		curve = _build_s_curve(start_node.position, _p_mid1, _p_mid2, end_node.position)
	else:
		curve = _build_c_curve(start_node.position, _p_mid1, end_node.position)
	
	var length := curve.get_baked_length()
	var target_step := road_type.lane_width * 16.0
	var count := maxi(1, int(round(length / target_step)))
	var actual_step := length / float(count)
	
	if count == 1:
		_create_segment_with_curve(start_node, end_node, road_type, curve)
	else:
		var prev_node := start_node
		for i in range(1, count + 1):
			if i == count:
				_create_segment_with_curve(prev_node, end_node, road_type, CurveMath.slice(curve, (i-1)*actual_step, length))
			else:
				var pos := curve.sample_baked(i * actual_step)
				var mid := RoadGraph.get_or_create(pos, true, true)
				_create_segment_with_curve(prev_node, mid, road_type, CurveMath.slice(curve, (i-1)*actual_step, i*actual_step))
				prev_node = mid
				
	cost_changed.emit(total_cost())
	_cleanup_degenerate_segments()

func _update() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	_guidelines.update(hit, road_type)
	
	if _stage == BuildStage.STRAIGHT_END:
		var final := _resolve_end(hit, _p_start, _start_t_segment, _start_guide_dir)
		var preview_end: Vector3 = final["point"]
		if _p_start.distance_to(preview_end) < road_type.lane_width:
			_preview.visible = false
			_snap_indicator.hide_indicator()
			return
		_preview.visible = true
		_preview.setup(road_type, _two_point_curve(_p_start, preview_end))
		_validate_preview(_p_start, preview_end, _start_t_segment, final["t_segment"])
		_snap_indicator.show_at(preview_end)
		
	elif _stage == BuildStage.CURVE_MID:
		var final := _resolve_end(hit, _p_start, _start_t_segment, _start_guide_dir)
		var preview_mid: Vector3 = final["point"]
		if _p_start.distance_to(preview_mid) < road_type.lane_width:
			_preview.visible = false
			_snap_indicator.hide_indicator()
			return
		_preview.visible = true
		_preview.setup(road_type, _two_point_curve(_p_start, preview_mid))
		_validate_preview(_p_start, preview_mid, _start_t_segment, final["t_segment"])
		_snap_indicator.show_at(preview_mid)
		
	elif _stage == BuildStage.CURVE_END:
		var final := _resolve_end(hit, _p_mid1, null, null)
		var preview_end: Vector3 = final["point"]
		if _p_start.distance_to(preview_end) < road_type.lane_width:
			_preview.visible = false
			_snap_indicator.hide_indicator()
			return
		_preview.visible = true
		_preview.setup(road_type, _build_c_curve(_p_start, _p_mid1, preview_end))
		_validate_preview(_p_start, preview_end, _start_t_segment, final["t_segment"])
		_snap_indicator.show_at(preview_end)
		
	elif _stage == BuildStage.SCURVE_MID1:
		var final := _resolve_end(hit, _p_start, _start_t_segment, _start_guide_dir)
		var preview_end: Vector3 = final["point"]
		if _p_start.distance_to(preview_end) < road_type.lane_width:
			_preview.visible = false
			_snap_indicator.hide_indicator()
			return
		_preview.visible = true
		_preview.setup(road_type, _two_point_curve(_p_start, preview_end))
		_validate_preview(_p_start, preview_end, _start_t_segment, final["t_segment"])
		_snap_indicator.show_at(preview_end)

	elif _stage == BuildStage.SCURVE_MID2:
		var final := _resolve_end(hit, _p_mid1, null, null)
		_p_mid2 = final["point"]
		var curve := _build_s_curve(_p_start, _p_mid1, _p_mid2, _p_mid2)
		_preview.visible = true
		_preview.setup(road_type, curve)
		_validate_preview(_p_start, _p_mid2, _start_t_segment, null)
		_snap_indicator.show_at(_p_mid2)

	elif _stage == BuildStage.SCURVE_END:
		var final := _resolve_end(hit, _p_mid2, null, null)
		var preview_end: Vector3 = final["point"]
		if _p_start.distance_to(preview_end) < road_type.lane_width:
			_preview.visible = false
			_snap_indicator.hide_indicator()
			return
		_p_end = preview_end
		var curve := _build_s_curve(_p_start, _p_mid1, _p_mid2, _p_end)
		_preview.visible = true
		_preview.setup(road_type, curve)
		_validate_preview(_p_start, _p_end, _start_t_segment, final["t_segment"])
		_snap_indicator.show_at(_p_end)

func _validate_preview(start: Vector3, end: Vector3, t_start: Variant, t_end: Variant) -> void:
	if _preview == null or _preview.curve == null: return
	var valid := _is_placement_valid(start, end, t_start, t_end, _preview.curve)
	_preview.set_preview_validity(valid)

func _cancel() -> void:
	_stage = BuildStage.NONE
	_start_t_segment = null
	_start_guide_dir = null
	_destroy_preview()
	if _snap_indicator != null: _snap_indicator.hide_indicator()
	if _start_indicator != null: _start_indicator.hide_indicator()
	if _guidelines != null: _guidelines.clear()

# ---------------------------------------------------------------- math

func _build_c_curve(p0: Vector3, p1: Vector3, p2: Vector3) -> Curve3D:
	# p0 = P (start), p1 = Q (mid-click), p2 = R (end)
	var c := Curve3D.new()
	
	# J falls on the PQ line. K falls on the QR line.
	var t := 0.55228475
	var j := p0.lerp(p1, t) 
	var k := p2.lerp(p1, t)
	
	# The curve starts at P, pulled towards J.
	# The curve ends at R, pulled from K.
	c.add_point(p0, Vector3.ZERO, j - p0)
	c.add_point(p2, k - p2, Vector3.ZERO)
	return c

func _build_s_curve(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(p0, Vector3.ZERO, p1 - p0)
	c.add_point(p3, p2 - p3, Vector3.ZERO)
	return c

# ---------------------------------------------------------------- utils

func _update_hover() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null:
		if _snap_indicator != null: _snap_indicator.hide_indicator()
		if _guidelines != null: _guidelines.clear()
		return
	var hit: Vector3 = hit_raw
	if _guidelines != null: _guidelines.update(hit, road_type)
	var r := SnapResolver.resolve_position(hit, settings, road_type)
	var kind: String = r["kind"]
	var rp: Vector3 = r["point"]
	if kind == "lane":
		_snap_indicator.show_at(rp, Color(0.2, 1.0, 0.4))
	else:
		_snap_indicator.show_at(rp)

func _exit_hover_mode() -> void:
	if _hovered_segment != null and is_instance_valid(_hovered_segment):
		_hovered_segment.set_hovered(false)
	_hovered_segment = null

func _demolish_hover() -> void:
	var seg := _find_segment_under_cursor()
	if seg == _hovered_segment: return
	if _hovered_segment != null and is_instance_valid(_hovered_segment):
		_hovered_segment.set_hovered(false)
	_hovered_segment = seg
	if _hovered_segment != null:
		_hovered_segment.set_hovered(true)

func _demolish_click() -> void:
	var seg := _find_segment_under_cursor()
	if seg == null: return
	if _segment_is_protected(seg): return
	if _hovered_segment == seg: _hovered_segment = null
	_remove_segment_and_cleanup(seg)
	cost_changed.emit(total_cost())

func _segment_is_protected(seg: RoadSegment) -> bool:
	if seg.start_node != null and (seg.start_node.is_entry or seg.start_node.is_exit): return true
	if seg.end_node != null and (seg.end_node.is_entry or seg.end_node.is_exit): return true
	return false

func _reverse_click() -> void:
	var seg := _find_segment_under_cursor()
	if seg == null: return
	seg.reverse()
	RoadGraph.graph_changed.emit()
	_rebuild_neighbours(seg.start_node, seg)
	_rebuild_neighbours(seg.end_node, seg)

func _update_click() -> void:
	var seg := _find_segment_under_cursor()
	if seg == null: return
	if road_type == null or seg.road_type == null: return
	if seg.road_type.lane_layout_string == road_type.lane_layout_string \
			and is_equal_approx(seg.road_type.lane_width, road_type.lane_width) \
			and is_equal_approx(seg.road_type.speed_limit_kmh, road_type.speed_limit_kmh):
		return
	seg.setup(road_type, seg.curve)
	_clear_node_arc_overrides(seg.start_node)
	_clear_node_arc_overrides(seg.end_node)
	RoadGraph.graph_changed.emit()
	_rebuild_neighbours(seg.start_node, seg)
	_rebuild_neighbours(seg.end_node, seg)
	cost_changed.emit(total_cost())

func _clear_node_arc_overrides(node: RoadNode) -> void:
	if node == null: return
	ArcOverrides.clear_node_overrides(node)

func _find_segment_under_cursor() -> RoadSegment:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return null
	var hit: Vector3 = hit_raw
	var best: RoadSegment = null
	var best_dist: float = DEMOLISH_PICK_RADIUS
	for s in RoadGraph.segments:
		if not is_instance_valid(s): continue
		if s.curve == null or s.road_type == null: continue
		
		var length: float = s.curve.get_baked_length()
		
		# If length is extremely small, just use the node position
		if length < 0.1:
			if s.start_node != null:
				var d: float = Vector2(s.start_node.position.x - hit.x, s.start_node.position.z - hit.z).length()
				if d < best_dist:
					best_dist = d
					best = s
			continue
			
		var samples: int = maxi(2, int(length * 0.5))
		for i in range(samples + 1):
			var t: float = float(i) / float(samples)
			var p: Vector3 = s.curve.sample_baked(t * length)
			var d: float = Vector2(p.x - hit.x, p.z - hit.z).length()
			if d < best_dist:
				best_dist = d
				best = s
	return best

func _remove_segment_and_cleanup(seg: RoadSegment) -> void:
	if not is_instance_valid(seg): return
	var sn := seg.start_node
	var en := seg.end_node
	_detach_and_remove(seg)
	var removed_any: bool = false
	if _cleanup_node(sn): removed_any = true
	if _cleanup_node(en): removed_any = true
	if removed_any: RoadGraph.graph_changed.emit()

func _cleanup_node(node: RoadNode) -> bool:
	if node == null: return false
	if node.segment_ends.size() > 0: return false
	RoadGraph.nodes.erase(node)
	return true

func _resolve_end(raw: Vector3, origin: Vector3, origin_t_seg: Variant, origin_guide: Variant = null) -> Dictionary:
	var pos_r := SnapResolver.resolve_position(raw, settings, road_type)
	var kind: String = pos_r["kind"]
	var pos: Vector3 = pos_r["point"]
	var t_seg: Variant = pos_r["t_segment"]
	var dir_kind: String = ""
	if kind == "free":
		var dir_r := SnapResolver.resolve_direction(origin, pos, origin_t_seg, origin_guide, settings)
		pos = dir_r["point"]
		dir_kind = dir_r["kind"]
	return { "point": pos, "kind": kind, "t_segment": t_seg, "direction_kind": dir_kind }
	
func _would_sharp_bend(start: Vector3, end: Vector3, start_t_segment: Variant, end_t_segment: Variant) -> bool:
	var new_dir: Vector3 = end - start
	new_dir.y = 0.0
	if new_dir.length_squared() < 0.01: return false
	new_dir = new_dir.normalized()
	if _endpoint_blocked(start, new_dir, start_t_segment): return true
	if _endpoint_blocked(end, -new_dir, end_t_segment): return true
	return false

func _endpoint_blocked(pos: Vector3, out_dir: Vector3, t_segment: Variant) -> bool:
	if t_segment != null:
		var s: RoadSegment = t_segment
		if s.start_node != null:
			var d1_v: Vector3 = s.start_node.position - pos
			d1_v.y = 0.0
			if d1_v.length_squared() > 0.01:
				var d1: Vector3 = d1_v.normalized()
				if out_dir.dot(d1) > MIN_BEND_DOT: return true
		if s.end_node != null:
			var d2_v: Vector3 = s.end_node.position - pos
			d2_v.y = 0.0
			if d2_v.length_squared() > 0.01:
				var d2: Vector3 = d2_v.normalized()
				if out_dir.dot(d2) > MIN_BEND_DOT: return true
	var node := RoadGraph.find_nearest(pos, 1.0)
	if node == null: return false
	for entry in node.segment_ends:
		var e: Dictionary = entry
		var seg_v: Variant = e["segment"]
		if seg_v == null: continue
		var seg: RoadSegment = seg_v
		if seg == t_segment: continue
		var other: Vector3
		if e["is_start"]:
			if seg.end_node == null: continue
			other = seg.end_node.position
		else:
			if seg.start_node == null: continue
			other = seg.start_node.position
		var outward_v: Vector3 = other - node.position
		outward_v.y = 0.0
		if outward_v.length_squared() < 0.01: continue
		var outward: Vector3 = outward_v.normalized()
		if out_dir.dot(outward) > MIN_BEND_DOT: return true
	return false

func _sharing_nodes(start: Vector3, end: Vector3, t_targets: Array = []) -> Array:
	var result: Array = []
	var ns := RoadGraph.find_nearest(start, 1.0)
	if ns != null: result.append(ns)
	var ne := RoadGraph.find_nearest(end, 1.0)
	if ne != null: result.append(ne)
	for t in t_targets:
		var ts: RoadSegment = t
		if ts == null: continue
		if ts.start_node != null and not (ts.start_node in result): result.append(ts.start_node)
		if ts.end_node != null and not (ts.end_node in result): result.append(ts.end_node)
	return result

func _destroy_preview() -> void:
	if _preview != null:
		_preview.queue_free()
		_preview = null

func _two_point_curve(a: Vector3, b: Vector3) -> Curve3D:
	var c := Curve3D.new()
	c.add_point(a)
	c.add_point(b)
	return c

func _absorb_chain(seg: Variant, pos: Vector3) -> Variant:
	var current: Variant = seg
	var safety: int = 0
	while safety < 8:
		safety += 1
		var w := _find_absorb_waypoint(current, pos)
		if w == null: return current
		var merged: Variant = _absorb_waypoint(w)
		if merged == null: return null
		current = merged
	return current

func _find_absorb_waypoint(seg: Variant, pos: Vector3) -> RoadNode:
	if seg == null: return null
	if not (seg is RoadSegment): return null
	var s: RoadSegment = seg
	var candidates: Array = []
	if s.start_node != null and s.start_node.is_pass_through(): candidates.append(s.start_node)
	if s.end_node != null and s.end_node.is_pass_through(): candidates.append(s.end_node)
	for w_v in candidates:
		var w: RoadNode = w_v
		var d: float = w.position.distance_to(pos)
		if d > 0.5 and d <= WAYPOINT_ABSORB_RADIUS: return w
	return null

func _absorb_waypoint(w: RoadNode) -> RoadSegment:
	if w == null: return null
	if not w.is_pass_through(): return null
	if w.segment_ends.size() != 2: return null
	var seg_a: RoadSegment = w.segment_ends[0]["segment"]
	var seg_b: RoadSegment = w.segment_ends[1]["segment"]
	if seg_a == null or seg_b == null: return null
	if not is_instance_valid(seg_a) or not is_instance_valid(seg_b): return null
	
	var a_is_start: bool = w.segment_ends[0]["is_start"]
	var other_a: RoadNode = seg_a.end_node if a_is_start else seg_a.start_node
	var b_is_start: bool = w.segment_ends[1]["is_start"]
	var other_b: RoadNode = seg_b.end_node if b_is_start else seg_b.start_node
	if other_a == null or other_b == null: return null
	
	var rt: RoadType = seg_a.road_type
	if seg_b.road_type != null:
		if rt == null or seg_b.road_type.lane_count() > rt.lane_count(): rt = seg_b.road_type
	
	# Check if either segment actually has curvature (non-zero handles)
	var is_curved := _segment_has_curve(seg_a) or _segment_has_curve(seg_b)
	
	var a_from_out := Vector3.ZERO
	var a_to_in := Vector3.ZERO
	var b_from_out := Vector3.ZERO
	var b_to_in := Vector3.ZERO
	
	if is_curved:
		var a_info := _get_segment_handles(seg_a, other_a, w)
		var b_info := _get_segment_handles(seg_b, w, other_b)
		a_from_out = a_info["from_out"]
		a_to_in = a_info["to_in"]
		b_from_out = b_info["from_out"]
		b_to_in = b_info["to_in"]
	
	_detach_and_remove(seg_a)
	_detach_and_remove(seg_b)
	var w_pos := w.position
	RoadGraph.nodes.erase(w)
	
	if is_curved:
		# Build a 3-point curve: other_a → w → other_b, preserving tangents.
		# Then _split_existing_segment slices it at _p_start, effectively
		# moving the waypoint smoothly to the new click position.
		var curve := Curve3D.new()
		curve.add_point(other_a.position, Vector3.ZERO, a_from_out)
		curve.add_point(w_pos, a_to_in, b_from_out)
		curve.add_point(other_b.position, b_to_in, Vector3.ZERO)
		return _create_segment_with_curve(other_a, other_b, rt, curve)
	
	return _create_segment(other_a, other_b, rt)

func _segment_has_curve(seg: RoadSegment) -> bool:
	if seg.curve == null or seg.curve.point_count < 2: return false
	var n := seg.curve.point_count - 1
	return seg.curve.get_point_out(0).length_squared() > 0.001 \
		or seg.curve.get_point_in(n).length_squared() > 0.001

func _get_segment_handles(seg: RoadSegment, from_node: RoadNode, to_node: RoadNode) -> Dictionary:
	var c := seg.curve
	var n := c.point_count - 1
	if from_node == seg.start_node:
		return {
			"from_out": c.get_point_out(0),
			"to_in": c.get_point_in(n),
		}
	else:
		return {
			"from_out": -c.get_point_in(n),
			"to_in": -c.get_point_out(0),
		}

func _create_chain(start_node: RoadNode, end_node: RoadNode, rt: RoadType) -> void:
	if start_node == end_node: return
	var dir: Vector3 = end_node.position - start_node.position
	var length: float = dir.length()
	if length < 0.1: return
	dir = dir.normalized()
	var step: float = rt.lane_width * WAYPOINT_SPACING_LANES
	var count: int = maxi(1, int(ceil(length / step)))
	if count == 1:
		_create_segment(start_node, end_node, rt)
		return
	var prev: RoadNode = start_node
	for i in range(1, count + 1):
		if i == count:
			_create_segment(prev, end_node, rt)
		else:
			var pos: Vector3 = start_node.position + dir * (length * float(i) / float(count))
			var mid := RoadGraph.get_or_create_waypoint(pos)
			_create_segment(prev, mid, rt)
			prev = mid

func _create_segment(start_node: RoadNode, end_node: RoadNode, rt: RoadType) -> RoadSegment:
	if start_node == end_node: return null
	var seg := RoadSegment.new()
	seg.start_node = start_node
	seg.end_node = end_node
	seg.setup(rt, _two_point_curve(start_node.position, end_node.position))
	start_node.add_segment_end(seg, true)
	end_node.add_segment_end(seg, false)
	_segments_root.add_child(seg)
	_segments.append(seg)
	RoadGraph.register_segment(seg)
	_rebuild_neighbours(start_node, seg)
	_rebuild_neighbours(end_node, seg)
	seg.rebuild_mesh()
	return seg

func _create_segment_with_curve(start_node: RoadNode, end_node: RoadNode, rt: RoadType, c: Curve3D) -> RoadSegment:
	if start_node == end_node: return null
	var seg := RoadSegment.new()
	seg.start_node = start_node
	seg.end_node = end_node
	seg.setup(rt, c)
	start_node.add_segment_end(seg, true)
	end_node.add_segment_end(seg, false)
	_segments_root.add_child(seg)
	_segments.append(seg)
	RoadGraph.register_segment(seg)
	_rebuild_neighbours(start_node, seg)
	_rebuild_neighbours(end_node, seg)
	seg.rebuild_mesh()
	return seg

func _rebuild_neighbours(node: RoadNode, exclude: RoadSegment) -> void:
	if node == null: return
	for entry in node.segment_ends:
		var e: Dictionary = entry
		var s: RoadSegment = e["segment"]
		if s == exclude: continue
		if is_instance_valid(s): s.rebuild_mesh()

func _split_existing_segment(seg: RoadSegment, at: Vector3) -> void:
	if not is_instance_valid(seg): return
	var old_start := seg.start_node
	var old_end := seg.end_node
	var rt := seg.road_type
	
	var length := seg.curve.get_baked_length()
	var res := RoadOps._get_closest_point_on_curve(at, seg.curve, length)
	var split_point: Vector3 = res["point"]
	var bake_dist: float = res["bake"]
	
	if bake_dist < 0.1 or bake_dist > length - 0.1: return
	
	_detach_and_remove(seg)
	var mid := RoadGraph.get_or_create(split_point, false, true)
	
	_create_segment_with_curve(old_start, mid, rt, CurveMath.slice(seg.curve, 0, bake_dist))
	_create_segment_with_curve(mid, old_end, rt, CurveMath.slice(seg.curve, bake_dist, length))

func _detach_and_remove(seg: RoadSegment) -> void:
	var sn := seg.start_node
	var en := seg.end_node
	_remove_end_from(sn, seg)
	_remove_end_from(en, seg)
	RoadGraph.unregister_segment(seg)
	_segments.erase(seg)
	if is_instance_valid(seg): seg.queue_free()
	if sn != null:
		for entry in sn.segment_ends:
			var e: Dictionary = entry
			var s: RoadSegment = e["segment"]
			if is_instance_valid(s): s.rebuild_mesh()
	if en != null:
		for entry in en.segment_ends:
			var e: Dictionary = entry
			var s: RoadSegment = e["segment"]
			if is_instance_valid(s): s.rebuild_mesh()

func _remove_end_from(node: RoadNode, seg: RoadSegment) -> void:
	if node == null: return
	var filtered: Array = []
	for e in node.segment_ends:
		if e["segment"] != seg: filtered.append(e)
	node.segment_ends = filtered

func _ground_hit() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null: return null
	var m := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(m)
	var dir := cam.project_ray_normal(m)
	var plane := Plane(Vector3.UP, 0.0)
	var hit_raw: Variant = plane.intersects_ray(from, dir)
	if hit_raw == null: return null
	var hit: Vector3 = hit_raw
	hit.x = clampf(hit.x, -level_half_size, level_half_size)
	hit.z = clampf(hit.z, -level_half_size, level_half_size)
	return hit

func _get_min_radius(curve: Curve3D) -> float:
	var min_r := INF
	var length := curve.get_baked_length()
	var steps := 24 # Enough to catch tight curves
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var r := _get_radius_at(curve, t)
		if r < min_r:
			min_r = r
	return min_r

func _get_radius_at(curve: Curve3D, t: float) -> float:
	var dt := 0.01
	var t0 := clampf(t - dt, 0.0, 1.0)
	var t1 := clampf(t + dt, 0.0, 1.0)
	
	var p0 := curve.sample_baked(t0 * curve.get_baked_length())
	var p1 := curve.sample_baked(t * curve.get_baked_length())
	var p2 := curve.sample_baked(t1 * curve.get_baked_length())
	
	p0.y = 0.0
	p1.y = 0.0
	p2.y = 0.0
	
	var v1 := p1 - p0
	var v2 := p2 - p1
	var len1 := v1.length()
	var len2 := v2.length()
	if len1 < 0.001 or len2 < 0.001:
		return INF
		
	v1 = v1.normalized()
	v2 = v2.normalized()
	
	var dot := clampf(v1.dot(v2), -1.0, 1.0)
	var angle := acos(dot)
	if angle < 0.001:
		return INF # Straight line, infinite radius
		
	var avg_len := (len1 + len2) * 0.5
	return avg_len / angle

func _is_placement_valid(start: Vector3, end: Vector3, t_start: Variant, t_end: Variant, curve: Curve3D) -> bool:
	var t_targets: Array = []
	if t_start != null: t_targets.append(t_start)
	if t_end != null: t_targets.append(t_end)
	var sharing := _sharing_nodes(start, end, t_targets)
	var hw: float = road_type.total_width() * 0.5
	var valid := RoadOps.is_placement_valid(start, end, hw, t_targets, sharing)
	if valid and _would_sharp_bend(start, end, t_start, t_end):
		valid = false
	if valid and curve != null:
		var min_r := _get_min_radius(curve)
		var req_r := hw + (1.5 * road_type.lane_width)
		if min_r < req_r:
			valid = false
	return valid

func _cleanup_degenerate_segments() -> void:
	var to_remove: Array[RoadSegment] = []
	for s in RoadGraph.segments:
		if not is_instance_valid(s): continue
		# If the segment has zero length, it's an invisible remnant
		if s.curve.get_baked_length() < 0.1:
			to_remove.append(s)
	for s in to_remove:
		_remove_segment_and_cleanup(s)

# ---------------------------------------------------------------- move it tool

func _move_hover() -> void:
	if _move_is_dragging: return
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	
	# If we have a selection, check if we are hovering over the entity itself
	if _move_selected_node != null:
		if hit.distance_to(_move_selected_node.position) < 2.0:
			# Optional: could highlight the node here
			pass

func _move_click_pressed() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	
	# 1. Check if clicking a handle
	if _move_selected_node != null:
		for entry in _move_selected_node.segment_ends:
			var seg = entry["segment"]
			var is_start = entry["is_start"]
			var last = seg.curve.point_count - 1
			var handle_pos = Vector3.ZERO
			if is_start: handle_pos = _move_selected_node.position + seg.curve.get_point_out(0)
			else: handle_pos = _move_selected_node.position + seg.curve.get_point_in(last)
			if hit.distance_to(handle_pos) < 2.0:
				_start_move_drag("handle", seg, is_start, hit)
				return
	elif _move_selected_segment != null:
		var seg = _move_selected_segment
		var last = seg.curve.point_count - 1
		if hit.distance_to(seg.start_node.position + seg.curve.get_point_out(0)) < 2.0:
			_start_move_drag("handle", seg, true, hit)
			return
		if hit.distance_to(seg.end_node.position + seg.curve.get_point_in(last)) < 2.0:
			_start_move_drag("handle", seg, false, hit)
			return

	# 2. Check if clicking selected node or segment to drag
	if _move_selected_node != null and hit.distance_to(_move_selected_node.position) < 2.0:
		_start_move_drag("node", null, false, hit)
		return
	if _move_selected_segment != null:
		var res = RoadOps._get_closest_point_on_curve(hit, _move_selected_segment.curve, _move_selected_segment.curve.get_baked_length())
		if res["dist"] < 2.0:
			_start_move_drag("segment", _move_selected_segment, false, hit)
			return

	# 3. Selection
	var best_node = RoadGraph.find_nearest(hit, 5.0)
	if best_node != null:
		_move_selected_node = best_node
		_move_selected_segment = null
		_update_move_gizmos()
		return
		
	var best_seg_res = RoadOps.find_nearest_segment(hit, 10.0)
	if best_seg_res != null:
		_move_selected_segment = best_seg_res["segment"]
		_move_selected_node = null
		_update_move_gizmos()
		return

	# 4. Deselect
	_move_selected_node = null
	_move_selected_segment = null
	_update_move_gizmos()

func _start_move_drag(target_type: String, target_seg: RoadSegment, is_start: bool, mouse_hit: Vector3) -> void:
	_move_is_dragging = true
	_move_drag_target = target_type
	_move_drag_segment = target_seg
	_move_drag_node_side = is_start
	_move_drag_start_mouse = mouse_hit
	
	_move_backup_curves.clear()
	_move_backup_nodes.clear()
	_move_drag_start_handles.clear()
	
	if target_type == "node":
		_move_drag_start_node_pos = _move_selected_node.position
		_move_backup_nodes[_move_selected_node] = _move_selected_node.position
		for entry in _move_selected_node.segment_ends:
			var s = entry["segment"]
			_move_backup_curves[s] = s.curve.duplicate()
	elif target_type == "handle":
		_move_backup_curves[_move_drag_segment] = _move_drag_segment.curve.duplicate()
		if Input.is_key_pressed(KEY_ALT):
			var other_seg = _find_other_segment_at_node(_move_drag_segment, _move_drag_node_side)
			if other_seg != null:
				_move_backup_curves[other_seg] = other_seg.curve.duplicate()
	elif target_type == "segment":
		_move_backup_curves[_move_drag_segment] = _move_drag_segment.curve.duplicate()
		var last = _move_drag_segment.curve.point_count - 1
		_move_drag_start_handles[_move_drag_segment] = {
			"out": _move_drag_segment.curve.get_point_out(0),
			"in": _move_drag_segment.curve.get_point_in(last)
		}

func _move_drag_update() -> void:
	if not _move_is_dragging: return
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null: return
	var hit: Vector3 = hit_raw
	
	if _move_drag_target == "node":
		var delta = hit - _move_drag_start_mouse
		var new_pos = _move_drag_start_node_pos + delta
		_move_selected_node.position = new_pos
		
		for entry in _move_selected_node.segment_ends:
			var s = entry["segment"]
			var is_start = entry["is_start"]
			var last = s.curve.point_count - 1
			if is_start:
				s.curve.set_point_position(0, new_pos)
				s.curve.set_point_out(0, s.curve.get_point_out(0) + delta)
			else:
				s.curve.set_point_position(last, new_pos)
				s.curve.set_point_in(last, s.curve.get_point_in(last) + delta)
			s.rebuild_mesh()
			
	elif _move_drag_target == "handle":
		var node_pos = _move_drag_segment.start_node.position if _move_drag_node_side else _move_drag_segment.end_node.position
		var last = _move_drag_segment.curve.point_count - 1
		var cur_handle = _move_drag_segment.curve.get_point_out(0) if _move_drag_node_side else _move_drag_segment.curve.get_point_in(last)
		var length = cur_handle.length()
		
		var dir = (hit - node_pos).normalized()
		var new_handle = dir * length
		
		if _move_drag_node_side:
			_move_drag_segment.curve.set_point_out(0, new_handle)
		else:
			_move_drag_segment.curve.set_point_in(last, new_handle)
		_move_drag_segment.rebuild_mesh()
		
		# Alt mirror
		if Input.is_key_pressed(KEY_ALT):
			var other_seg = _find_other_segment_at_node(_move_drag_segment, _move_drag_node_side)
			if other_seg != null:
				var o_last = other_seg.curve.point_count - 1
				var o_handle = other_seg.curve.get_point_in(o_last) if _move_drag_node_side else other_seg.curve.get_point_out(0)
				var o_len = o_handle.length()
				var o_dir = -dir
				if _move_drag_node_side:
					other_seg.curve.set_point_in(o_last, o_dir * o_len)
				else:
					other_seg.curve.set_point_out(0, o_dir * o_len)
				other_seg.rebuild_mesh()
				
	elif _move_drag_target == "segment":
		var s = _move_drag_segment
		var p0 = s.start_node.position
		var p3 = s.end_node.position
		var chord = p3 - p0
		var chord_dir = chord.normalized()
		var perp = Vector3(-chord_dir.z, 0, chord_dir.x)
		
		var to_mouse = hit - p0
		var offset = to_mouse.dot(perp)
		
		var start_handles = _move_drag_start_handles[s]
		var orig_offset = start_handles["out"].dot(perp)
		
		var delta_offset = offset - orig_offset
		var h_offset = perp * delta_offset * 1.5
		
		var last = s.curve.point_count - 1
		s.curve.set_point_out(0, start_handles["out"] + h_offset)
		s.curve.set_point_in(last, start_handles["in"] - h_offset)
		s.rebuild_mesh()

func _move_click_released() -> void:
	if not _move_is_dragging: return
	_move_is_dragging = false
	
	var moved_segments: Array = []
	for s in _move_backup_curves.keys():
		moved_segments.append(s)
		
	if _is_move_valid(moved_segments):
		# Accept changes
		RoadGraph.graph_changed.emit()
		cost_changed.emit(total_cost())
	else:
		# Revert
		for n in _move_backup_nodes.keys():
			n.position = _move_backup_nodes[n]
		for s in _move_backup_curves.keys():
			s.setup(s.road_type, _move_backup_curves[s])
			
		RoadGraph.graph_changed.emit()
		cost_changed.emit(total_cost())
		
	_move_backup_curves.clear()
	_move_backup_nodes.clear()
	_move_drag_start_handles.clear()
	_update_move_gizmos()

func _is_move_valid(moved_segments: Array) -> bool:
	for s1 in moved_segments:
		var hw1 = s1.road_type.total_width() * 0.5
		var len1 = s1.curve.get_baked_length()
		var steps1 = maxi(4, int(len1 / 5.0))
		
		for s2 in RoadGraph.segments:
			if s1 == s2 or s2 in moved_segments: continue
			var hw2 = s2.road_type.total_width() * 0.5
			var len2 = s2.curve.get_baked_length()
			var steps2 = maxi(4, int(len2 / 5.0))
			
			for i in range(steps1):
				var a0 = s1.curve.sample_baked((float(i)/steps1) * len1)
				var a1 = s1.curve.sample_baked((float(i+1)/steps1) * len1)
				for j in range(steps2):
					var b0 = s2.curve.sample_baked((float(j)/steps2) * len2)
					var b1 = s2.curve.sample_baked((float(j+1)/steps2) * len2)
					var d = RoadOps._seg_seg_min_dist_2d(
						Vector2(a0.x, a0.z), Vector2(a1.x, a1.z),
						Vector2(b0.x, b0.z), Vector2(b1.x, b1.z)
					)
					if d < hw1 + hw2 - 0.01:
						return false
	return true

func _find_other_segment_at_node(seg: RoadSegment, is_start: bool) -> RoadSegment:
	var node = seg.start_node if is_start else seg.end_node
	if node == null: return null
	for entry in node.segment_ends:
		var s = entry["segment"]
		if s != seg:
			return s
	return null

func _update_move_gizmos() -> void:
	_clear_move_gizmos()
	
	if _move_selected_node != null:
		_add_gizmo(_move_selected_node.position, Color.GREEN, 1.0)
		for entry in _move_selected_node.segment_ends:
			var seg = entry["segment"]
			var is_start = entry["is_start"]
			var last = seg.curve.point_count - 1
			if is_start:
				_add_gizmo(_move_selected_node.position + seg.curve.get_point_out(0), Color.CYAN, 0.5)
			else:
				_add_gizmo(_move_selected_node.position + seg.curve.get_point_in(last), Color.CYAN, 0.5)
				
	elif _move_selected_segment != null:
		var last = _move_selected_segment.curve.point_count - 1
		_add_gizmo(_move_selected_segment.start_node.position, Color.GREEN, 1.0)
		_add_gizmo(_move_selected_segment.end_node.position, Color.GREEN, 1.0)
		_add_gizmo(_move_selected_segment.start_node.position + _move_selected_segment.curve.get_point_out(0), Color.CYAN, 0.5)
		_add_gizmo(_move_selected_segment.end_node.position + _move_selected_segment.curve.get_point_in(last), Color.CYAN, 0.5)

func _add_gizmo(pos: Vector3, color: Color, radius: float) -> void:
	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mesh.material_override = mat
	mesh.position = pos + Vector3(0, 0.1, 0)
	add_child(mesh)
	_move_gizmos.append(mesh)

func _clear_move_gizmos() -> void:
	for g in _move_gizmos:
		g.queue_free()
	_move_gizmos.clear()
