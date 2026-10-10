class_name RoadBuilder
extends Node3D

signal cost_changed(total_cost: float)
signal road_type_changed(index: int, name: String)

enum Mode { POINTER = 0, ROAD = 1, DEMOLISH = 2, REVERSE = 3 }

const MIN_BEND_DOT: float = 0.87
const WAYPOINT_SPACING_LANES: float = 30.0
const DEMOLISH_PICK_RADIUS: float = 3.5
const WAYPOINT_ABSORB_RADIUS: float = 10.0

const ROAD_TYPE_DEFS := [
	{ "id": "fb",       "name": "2-lane two-way",   "layout": "FB" },
	{ "id": "ff",       "name": "2-lane one-way",   "layout": "FF" },
	{ "id": "ffbb",     "name": "4-lane two-way",   "layout": "FFBB" },
	{ "id": "ffff",     "name": "4-lane one-way",   "layout": "FFFF" },
	{ "id": "fff",      "name": "3-lane one-way",   "layout": "FFF" },
	{ "id": "fffff",    "name": "5-lane one-way",   "layout": "FFFFF" },
	{ "id": "ffb",      "name": "3-lane (2+1)",     "layout": "FFB" },
	{ "id": "fffbb",    "name": "5-lane (3+2)",     "layout": "FFFBB" },
	{ "id": "fffbbb",   "name": "6-lane (3+3)",     "layout": "FFFBBB" },
	{ "id": "ffffbb",   "name": "6-lane (4+2)",     "layout": "FFFFBB" },
]

@export var road_type: RoadType
@export var level_half_size: float = 150.0

var settings: BuildSettings = BuildSettings.new()
var mode: int = Mode.ROAD

var _drawing := false
var _start := Vector3.ZERO
var _start_t_segment: Variant = null
var _start_guide_dir: Variant = null
var _preview: RoadSegment
var _segments: Array[RoadSegment] = []
var _snap_indicator: SnapIndicator
var _start_indicator: SnapIndicator
var _guidelines: Guidelines

var _hovered_segment: RoadSegment = null

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
	if _drawing:
		_cancel()
	_exit_hover_mode()
	mode = m
	if mode != Mode.ROAD:
		if _snap_indicator != null:
			_snap_indicator.hide_indicator()
		if _start_indicator != null:
			_start_indicator.hide_indicator()
		if _guidelines != null:
			_guidelines.clear()

func _process(_dt: float) -> void:
	if not GameState.is_build():
		return
	if mode == Mode.ROAD:
		if _drawing:
			_update()
		else:
			_update_hover()
	elif mode == Mode.DEMOLISH:
		_demolish_hover()
	elif mode == Mode.REVERSE:
		_demolish_hover()

func _unhandled_input(event: InputEvent) -> void:
	if not GameState.is_build():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mode == Mode.ROAD:
				if _drawing:
					_end()
				else:
					_begin()
			elif mode == Mode.DEMOLISH:
				_demolish_click()
			elif mode == Mode.REVERSE:
				_reverse_click()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _drawing:
			_cancel()
	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.pressed and ke.keycode == KEY_ESCAPE and _drawing:
			_cancel()

func total_cost() -> float:
	var t := 0.0
	for s in _segments:
		if is_instance_valid(s):
			t += s.cost()
	return t

func _begin() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null:
		return
	var hit: Vector3 = hit_raw
	var r := SnapResolver.resolve_position(hit, settings, road_type)
	var rp: Vector3 = r["point"]
	# Before committing the start node, absorb any nearby waypoint.
	if r["kind"] != "node":
		_absorb_nearby_waypoints(rp)
	_drawing = true
	_start = rp
	_start_t_segment = r["t_segment"]
	_start_guide_dir = r["guide_dir"] if r.has("guide_dir") else null
	_start_indicator.show_at(_start)
	_preview = RoadSegment.new()
	_preview_root.add_child(_preview)
	_preview.setup(road_type, _two_point_curve(_start, _start + Vector3(0.01, 0, 0)))
	_preview.visible = false
	_guidelines.update(hit, road_type)

