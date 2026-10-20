class_name BuildSettings
extends Resource

enum RoadShape { STRAIGHT, CURVE, S_CURVE }

@export var snap_node: bool = true
@export var snap_lane: bool = true
@export var snap_segment: bool = true
@export var snap_guide: bool = true
@export var snap_length: bool = true
@export var snap_angle: bool = true
@export var angle_step_deg: float = 15.0
@export var road_shape: RoadShape = RoadShape.STRAIGHT
@export var elevation_step: float = 1.0
