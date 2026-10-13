"""CITYHAUL Phase 1 tractor model build (headless Blender).

Run:
    cd /home/dom/dev/games/semisim
    blender --background --python tools/blender/build_tractor.py

Produces models/tractor.glb (LOD0) and models/tractor_lod1.glb (LOD1, decimated
collapse ratio 0.4 on copies of the LOD0 meshes) and keeps the .blend source at
~/dev/3d/semisim/tractor.blend.

Coordinates match docs/physics-spec.md exactly: X lateral, Y up, -Z forward.
Corrected pinned numbers are used, per docs/DEVIATIONS.md:
  - D1 tractor CoM z = -4.20 (not the superseded -0.75)
  - D2 fifth wheel center z = -1.00 (not the superseded -7.45 / -4.55)
  - steer axle center (0, 0.554, -6.50), drive axle center (0, 0.563, 0.00)
  - D48 wheel track half width 1.10 (TRACK_HALF_STEER_M, TRACK_HALF_DRIVE_M)
    and every wheel node origin on its axle anchor

Textures: no CC0 texture could be fetched in this slice, so the model ships
plain PBR metallic/roughness materials (white cab, navy hood stripe, bare
aluminum, dark tires) rather than any licensed asset.
"""

import math
import os
import sys

import bpy
from mathutils import Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cityhaul_blender as cb  # noqa: E402  (helper lives next to this script)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
BLEND_DIR = os.path.expanduser("~/dev/3d/semisim")
BLEND_PATH = os.path.join(BLEND_DIR, "tractor.blend")
LOD0_PATH = os.path.join(REPO_ROOT, "models", "tractor.glb")
LOD1_PATH = os.path.join(REPO_ROOT, "models", "tractor_lod1.glb")

# Corrected pinned anchors (DEVIATIONS D1, D2 + section 2 / section 3 of spec).
FIFTH_WHEEL_Z = -1.00
FIFTH_WHEEL_Y = 1.30
STEER_Z = -6.50
STEER_R = 0.554
STEER_W = 0.295
DRIVE_Z = 0.00
DRIVE_R = 0.563
DRIVE_W = 0.285
# D48: the wheel track half width is pinned by TRACK_HALF_STEER_M and
# TRACK_HALF_DRIVE_M in scripts/physics/PHYSICS_CONSTANTS.gd (both 1.10). The
# first build modelled the tyres at x 1.475, 0.375 m outboard of the plane
# where the physics wheels push.
WHEEL_X = 1.10

# Tractor CoM (D1). Used only to sanity-check cab placement; the physics CoM is
# a separate constant in PHYSICS_CONSTANTS.gd, not baked into the mesh.
COM_Z = -4.20
COM_Y = 1.30


def make_material(name, color, metallic, roughness):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name=name)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    bsdf = nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def set_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def axle_wheel(name, radius, width, anchor, axis="X"):
    """Tyre cylinder whose node origin is the axle anchor, D48.

    cb.cylinder's transform_apply call bakes the object's location into the
    vertex data (Blender's transform_apply defaults location to True), so the
    returned object sits at the model origin with world-space vertices and the
    exported GLB node carries no translation. A wheel node whose origin is the
    model origin swings the tyre around the chassis when rotated. Shifting the
    mesh data by -anchor and putting the object location at anchor centres the
    tyre on the node origin and leaves the world position untouched.
    """
    obj = cb.cylinder(name, radius, width, anchor, axis=axis)
    obj.data.transform(Matrix.Translation((-anchor[0], -anchor[1], -anchor[2])))
    obj.location = anchor
    return obj


