class_name RoadSegment
extends Node3D

var uid: int = 0

var road_type: RoadType
var curve: Curve3D
var start_node: RoadNode
var end_node: RoadNode

var _mesh_instance: MeshInstance3D
var _material: StandardMaterial3D
var _base_color: Color = Color(0.22, 0.22, 0.25)
var _hovered: bool = false

var _pillar_root: Node3D

func setup(rt: RoadType, c: Curve3D) -> void:
	road_type = rt
	curve = c
	_do_rebuild()

func rebuild_mesh() -> void:
	_do_rebuild()

func length() -> float:
	if curve == null:
		return 0.0
	return curve.get_baked_length()

func avg_abs_height() -> float:
	if curve == null:
		return 0.0
	var n := 16
	var total := 0.0
	var baked := curve.get_baked_length()
	for i in n:
		var t := float(i) / float(n - 1)
		total += absf(curve.sample_baked(t * baked).y)
	return total / float(n)

func cost() -> float:
	if road_type == null or curve == null:
		return 0.0
	var L := length()
	var lanes := road_type.lane_count()
	var cfg := CostConfig.new()
	var base := L * float(lanes) * cfg.lane_rate
	
	# Add elevation cost multiplier
	var avg_h := avg_abs_height()
	var multiplier := 1.0 + (avg_h * 0.5)
	return base * multiplier

func set_preview_validity(valid: bool) -> void:
	if _material == null:
		return
	if _hovered:
		return
	if valid:
		_material.albedo_color = _base_color
	else:
		_material.albedo_color = Color(0.68, 0.15, 0.15)

func set_hovered(on: bool) -> void:
	_hovered = on
	if _material == null:
		return
	if on:
		_material.albedo_color = Color(0.85, 0.35, 0.15)
	else:
		_material.albedo_color = _base_color

func is_hovered() -> bool:
	return _hovered

func reverse() -> void:
	if curve == null:
		return
	var old_start := start_node
	var old_end := end_node
	var L: float = curve.get_baked_length()
	var samples: int = maxi(8, int(L * 0.5))
	var new_curve := Curve3D.new()
	for i in range(samples + 1):
		var t: float = 1.0 - float(i) / float(samples)
		new_curve.add_point(curve.sample_baked(t * L))
	curve = new_curve
	start_node = old_end
	end_node = old_start
	if old_start != null:
		for e in old_start.segment_ends:
			var ed: Dictionary = e
			if ed["segment"] == self:
				ed["is_start"] = false
				break
	if old_end != null:
		for e in old_end.segment_ends:
			var ed: Dictionary = e
			if ed["segment"] == self:
				ed["is_start"] = true
				break
	_do_rebuild()

func _do_rebuild() -> void:
	_ensure_mesh_instance()
	if road_type == null or curve == null:
		return
	var L := curve.get_baked_length()
	var inset_start: float = 0.0
	var inset_end: float = 0.0
	if not _is_pure_waypoint(start_node):
		inset_start = minf(RoadMesh.VISUAL_INSET, L / 3.0)
	if not _is_pure_waypoint(end_node):
		inset_end = minf(RoadMesh.VISUAL_INSET, L / 3.0)
	var mesh := RoadMesh.build_slab(curve, road_type, inset_start, inset_end)
	_mesh_instance.mesh = mesh
	_rebuild_pillars()

static func _is_pure_waypoint(node: RoadNode) -> bool:
	if node == null:
		return false
	return node.is_pass_through()

func _ensure_mesh_instance() -> void:
	if _mesh_instance != null:
		return
	_mesh_instance = MeshInstance3D.new()
	_material = StandardMaterial3D.new()
	_material.albedo_color = _base_color
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.roughness = 0.95
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)

func _rebuild_pillars() -> void:
	if start_node != null:
		_build_node_pillar(start_node)
	if end_node != null:
		_build_node_pillar(end_node)

func _build_node_pillar(node: RoadNode) -> void:
	if node.position.y <= 0.1: return
	if node.pillar_instance != null: return
	
	var mesh_inst = MeshInstance3D.new()
	var box = BoxMesh.new()
	var width = road_type.total_width() * 0.6
	box.size = Vector3(width, node.position.y, width)
	mesh_inst.mesh = box
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.3, 0.35)
	mesh_inst.material_override = mat
	
	mesh_inst.position = Vector3(node.position.x, node.position.y * 0.5, node.position.z)
	get_tree().current_scene.add_child(mesh_inst)
	node.pillar_instance = mesh_inst
	
static func clear_node_pillar(node: RoadNode) -> void:
	if node != null and node.pillar_instance != null:
		if is_instance_valid(node.pillar_instance):
			node.pillar_instance.queue_free()
		node.pillar_instance = null
