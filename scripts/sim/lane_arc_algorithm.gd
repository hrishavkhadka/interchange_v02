class_name LaneArcAlgorithm
extends RefCounted

const ANGLE_SOFT_FORBID_DEG: float = 30.0

# =============================================================================
# PHASE 1 — initialize the promise matrix
# =============================================================================

static func init_phase1(entries: Array, exits: Array, debug: bool = false) -> Dictionary:
	var n_e: int = entries.size()
	var n_x: int = exits.size()

	var matrix: Array = []
	for i in n_e:
		var row: Array = []
		for j in n_x:
			row.append(0)
		matrix.append(row)

	if debug:
		_print_matrix("Step 0: initial state (all zeros)", entries, exits, matrix)

	for i in n_e:
		var e: Dictionary = entries[i]
		for j in n_x:
			var x: Dictionary = exits[j]
			if int(e["segment_id"]) == int(x["segment_id"]):
				matrix[i][j] = -1

	if debug:
		_print_matrix("Step 1: mark U-turns (-1)", entries, exits, matrix)

	for i in n_e:
		var e2: Dictionary = entries[i]
		var e_in: Vector3 = e2["dir"]
		var e_out := Vector3(-e_in.x, 0.0, -e_in.z)
		for j2 in n_x:
			if matrix[i][j2] != 0:
				continue
			var x_out: Vector3 = exits[j2]["dir"]
			var ang_deg: float = _angle_between_deg(e_out, x_out)
			if ang_deg <= ANGLE_SOFT_FORBID_DEG:
				matrix[i][j2] = -2

	if debug:
		_print_matrix("Step 2: mark soft-forbidden (-2)", entries, exits, matrix)

	for i in n_e:
		for j in n_x:
			if matrix[i][j] == 0:
				matrix[i][j] = 1

	for i in n_e:
		var row_sum: int = 0
		for j in n_x:
			if matrix[i][j] > 0:
				row_sum += matrix[i][j]
		entries[i]["commits"] = row_sum
	for j in n_x:
		var col_sum: int = 0
		for i in n_e:
			if matrix[i][j] > 0:
				col_sum += matrix[i][j]
		exits[j]["commits"] = col_sum

	if debug:
		_print_matrix("Step 3: initial 1-to-1 commitment", entries, exits, matrix)

	return { "matrix": matrix, "entries": entries, "exits": exits }

# =============================================================================
# PHASE 2 — iteratively balance the promise matrix
# =============================================================================

