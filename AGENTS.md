# CITYHAUL Agent Contract

Project: CITYHAUL, a technical semi truck simulator in Godot 4.7.2 + Blender
4.5.1, driven through their MCP servers. Read this file before any edit.

## Rule list

- CPU-only: never let Godot or Blender touch the Intel Arc GPUs; use the `godot`, `godot-headless`, `blender` wrappers only.
- godot-mcp is single instance on 127.0.0.1:6505. Never `pkill -f godot-mcp`. Free stuck ports by exact pid from `ss -ltnp`.
- Never run `hermes mcp test godot` while a live session holds the bridge. `hermes mcp test blender` is safe anytime.
- `scripts/physics/PHYSICS_CONSTANTS.gd` is the single source of truth for physics constants; changing one updates `docs/physics-spec.md` in the same commit.
- Never commit `.godot/`.
- Media worked means verified content: check node names, triangle counts and screenshots, not file size.
- Every third-party asset is CC0 or OFL and recorded in `docs/ATTRIBUTION.md`.
- Tests before push: GUT unit suite green, headless smoke green.
- Style: tabs, snake_case, static typing, ASCII strings, no em dash in UI text or comments, gdlint clean.
- Commit messages imperative and scoped. No force-push to main.
- Do not expand a phase's scope. Phase 2 adds the world and cargo loop; Phase 3 adds polish and packaging.
- Done means screenshots plus tests plus green CI, never a green compile alone.

## Phase status table

| Phase | Scope | Status |
|---|---|---|
| 1 | Driving core: physics, test yard, 3 challenges, tests, CI | IN PROGRESS |
| 2 | World and cargo loop: city, towns, deliveries, AI traffic | NOT STARTED |
| 3 | Polish and Steam packaging | NOT STARTED |

## Directory ownership map

| Path | Owner |
|---|---|
| `scenes/` | Scene structure: boot, main menu, test yard, debug sandbox, vehicles, challenges |
| `scripts/physics/` | Tire model, engine/transmission, air brakes, kingpin, load math. `PHYSICS_CONSTANTS.gd` is the single source of truth for physics constants |
| `scripts/vehicles/` | Tractor and trailer rigid bodies, suspension, coupling, damage state |
| `scripts/world/` | Test yard geometry, spawns, challenge volumes |
| `scripts/ui/` | HUD, debug overlay, pause menu |
| `scripts/challenges/` | Challenge definitions, scoring, save of best times |
| `scripts/autoloads/` | `GAME_STATE`, `SAVE_SYS` |
| `models/` | Exported `.glb` assets (travel with builds) |
| `materials/`, `ui/`, `audio/` | Materials, UI art, procedural audio scripts |
| `tests/unit/`, `tests/sim/` | GUT unit tests and headless scenario scripts |
| `docs/` | Architecture, physics spec, asset pipeline, controls, roadmap, attribution, deviations, evidence |

Physics constants single source of truth: `scripts/physics/PHYSICS_CONSTANTS.gd`.
