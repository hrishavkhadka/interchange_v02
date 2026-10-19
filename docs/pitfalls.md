# Pitfalls

Known traps. Read this before touching a subsystem. Add an entry whenever a bug takes more than ~15 minutes to diagnose, or when a subtlety bites us that a future reader would fall into again.

## Format

```
## <area> — <one-line symptom>
**Cause:** <one-line root cause>
**Fix:** <what we did / should do>
**Detected in:** Phase N/M (or "pre-existing")
**Files:** <affected files>
**Status:** fixed / open / workaround-only
```

---

## Curve3D — Curved road renders with chamfered corners

**Cause:** `Curve3D.add_point(pos)` without handle args gives each point zero in/out handles. Zero handles = straight line to neighbors. The 4-point C-curve and 7-point S-curve were polylines, not curves.

**Fix:** Use `add_point(pos, in_handle, out_handle)`. Quadratic Bezier `P0 → C → P2` as cubic: `out_handle(P0) = 2/3 * (C - P0)`, `in_handle(P2) = 2/3 * (C - P2)`. Cubic `P0 → C1 → C2 → P3`: `out_handle(P0) = C1 - P0`, `in_handle(P3) = C2 - P3`.

**Detected in:** Phase 1/4
**Files:** `scripts/build/road_builder.gd` — `_build_c_curve`, `_build_s_curve`
**Status:** fixed

---

## RoadOps — Curved segment hit detection snaps to chord, not curve

**Cause:** `find_segment_under_point`, `find_nearest_segment`, `find_crossings` project to the **straight chord** between `start_node.position` and `end_node.position`. Curved segments bulge away from the chord — hovering the visible road returns nothing (or a false positive near the chord). `find_lane_under_point` is already curve-aware via `_project_to_curve_xz`; the segment path isn't.

**Fix:** Pending Phase 2/4. Project onto the `Curve3D` via `sample_baked` (or verify `Curve3D.get_closest_offset` handles Y correctly).

**Detected in:** Phase 1/4 diagnosis
**Files:** `scripts/core/road_ops.gd`
**Status:** fixed

---

## RoadBuilder — Splitting a curved segment flattens the curve

**Cause:** `_split_existing_segment` → `_create_chain` → `_create_segment` → `_two_point_curve`. Two-point curves have zero handles, so both halves of the split are straight. `CurveMath.slice` exists and works but isn't called from the splitter — only from `_commit_curve_data` for long-curve waypointing.

**Fix:** Pending Phase 3/4. `_split_existing_segment` should accept a baked distance, call `CurveMath.slice(seg.curve, 0, d)` and `CurveMath.slice(seg.curve, d, total)`, place mid node at `seg.curve.sample_baked(d)` (not the cursor projection), and create two segments with sliced curves.

**Detected in:** Phase 1/4 diagnosis
**Files:** `scripts/build/road_builder.gd` — `_split_existing_segment`
**Status:** fixed

---

## RoadBuilder — S-curve preview degenerates during SCURVE_MID2

**Cause:** `_update()` for `BuildStage.SCURVE_MID2` calls `_build_s_curve(_p_start, _p_mid1, _p_mid2, _p_mid2)` — `_p_mid2` passed as both p2 and p3, giving zero length for the preview's second half.

**Fix:** Pending Phase 4/4. During SCURVE_MID2, either (a) use mouse position as tentative end (`p3`) with the understanding that only the first half is locked, or (b) preview only the first half until mid2 is clicked.

**Detected in:** Phase 1/4 diagnosis
**Files:** `scripts/build/road_builder.gd` — `_update`
**Status:** open (Phase 4/4)

## RoadNode — Tight curves create junctions instead of waypoints
**Cause:** `is_pass_through()` checked the angle between the segment endpoints (the chord), not the actual curve tangents.
**Fix:** Calculate the actual tangent using the Bezier control handles (`get_point_in` / `get_point_out`). For straight roads (which returned zero-length baked tangents), fallback to chord direction.
**Detected in:** Phase 1/4
**Files:** `scripts/core/road_node.gd`
**Status:** fixed

## Curve Math — Waypoint nodes snap to previous nodes on tight curves
**Cause:** `RoadGraph.get_or_create_waypoint()` snaps to existing nodes within 5.0m. On tight curves, the waypoint was closer than 5m to the start point, so the node was placed at the start, leaving the mesh geometry separated from the node.
**Fix:** Added `force_new` parameter to `get_or_create()`. Internal curve waypoints now force a new node at the exact curve position.
**Detected in:** Phase 1/4
**Files:** `scripts/core/road_graph.gd`, `scripts/build/road_builder.gd`
**Status:** fixed

## RoadBuilder — Sharp curves invert the inner mesh
**Cause:** If the radius of curvature is smaller than the half-width of the road, the inner edge of the curve crosses over itself, creating bowtie faces that disappear under backface culling.
**Fix:** Added `_get_min_radius()` to sample curvature. `_validate_preview()` now rejects placements where minimum radius < `half_width + 1.5 * lane_width`.
**Detected in:** Phase 1/4
**Files:** `scripts/build/road_builder.gd`
**Status:** fixed

## RoadBuilder — Red preview could still be placed
**Cause:** The radius check was only present in `_validate_preview()`. The actual click handlers (`_click_curve_end`, etc.) called `is_placement_valid` directly and missed the radius check.
**Fix:** Extracted validation into `_is_placement_valid()`, which is now called by both the preview updater and the click handlers.
**Detected in:** Phase 1/4
**Files:** `scripts/build/road_builder.gd`
**Status:** fixed

## CurveMath — Slicing causes mesh folds and invisible remnants
**Cause:** The previous De Casteljau slice used an approximate binary search for arc length, causing sub-curves to be physically misaligned with their parent nodes. This caused nodes to appear in the middle of meshes, the inner mesh to fold (nipple), and invisible 0-length segments to be created.
**Fix:** Rewrote `slice()` to sample exact start/end tangents and generate a mathematically perfect 2-point cubic Bezier for the slice.
**Detected in:** Phase 1/4
**Files:** `scripts/core/curve_math.gd`
**Status:** fixed

## RoadBuilder — Curve spiked ("nipple") when snapped
**Cause:** A handle realignment hack was stretching handles after the curve was built, causing the curve to fold over itself.
**Fix:** `_commit_curve_data` now rebuilds the curve from scratch using the snapped node positions, ensuring handles are calculated from the final anchored points.
**Detected in:** Phase 1/4
**Files:** `scripts/build/road_builder.gd`
**Status:** fixed

## RoadBuilder — Waypoint absorption fails on 2-point cubic curves
**Cause:** `_absorb_waypoint` checked `point_count > 2` to detect curves. Our curves are 2-point cubics (2 points + handles), so the check always failed. The absorption fell through to straight-line creation, flattening the curve.
**Fix:** `_segment_has_curve()` now checks handle lengths instead of point count. `_absorb_waypoint` extracts the exact handles and builds a 3-point spline through the absorbed waypoint, preserving tangents before splitting.
**Detected in:** Phase 3/4
**Files:** `scripts/build/road_builder.gd`
**Status:** fixed