static func iterate_phase2(entries: Array, exits: Array, matrix: Array, debug: bool = false) -> Dictionary:
	var n_e: int = entries.size()
	var n_x: int = exits.size()
	var safety: int = (n_e + n_x) * 32 + 64
	var iteration: int = 0

	while iteration < safety:
		iteration += 1

		var entry_surplus: Array = []
		var exit_surplus: Array = []
		for i in n_e:
			entry_surplus.append(int(entries[i]["lanes"]) - int(entries[i]["commits"]))
		for j in n_x:
			exit_surplus.append(int(exits[j]["lanes"]) - int(exits[j]["commits"]))

		var any_surplus: bool = false
		for s in entry_surplus:
			if s > 0:
				any_surplus = true
				break
		if not any_surplus:
			for s2 in exit_surplus:
				if s2 > 0:
					any_surplus = true
					break
		if not any_surplus:
			break

		var first_is_entry: bool = true
		var first_idx: int = -1
		var b_surplus: int = 0
		var b_ratio: float = 0.0
		var b_lanes: int = 0
		var b_id: int = 0
		for i in n_e:
			var s: int = entry_surplus[i]
			var commits: int = int(entries[i]["commits"])
			var ratio: float = 99999.0 if commits <= 0 else float(int(entries[i]["lanes"])) / float(commits)
			var lanes: int = int(entries[i]["lanes"])
			var id: int = int(entries[i]["id"])
			if _better_first(s, ratio, lanes, id, b_surplus, b_ratio, b_lanes, b_id, first_idx < 0):
				first_is_entry = true
				first_idx = i
				b_surplus = s
				b_ratio = ratio
				b_lanes = lanes
				b_id = id
		for j in n_x:
			var s2: int = exit_surplus[j]
			var commits2: int = int(exits[j]["commits"])
			var ratio2: float = 99999.0 if commits2 <= 0 else float(int(exits[j]["lanes"])) / float(commits2)
			var lanes2: int = int(exits[j]["lanes"])
			var id2: int = int(exits[j]["id"])
			if _better_first(s2, ratio2, lanes2, id2, b_surplus, b_ratio, b_lanes, b_id, first_idx < 0):
				first_is_entry = false
				first_idx = j
				b_surplus = s2
				b_ratio = ratio2
				b_lanes = lanes2
				b_id = id2
		if first_idx < 0:
			break

		var second_idx: int = -1
		var s_surplus: int = 0
		var s_ratio: float = 0.0
		var s_lanes: int = 0
		var s_id: int = 0
		var s_cell: int = 0
		if first_is_entry:
			var i2: int = first_idx
			for j2 in n_x:
				var cell: int = int(matrix[i2][j2])
				if cell == -1:
					continue
				var s3: int = exit_surplus[j2]
				var commits3: int = int(exits[j2]["commits"])
				var ratio3: float = 99999.0 if commits3 <= 0 else float(int(exits[j2]["lanes"])) / float(commits3)
				var lanes3: int = int(exits[j2]["lanes"])
				var id3: int = int(exits[j2]["id"])
				if _better_second(cell, s3, ratio3, lanes3, id3, s_cell, s_surplus, s_ratio, s_lanes, s_id, second_idx < 0):
					second_idx = j2
					s_surplus = s3
					s_ratio = ratio3
					s_lanes = lanes3
					s_id = id3
					s_cell = cell
		else:
			var j4: int = first_idx
			for i3 in n_e:
				var cell2: int = int(matrix[i3][j4])
				if cell2 == -1:
					continue
				var s4: int = entry_surplus[i3]
				var commits4: int = int(entries[i3]["commits"])
				var ratio4: float = 99999.0 if commits4 <= 0 else float(int(entries[i3]["lanes"])) / float(commits4)
				var lanes4: int = int(entries[i3]["lanes"])
				var id4: int = int(entries[i3]["id"])
				if _better_second(cell2, s4, ratio4, lanes4, id4, s_cell, s_surplus, s_ratio, s_lanes, s_id, second_idx < 0):
					second_idx = i3
					s_surplus = s4
					s_ratio = ratio4
					s_lanes = lanes4
					s_id = id4
					s_cell = cell2
		if second_idx < 0:
			break

		var ei: int = first_idx if first_is_entry else second_idx
		var xj: int = second_idx if first_is_entry else first_idx
		matrix[ei][xj] = int(matrix[ei][xj]) + 1
		entries[ei]["commits"] = int(entries[ei]["commits"]) + 1
		exits[xj]["commits"] = int(exits[xj]["commits"]) + 1

		if debug:
			_print_matrix("Iteration %d: E%s -> X%s" % [
				iteration, str(entries[ei]["id"]), str(exits[xj]["id"])],
				entries, exits, matrix)

	if debug:
		_print_matrix("Phase 2 complete after %d iterations" % iteration, entries, exits, matrix)

	return { "matrix": matrix, "entries": entries, "exits": exits }

# =============================================================================
# PHASE 3 — assign specific lanes and emit arcs
# =============================================================================
#
# Rotation order: sweep clockwise around the junction, starting from the
# entry's own physical position. The first exit encountered (excluding the
# entry's own segment, which is the U-turn) is "right next to" the entry.
#
# For an exit, the same scan but anticlockwise; numerically it is the same
# formula (see _rotation_offset).
#
# Returned arcs use algorithm ordinals: 1 = innermost lane, N = outermost.

