# CITYHAUL Phase 2 Plan: World and Cargo Loop

Status: working plan, drafted 2026-10-12 from the measured Phase 1 tree at commit
4441d7e. This is the input to the contract deliverable. The build spec (section 20)
requires `docs/phase2-prompt.md` written at Phase 1 exit, and that prompt must open
by quoting the measured end state from `docs/phase1-end-state.md` items 1 to 9.
Neither end-state file exists yet, so this plan is not a substitute for either.

Rule that bounds this plan, quoted from the repo contract: "Do not expand a phase's
scope. Phase 2 adds the world and cargo loop; Phase 3 adds polish and packaging."

## 1. Measured Phase 1 starting state

Every number below was read out of the repo or a run, not restated from the spec.

| Item | Measured value |
|---|---|
| Repo | github.com/dominick253/semisim, main at 4441d7e, 10 commits |
| CI | Green. Run 38248767273, jobs `style` and `test`, test job 1m57s |
| Unit suite | 142 tests, 1460 asserts, 0 failures (GUT, `-ginclude_subdirs`) |
| Engine | Godot 4.7.2-stable headless, `3d/physics_engine="Jolt"` |
| Physics tick | `physics_ticks_per_second=120`, `max_physics_steps_per_frame=16` |
| Autoloads | PHYSICS_CONSTANTS, GAME_STATE, SAVE_SYS, INPUT_SETUP |
| Deviations log | 40 rows, D1 through D40 |
| Evidence files | 9: 3 audio windows, audio waveform PNG, 4 camera PNGs, HUD PNG |
| Implemented subsystems | tires, engine and transmission, retarder, air brakes, kingpin articulation, coupling and landing gear, suspension and steering, test yard, controls, HUD, 4 cameras, procedural audio |
| Not implemented | challenges and scoring (`scripts/challenges/` is empty), S1 to S3 scenarios, golden determinism test, `scenes/boot.tscn`, main menu, tractor.glb, trailer.glb, `scripts/run_acceptance.sh`, `docs/phase1-end-state.md` |

Baseline that Phase 2 depends on and does not have yet: measured FPS for a 60 s yard
drive (profiler_stats, llvmpipe, 1280x720). No city rendering budget can be set
until that number exists, because it is the only measurement of what this CPU-only
renderer costs for one truck.

## 2. Open Phase 1 work that Phase 2 must not swallow

Phase 2 does not start until these close. Each one gates a Phase 1 acceptance ID.

| Task | Gates | Why Phase 2 needs it first |
|---|---|---|
| 3 challenges plus scoring, SAVE_SYS (A10, A13) | A10, A13 | The cargo loop is a scoring and save extension. Building delivery on an unbuilt scoring model means rewriting it twice. |
| S1, S2, S3 scenario scripts (A9, A11, A12) | A9, A11, A12 | The alley reverse S1 is the only measured evidence that the combination fits a tight street. City street widths should be set from that number, not guessed. |
| Golden determinism test, 600 steps, hash transforms (A14) | A14 | AI traffic is the biggest determinism risk in the project. The hash harness must exist before traffic is added, so traffic can be proven to be inside or outside the deterministic envelope. |
| `boot.tscn` and `main_menu.tscn` (A16) | A16 | Also removes a live CI defect, see section 3 item 2. |
| tractor.glb, trailer.glb, import (A3, A4, A5, A17) | A3, A4, A5, A17 | Camera anchors (D31) and every Phase 2 screenshot depend on real GLB pivot empties. City props reuse the same export pipeline. |
| Acceptance run plus evidence and screenshots (A1 to A20) | all | Produces `acceptance.txt` and the measured end state that the Phase 2 prompt must quote. |
| `phase1-end-state.md` then `phase2-prompt.md` (A20) | A20 | Contract exit gate. |

## 3. Technical debt carried into Phase 2

Each item has measured evidence in the repo already.

1. Kingpin plate error, 0.44 m measured drift, accepted at 0.50 m
   (`KINGPIN_MAX_PLATE_ERROR_M`, D36). Godot-Jolt implements Generic6DOFJoint3D
   linear limits as soft limits, so the pin is not rigid. In the yard this is
   tolerable. In the city it is not: a 0.44 m error at a dock is enough to contact
   a loading bay, and a long drive amplifies it into visible trailer wander.
   Phase 2 work: re-measure drift after a 60 s city drive, then either tighten the
   joint with a corrected `force_limit` or add a positional correction pass, and
   record whichever works as a new DEVIATIONS row. Do not silently re-pin the
   accepted error.

2. `run/main_scene="res://scenes/boot.tscn"` points at a file that does not exist.
   Measured in a clean clone of the committed tree: the headless import prints
   `ERROR: Cannot open file 'res://scenes/boot.tscn'.` and
   `ERROR: Failed loading resource: res://scenes/boot.tscn.`, then exits 0. The CI
   import step therefore passes while printing errors, and A16 (headless boot 10 s,
   0 errors, 0 warnings) cannot pass. Fix belongs to task 28, not to Phase 2.

