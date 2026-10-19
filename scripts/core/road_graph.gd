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
