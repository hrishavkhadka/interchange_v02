# Changelog

Append-only log of every phase commit. **Newest entries at the top.**



## 2026-10-19 — Phase 4/4 — Move It Tool (Node/Handle/Segment Dragging)
**Commit:** `<sha>` — `Phase 4/4 — Move It Tool (Node/Handle/Segment Dragging)`
**Files:** `scripts/build/road_builder.gd`, `scripts/ui/main_toolbar.gd`, `scripts/core/road_ops.gd`, `context.md`, `CHANGELOG.md`, `docs/architecture.md`, `docs/decisions.md`, `docs/pitfalls.md`
**Why:** Players needed the ability to adjust placed roads (Move It mod style) to fine-tune interchanges without demolishing and rebuilding.
**What:**
- Added `Mode.MOVE` and a toolbar button.
- Clicking a node or segment selects it and shows 3D gizmos (spheres and lines) for the entity and its tangent handles.
- **Node Dragging:** Translates the node and shifts the connected curve endpoints. Handles translate automatically to preserve curve tension.
- **Handle Dragging:** Rotates the tangent handle around the node while preserving its magnitude. Holding `Alt` mirrors the rotation to the adjacent segment for smooth continuous roads.
- **Segment Bowing:** Adds a perpendicular offset to both handles, bowing the road without moving the endpoints.
- **Straight Road Support:** Synthesizes temporary handles for straight roads so they can be grabbed and dragged into a curve.
- **Validation:** On mouse release, the moved geometry is checked against other roads using `RoadOps.is_placement_valid`. If it collides, the move reverts automatically.
**Tested:** Node translation, handle rotation, bowing, Alt-mirroring, straight-to-curve dragging, invalid move reversion. Handles and nodes render consistently on straight and curved roads.
**Follow-ups:** Elevation (raised/sunken roads) for nodes and handles. Undo/Redo system for edits.

## 2026-10-19 — Phase 2 & 3/4 — Curve hit detection and preserving split
**Commit:** `<sha>` — `Phase 2 & 3/4 — Curve hit detection and preserving split`
**Files:** `scripts/core/road_ops.gd`, `scripts/build/road_builder.gd`, `scripts/build/snap_resolver.gd`
**Why:** Hitboxes used straight chords, allowing roads to be built over curves. Splitting a curve at a T-junction converted it back to straight lines. Absorbing waypoints near curves flattened them.
**What:**
- Implemented `_get_closest_point_on_curve()` in `RoadOps`. Snapping, hovering, and demolishing now project onto the actual `Curve3D`.
- `is_placement_valid` now samples curves into 5m segments to accurately detect collisions against curved geometry.
- `_split_existing_segment` now calculates the exact bake distance, and uses `CurveMath.slice` to create two perfect curved sub-segments.
- Fixed `_absorb_waypoint` curve detection. It now checks handle lengths instead of `point_count` (since our curves are 2-point cubics).
- Absorbing a waypoint on a curve now builds a 3-point spline (`other_a → w → other_b`) preserving the original tangents. The splitter then slices this smoothly.
**Tested:** Snapping and building over curves. T-junctions on curves remain curved. Absorbing waypoints near curves preserves the curve and moves the junction smoothly.
**Follow-ups:** S-curve preview degeneracy (Phase 4), Move It tool (Phase 4).

## 2026-10-19 — Phase 1/4 — Curve geometry and builder
**Commit:** `<sha>` — `Phase 1/4 — Curve geometry and builder`
**Files:** `scripts/build/road_builder.gd`, `scripts/core/road_node.gd`, `scripts/core/curve_math.gd`, `scripts/core/road_graph.gd`
**Why:** The initial curve implementation created polyline approximations instead of Beziers, lacked straight-preview updates, placed junctions at waypoints, caused node-mesh desync on snapped curves, and allowed broken mesh inversion on sharp curves.
**What:**
- Fixed curve construction: C-curves use quadratic control points with a 0.5522 factor for perfect circular arcs. S-curves use proper cubic handles.
- Fixed `_update()` to render straight road previews (added missing `STRAIGHT_END` stage).
- Added exact tangent checks in `RoadNode.is_pass_through()`, ensuring tight curves remain waypoints rather than junctions.
- Upgraded `CurveMath.slice()` to guarantee perfect start/end tangents, eliminating the mesh/node desync that caused invisible remnants (A1/A2/A3).
- Added minimum radius validation. If the curve turns tighter than `half_width + 1.5 * lane_width`, the preview turns red and placement is blocked.
- Centralized placement validation to `_is_placement_valid()` to ensure red previews cannot be placed.
- Reduced curve waypoint density to 16 lanes (~51m). Equalized spacing so there are no tiny remnant segments.
- Enabled demolishing of tiny segments.
**Tested:** C-curves, S-curves, straight roads. Snapping works relative to the previous point. Free-placed points no longer shift. Tight curves do not become junctions. Red previews block placement. Demolish cleans up completely. Mesh perfectly aligns with waypoints.
**Follow-ups:** Curve-aware hit detection (Phase 2), curve-preserving splitting (Phase 3), Move It tool (Phase 4).




## Entry format

```
## YYYY-MM-DD — Phase N/M — Short title
**Commit:** `<sha>` — `<header line>`
**Files:** `path/a.gd`, `path/b.gd`, `docs/...`
**Why:** one-line reason this phase existed
**What:**
- concrete change 1
- concrete change 2
**Tested:** what passed in-game, and how
**Follow-ups:** known remaining issues (or "none")
```

---

<!-- No phases committed yet. First entry appears below once Phase 1/4 passes the in-game test protocol. -->