3. Camera anchors are pinned local vectors (D31), not GLB named empties. Re-anchor
   cab eye, tractor ref and trailer ref to the GLB pivot empties as soon as task 31
   lands, before any city camera work, or every Phase 2 screenshot inherits the
   placeholder offsets.

4. Off-tracking geometric shortfall, 3.82 m on the 15 m circle (D27). The geometric
   model under-predicts what the physics combination does. City intersections are
   the first place this becomes a gameplay problem, so Phase 2 must decide whether
   to widen streets or fix the model, and must state which.

5. Audio teardown leaks 1 ObjectDB instance per AudioStreamGenerator (D40), and the
   leak gate tolerates it. Full Phase 2 audio means many more generators, so the
   tolerance must be re-measured with the city soundscape live rather than inherited.

6. HUD is a programmatic Control tree with the built-in theme font (D30) and no
   settings UI. Save and settings expansion (milestone M4) needs a real theme, a
   font decision recorded in ATTRIBUTION if a font is vendored, and a control
   remap screen that writes through INPUT_SETUP rather than editing project.godot.

7. CI runner drift. The run annotations say actions/checkout@v4 and
   actions/setup-python@v5 still target Node 20 and are forced onto Node 24, and
   `ubuntu-latest` migrates to Ubuntu 26 on 2026-10-19. Phase 2 expands CI (more
   scenarios, screenshots, determinism), so bump the action versions and pin the
   runner image before adding steps, not after a red run.

8. Spec conflict to resolve in writing. Build spec section 20 lists "Steam packaging
   prep (export presets, storefront assets)" inside Phase 2 scope, while section 21
   says Phase 3 adds polish and packaging. This plan follows section 21 and assigns
   packaging prep to Phase 3. Log the decision in DEVIATIONS rather than letting two
   phase documents disagree.

## 4. Phase 2 scope, locked

Scope source: build spec section 20 and `docs/ROADMAP.md`. The single big city
(block grid, tight streets, alleys, the yards), 3 small towns with farms, cargo and
delivery game loop, AI traffic, save and settings expansion, full audio. Exit gate:
`docs/phase2-end-state.md` and `docs/phase3-prompt.md`.

Milestones run in this order because each one consumes the previous one's output.

### M1 Road network and city block grid

Deliverables: a data-driven road graph (blocks, street segments, lane widths, alleys,
curb radii) separate from collision geometry; the city scene assembled from that
graph; the 3 towns and farms as the same graph with a different block profile; the
existing test yard kept intact as the challenge space, not replaced.

Decisions to make before writing geometry, and to record in a new
`docs/world-spec.md`: minimum street width (set from the S1 alley result and the
D27 off-tracking measurement, not from taste), intersection corner radius, whether
the city is one scene or streamed chunks, draw-call and triangle budgets (the Phase
1 yard budget is 80 draw calls; the city needs a measured number from the Phase 1
FPS baseline), LOD policy for props, MultiMesh3D instancing rules for repeated props.

Exit criteria: headless assertion that the graph is connected and every delivery
destination is reachable; measured FPS on a city drive at 1280x720 llvmpipe, recorded
next to the yard FPS; screenshots of 3 city views with a visible truck.

### M2 Cargo and delivery loop

Deliverables: cargo types with mass and volume; load and unload flow reusing the
Phase 1 loading rules (physics-spec 5.6 loaded versus unloaded) so cargo mass feeds
the existing per-axle static load split rather than a new mass path; delivery
contracts with generated routes over the M1 graph; scoring extension of the Phase 1
challenge scoring; SAVE_SYS persistence of contracts, cargo state and progress.

Exit criteria: a scripted delivery from origin to dock with cargo mass changing the
measured brake distance, reported as before and after numbers on the same workload;
save round-trip test proving contracts and cargo survive a reload.

### M3 AI traffic

Deliverables: path-following agents on the M1 graph, headway keeping, a hard agent
count budget, no pedestrians and no cyclists (same exclusion the yard applied).

Non-negotiable ordering: run this after the golden determinism harness exists.
Traffic must be provably outside the deterministic envelope, or the golden test must
run with traffic disabled and say so in its name. A determinism test written after
traffic is added cannot tell you which subsystem broke it.

Exit criteria: measured frame time at the agent budget (record the number that
starts dropping ticks), a collision course test proving an agent yields to the
player combination, and a strike-count test proving traffic contacts register
through the existing 15 kN strike rule.

### M4 Save and settings expansion

Deliverables: settings screen (graphics quality, audio, control remap), save slots,
options persistence. Control remap must go through the INPUT_SETUP autoload that
already installs the pinned map (D28); editing project.godot at runtime is not an
option and would break the control-map tests.

Exit criteria: unit tests for option persistence, a test that a remap changes the
live action mapping and survives reload, and a test that a corrupt save file cannot
crash boot.

### M5 Full audio

