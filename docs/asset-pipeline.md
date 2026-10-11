# CITYHAUL Asset Pipeline

Blender (4.5.1, CPU-only via the `blender` wrapper) to Godot (4.7.2).

## Workflow

1. Model in Blender via `mcp__blender__execute_blender_code` to the exact
   section 5 dimensions of the build spec. Mirror modifiers for symmetry; all
   modifiers applied before export.
2. PBR metallic-roughness only, baked image textures, no procedural nodes in
   the exported file. Texture sources: ambientCG CC0 concrete (trailer),
   painted metal (cab), steel (chassis and wheels).
3. Budgets (hard caps): tractor LOD0 45,000 tris, trailer LOD0 35,000 tris,
   LOD1 18,000 tris each, cone 2,000 tris. Textures: tractor body 2048,
   trailer 2048, shared chassis/wheels 1024. LOD1: decimate collapse ratio 0.4
   on copies.
4. Keep every `.blend` source in `~/dev/3d/`. Export GLB into the Godot
   project `models/` so assets travel with builds.
5. Export with `bpy.ops.export_scene.gltf`, `export_format='GLB'`, +Y up, no
   extra node transforms.
6. After every export verify the file exists, is non-empty, and node names
   match (`mcp__godot__resource_load`).
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
`wheel_drive_R`, `kingpin`, `fifth_wheel`, `landing_contact`, `cab_eye`,
`trailer_ref`.

## Third-party assets

Kenney City assets (CC0) for warehouse shells and street props; ambientCG
(CC0) PBR textures; Godot built-in Open Sans SemiBold (OFL). Forbidden: any
non-CC0 model, any GPL-licensed 3D asset. Every third-party file gets an entry
in `docs/ATTRIBUTION.md` with source URL and license.
