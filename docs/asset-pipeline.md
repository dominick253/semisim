# CITYHAUL Asset Pipeline

Blender (4.5.1, CPU-only via the `blender` wrapper) to Godot (4.7.2).

## Two routes, one verified

Route A, headless scripts. Default, and verified end to end on this host
(Blender exports a GLB with named pivot empties, Godot imports it, the report
tool reads the inventory back):

```bash
# 1. Build or rebuild a model from a version-controlled script. No display,
#    no GPU, no MCP bridge.
blender --background --python tools/blender/build_tractor.py

# 2. Import the exported GLB into the project (separate process, CPU only).
godot-headless --path ~/dev/games/semisim --import

# 3. Measure what actually landed.
godot-headless --path ~/dev/games/semisim \
  -s res://scripts/tools/model_report.gd -- --model res://models/tractor.glb
```

Route B, interactive MCP bridge: `mcp__blender__execute_blender_code` through
`uvx mcp-for-blender`, and `mcp__godot__*` through `godot-mcp`. Only for
hands-on shaping in a GUI session. Measured state on this host: `godot-mcp`
holds 127.0.0.1:6505, but a bridge call only reaches a project while the Godot
GUI editor is running, and nothing listens on the Blender addon socket 9876
unless Blender is open with `Interface: MCP for Blender` enabled and Start MCP
Server clicked. No deliverable may depend on either GUI, so everything is
produced through Route A and Route B stays a convenience.

## Workflow

1. Build the model from a script in `tools/blender/` to the exact section 5
   dimensions of the build spec. Mirror modifiers for symmetry; all modifiers
   applied before export (`export_apply=True`).
2. PBR metallic-roughness only, baked image textures, no procedural nodes in
   the exported file. Texture sources: ambientCG CC0 concrete (trailer),
   painted metal (cab), steel (chassis and wheels).
3. Budgets (hard caps): tractor LOD0 45,000 tris, trailer LOD0 35,000 tris,
   LOD1 18,000 tris each, cone 2,000 tris. Textures: tractor body 2048,
   trailer 2048, shared chassis/wheels 1024. LOD1: decimate collapse ratio 0.4
   on copies.
4. Keep every `.blend` source in `~/dev/3d/semisim/`. Export GLB into the Godot
   project `models/` so assets travel with builds.
5. Export with `bpy.ops.export_scene.gltf`, `export_format='GLB'`,
   `export_yup=False` (D45; the Y-up conversion must not run on top of geometry
   that is already written in the Godot convention), no extra node transforms.
6. After every export verify the file exists, is non-empty, and node names
   match, using `scripts/tools/model_report.gd`. The report prints `NODE_COUNT`,
   `NODE_NAMES`, `MESHES`, `TOTAL_TRIS` and `PIVOT_EMPTIES_FOUND` lines, so
   acceptance evidence is the measured report rather than a file listing.
7. Import into Godot with a separate headless process (no bridge conflict):

   ```bash
   godot-headless --path ~/dev/games/semisim --import
   ```

8. Collision: convex decomposition from the GLB (`scene_import` option, max 16
   convex pieces per body).

## Node naming inventory (exact)

Tractor file nodes: `Tractor`, `Cab`, `Chassis`, `WheelSteerL`, `WheelSteerR`,
`WheelDriveL`, `WheelDriveR`, `FifthWheel`, `LandingGear`.
Trailer file nodes: `Trailer`, `CargoBox`, `TrailerWheelFL`, `TrailerWheelFR`,
`TrailerWheelRL`, `TrailerWheelRR`, `TrailerKingpin`, `LandingGear`.

Named pivot empties: `wheel_steer_L`, `wheel_steer_R`, `wheel_drive_L`,
`wheel_drive_R`, `kingpin`, `fifth_plate`, `landing_contact`, `cab_eye`,
`trailer_ref`.

Two rules that the pipeline depends on and that cost a rebuild to learn (D44, D45):

- No pivot or node name may end in `wheel`. Godot 4.7.2's glTF importer turns any
  node whose name ends in `_wheel` or `-wheel` into a `VehicleWheel3D` and strips
  the suffix, so the name is gone and a physics node appears in its place. That is
  why the fifth-wheel anchor is `fifth_plate`.
- `export_yup=False`. Build scripts write geometry in the Godot convention
  directly, so Blender's glTF Y-up conversion must not run on top of it. With the
  conversion on, an upright model lands nose down and only a coordinate probe
  reveals it.

## Third-party assets

Kenney City assets (CC0) for warehouse shells and street props; ambientCG
(CC0) PBR textures; Godot built-in Open Sans SemiBold (OFL). Forbidden: any
non-CC0 model, any GPL-licensed 3D asset. Every third-party file gets an entry
in `docs/ATTRIBUTION.md` with source URL and license.
