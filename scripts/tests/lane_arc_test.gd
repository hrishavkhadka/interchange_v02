extends Node

func _ready() -> void:
	test_pdf_example()

func test_pdf_example() -> void:
	print("")
	print("##########################################################")
	print("# PDF worked example: Phase 1 + 2 + 3                     #")
	print("##########################################################")

	var entries: Array = [
		{ "id": 1, "lanes": 5, "segment_id": 1, "dir": Vector3(1, 0, 0) },
		{ "id": 2, "lanes": 4, "segment_id": 2, "dir": Vector3(0, 0, 1) },
		{ "id": 3, "lanes": 1, "segment_id": 3, "dir": Vector3(-0.707, 0, -0.707) },
	]
	var exits: Array = [
		{ "id": 1, "lanes": 2, "segment_id": 1, "dir": Vector3(-1, 0, 0) },
		{ "id": 2, "lanes": 3, "segment_id": 2, "dir": Vector3(0, 0, -1) },
		{ "id": 3, "lanes": 1, "segment_id": 4, "dir": Vector3(1, 0, 0) },
		{ "id": 4, "lanes": 6, "segment_id": 5, "dir": Vector3(0, 0, 1) },
	]

	var p1: Dictionary = LaneArcAlgorithm.init_phase1(entries, exits, false)
	var p2: Dictionary = LaneArcAlgorithm.iterate_phase2(p1["entries"], p1["exits"], p1["matrix"], false)
	var arcs: Array = LaneArcAlgorithm.assign_phase3(p2["entries"], p2["exits"], p2["matrix"], true)
	print("")
	print("Total arcs emitted: %d" % arcs.size())
