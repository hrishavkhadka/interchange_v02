class_name LaneArcBuilder
extends RefCounted

# Build all legal arcs at a junction. The algorithm decides which are
# enabled by default; the rest are still returned but with default_enabled
# false, so the editor can turn them on.
#
# Return value: Array of Dictionary with keys:
#   from_lane       : Lane
#   to_lane         : Lane
#   default_enabled : bool
static func build(node: RoadNode, all_lanes: Array, debug: bool = false) -> Array:
	var ex: Dictionary = extract(node, all_lanes)
	var entries: Array = ex["entries"]
	var exits: Array = ex["exits"]
	var entry_lane_map: Array = ex["entry_lane_map"]
	var exit_lane_map: Array = ex["exit_lane_map"]
	if entries.is_empty() or exits.is_empty():
		return []

	var p1: Dictionary = LaneArcAlgorithm.init_phase1(entries, exits, false)
	var p2: Dictionary = LaneArcAlgorithm.iterate_phase2(p1["entries"], p1["exits"], p1["matrix"], false)
	var arcs_data: Array = LaneArcAlgorithm.assign_phase3(p2["entries"], p2["exits"], p2["matrix"], debug)

	# Build a set of (from_lane, to_lane) pairs the algorithm picked.
	var algorithm_set: Dictionary = {}
	for a_v in arcs_data:
		var a: Dictionary = a_v
		var i: int = int(a["entry_i"])
		var j: int = int(a["exit_j"])
		var el: int = int(a["entry_lane"])
		var xl: int = int(a["exit_lane"])
		var ent_lanes: Array = entry_lane_map[i]
		var ex_lanes: Array = exit_lane_map[j]
		if el < 1 or el > ent_lanes.size():
			continue
		if xl < 1 or xl > ex_lanes.size():
			continue
		var from_lane: Lane = ent_lanes[el - 1]
		var to_lane: Lane = ex_lanes[xl - 1]
		algorithm_set[_pair_key(from_lane, to_lane)] = true

	# Enumerate every legal (arriving, departing) pair at this node. A pair
	# is legal if it uses two different segments. Same-segment pairs are
	# U-turns and are not emitted at all.
	var result: Array = []
	for arriving_v in all_lanes:
		var arriving: Lane = arriving_v
		if arriving.to_node != node or arriving.from_node == node:
			continue
		for departing_v in all_lanes:
			var departing: Lane = departing_v
			if departing.from_node != node or departing.to_node == node:
				continue
			if departing.segment == arriving.segment:
				continue
			result.append({
				"from_lane": arriving,
				"to_lane": departing,
				"default_enabled": algorithm_set.has(_pair_key(arriving, departing)),
			})

	if debug:
		print("")
		print("========== Junction node %d ==========" % node.id)
		_print_groups(entries, exits)
		LaneArcAlgorithm._print_matrix("Phase 2 final", p2["entries"], p2["exits"], p2["matrix"])
		print("  Total candidate arcs: %d" % result.size())
		var enabled_count: int = 0
		for r in result:
			if r["default_enabled"]:
				enabled_count += 1
		print("  Algorithm-enabled arcs: %d" % enabled_count)

	return result

static func _pair_key(a: Lane, b: Lane) -> String:
	return "%d_%d_%d_%d" % [
		a.segment.get_instance_id(), a.lane_index,
		b.segment.get_instance_id(), b.lane_index,
	]

# ---------------------------------------------------------------------------
# Extraction
# ---------------------------------------------------------------------------

static func extract(node: RoadNode, all_lanes: Array) -> Dictionary:
	var entries: Array = []
	var exits: Array = []
	var entry_lane_map: Array = []
	var exit_lane_map: Array = []

	var sorted_ends: Array = []
	for e in node.segment_ends:
		sorted_ends.append(e)
	sorted_ends.sort_custom(func(a, b):
		var sa: RoadSegment = a["segment"]
		var sb: RoadSegment = b["segment"]
		if sa == null or sb == null:
			return false
		return sa.uid < sb.uid)

	for entry_d in sorted_ends:
		var e: Dictionary = entry_d
		var seg: RoadSegment = e["segment"]
		if seg == null or seg.road_type == null:
			continue
		var is_start: bool = e["is_start"]
		var other: RoadNode
		if is_start:
			other = seg.end_node
		else:
			other = seg.start_node
		if other == null:
			continue

		var f_lanes: Array = []
		var b_lanes: Array = []
		for lane_v in all_lanes:
			var lane: Lane = lane_v
			if lane.segment != seg:
				continue
			if lane.direction == "F":
				f_lanes.append(lane)
			else:
				b_lanes.append(lane)
		f_lanes.sort_custom(func(a, b): return a.lane_index < b.lane_index)
		b_lanes.sort_custom(func(a, b): return a.lane_index < b.lane_index)

		var dir_to_node: Vector3 = (node.position - other.position).normalized()
		var dir_from_node: Vector3 = -dir_to_node

		var f_is_entry: bool = not is_start
		var b_is_entry: bool = is_start

		if not f_lanes.is_empty():
			if f_is_entry:
				entries.append(_make_group(seg.uid, f_lanes.size(), dir_to_node))
				entry_lane_map.append(_ordinal_order(f_lanes, "F", seg.road_type))
			else:
				exits.append(_make_group(seg.uid, f_lanes.size(), dir_from_node))
				exit_lane_map.append(_ordinal_order(f_lanes, "F", seg.road_type))

		if not b_lanes.is_empty():
			if b_is_entry:
				entries.append(_make_group(seg.uid, b_lanes.size(), dir_to_node))
				entry_lane_map.append(_ordinal_order(b_lanes, "B", seg.road_type))
			else:
				exits.append(_make_group(seg.uid, b_lanes.size(), dir_from_node))
				exit_lane_map.append(_ordinal_order(b_lanes, "B", seg.road_type))

	for i in entries.size():
		entries[i]["id"] = i + 1
	for j in exits.size():
		exits[j]["id"] = j + 1

	return {
		"entries": entries,
		"exits": exits,
		"entry_lane_map": entry_lane_map,
		"exit_lane_map": exit_lane_map,
	}

static func _make_group(seg_uid: int, lanes: int, dir: Vector3) -> Dictionary:
	return {
		"id": 0,
		"lanes": lanes,
		"segment_id": seg_uid,
		"dir": dir,
	}

# Returns lanes in algorithm ordinal order:
# index 0 = ordinal 1 (innermost), index N-1 = ordinal N (outermost).
static func _ordinal_order(lanes: Array, direction: String, rt: RoadType) -> Array:
	if direction == "F":
		var out: Array = []
		for i in range(lanes.size() - 1, -1, -1):
			out.append(lanes[i])
		return out
	return lanes

static func _print_groups(entries: Array, exits: Array) -> void:
	print("  Entries:")
	for i in entries.size():
		var e: Dictionary = entries[i]
		print("    id=%d seg=%d lanes=%d dir=%s" % [
			int(e["id"]), int(e["segment_id"]), int(e["lanes"]), str(e["dir"])])
	print("  Exits:")
	for j in exits.size():
		var x: Dictionary = exits[j]
		print("    id=%d seg=%d lanes=%d dir=%s" % [
			int(x["id"]), int(x["segment_id"]), int(x["lanes"]), str(x["dir"])])
