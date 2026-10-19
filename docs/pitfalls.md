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
**Status:** fixed (pending in-game verification)

---

## RoadOps — Curved segment hit detection snaps to chord, not curve

**Cause:** `find_segment_under_point`, `find_nearest_segment`, `find_crossings` project to the **straight chord** between `start_node.position` and `end_node.position`. Curved segments bulge away from the chord — hovering the visible road returns nothing (or a false positive near the chord). `find_lane_under_point` is already curve-aware via `_project_to_curve_xz`; the segment path isn't.

**Fix:** Pending Phase 2/4. Project onto the `Curve3D` via `sample_baked` (or verify `Curve3D.get_closest_offset` handles Y correctly).

**Detected in:** Phase 1/4 diagnosis
**Files:** `scripts/core/road_ops.gd`
**Status:** open (Phase 2/4)

---

## RoadBuilder — Splitting a curved segment flattens the curve

**Cause:** `_split_existing_segment` → `_create_chain` → `_create_segment` → `_two_point_curve`. Two-point curves have zero handles, so both halves of the split are straight. `CurveMath.slice` exists and works but isn't called from the splitter — only from `_commit_curve_data` for long-curve waypointing.

**Fix:** Pending Phase 3/4. `_split_existing_segment` should accept a baked distance, call `CurveMath.slice(seg.curve, 0, d)` and `CurveMath.slice(seg.curve, d, total)`, place mid node at `seg.curve.sample_baked(d)` (not the cursor projection), and create two segments with sliced curves.

**Detected in:** Phase 1/4 diagnosis
**Files:** `scripts/build/road_builder.gd` — `_split_existing_segment`
**Status:** open (Phase 3/4)

---

## RoadBuilder — S-curve preview degenerates during SCURVE_MID2

**Cause:** `_update()` for `BuildStage.SCURVE_MID2` calls `_build_s_curve(_p_start, _p_mid1, _p_mid2, _p_mid2)` — `_p_mid2` passed as both p2 and p3, giving zero length for the preview's second half.

**Fix:** Pending Phase 4/4. During SCURVE_MID2, either (a) use mouse position as tentative end (`p3`) with the understanding that only the first half is locked, or (b) preview only the first half until mid2 is clicked.

**Detected in:** Phase 1/4 diagnosis
**Files:** `scripts/build/road_builder.gd` — `_update`
**Status:** open (Phase 4/4)