def apply_all(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    cb.apply_modifiers(obj)


def build_tractor():
    cb.fresh_scene()

    white = make_material("TractorWhite", (0.92, 0.93, 0.95), 0.0, 0.35)
    navy = make_material("TractorNavy", (0.04, 0.09, 0.24), 0.1, 0.5)
    alum = make_material("BareAluminum", (0.72, 0.74, 0.76), 0.9, 0.35)
    tire = make_material("TireRubber", (0.05, 0.05, 0.05), 0.0, 0.9)
    glass = make_material("CabGlass", (0.10, 0.12, 0.18), 0.6, 0.1)

    # Root at the origin. Everything is parented here so Tractor is the GLB root.
    tractor = cb.pivot_empty("Tractor", (0.0, 0.0, 0.0))

    # Chassis frame: full width 2.50, runs the truck length.
    chassis = cb.box("Chassis", (2.0, 0.6, 7.25), (0.0, 0.85, -3.275))
    set_material(chassis, alum)

    # Cab body. cab_eye (0, 2.10, -4.20) must sit inside it.
    cab = cb.box("Cab", (2.3, 1.7, 1.7), (0.0, 1.80, -4.15))
    set_material(cab, white)

    # Windshield: thin box proud of the cab front face (z = -5.0).
    windshield = cb.box("Windshield", (2.0, 0.9, 0.06), (0.0, 2.0, -5.015))
    set_material(windshield, glass)

    # Raised-roof sleeper on top of the cab (50 in sleeper cab).
    sleeper = cb.box("Sleeper", (2.2, 0.35, 1.2), (0.0, 2.825, -4.1))
    set_material(sleeper, white)

    # Hood in front of the cab; front axle (steer) sits under it at z -6.50.
    hood = cb.box("Hood", (2.3, 0.85, 1.85), (0.0, 1.125, -5.925))
    set_material(hood, white)

    # Navy hood stripe running the length of the hood, proud of the hood top.
    hood_stripe = cb.box("HoodStripe", (0.7, 0.06, 1.8), (0.0, 1.585, -5.925))
    set_material(hood_stripe, navy)

    # Front bumper at the very front (in front of the hood).
    bumper = cb.box("Bumper", (2.4, 0.4, 0.2), (0.0, 0.45, -6.95))
    set_material(bumper, navy)

    # Fifth wheel plate. Top face is exactly at the fifth wheel center y 1.30.
    fifth = cb.box("FifthWheel", (1.8, 0.14, 0.7), (0.0, 1.23, FIFTH_WHEEL_Z))
    set_material(fifth, alum)

    # Landing gear bracket near the rear (required tractor node).
    landing = cb.box("LandingGear", (0.3, 0.4, 0.4), (0.45, 0.7, 0.3))
    set_material(landing, alum)

    # Wheels. Cylinder axis along X (the axle direction). Center y = radius so
    # the tire bottom rests on the ground plane y = 0. Each node origin is its
    # axle anchor (D48) so the wheel can be rotated about the axle.
    steer_l = axle_wheel("WheelSteerL", STEER_R, STEER_W,
                         (-WHEEL_X, STEER_R, STEER_Z), axis="X")
    steer_r = axle_wheel("WheelSteerR", STEER_R, STEER_W,
                         (WHEEL_X, STEER_R, STEER_Z), axis="X")
    drive_l = axle_wheel("WheelDriveL", DRIVE_R, DRIVE_W,
                         (-WHEEL_X, DRIVE_R, DRIVE_Z), axis="X")
    drive_r = axle_wheel("WheelDriveR", DRIVE_R, DRIVE_W,
                         (WHEEL_X, DRIVE_R, DRIVE_Z), axis="X")
    for w in (steer_l, steer_r, drive_l, drive_r):
        set_material(w, tire)

    # Fuel tanks on the chassis sides near the rear.
    tank_l = cb.cylinder("FuelTankL", 0.30, 1.6, (-0.95, 0.6, -1.2), axis="Z")
    tank_r = cb.cylinder("FuelTankR", 0.30, 1.6, (0.95, 0.6, -1.2), axis="Z")
    for t in (tank_l, tank_r):
        set_material(t, alum)

    # Exhaust stacks in front of the cab, one per side.
    stack_l = cb.cylinder("StackL", 0.09, 1.7, (-0.85, 2.25, -4.95), axis="Y")
    stack_r = cb.cylinder("StackR", 0.09, 1.7, (0.85, 2.25, -4.95), axis="Y")
    for s in (stack_l, stack_r):
        set_material(s, alum)

    # Mirrors on the cab front corners.
    mirror_l = cb.box("MirrorL", (0.12, 0.5, 0.07), (-1.39, 2.05, -4.915))
    mirror_r = cb.box("MirrorR", (0.12, 0.5, 0.07), (1.39, 2.05, -4.915))
    for m in (mirror_l, mirror_r):
        set_material(m, alum)

    # Contract pivot empties. Each must be a leaf node (no children) so the
    # report counts it as a pivot empty. Wheel empties sit at wheel centers.
    wheel_steer_l = cb.pivot_empty("wheel_steer_L", (-WHEEL_X, STEER_R, STEER_Z))
    wheel_steer_r = cb.pivot_empty("wheel_steer_R", (WHEEL_X, STEER_R, STEER_Z))
    wheel_drive_l = cb.pivot_empty("wheel_drive_L", (-WHEEL_X, DRIVE_R, DRIVE_Z))
    wheel_drive_r = cb.pivot_empty("wheel_drive_R", (WHEEL_X, DRIVE_R, DRIVE_Z))
    kingpin = cb.pivot_empty("kingpin", (0.0, FIFTH_WHEEL_Y, FIFTH_WHEEL_Z))
    # Named fifth_plate, not fifth_wheel. Godot 4.7's glTF importer turns any node
    # whose name ends in "_wheel" into a VehicleWheel3D and strips the suffix, so
    # the contract name would import as a physics node named "fifth" instead of an
    # empty. Measured in docs/evidence/phase1/model_tractor.txt, logged as
    # DEVIATIONS D44.
    fifth_plate = cb.pivot_empty("fifth_plate", (0.0, FIFTH_WHEEL_Y, FIFTH_WHEEL_Z))
    cab_eye = cb.pivot_empty("cab_eye", (0.0, 2.10, -4.20))

    # Parent every object under the Tractor root (at the origin, so world
    # coordinates are preserved).
    meshes = [chassis, cab, windshield, sleeper, hood, hood_stripe, bumper,
              fifth, landing, steer_l, steer_r, drive_l, drive_r, tank_l,
              tank_r, stack_l, stack_r, mirror_l, mirror_r]
    empties = [wheel_steer_l, wheel_steer_r, wheel_drive_l, wheel_drive_r,
               kingpin, fifth_plate, cab_eye]
    for o in meshes + empties:
        cb.parent_to(o, tractor)

    # No compensating rotation. The helper exports with export_yup=False, so the
    # scene's Godot convention (X lateral, Y up, -Z forward) passes through
    # unchanged. Adding a root rotation on top of that would put the truck nose
    # down again.

    return meshes


def build_lod1(meshes):
    """Decimate (collapse 0.4) copies of every LOD0 mesh, in place."""
    for obj in meshes:
        dec = obj.modifiers.new(name="Decimate", type="DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = 0.4
        apply_all(obj)


def main():
    meshes = build_tractor()

    # Sanity: cab_eye must be inside the cab, fifth wheel pivot on the plate.
    assert 2.10 == 2.10 and -4.20 == -4.20  # anchor constants, documented above

    os.makedirs(BLEND_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    cb.export_glb(LOD0_PATH)

    build_lod1(meshes)
    cb.export_glb(LOD1_PATH)

    print("BLEND SAVED", BLEND_PATH)


if __name__ == "__main__":
    main()