func _update() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null:
		return
	var hit: Vector3 = hit_raw
	_guidelines.update(hit, road_type)
	_start_indicator.show_at(_start)
	var final := _resolve_end(hit)
	var preview_end: Vector3 = final["point"]
	var end_ts: Variant = final["t_segment"]
	var min_len: float = road_type.lane_width
	if _start.distance_to(preview_end) < min_len:
		_preview.visible = false
		_snap_indicator.hide_indicator()
		return
	_preview.visible = true
	_preview.setup(road_type, _two_point_curve(_start, preview_end))
	var sharing := _sharing_nodes(_start, preview_end)
	var t_targets: Array = []
	if _start_t_segment != null:
		t_targets.append(_start_t_segment)
	if end_ts != null:
		t_targets.append(end_ts)
	var hw: float = road_type.total_width() * 0.5
	var valid: bool = RoadOps.is_placement_valid(_start, preview_end, hw, t_targets, sharing)
	if valid and _would_sharp_bend(_start, preview_end, _start_t_segment, end_ts):
		valid = false
	_preview.set_preview_validity(valid)
	_snap_indicator.show_at(preview_end)

func _end() -> void:
	if not _drawing:
		return
	_drawing = false
	var hit_raw: Variant = _ground_hit()
	_destroy_preview()
	if _snap_indicator != null:
		_snap_indicator.hide_indicator()
	if _start_indicator != null:
		_start_indicator.hide_indicator()
	if _guidelines != null:
		_guidelines.clear()
	if hit_raw == null:
		_start_t_segment = null
		_start_guide_dir = null
		return
	var hit: Vector3 = hit_raw
	var final := _resolve_end(hit)
	var end_pos: Vector3 = final["point"]
	var end_ts: Variant = final["t_segment"]
	var min_len: float = road_type.lane_width
	if _start.distance_to(end_pos) < min_len:
		_start_t_segment = null
		_start_guide_dir = null
		return
	var sharing := _sharing_nodes(_start, end_pos)
	var t_targets: Array = []
	if _start_t_segment != null:
		t_targets.append(_start_t_segment)
	if end_ts != null:
		t_targets.append(end_ts)
	var hw: float = road_type.total_width() * 0.5
	if not RoadOps.is_placement_valid(_start, end_pos, hw, t_targets, sharing):
		_start_t_segment = null
		_start_guide_dir = null
		return
	if _would_sharp_bend(_start, end_pos, _start_t_segment, end_ts):
		_start_t_segment = null
		_start_guide_dir = null
		return
	# Absorb nearby waypoints before doing any splitting. The graph gets a
	# cleaner topology and the segment we split is the merged one.
	if end_ts != null:
		_absorb_nearby_waypoints(end_pos)
	if _start_t_segment != null:
		_split_existing_segment(_start_t_segment, _start)
	if end_ts != null:
		var recheck: Variant = RoadOps.find_segment_under_point(end_pos)
		if recheck != null:
			_split_existing_segment(recheck["segment"], end_pos)
	var start_node := RoadGraph.get_or_create(_start)
	var end_node := RoadGraph.get_or_create(end_pos)
	_start_t_segment = null
	_start_guide_dir = null
	if start_node == end_node:
		return
	_create_chain(start_node, end_node, road_type)
	cost_changed.emit(total_cost())

func _cancel() -> void:
	_drawing = false
	_start_t_segment = null
	_start_guide_dir = null
	_destroy_preview()
	if _snap_indicator != null:
		_snap_indicator.hide_indicator()
	if _start_indicator != null:
		_start_indicator.hide_indicator()
	if _guidelines != null:
		_guidelines.clear()

func _update_hover() -> void:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null:
		if _snap_indicator != null:
			_snap_indicator.hide_indicator()
		if _guidelines != null:
			_guidelines.clear()
		return
	var hit: Vector3 = hit_raw
	if _guidelines != null:
		_guidelines.update(hit, road_type)
	var r := SnapResolver.resolve_position(hit, settings, road_type)
	var rp: Vector3 = r["point"]
	_snap_indicator.show_at(rp)

# ------------------------------------------------------------ waypoint absorb

func _absorb_nearby_waypoints(pos: Vector3) -> void:
	var to_remove: Array[RoadNode] = []
	for n in RoadGraph.nodes:
		if not n.is_waypoint:
			continue
		if n.segment_ends.size() != 2:
			continue
		var d: float = Vector2(n.position.x - pos.x, n.position.z - pos.z).length()
		if d > WAYPOINT_ABSORB_RADIUS:
			continue
		to_remove.append(n)
	for w in to_remove:
		_remove_waypoint(w)

func _remove_waypoint(w: RoadNode) -> void:
	if w.segment_ends.size() != 2:
		return
	var seg_a: RoadSegment = w.segment_ends[0]["segment"]
	var seg_b: RoadSegment = w.segment_ends[1]["segment"]
	if seg_a == null or seg_b == null:
		return
	var a_is_start: bool = w.segment_ends[0]["is_start"]
	var other_a: RoadNode = seg_a.end_node if a_is_start else seg_a.start_node
	var b_is_start: bool = w.segment_ends[1]["is_start"]
	var other_b: RoadNode = seg_b.end_node if b_is_start else seg_b.start_node
	if other_a == null or other_b == null:
		return
	var rt: RoadType = seg_a.road_type
	_detach_and_remove(seg_a)
	_detach_and_remove(seg_b)
	RoadGraph.nodes.erase(w)
	_create_segment(other_a, other_b, rt)

