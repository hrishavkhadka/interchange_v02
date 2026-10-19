# Interchange — Project Context

Master handoff document. **Read this first in every new chat.** Deeper reference lives in `docs/`.

## 1. Project Goal & Vision

A level-based traffic puzzle game built in Godot 4. The player receives entry/exit roads, a demand matrix, a budget, and a time limit. The player builds roads, junctions, interchanges, and traffic lights to route every vehicle from its entry to its exit before time runs out, without exceeding budget.

The game focuses exclusively on the traffic management and road-building aspects of Cities: Skylines (especially CS2), without city-building overhead.

## 2. Core Pillars

1. **Readable** — Every lane, connection, and movement must be legible at a glance.
2. **Forgiving** — Slightly unrealistic slope and clearance values are acceptable if they make building easier.
3. **Deterministic** — Same level + same build = same result. Seeded RNG, fixed timestep.
4. **Fast to iterate** — Build → Play → Fail → Edit in under a minute.

## 3. Technical Stack & Constraints

- **Engine**: Godot 4.4+ (Standard, not .NET).
- **Language**: GDScript.
- **Platform**: Offline PC (Windows) primary target.
- **Simulation rate**: 60 Hz fixed step, render-decoupled.
- **Max vehicles**: 200.
- **Driving side**: Right (US).
- **Terrain**: Flat ground; terrain features exist only as blockers around the play area.
- **Road elevation**: Ground, elevated (overpasses), sunken (underpasses with retaining walls). Maximum grade 10%. Minimum clearance 5.0 m.
- **Constraints**: Zero budget, no international payments (based in Nepal). All tools, assets, and services must be free. AI is doing all coding.
- **Assets**: Kenney (CC0) kits for vehicles and props. Flat stylized materials.

## 4. Document Map

| File                   | Purpose                                   | When to read                                      |
| ---------------------- | ----------------------------------------- | ------------------------------------------------- |
| `context.md` (this)    | High-level master handoff                 | Every new chat                                    |
| `CHANGELOG.md`         | Phase-by-phase log of what shipped        | "What did we just do?" / regression triage        |
| `docs/architecture.md` | Subsystem deep-dive, algorithms, math     | Before touching an unfamiliar subsystem           |
| `docs/decisions.md`    | Non-obvious design choices with rationale | Before proposing a change to an existing decision |
| `docs/pitfalls.md`     | Known bugs and traps with cause + fix     | Before editing the affected area                  |

## 5. Architecture Summary

Full details in `docs/architecture.md`. Short version:

- **Core Graph** — `RoadGraph` (autoload) owns `nodes: Array[RoadNode]` and `segments: Array[RoadSegment]`.
  - `RoadNode`: position + attached segment ends + flags (is_entry, is_exit, is_waypoint, forced_junction).
  - `RoadSegment`: `Curve3D` + `RoadType` + start/end nodes + stable uid.
  - `RoadType`: defined by `lane_layout_string` (e.g. `"FB"`, `"FFBB"`). Lane index 0 is rightmost when facing forward.
- **Lane Graph** — `LaneGraph` (autoload) rebuilds lanes and arcs on `graph_changed`.
  - `Lane`: single lane along a segment (offset curve), from/to nodes, direction, trimmed at junctions.
  - `LaneArc`: directed connection between two lanes with Bezier curve, length, enabled flag, conflicting_arcs.
- **Junction Arc Algorithm** — `LaneArcAlgorithm` (3-phase: promise matrix → surplus commits → clockwise exit ordering) wrapped by `LaneArcBuilder`. Only algorithm-approved arcs are enabled; disabled ones remain for manual override via `JunctionEditor`. Pass-throughs are handled by the algorithm itself.
- **Routing** — `LanePathfinder`: A\* on the lane graph, penalizes lane changes.
- **Simulation** — `VehicleManager` handles spawn, occupancy, IDM, MOBIL, junction arc reservations. `Vehicle` moves kinematically along `path: Array[PathStep]`, no physics bodies.
- **Build Tools** — `RoadBuilder` (straight/curve/S-curve placement), `SnapResolver`, `JunctionEditor`, `MarkerEditor`.

## 6. Saved Format

Levels are saved as JSON in `user://levels/`:

