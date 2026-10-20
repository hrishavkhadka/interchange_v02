# Architecture Reference

Deep reference for Interchange subsystems. `context.md` gives the overview; this file gives details.

Stubs marked `TODO` — flesh out when touched.

## Table of Contents

1. [Coordinate Conventions](#1-coordinate-conventions)
2. [Core Graph](#2-core-graph)
3. [Lane Graph](#3-lane-graph)
4. [Junction Arc Algorithm](#4-junction-arc-algorithm)
5. [Routing](#5-routing)
6. [Simulation](#6-simulation)
7. [Build Tools](#7-build-tools)
8. [Mesh Generation](#8-mesh-generation)
9. [Curve Math & Geometry](#9-curve-math--geometry)
10. [UI](#10-ui)
11. [Saved Format](#11-saved-format)

---

## 1. Coordinate Conventions

- **Up axis**: Y (Godot default).
- **Horizontal plane**: XZ.
- **Right-side driving** (US convention).
- **Lane index 0** = rightmost lane when facing forward along a segment's `start → end` direction.
- **Direction letters**: `F` = forward (start→end), `B` = backward (end→start).
- **Lane layout strings**: e.g. `FFBB` = two forward lanes on the right, two backward on the left, when looking along start→end.

---

## 2. Core Graph

### `RoadGraph` (autoload) — `scripts/core/road_graph.gd`

Owns all nodes and segments. Single source of truth.

**State**: `nodes: Array[RoadNode]`, `segments: Array[RoadSegment]`, `_next_id`, `_next_seg_uid`.

**Signals**: `node_added(node)`, `graph_changed()`.

**Batch mode**: `begin_batch()` suppresses `graph_changed` until `end_batch()`. Use when making N-related changes that should trigger one `LaneGraph` rebuild.

**Key methods**:

- `find_nearest(pos, radius) -> RoadNode`
- `get_or_create(pos, is_waypoint=false) -> RoadNode` — returns existing node within snap radius, else creates new
- `get_or_create_waypoint(pos) -> RoadNode`
- `register_segment(seg)` / `unregister_segment(seg)`
- `segment_by_uid(uid)` / `node_by_id(id)`

### `RoadNode` — `scripts/core/road_node.gd`

- `id: int`, `position: Vector3`
- `segment_ends: Array[Dictionary]` — each entry: `{ "segment": RoadSegment, "is_start": bool }`
- Flags: `is_entry`, `is_exit`, `is_waypoint`, `forced_junction`
- `is_pass_through() -> bool` — true if no turn happens here (pure waypoint)
- `add_segment_end(seg, is_start)`

### `RoadSegment` — `scripts/core/road_segment.gd`

- `uid: int`, `road_type: RoadType`, `curve: Curve3D`
- `start_node: RoadNode`, `end_node: RoadNode`
- `length()` → `curve.get_baked_length()`
- `rebuild_mesh()` — rebuilds slab via `RoadMesh.build_slab`
- `reverse()` — flips curve direction and node assignments
- `set_preview_validity(valid)`, `set_hovered(on)` — visual state

Long roads are split into multiple `RoadSegment`s at waypoints (every 30 lane-widths). Sliced via `CurveMath.slice`.

### `RoadType` — `scripts/core/road_type.gd`

- `id: String`, `display_name: String`, `lane_layout_string: String`
- `lane_width: float` (default 3.2m), `speed_limit_kmh: float`
- `total_width() -> float`, `lane_count() -> int`

---

## 3. Lane Graph

### `LaneGraph` (autoload) — `scripts/sim/lane_graph.gd`

Rebuilds all lanes and arcs whenever `RoadGraph.graph_changed` fires.

**State**: `lanes: Array[Lane]`, `arcs: Array[LaneArc]`.

### `Lane` — `scripts/sim/lane.gd`

Single drivable lane along a segment.

- `from_node`, `to_node`, `direction` (`"F"`/`"B"`), `curve: Curve3D` (offset from centerline), `length`, `segment`.
- **Trim rule**: lanes are trimmed at junctions using an angle-based formula (max 5.0× lane width), so sharp turns don't produce overlapping lane geometry.

### `LaneArc` — `scripts/sim/lane_arc.gd`

Directed connection from one lane to another across a junction or pass-through.

- `from_lane`, `to_lane`, `curve: Curve3D` (Bezier), `length`
- `enabled: bool` — only enabled arcs are routable
- `conflicting_arcs: Array[LaneArc]` — junction reservation system

---

## 4. Junction Arc Algorithm

`LaneArcAlgorithm` (`scripts/sim/lane_arc_algorithm.gd`) decides which lane-to-lane connections exist at each junction. Wrapped by `LaneArcBuilder` (`scripts/sim/lane_arc_builder.gd`).

### Three phases

**Phase 1 — Promise matrix.** For every (in-lane, out-lane) pair, initialize a promise value.

- U-turn (same segment, opposite directions): `-1` (forbidden).
- Soft-forbid (e.g. angle exceeds max): `-2` (forbidden unless surplus forces it).

**Phase 2 — Iterative commits based on surplus.** Count out-lanes-per-in-lane and in-lanes-per-out-lane. Commit arcs in order of scarcity — lanes with fewer alternatives get priority.

**Phase 3 — Clockwise exit ordering.** Exits around the junction ordered clockwise. In-lanes spread across out-lanes to minimize crossing and produce natural connections. Specific lane indices assigned.

### Pass-throughs

Pass-throughs are **not** hardcoded to 1-to-1 matching. The algorithm handles them based on lane counts.

### Overrides

Only algorithm-produced arcs are enabled. All other possible pairs exist as **disabled** arcs, available for manual toggle via `JunctionEditor`. Overrides tracked in `ArcOverrides` (`scripts/sim/arc_overrides.gd`) per node.

---

## 5. Routing

### `LanePathfinder` — `scripts/sim/lane_pathfinder.gd`

A\* search on the lane graph.

- Cost: travel time + lane-change penalty.
- Output: `Array[PathStep]` — the sequence a vehicle follows.

---

## 6. Simulation

### `VehicleManager` — `scripts/sim/vehicle_manager.gd`

Owns all vehicles and per-step simulation.

- Spawns from `VehicleOrder` (TODO: locate definition) and `DemandMatrix`.
- Occupancy: leader/follower lookup per lane and per arc.
- IDM car-following.
- MOBIL lane changes.
- Junction arc reservations: entering vehicle reserves conflicting arcs.

### `Vehicle` — `scripts/sim/vehicle.gd`

- `path: Array[PathStep]`, `speed: float`, `step_index: int`.
- Moves kinematically along the current step's curve. **No physics bodies.**

### `PathStep` — `scripts/sim/path_step.gd`

Represents one traversal unit (lane or arc) along a vehicle's path.

---

## 7. Build Tools

### `RoadBuilder` — `scripts/build/road_builder.gd`

Main road placement tool.

**Modes** (`enum Mode`): `POINTER`, `ROAD`, `DEMOLISH`, `REVERSE`, `UPDATE`, `MOVE`.

**Build stages** (`enum BuildStage`): `NONE`, `STRAIGHT_END`, `CURVE_MID`, `CURVE_END`, `SCURVE_MID1`, `SCURVE_MID2`, `SCURVE_END`.

**Shape flow** (from `settings.road_shape`):
- `STRAIGHT`: click start → click end → commit.
- `CURVE`: click start → click mid (control point) → click end → commit.
- `S_CURVE`: click start → click control1 → click control2 → click end → commit.

**Move It Tool (`Mode.MOVE`)**:
- Selects nodes or segments. Renders green node spheres and cyan handle spheres (connected by lines).
- **Node Dragging**: Translates the node position. Connected `Curve3D` start/end points update. Handles translate automatically.
- **Handle Dragging**: Rotates the handle around the node. Magnitude is preserved. `Alt` mirrors the rotation to the adjacent segment.
- **Segment Bowing**: Adds a perpendicular offset to both handles, creating a U-shape.
- **Validation**: On release, checks against other segments. Reverts if overlapping.
- **Straight Roads**: Synthesizes handles at `dist / 3.0` to allow dragging straight roads into curves.

### `SnapResolver` — `scripts/build/snap_resolver.gd`

Resolves raw cursor hit to a snapped position + metadata.

**Priority chain** (`resolve_position`): node snap → lane snap → segment snap → guide snap → free.

**Returns**: `{ point: Vector3, kind: String, t_segment: Variant, guide_dir: Variant }`.

`resolve_direction` handles angular snapping (config in `BuildSettings`).

### `JunctionEditor` — `scripts/build/junction_editor.gd`

- Shift-click a pass-through to promote it.
- Drag entry/exit dots to toggle lane arcs.
- Panel with "Clear all" and "Reset to default".

### `MarkerEditor` — `scripts/build/marker_editor.gd`

Places entry/exit markers on nodes.

---

## 8. Mesh Generation

### `RoadMesh` — `scripts/core/road_mesh.gd`

- `build_slab(curve, road_type, inset_start, inset_end) -> ArrayMesh`.
- Samples curve every 0.5 m, extrudes to lane width.
- `VISUAL_INSET` shrinks mesh from segment ends to avoid overlapping junction meshes.

### `JunctionMesh` — `scripts/core/junction_mesh.gd`

Generates the intersection polygon where segments meet.

### `TransitionMesh` — `scripts/sim/transition_mesh.gd`

TODO — purpose unclear from filename alone; fill in when touched.

---

## 9. Curve Math & Geometry

### `CurveMath` — `scripts/core/curve_math.gd`

- `slice(curve: Curve3D, start_dist: float, end_dist: float) -> Curve3D` — Samples the parent curve's exact tangents at `start_dist` and `end_dist` and generates a mathematically perfect 2-point cubic Bézier. This guarantees the sliced sub-curve perfectly aligns with the parent curve's geometry, preventing mesh desync or visual kinks at waypoint boundaries.

**Pitfall**: `Curve3D.add_point(pos)` with no handle args produces a **polyline** (0 handles = straight line to neighbors). For curves, pass handles: `add_point(pos, in_handle, out_handle)`. See `docs/pitfalls.md`.

**Quadratic-as-cubic**: to represent a quadratic Bezier `P0, C, P2` as a cubic:

- `out_handle(P0) = 2/3 * (C - P0)`
- `in_handle(P2) = 2/3 * (C - P2)`

### `RoadOps` — `scripts/core/road_ops.gd`

- `find_segment_under_point(pos) -> Variant` — cursor hit test. Projects to `Curve3D` via `_get_closest_point_on_curve`.
- `find_nearest_segment(pos, radius) -> Variant` — projects to `Curve3D`.
- `is_placement_valid(...) -> bool` — samples curve segments every 5m for collision checks against the new road.

**Curve-aware projection**: `_get_closest_point_on_curve()` does a two-pass search (16 coarse samples + binary refinement) to find the exact bake distance and point on a `Curve3D`.

**Known limitation**: `find_segment_under_point`, `find_nearest_segment`, `find_crossings` project to the **chord** between segment endpoints. Correct for straight segments; wrong for curved segments. Phase 2/4 fixes. `find_lane_under_point` is already curve-aware via `_project_to_curve_xz`.

---

## 10. UI

### `MainToolbar` — `scripts/ui/main_toolbar.gd`

- Tool selection (POINTER/ROAD/DEMOLISH/REVERSE/UPDATE).
- Road type dropdown (from `RoadBuilder.ROAD_TYPE_DEFS`).
- Road shape dropdown (Straight / Curve / S-Curve) — sub-menu.
- Snapping toggle.
- Level data toggle.

### `RoadTypeMenu` — `scripts/ui/road_type_menu.gd`

Menu for road-type selection.

### `HUD` — `scripts/ui/hud.gd`

In-game HUD overlay.

### `LevelDataPanel` — `scripts/ui/level_data_panel.gd`

Level metadata display (budget, time, demand matrix).

---

## 11. Saved Format
Levels are saved as JSON in `user://levels/`.
**Format Version**: 2
- `version`, `bounds`, `budget`, `time_limit`
- `blockers`, `fixed_roads`, `props`
- `demand matrix`, `vehicle_order`
- `nodes`: `[position, is_waypoint, is_entry, is_exit, demand]`
- `segments`: `[road_type, start_node, end_node, curve_data]`
  - `curve_data`: Array of `{ pos, in, out }` for each control point, preserving exact Bézier geometry.
- Arc overrides via `ArcOverrides`, serialized alongside.

## Appendix: Data Flow

1. **Build**: `RoadBuilder` → `RoadGraph` (`get_or_create`, `register_segment`) → `graph_changed`
2. **Lane rebuild**: `LaneGraph` catches `graph_changed` → rebuilds `lanes` / `arcs` via `LaneBuilder` + `LaneArcBuilder`
3. **Routing**: `LanePathfinder` A\* over `LaneGraph.arcs`
4. **Simulation**: `VehicleManager` iterates vehicles, uses `PathStep`s, checks occupancy, updates positions
5. **Render**: `RoadSegment.rebuild_mesh()` + `JunctionRenderer` on graph change
