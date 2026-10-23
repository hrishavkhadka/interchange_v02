extends Node

signal node_added(node: RoadNode)
signal graph_changed()

const SNAP_RADIUS := 5.0

var nodes: Array[RoadNode] = []
var segments: Array[RoadSegment] = []
var _next_id := 1
var _next_seg_uid := 1
var _suppress: bool = false

func begin_batch() -> void:
	_suppress = true

func end_batch() -> void:
	_suppress = false
	graph_changed.emit()

func find_nearest(pos: Vector3, radius: float = SNAP_RADIUS) -> RoadNode:
	var best: RoadNode = null
	var best_dist := radius
	for n in nodes:
		var d := n.position.distance_to(pos)
		if d < best_dist:
			best_dist = d
			best = n
	return best

func get_or_create(pos: Vector3, is_waypoint: bool = false, force_new: bool = false) -> RoadNode:
	if not force_new:
		var existing := find_nearest(pos)
		if existing != null:
			return existing
	var node := RoadNode.new(pos, _next_id)
	node.is_waypoint = is_waypoint
	_next_id += 1
	nodes.append(node)
	node_added.emit(node)
	if not _suppress:
		graph_changed.emit()
	return node

func get_or_create_waypoint(pos: Vector3) -> RoadNode:
	return get_or_create(pos, true)

func register_segment(seg: RoadSegment) -> void:
	if seg.uid == 0:
		seg.uid = _next_seg_uid
		_next_seg_uid += 1
	if not segments.has(seg):
		segments.append(seg)
		if not _suppress:
			graph_changed.emit()

func unregister_segment(seg: RoadSegment) -> void:
	segments.erase(seg)
	if not _suppress:
		graph_changed.emit()

func clear() -> void:
	nodes.clear()
	segments.clear()
	_next_id = 1
	_next_seg_uid = 1
	graph_changed.emit()

func segment_by_uid(uid: int) -> RoadSegment:
	for s in segments:
		if s.uid == uid:
			return s
	return null

func node_by_id(nid: int) -> RoadNode:
	for n in nodes:
		if n.id == nid:
			return n
	return null

func cleanup_duplicate_nodes() -> void:
	var merged: bool = true
	var safety: int = 0
	while merged and safety < 10:
		safety += 1
		merged = false
		var nodes_copy = nodes.duplicate()
		for i in range(nodes_copy.size()):
			var n1: RoadNode = nodes_copy[i]
			if not is_instance_valid(n1): continue
			for j in range(i + 1, nodes_copy.size()):
				var n2: RoadNode = nodes_copy[j]
				if not is_instance_valid(n2): continue
				
				# Only merge if they are almost exactly on top of each other (0.5m)
				if n1.position.distance_to(n2.position) < 0.5:
					merged = true
					for entry in n2.segment_ends:
						var seg: RoadSegment = entry["segment"]
						var is_start: bool = entry["is_start"]
						if is_start: seg.start_node = n1
						else: seg.end_node = n1
						n1.add_segment_end(seg, is_start)
					
					n2.segment_ends.clear()
					nodes.erase(n2)
					break
			if merged: break
	if merged:
		graph_changed.emit()
