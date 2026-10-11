# CITYHAUL Architecture

## Scene tree

```
boot.tscn            Main scene. Loads main menu.
main_menu.tscn       Start, challenge select, settings stub.
test_yard.tscn       Yard geometry, spawns, challenges, combination, cameras, HUD.
debug_sandbox.tscn   Free-drive sandbox with debug overlay by default.
vehicles/tractor.tscn   RigidBody3D + suspension + tire nodes + cab + wheels.
vehicles/trailer.tscn   RigidBody3D + bogie wheels + kingpin + landing gear.
challenges/challenge_hud.tscn  Timer, objective line, medal thresholds.
```

## Autoloads

- `PHYSICS_CONSTANTS` (`scripts/physics/PHYSICS_CONSTANTS.gd`): single source
  of truth for every physics constant.
- `GAME_STATE` (`scripts/autoloads/game_state.gd`): vehicle state machine,
  coupling state machine, challenge state, current run metrics.
- `SAVE_SYS` (`scripts/autoloads/save_sys.gd`): best times and settings in
  `user://cityhaul.cfg`.

## Module ownership

- `scripts/physics/`: pure-math modules (tire model, engine/transmission,
  air system, kingpin torques, load math). No node dependencies; unit-testable
  in isolation.
- `scripts/vehicles/`: node-side code that feeds physics modules each tick and
  applies resulting forces/torques to the rigid bodies.
- `scripts/world/`: test yard geometry, spawn transforms, challenge volumes.
- `scripts/ui/`: HUD widgets, debug overlay, pause menu.
- `scripts/challenges/`: challenge definitions, goal checks, scoring, medals.
- `scripts/autoloads/`: state machines and persistence.

## Data flow

Input (keyboard/gamepad) -> input map -> vehicle controller scripts ->
physics modules (pure functions of state) -> applied forces/torques on
RigidBody3D + Generic6DOFSpringConstraint3D -> Jolt step -> GAME_STATE
(articulation, speed, air, damage, challenge state) -> HUD, audio, cameras.

Determinism rules: physics ticks pinned 120, no time-scale variation, no RNG
anywhere in physics code, all constants from `PHYSICS_CONSTANTS`.
