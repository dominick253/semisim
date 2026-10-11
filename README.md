# CITYHAUL

CITYHAUL is a technical semi truck simulator. The product is the driving:
articulation through the kingpin, tire friction under load, the difference
between an empty trailer and a loaded one, and backing into tight spaces.
It takes the American Truck Simulator game loop and narrows it to what makes
it interesting: no open world, no long-haul, just hard driving done properly.
Phase 1 builds a test yard and the full physics driving core.

## Engine and version

- Godot 4.7.2 (Jolt physics backend, 120 physics ticks/s)
- Blender 4.5.1 LTS for all first-party 3D assets (CPU-only rendering)
- GDScript, GUT test framework

## Build instructions

1. Install Godot 4.7.2.
2. Clone this repository.
3. Open the project in Godot, or run headless:

   ```bash
   godot-headless --path . --import   # first run: import assets
   godot --path .                     # play
   ```

4. Tests:

   ```bash
   godot-headless --headless --path . -s res://addons/gut/gut_cmdln.gd \
     -gdir=res://tests/unit -ginclude_subdirs -gexit
   ```

5. Acceptance evidence (GUT, scenarios, golden determinism, smoke, screenshots):

   ```bash
   scripts/run_acceptance.sh
   ```

## Controls summary

Keyboard: W throttle, S brake, Shift clutch, A/D steer, keys 1..0 shift gears
(1..5 high range, 6..0 low range), R reverse, N neutral, E range toggle,
Z/X retarder up/down, Space parking brake, U coupler unlock, L landing gear,
Tab camera cycle, G trailer path overlay, V transmission mode, F3 debug
overlay, F1 context help, Esc pause menu. Full table: `docs/controls.md`.

## Phase roadmap

1. Phase 1: driving core (physics, test yard, 3 challenges, tests, CI).
2. Phase 2: world and cargo loop (one city, 3 towns with farms, deliveries,
   AI traffic, save/settings expansion).
3. Phase 3: polish and Steam packaging.

## License

Code is MIT (see `LICENSE`). Third-party assets are CC0 or OFL and are listed
with source URLs in `docs/ATTRIBUTION.md`. First-party models are built in
Blender by this project.

## Asset attribution

See `docs/ATTRIBUTION.md` for every third-party file, its source URL and its
license. `docs/asset-pipeline.md` describes the Blender-to-Godot workflow.
