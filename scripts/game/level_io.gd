extends Node

const LEVEL_DIR: String = "user://levels"
const FORMAT_VERSION: int = 2

func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(LEVEL_DIR)

func save_level(name: String) -> String:
	ensure_dir()
	if name == "":
		name = "level_%d" % Time.get_unix_time_from_system()
	var path := "%s/%s.json" % [LEVEL_DIR, name]
	var data := _serialize()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	return path

func load_level(name: String) -> bool:
	if not name.ends_with(".json"):
		name = name + ".json"
	var path := "%s/%s" % [LEVEL_DIR, name]
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		return false
	_deserialize(parsed)
	return true

func _serialize() -> Dictionary:
	var seg_to_idx: Dictionary = {}
	for i in RoadGraph.segments.size():
		seg_to_idx[RoadGraph.segments[i]] = i
	var node_to_idx: Dictionary = {}
	for i in RoadGraph.nodes.size():
		node_to_idx[RoadGraph.nodes[i]] = i

	var segments_data: Array = []
	for i in RoadGraph.segments.size():
		var seg: RoadSegment = RoadGraph.segments[i]
		if seg.curve == null or seg.road_type == null:
			continue
		if seg.start_node == null or seg.end_node == null:
			continue
			
		# Save exact Bezier control points and handles
		var curve_data: Array = []
		for k in seg.curve.point_count:
			var p = seg.curve.get_point_position(k)
			var in_h = seg.curve.get_point_in(k)
			var out_h = seg.curve.get_point_out(k)
			curve_data.append({
				"pos": [p.x, p.y, p.z],
				"in": [in_h.x, in_h.y, in_h.z],
				"out": [out_h.x, out_h.y, out_h.z]
			})
			
		segments_data.append({
			"road_type": seg.road_type.id,
			"lane_layout": seg.road_type.lane_layout_string,
			"lane_width": seg.road_type.lane_width,
			"speed_limit_kmh": seg.road_type.speed_limit_kmh,
			"start_node": node_to_idx.get(seg.start_node, -1),
			"end_node": node_to_idx.get(seg.end_node, -1),
			"curve_data": curve_data,
		})

	var nodes_data: Array = []
	for n in RoadGraph.nodes:
		nodes_data.append({
			"position": [n.position.x, n.position.y, n.position.z],
			"is_waypoint": n.is_waypoint,
			"is_entry": n.is_entry,
			"is_exit": n.is_exit,
			"map_label": n.map_label,
			"forced_junction": n.forced_junction,
			"demand": _demand_to_serializable(n, node_to_idx),
		})

	return {
		"version": FORMAT_VERSION,
		"name": "level",
		"time_limit": GameState.time_limit,
		"default_target_count": GameState.default_target_count,
		"nodes": nodes_data,
		"segments": segments_data,
		"arc_overrides": ArcOverrides.serialize(),
	}