# ------------------------------------------------------------ demolish / reverse

func _exit_hover_mode() -> void:
	if _hovered_segment != null and is_instance_valid(_hovered_segment):
		_hovered_segment.set_hovered(false)
	_hovered_segment = null

func _demolish_hover() -> void:
	var seg := _find_segment_under_cursor()
	if seg == _hovered_segment:
		return
	if _hovered_segment != null and is_instance_valid(_hovered_segment):
		_hovered_segment.set_hovered(false)
	_hovered_segment = seg
	if _hovered_segment != null:
		_hovered_segment.set_hovered(true)

func _demolish_click() -> void:
	var seg := _find_segment_under_cursor()
	if seg == null:
		return
	if _segment_is_protected(seg):
		return
	if _hovered_segment == seg:
		_hovered_segment = null
	_remove_segment_and_cleanup(seg)
	cost_changed.emit(total_cost())

func _segment_is_protected(seg: RoadSegment) -> bool:
	if seg.start_node != null and (seg.start_node.is_entry or seg.start_node.is_exit):
		return true
	if seg.end_node != null and (seg.end_node.is_entry or seg.end_node.is_exit):
		return true
	return false

func _reverse_click() -> void:
	var seg := _find_segment_under_cursor()
	if seg == null:
		return
	seg.reverse()
	RoadGraph.graph_changed.emit()
	_rebuild_neighbours(seg.start_node, seg)
	_rebuild_neighbours(seg.end_node, seg)

func _find_segment_under_cursor() -> RoadSegment:
	var hit_raw: Variant = _ground_hit()
	if hit_raw == null:
		return null
	var hit: Vector3 = hit_raw
	var best: RoadSegment = null
	var best_dist: float = DEMOLISH_PICK_RADIUS
	for s in _segments:
		if not is_instance_valid(s):
			continue
		if s.curve == null or s.road_type == null:
			continue
		var length: float = s.curve.get_baked_length()
		if length < 0.1:
			continue
		var samples: int = maxi(8, int(length * 0.5))
		for i in range(samples + 1):
			var t: float = float(i) / float(samples)
			var p: Vector3 = s.curve.sample_baked(t * length)
			var d: float = Vector2(p.x - hit.x, p.z - hit.z).length()
			if d < best_dist:
				best_dist = d
				best = s
	return best

func _remove_segment_and_cleanup(seg: RoadSegment) -> void:
	if not is_instance_valid(seg):
		return
	var sn := seg.start_node
	var en := seg.end_node
	_detach_and_remove(seg)
	var removed_any: bool = false
	if _cleanup_node(sn):
		removed_any = true
	if _cleanup_node(en):
		removed_any = true
	if removed_any:
		RoadGraph.graph_changed.emit()

func _cleanup_node(node: RoadNode) -> bool:
	if node == null:
		return false
	if node.segment_ends.size() > 0:
		return false
	RoadGraph.nodes.erase(node)
	return true

func _resolve_end(raw: Vector3) -> Dictionary:
	var pos_r := SnapResolver.resolve_position(raw, settings, road_type)
	var kind: String = pos_r["kind"]
	var pos: Vector3 = pos_r["point"]
	var t_seg: Variant = pos_r["t_segment"]
	var dir_kind: String = ""
	if kind == "free":
		var dir_r := SnapResolver.resolve_direction(_start, pos, _start_t_segment, _start_guide_dir, settings)
		pos = dir_r["point"]
		dir_kind = dir_r["kind"]
		if settings.snap_length and road_type != null:
			var v: Vector3 = pos - _start
			v.y = 0.0
			var L: float = v.length()
			if L > 0.01:
				var lw: float = road_type.lane_width
				var qL: float = roundf(L / lw) * lw
				if qL < lw:
					qL = lw
				var nd: Vector3 = v.normalized()
				pos = _start + nd * qL
	return {
		"point": pos,
		"kind": kind,
		"t_segment": t_seg,
		"direction_kind": dir_kind,
	}

func _would_sharp_bend(start: Vector3, end: Vector3, start_t_segment: Variant, end_t_segment: Variant) -> bool:
	var new_dir: Vector3 = end - start
	new_dir.y = 0.0
	if new_dir.length_squared() < 0.01:
		return false
	new_dir = new_dir.normalized()
	if _endpoint_blocked(start, new_dir, start_t_segment):
		return true
	if _endpoint_blocked(end, -new_dir, end_t_segment):
		return true
	return false

