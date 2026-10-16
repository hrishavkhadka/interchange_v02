extends Node

signal overrides_changed

# Key: "node_idx|from_seg_idx|from_lane_idx|to_seg_idx|to_lane_idx"
# Value: -1 = force disabled, +1 = force enabled. Absence = no override.
var _values: Dictionary = {}

var _node_idx: Dictionary = {}
var _seg_idx: Dictionary = {}

func refresh_indices() -> void:
	_node_idx.clear()
	_seg_idx.clear()
	for i in RoadGraph.nodes.size():
		_node_idx[RoadGraph.nodes[i]] = i
	for i in RoadGraph.segments.size():
		_seg_idx[RoadGraph.segments[i]] = i

func _index_of_node(node: RoadNode) -> int:
	if _node_idx.is_empty() and RoadGraph.nodes.size() > 0:
		refresh_indices()
	return _node_idx.get(node, -1)

func _index_of_segment(seg: RoadSegment) -> int:
	if _seg_idx.is_empty() and RoadGraph.segments.size() > 0:
		refresh_indices()
	return _seg_idx.get(seg, -1)

func _key(node: RoadNode, from_lane: Lane, to_lane: Lane) -> String:
	var ni: int = _index_of_node(node)
	var fsi: int = _index_of_segment(from_lane.segment)
	var tsi: int = _index_of_segment(to_lane.segment)
	if ni < 0 or fsi < 0 or tsi < 0:
		return ""
	return "%d|%d|%d|%d|%d" % [ni, fsi, from_lane.lane_index, tsi, to_lane.lane_index]

# Returns -1 (forced off), 0 (no override), or +1 (forced on).
func get_override(node: RoadNode, from_lane: Lane, to_lane: Lane) -> int:
	var k := _key(node, from_lane, to_lane)
	if k == "":
		return 0
	return int(_values.get(k, 0))

func set_override(node: RoadNode, from_lane: Lane, to_lane: Lane, value: int) -> void:
	var k := _key(node, from_lane, to_lane)
	if k == "":
		return
	if value == 0:
		_values.erase(k)
	else:
		_values[k] = -1 if value < 0 else 1
	overrides_changed.emit()

# Back-compat shims used by the rest of the codebase.
func is_disabled(node: RoadNode, from_lane: Lane, to_lane: Lane) -> bool:
	return get_override(node, from_lane, to_lane) == -1

func set_disabled(node: RoadNode, from_lane: Lane, to_lane: Lane, disabled: bool) -> void:
	set_override(node, from_lane, to_lane, -1 if disabled else 1)

func clear_node_overrides(node: RoadNode) -> void:
	if node == null:
		return
	var nid: int = _index_of_node(node)
	if nid < 0:
		return
	var to_remove: Array = []
	for k in _values.keys():
		var parts: PackedStringArray = String(k).split("|")
		if parts.size() != 5:
			continue
		if int(parts[0]) == nid:
			to_remove.append(k)
	for r in to_remove:
		_values.erase(r)
	overrides_changed.emit()

func serialize() -> Array:
	var result: Array = []
	for k in _values.keys():
		var parts: PackedStringArray = String(k).split("|")
		if parts.size() != 5:
			continue
		result.append({
			"node": int(parts[0]),
			"from_seg": int(parts[1]),
			"from_lane": int(parts[2]),
			"to_seg": int(parts[3]),
			"to_lane": int(parts[4]),
			"value": int(_values[k]),
		})
	return result

func set_override_stable(node_idx: int, from_seg_idx: int, from_lane_idx: int, to_seg_idx: int, to_lane_idx: int, value: int) -> void:
	var k := "%d|%d|%d|%d|%d" % [node_idx, from_seg_idx, from_lane_idx, to_seg_idx, to_lane_idx]
	if value == 0:
		_values.erase(k)
	else:
		_values[k] = -1 if value < 0 else 1

func clear() -> void:
	_values.clear()
	overrides_changed.emit()