Deliverables: extend the Phase 1 procedural base (engine, tire squeal, air brake,
hiss) with city ambience, dock and town soundscapes, and Doppler for traffic.
Phase 1 pinned zero audio files; Phase 2 may introduce third-party audio only if it
is CC0 or OFL and recorded in ATTRIBUTION, which is a decision to make explicitly
rather than by accident.

Exit criteria: keep the Phase 1 audio evidence pattern (waveform peak rising with
rpm, squeal above slip 0.12, log plus generator buffer dump) for every new source,
plus a re-measured leak count with the full soundscape running.

### M6 Phase 2 exit

`docs/phase2-end-state.md` with the same 9 item shape as section 20 (measured
numbers only), then `docs/phase3-prompt.md`, both committed, then final push with
green CI.

## 5. Proposed Phase 2 acceptance IDs

Continuing the Phase 1 numbering. Each needs evidence under `docs/evidence/phase2/`.

| ID | Measurable assertion |
|---|---|
| A21 | Road graph loads headless, is connected, and every delivery destination is reachable, asserted by script |
| A22 | City scene renders at 1280x720 llvmpipe with measured FPS recorded in `phase2-end-state.md`, and the number is compared against the Phase 1 yard FPS on the same 60 s drive shape |
| A23 | 3 city screenshots (wide block view, tight street with truck, dock approach) show a visible truck, no black frames, no missing textures |
| A24 | 3 towns plus farms load from the same graph code, asserted by node inventory and a headless reachability test |
| A25 | A cargo load changes measured 80 to 0 km/h stop distance, reported as before and after on the identical workload |
| A26 | Delivery contract completes end to end with scripted inputs, and scoring records the result in SAVE_SYS |
| A27 | Save round trip: contract, cargo and progress survive reload; a corrupt save file does not crash boot |
| A28 | Settings: quality, audio and a control remap persist and take effect live through INPUT_SETUP |
| A29 | AI traffic at the declared agent budget holds 120 physics ticks per second, with the measured frame time recorded |
| A30 | A traffic agent yields to the player combination in a scripted head-on scenario, and a scripted traffic contact registers as a strike above 15 kN |
| A31 | Golden determinism still reproduces an identical hash across two runs, and the test states whether traffic was enabled |
| A32 | Every new audio source passes the Phase 1 evidence pattern (log plus generator buffer dump), and the ObjectDB leak count is re-measured |
| A33 | CI green on the Phase 2 tree with the scenario and determinism steps added, and no ERROR line in the import step |
| A34 | `docs/phase2-end-state.md` and `docs/phase3-prompt.md` written; DEVIATIONS has no unlogged divergence |

## 6. Test strategy additions

Unit: road graph connectivity and reachability, route generation determinism, cargo
mass to per-axle load split, contract state machine, save round trip and corrupt-save
resilience, settings persistence, remap effect, traffic headway rule, strike
registration from an agent contact.

Scenario (headless scripts, same shape as S1 to S3): S4 dock-to-dock city delivery,
S5 tight two-lane street turn with a loaded trailer, S6 traffic interaction at an
intersection, S7 town farm approach with a crop yield gate on the trailer.

Golden: extend the 600 step yard hash to a 1200 step city drive, traffic disabled,
hash of transforms only, run twice, byte-identical.

Live-harness rule carried from the Phase 1 steering defect: a unit test on pure math
does not prove the combination turns. Every Phase 2 scenario that depends on
articulation must assert a changed heading or path in a live physics harness, not
only in a pure function.

## 7. Risks, ranked

1. CPU-only rendering is the binding constraint, not physics. llvmpipe at 1280x720
   already carries the whole cost of one truck. Mitigation: measure the yard FPS
   first, set a city triangle and draw-call budget from that number, instance props
   with MultiMesh3D, and keep the city in its own scene so the yard stays cheap.
2. Jolt body count with traffic. The combination is already the most constrained
   rig in the project. Mitigation: declare an agent budget before building agents,
   and measure tick rate at that budget rather than after.
3. Determinism versus AI. Mitigation: golden test before traffic, traffic outside
   the hash envelope, and the test name states which mode it ran in.
4. Scope creep toward packaging. Mitigation: section 8 list plus the contract rule
   quoted at the top of this file.
5. Silent spec drift between phase documents. Mitigation: every decision in this
   plan that diverges from the build spec becomes a DEVIATIONS row in the same commit
   as the decision.

## 8. Explicitly out of scope for Phase 2

Component damage and damage model (Phase 3), separate trailer brake valve (Phase 3,
per physics-spec section 5.4), Steam export presets and storefront assets (Phase 3,
per contract rule; note the section 20 conflict in section 3 item 8), pedestrians,
cyclists, weather, day night cycle, damage repair economy, multiple truck chassis.

## 9. Commit cadence and CI

Same cadence as Phase 1: imperative scoped messages, at least one commit per
milestone deliverable, no force-push, no rewritten history. CI grows from the current
two jobs to add the scenario scripts and the golden determinism run, and the action
versions and runner image get pinned in the same commit that adds steps, so a runner
migration cannot redden main mid-phase.