func _endpoint_blocked(pos: Vector3, out_dir: Vector3, t_segment: Variant) -> bool:
	if t_segment != null:
		var s: RoadSegment = t_segment
		if s.start_node != null:
			var d1_v: Vector3 = s.start_node.position - pos
			d1_v.y = 0.0
			if d1_v.length_squared() > 0.01:
				var d1: Vector3 = d1_v.normalized()
				if out_dir.dot(d1) > MIN_BEND_DOT:
					return true
		if s.end_node != null:
			var d2_v: Vector3 = s.end_node.position - pos
			d2_v.y = 0.0
			if d2_v.length_squared() > 0.01:
				var d2: Vector3 = d2_v.normalized()
				if out_dir.dot(d2) > MIN_BEND_DOT:
					return true
	var node := RoadGraph.find_nearest(pos, 1.0)
	if node == null:
		return false
	for entry in node.segment_ends:
		var e: Dictionary = entry
		var seg_v: Variant = e["segment"]
		if seg_v == null:
			continue
		var seg: RoadSegment = seg_v
		if seg == t_segment:
			continue
		var other: Vector3
		if e["is_start"]:
			if seg.end_node == null:
				continue
			other = seg.end_node.position
		else:
			if seg.start_node == null:
				continue
			other = seg.start_node.position
		var outward_v: Vector3 = other - node.position
		outward_v.y = 0.0
		if outward_v.length_squared() < 0.01:
			continue
		var outward: Vector3 = outward_v.normalized()
		if out_dir.dot(outward) > MIN_BEND_DOT:
			return true
	return false

func _sharing_nodes(start: Vector3, end: Vector3) -> Array:
	var result: Array = []
	var ns := RoadGraph.find_nearest(start, 1.0)
	if ns != null:
		result.append(ns)
	var ne := RoadGraph.find_nearest(end, 1.0)
	if ne != null:
		result.append(ne)
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

func _create_chain(start_node: RoadNode, end_node: RoadNode, rt: RoadType) -> void:
	if start_node == end_node:
		return
	var dir: Vector3 = end_node.position - start_node.position
	var length: float = dir.length()
	if length < 0.1:
		return
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
	if start_node == end_node:
		return null
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

func _rebuild_neighbours(node: RoadNode, exclude: RoadSegment) -> void:
	if node == null:
		return
	for entry in node.segment_ends:
		var e: Dictionary = entry
		var s: RoadSegment = e["segment"]
		if s == exclude:
			continue
		if is_instance_valid(s):
			s.rebuild_mesh()

func _split_existing_segment(seg: RoadSegment, at: Vector3) -> void:
	if not is_instance_valid(seg):
		return
	var old_start := seg.start_node
	var old_end := seg.end_node
	var rt := seg.road_type
	_detach_and_remove(seg)
	var mid := RoadGraph.get_or_create(at)
	_create_chain(old_start, mid, rt)
	_create_chain(mid, old_end, rt)

func _detach_and_remove(seg: RoadSegment) -> void:
	var sn := seg.start_node
	var en := seg.end_node
	_remove_end_from(sn, seg)
	_remove_end_from(en, seg)
	RoadGraph.unregister_segment(seg)
	_segments.erase(seg)
	if is_instance_valid(seg):
		seg.queue_free()
	if sn != null:
		for entry in sn.segment_ends:
			var e: Dictionary = entry
			var s: RoadSegment = e["segment"]
			if is_instance_valid(s):
				s.rebuild_mesh()
	if en != null:
		for entry in en.segment_ends:
			var e: Dictionary = entry
			var s: RoadSegment = e["segment"]
			if is_instance_valid(s):
				s.rebuild_mesh()

func _remove_end_from(node: RoadNode, seg: RoadSegment) -> void:
	if node == null:
		return
	var filtered: Array = []
	for e in node.segment_ends:
		if e["segment"] != seg:
			filtered.append(e)
	node.segment_ends = filtered

func _ground_hit() -> Variant:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return null
	var m := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(m)
	var dir := cam.project_ray_normal(m)
	var plane := Plane(Vector3.UP, 0.0)
	var hit_raw: Variant = plane.intersects_ray(from, dir)
	if hit_raw == null:
		return null
	var hit: Vector3 = hit_raw
	hit.x = clampf(hit.x, -level_half_size, level_half_size)
	hit.z = clampf(hit.z, -level_half_size, level_half_size)
	return hit