- `version`, `bounds`, `budget`, `time_limit`
- `blockers`, `fixed_roads`, `props`
- `demand matrix`, `vehicle_order`
- Arc overrides via `ArcOverrides`, serialized alongside.

## 7. Current Implementation State

- **Working**:
  - Road drawing (straight), snapping, T-junctions on straight segments, junction meshes.
  - Custom arc algorithm, lane connector tool.
  - IDM car following, vehicle despawning.
  - Entry/exit markers, demand matrix.
  - Save/load (F9/F10 quick save + named saves via buttons).
  - Curved road drawing (C-curves and S-curves) via multi-click placement + road shape sub-menu on the Road tool.
- **In progress — curve roads (Phase 1/4 → 4/4)**:
  - [x] **Phase 1/4 — Curve geometry & builder.** Real Bézier handles, curve passes through mid-click, correct click sequence, finer waypoint spacing, straight preview fixed, pass-through tangents fixed, minimum radius check added.
  - [ ] **Phase 2/4 — Curve-aware hit detection.** `RoadOps` projection: chord → `Curve3D`.
  - [ ] **Phase 3/4 — Curve-preserving split.** `_split_existing_segment` uses `CurveMath.slice`.
  - [ ] **Phase 4/4 — S-curve preview.** Fix `SCURVE_MID2` degenerate preview.
- **Known pending issues**: see `docs/pitfalls.md` (`Status: open` entries).

## 8. Workflow & Conventions

### Phase structure

Work is organized into **phases**. One phase = one commit. Header format:

```
Phase N/M — Short title

<body: what changed, why, what breaks if reverted>
```

Examples:

- `Phase 1/4 — Fix curve geometry`
- `Phase 2/4 — Curve-aware hit detection`
- `Phase 1/1 — Add CONTEXT docs split` (non-phased work still uses a phase header, so `git log --oneline` sorts cleanly)
- `Hotfix — <title>` (out-of-phase urgent fix; flagged explicitly)

### Per-phase commit includes

1. Code changes (full functions, no stubs).
2. `CHANGELOG.md` — new entry at the top.
3. `context.md` §7 — Current Implementation State.
4. `docs/architecture.md` — if the phase changed a subsystem's contract.
5. `docs/pitfalls.md` — entry if the phase fixed a bug worth remembering.
6. `docs/decisions.md` — entry if the phase introduced/revised a non-obvious choice.

### Verification gate

No phase is committed until the in-game test protocol for that phase passes. If it fails, we iterate on the phase before committing.

### Docs update timing

Default cadence is per-phase. Exception: if a phase uncovers a fact that would mislead a future reader if left unrecorded for hours, we update the relevant doc **mid-phase** as a micro-commit. Flag it explicitly in the commit header.

## 9. Rules for the AI

1. **Do not guess the code state.** Always ask for the file contents if a patch depends on code not shown in the current chat context.
2. **Provide full functions, not snippets**, when modifying more than a few lines. If a change touches >3 files, break it into subphases.
3. **Break changes into small, testable phases.** Do not generate 5 large files at once.
4. **Explain the _why_ before the code**, especially for math-heavy work. User is a CE grad and understands math, but is rusty at coding.
5. **Challenge redundancy, inefficiency, and wrong assumptions.** Say so directly.
6. **Recovery protocol**: if the game breaks (parse errors, crashes), guide through clearing `.godot/` and restarting Godot before other debugging.
7. **Git**: Provide a commit message after every successful phase (header line + full body).

## 10. Glossary

- **Segment** — a `RoadSegment`: a single road slab between two `RoadNode`s. Long roads are made of many segments.
- **Lane** — a single drivable lane along a segment.
- **Arc** — a `LaneArc`: directed connection from one lane to another across a junction or pass-through.
- **Waypoint** — a `RoadNode` on the interior of a logical road. Splits it into segments. Not a real intersection.
- **Pass-through** — a waypoint where no lane-to-lane change happens (e.g. boundary between two collinear segments). Can be "promoted" to a real junction via `JunctionEditor`.
- **Junction** — a `RoadNode` with ≥3 attached segments where turns happen.
- **Chord** — the straight line between `segment.start_node.position` and `segment.end_node.position`. Valid geometry for straight segments only. **Do not use for projection on curved segments** (see `docs/pitfalls.md`).