func _demand_to_serializable(node: RoadNode, node_to_idx: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for exit_id in node.demand:
		var exit_node := _find_node_by_id(int(exit_id))
		if exit_node == null:
			continue
		var idx: int = node_to_idx.get(exit_node, -1)
		if idx < 0:
			continue
		out[str(idx)] = int(node.demand[exit_id])
	return out

func _find_node_by_id(nid: int) -> RoadNode:
	for n in RoadGraph.nodes:
		if n.id == nid:
			return n
	return null

func _deserialize(data: Dictionary) -> void:
	_clear_graph()
	ArcOverrides.clear()
	RoadGraph.begin_batch()

	var nodes_data: Array = data.get("nodes", [])
	var created_nodes: Array[RoadNode] = []
	for entry in nodes_data:
		var e: Dictionary = entry
		var p_raw: Array = e.get("position", [0, 0, 0])
		var pos := Vector3(p_raw[0], p_raw[1], p_raw[2])
		var node: RoadNode = RoadGraph.get_or_create(pos)
		node.is_waypoint = bool(e.get("is_waypoint", false))
		node.is_entry = bool(e.get("is_entry", false))
		node.is_exit = bool(e.get("is_exit", false))
		node.map_label = String(e.get("map_label", ""))
		node.forced_junction = bool(e.get("forced_junction", false))
		created_nodes.append(node)

	var segments_data: Array = data.get("segments", [])
	var seg_root := get_tree().current_scene.find_child("SegmentsRoot", true, false)
	for entry in segments_data:
		var e: Dictionary = entry
		var rt := RoadType.new()
		rt.id = String(e.get("road_type", ""))
		rt.display_name = rt.id
		rt.lane_layout_string = String(e.get("lane_layout", "FB"))
		rt.lane_width = float(e.get("lane_width", 3.2))
		rt.speed_limit_kmh = float(e.get("speed_limit_kmh", 50.0))
		
		var curve := Curve3D.new()
		if e.has("curve_data"):
			# v2 format: exact bezier handles
			var c_data: Array = e.get("curve_data", [])
			for p_v in c_data:
				var pd: Dictionary = p_v
				var p_raw: Array = pd.get("pos", [0,0,0])
				var i_raw: Array = pd.get("in", [0,0,0])
				var o_raw: Array = pd.get("out", [0,0,0])
				curve.add_point(
					Vector3(p_raw[0], p_raw[1], p_raw[2]),
					Vector3(i_raw[0], i_raw[1], i_raw[2]),
					Vector3(o_raw[0], o_raw[1], o_raw[2])
				)
		else:
			# v1 format: fallback to polyline points
			var pts: Array = e.get("curve", [])
			if pts.size() < 2:
				continue
			for p_v in pts:
				var p: Array = p_v
				curve.add_point(Vector3(p[0], p[1], p[2]))
				
		var sn: int = int(e.get("start_node", -1))
		var en: int = int(e.get("end_node", -1))
		if sn < 0 or en < 0 or sn >= created_nodes.size() or en >= created_nodes.size():
			continue
		var start_node: RoadNode = created_nodes[sn]
		var end_node: RoadNode = created_nodes[en]
		var seg := RoadSegment.new()
		seg.start_node = start_node
		seg.end_node = end_node
		seg.setup(rt, curve)
		start_node.add_segment_end(seg, true)
		end_node.add_segment_end(seg, false)
		if seg_root != null:
			seg_root.add_child(seg)
		else:
			get_tree().current_scene.add_child(seg)
		RoadGraph.register_segment(seg)
		seg.rebuild_mesh()

	GameState.time_limit = float(data.get("time_limit", 90.0))
	GameState.default_target_count = int(data.get("default_target_count", 40))
	GameState.time_remaining = GameState.time_limit
	GameState.target_count = GameState.default_target_count

	for i in created_nodes.size():
		var node: RoadNode = created_nodes[i]
		if i < nodes_data.size():
			var nd: Dictionary = nodes_data[i]
			var demand_raw: Dictionary = nd.get("demand", {})
			for k in demand_raw:
				var idx: int = int(k)
				if idx < 0 or idx >= created_nodes.size():
					continue
				var exit_node: RoadNode = created_nodes[idx]
				node.demand[exit_node.id] = int(demand_raw[k])

	for o_v in data.get("arc_overrides", []):
		var o: Dictionary = o_v
		ArcOverrides.set_override_stable(
			int(o.get("node", -1)),
			int(o.get("from_seg", -1)),
			int(o.get("from_lane", 0)),
			int(o.get("to_seg", -1)),
			int(o.get("to_lane", 0)),
			int(o.get("value", 0)))

	RoadGraph.end_batch()

func _clear_graph() -> void:
	var scene_root := get_tree().current_scene
	if scene_root != null:
		var seg_root := scene_root.find_child("SegmentsRoot", true, false)
		if seg_root != null:
			for c in seg_root.get_children():
				c.queue_free()
	for seg in RoadGraph.segments:
		if is_instance_valid(seg):
			seg.queue_free()
	RoadGraph.segments.clear()
	RoadGraph.nodes.clear()