static func assign_phase3(entries: Array, exits: Array, matrix: Array, debug: bool = false) -> Array:
	var n_e: int = entries.size()
	var n_x: int = exits.size()

	var entry_pos_angle: Array = []
	var exit_pos_angle: Array = []
	for i in n_e:
		var d: Vector3 = entries[i]["dir"]
		entry_pos_angle.append(_screen_angle(Vector3(-d.x, 0.0, -d.z)))
	for j in n_x:
		var d2: Vector3 = exits[j]["dir"]
		exit_pos_angle.append(_screen_angle(Vector3(d2.x, 0.0, d2.z)))

	# Entry rotation orders.
	var entry_order: Array = []
	for i in n_e:
		var e_ang: float = entry_pos_angle[i]
		var items: Array = []
		for j in n_x:
			if matrix[i][j] <= 0:
				continue
			var x_ang: float = exit_pos_angle[j]
			var off: float = fposmod(e_ang - x_ang, 360.0)
			items.append({ "j": j, "off": off })
		items.sort_custom(func(a, b):
			if absf(a["off"] - b["off"]) > 0.001:
				return a["off"] < b["off"]
			return a["j"] < b["j"])
		var order: Array = []
		for it in items:
			order.append(it["j"])
		entry_order.append(order)

	# Exit rotation orders.
	var exit_order: Array = []
	for j in n_x:
		var x_ang2: float = exit_pos_angle[j]
		var items2: Array = []
		for i in n_e:
			if matrix[i][j] <= 0:
				continue
			var e_ang2: float = entry_pos_angle[i]
			var off2: float = fposmod(e_ang2 - x_ang2, 360.0)
			items2.append({ "i": i, "off": off2 })
		items2.sort_custom(func(a, b):
			if absf(a["off"] - b["off"]) > 0.001:
				return a["off"] < b["off"]
			return a["i"] < b["i"])
		var order2: Array = []
		for it2 in items2:
			order2.append(it2["i"])
		exit_order.append(order2)

	# Entry lane assignment.
	var entry_slots: Array = []
	for i in n_e:
		var order: Array = entry_order[i]
		var commits: int = 0
		for j in order:
			commits += int(matrix[i][j])
		var lanes: int = int(entries[i]["lanes"])
		var slots: Array = []
		var k: int = 0
		for j in order:
			var cnt: int = int(matrix[i][j])
			for sub in cnt:
				var ord: int = _lane_for_commit(k, lanes, commits)
				slots.append({ "exit_j": j, "sub": sub, "lane": ord })
				k += 1
		entry_slots.append(slots)

	# Exit lane assignment.
	var exit_slots: Array = []
	for j in n_x:
		var order2: Array = exit_order[j]
		var commits2: int = 0
		for i in order2:
			commits2 += int(matrix[i][j])
		var lanes2: int = int(exits[j]["lanes"])
		var slots2: Array = []
		var k2: int = 0
		for i in order2:
			var cnt2: int = int(matrix[i][j])
			for sub2 in cnt2:
				var ord2: int = _lane_for_commit(k2, lanes2, commits2)
				slots2.append({ "entry_i": i, "sub": sub2, "lane": ord2 })
				k2 += 1
		exit_slots.append(slots2)

	# Match up.
	var arcs: Array = []
	for i in n_e:
		for s in entry_slots[i]:
			var j3: int = s["exit_j"]
			var sub3: int = s["sub"]
			var el: int = s["lane"]
			var xl: int = -1
			for xs in exit_slots[j3]:
				if xs["entry_i"] == i and xs["sub"] == sub3:
					xl = xs["lane"]
					break
			if xl < 0:
				continue
			arcs.append({
				"entry_i": i, "entry_lane": el,
				"exit_j": j3, "exit_lane": xl,
			})

	if debug:
		_print_phase3(entries, exits, matrix, entry_order, exit_order, entry_slots, exit_slots, arcs)

	return arcs

# =============================================================================
# Helpers
# =============================================================================

static func _screen_angle(d: Vector3) -> float:
	# 0 = east, 90 = north, 180 = west, 270 = south.
	var ang_rad: float = atan2(-d.z, d.x)
	return fposmod(rad_to_deg(ang_rad), 360.0)

static func _lane_for_commit(k: int, lanes: int, commits: int) -> int:
	if commits <= 0:
		return 1
	var step: float = float(lanes) / float(commits)
	var pos: float = 0.5 + step * float(k)
	var lane: int = int(floor(pos + 0.5))
	return clampi(lane, 1, lanes)

static func _better_first(a_surplus: int, a_ratio: float, a_lanes: int, a_id: int,
		b_surplus: int, b_ratio: float, b_lanes: int, b_id: int, no_best: bool) -> bool:
	if no_best:
		return true
	if a_surplus != b_surplus:
		return a_surplus > b_surplus
	if absf(a_ratio - b_ratio) > 0.0001:
		return a_ratio > b_ratio
	if a_lanes != b_lanes:
		return a_lanes > b_lanes
	return a_id < b_id

