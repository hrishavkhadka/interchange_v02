# Decisions Log

ADR-style log of non-obvious design choices. Each entry: what was decided, why, what was rejected, consequences.

**Do not silently reverse a decision listed here.** If you want to change one, add a new entry that supersedes the old (mark the old `Superseded by ADR-N`).

---

## ADR-001 — Custom lane-arc algorithm instead of hardcoded rules

**Decided:** Lane-to-lane connections at junctions are decided by `LaneArcAlgorithm` (3-phase: promise matrix → surplus commits → clockwise ordering), not a lookup table of "if road type X meets road type Y, use connections Z".

**Why:** Hardcoded tables explode combinatorially (road types × angles × lane counts × driving side). The algorithm produces natural-looking results from first principles and scales to any combination.

**Rejected:** Manual connection tables; hardcoded 1-to-1 pass-through matching (algorithm handles pass-throughs).

**Consequences:** All arcs generated; only algorithm-approved ones enabled. Manual override always available via `JunctionEditor` + `ArcOverrides`.

---

## ADR-002 — Kinematic vehicles, no physics bodies

**Decided:** `Vehicle` moves kinematically along its path curve. No `RigidBody3D` / `CharacterBody3D`.

**Why:** Determinism (pillar #3), performance (200 vehicles), no physics tuning needed. A traffic puzzle benefits from predictability, not physical realism.

**Consequences:** Collision / reservation must be explicit (`VehicleManager` arc reservations). Vehicles cannot be pushed off course — always follow path.

---

## ADR-003 — 60 Hz fixed simulation timestep

**Decided:** Simulation updates at fixed 60 Hz. Rendering decoupled.

**Why:** Determinism. Same input → same output, frame-rate independent.

**Consequences:** Any `_process(dt)` use in simulation code must use the fixed `dt`, not the frame delta.

---

## ADR-004 — Long roads split into segments at waypoints

**Decided:** Roads longer than 30 lane-widths (~96 m) are split into multiple `RoadSegment`s at evenly spaced waypoints.

**Why:** Bounds per-segment complexity (lane count, mesh vertex count, A\* branching). Doesn't affect visuals because slices use `CurveMath.slice`.

**Rejected:** One `RoadSegment` per logical road (slow mesh builds, deep A\*).

**Consequences:** Waypoints are real `RoadNode`s, `is_pass_through()`, invisible if no turn happens. Watch for visual seams at slice boundaries on curves (part of Phase 2/4 testing).

---

## ADR-005 — Curve control points: pull-toward, not pass-through

**Decided:** In curve mode, the mid-click is a Bezier **control point** (CS2 semantics), not a "curve must pass through this point" constraint (Catmull-Rom semantics).

**Why:** Matches CS2 mental model. User clicks where they want to _pull_ the road toward.

**Rejected:** Catmull-Rom pass-through semantics — feasible but more math and diverges from CS2.

**Consequences:** Mid-click is _not_ on the road. If a future feature wants pass-through semantics (spline tool), it's a new shape option, not a change to Curve.

---

## ADR-006 — Sub-menu for road shapes, no modifier keys

**Decided:** Straight / C-Curve / S-Curve selected from a sub-menu on the Road tool button. No `Shift`-hold or modifier.

**Why:** Discoverable, consistent with CS2, no hidden keyboard state.

**Rejected:** `Shift`-hold for S-curve (proposed earlier, dropped).

**Consequences:** Three-click and four-click flows both behind the same tool button. User selects shape before placing.

---

## ADR-007 — Right-side driving (US)

**Decided:** Right-side driving.

**Why:** Target audience default. Lane layout strings interpret "right side" as the forward-direction side (`F`).

**Consequences:** Lane offset logic assumes right-side. Lane index 0 = rightmost when facing forward. Left-side driving would require mirrored offsets.

---

## ADR-008 — Flat terrain with blockers only

**Decided:** Terrain flat. Features exist only as impassable blockers around the play area.

**Why:** Focus on traffic management, not terrain.

**Consequences:** No terrain-following curves. Road elevation (overpasses/underpasses) is a per-segment feature, not terrain-driven.

---

## ADR-009 — No Photoshop-style curve handles (deferred)

**Decided:** Drag-handle curve editing (Pen-tool-style) is out of scope. MoveIt-style "drag the middle of the segment to bow it" is the future plan, deferred.

**Why:** Photoshop handles are a large UX investment with marginal benefit — curves are placed once and rarely edited.

**Rejected:** Pen-tool-style editing handles.

**Consequences:** `RoadSegment` does not store Bezier control points separately. They can be derived from `Curve3D` but are not first-class edit state.

---

## ADR-010 — Per-segment metadata, not per-logical-road

**Decided:** Info relevant to a road (curvature, length, mesh, control points) is stored per `RoadSegment`, not aggregated per logical multi-segment road.

**Why:** Segment-level granularity matches the data model (waypoints split long roads). Simpler than maintaining parallel "logical road" structure.

**Rejected:** Aggregating segments into a `LogicalRoad` object.

**Consequences:** Features needing "the whole road" (e.g. MoveIt drag across waypoints) must traverse segments via node adjacency. Watch for this when implementing MoveIt.

---

## ADR-011 — Move It handle dragging preserves magnitude and allows broken tangents
**Decided:** Dragging a tangent handle rotates it around the node but preserves its original length. By default, adjacent segments are allowed to break their tangent (creating sharp corners). Holding `Alt` mirrors the rotation to the adjacent segment to keep the road smooth.
**Why:** Allowing handle lengths to stretch freely causes self-intersecting loops. Preserving magnitude prevents "nipple" artifacts. Allowing tangents to break by default matches standard 3D modeling tools and gives the user full control over sharp corners.
**Rejected:** Auto-mirroring handles by default (can be frustrating for creating specific corners); allowing handles to scale infinitely.
**Consequences:** Players can build sharp corners by default, but must hold `Alt` to keep roads smooth.

---

## ADR-012 — Save curve data as Bézier handles, not polylines
**Decided:** `level_io.gd` serializes `Curve3D` as an array of control points and their `in`/`out` handles.
**Why:** Sampling curves into polylines destroys tangent data, breaking Move It and waypoint absorption on reloaded levels.
**Consequences:** Format version bumped to 2. A fallback is maintained for loading v1 (polyline) saves.

---

## ADR-013 — Elevation snapping adopts the target's height
**Decided:** When hovering over an elevated node/segment with the road tool, the current build elevation automatically snaps to the target's elevation, rather than remaining on the ground plane.
**Why:** Standard CS2 behavior. Allows connecting new roads to existing bridges without manually dialing in the exact height.
**Consequences:** `_resolve_end` and `_start_drag` now mutate `_current_elevation` when snapping to a node/segment.
