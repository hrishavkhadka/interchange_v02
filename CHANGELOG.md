# Changelog

Append-only log of every phase commit. **Newest entries at the top.**

## 2026-10-19 — Phase 1/4 — Curve geometry and builder
**Commit:** `<sha>` — `Phase 1/4 — Curve geometry and builder`
**Files:** `scripts/build/road_builder.gd`, `scripts/core/road_node.gd`, `scripts/core/curve_math.gd`, `scripts/core/road_graph.gd`
**Why:** The initial curve implementation created polylines instead of Beziers, lacked straight-preview updates, placed junctions at waypoints, and allowed broken mesh inversion on sharp curves.
**What:**
- Fixed curve construction: C-curves now use quadratic control points to pass through the mid-click with correct tangents. S-curves use proper cubic control points.
- Fixed `_update()` to render straight road previews (added missing `STRAIGHT_END` stage).
- Added exact tangent checks in `RoadNode.is_pass_through()`, ensuring tight curves remain waypoints rather than junctions.
- Upgraded `CurveMath.slice()` to use De Casteljau's algorithm for perfect cubic sub-curve splitting.
- Added minimum radius validation. If the curve turns tighter than `half_width + 1.5 * lane_width`, the preview turns red and placement is blocked.
- Reduced curve waypoint density to 16 lanes (~51m). Equalized spacing so there are no tiny "remnant" segments.
- Enabled demolishing of tiny segments.
**Tested:** C-curves, S-curves, straight roads. Snapping works relative to the previous point. Free-placed points no longer shift. Tight curves do not become junctions. Demolish cleans up completely.
**Follow-ups:** Curve segment splitting when connecting new roads (T-junctions on curves).

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