static func _better_second(a_cell: int, a_surplus: int, a_ratio: float, a_lanes: int, a_id: int,
		b_cell: int, b_surplus: int, b_ratio: float, b_lanes: int, b_id: int, no_best: bool) -> bool:
	if no_best:
		return true
	var a_soft: bool = (a_cell == -2)
	var b_soft: bool = (b_cell == -2)
	if a_soft != b_soft:
		return not a_soft
	if a_surplus != b_surplus:
		return a_surplus > b_surplus
	if absf(a_ratio - b_ratio) > 0.0001:
		return a_ratio > b_ratio
	if a_lanes != b_lanes:
		return a_lanes > b_lanes
	return a_id < b_id

static func _angle_between_deg(a: Vector3, b: Vector3) -> float:
	var da: Vector3 = Vector3(a.x, 0.0, a.z)
	var db: Vector3 = Vector3(b.x, 0.0, b.z)
	if da.length_squared() < 0.0001 or db.length_squared() < 0.0001:
		return 0.0
	da = da.normalized()
	db = db.normalized()
	var dot: float = clampf(da.dot(db), -1.0, 1.0)
	return rad_to_deg(acos(dot))

static func _row_sum(matrix: Array, i: int) -> int:
	var s: int = 0
	for j in matrix[i].size():
		if int(matrix[i][j]) > 0:
			s += int(matrix[i][j])
	return s

static func _col_sum(matrix: Array, j: int) -> int:
	var s: int = 0
	for i in matrix.size():
		if int(matrix[i][j]) > 0:
			s += int(matrix[i][j])
	return s

static func _fmt_str(s: String, w: int) -> String:
	var out: String = s
	while out.length() < w:
		out = " " + out
	return out

static func _print_matrix(title: String, entries: Array, exits: Array, matrix: Array) -> void:
	print("")
	print("=== %s ===" % title)
	var header: String = "         "
	for j in exits.size():
		var x: Dictionary = exits[j]
		var cell: String = "%s(%d,%d)" % [str(x["id"]), int(x["lanes"]), _col_sum(matrix, j)]
		header += _fmt_str(cell, 12)
	print(header)
	for i in entries.size():
		var e: Dictionary = entries[i]
		var prefix: String = "E%s(%d,%d)" % [str(e["id"]), int(e["lanes"]), _row_sum(matrix, i)]
		var line: String = _fmt_str(prefix, 9)
		for j in exits.size():
			var v: int = int(matrix[i][j])
			if v < 0:
				line += _fmt_str("(%d)" % v, 12)
			else:
				line += _fmt_str(str(v), 12)
		print(line)

static func _print_phase3(entries: Array, exits: Array, matrix: Array,
		entry_order: Array, exit_order: Array,
		entry_slots: Array, exit_slots: Array, arcs: Array) -> void:
	print("")
	print("============ Phase 3 ============")

	print("")
	print("-- Entry rotation orders (CW from own position) --")
	for i in entries.size():
		var ids: Array = []
		for j in entry_order[i]:
			ids.append("X%s" % str(exits[j]["id"]))
		print("  E%s: %s" % [str(entries[i]["id"]), ", ".join(ids)])

	print("")
	print("-- Exit rotation orders (same numeric formula) --")
	for j in exits.size():
		var ids2: Array = []
		for i in exit_order[j]:
			ids2.append("E%s" % str(entries[i]["id"]))
		print("  X%s: %s" % [str(exits[j]["id"]), ", ".join(ids2)])

	print("")
	print("-- Entry lane assignments --")
	for i in entries.size():
		var parts: Array = []
		for s in entry_slots[i]:
			parts.append("->X%s.%d @lane%d" % [
				str(exits[s["exit_j"]]["id"]), s["sub"], s["lane"]])
		print("  E%s (%d lanes): %s" % [
			str(entries[i]["id"]), entries[i]["lanes"], "  ".join(parts)])

	print("")
	print("-- Exit lane assignments --")
	for j in exits.size():
		var parts2: Array = []
		for s2 in exit_slots[j]:
			parts2.append("<-E%s.%d @lane%d" % [
				str(entries[s2["entry_i"]]["id"]), s2["sub"], s2["lane"]])
		print("  X%s (%d lanes): %s" % [
			str(exits[j]["id"]), exits[j]["lanes"], "  ".join(parts2)])

	print("")
	print("-- Final arcs --")
	for a in arcs:
		print("  E%s lane %d -> X%s lane %d" % [
			str(entries[a["entry_i"]]["id"]), a["entry_lane"],
			str(exits[a["exit_j"]]["id"]), a["exit_lane"]])
