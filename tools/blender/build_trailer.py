"""CITYHAUL Phase 1 trailer model build (headless Blender).

Run:
    cd /home/dom/dev/games/semisim
    blender --background --python tools/blender/build_trailer.py

Produces models/trailer.glb (LOD0) and models/trailer_lod1.glb (LOD1, decimated
collapse ratio 0.4 on copies of the LOD0 meshes) and keeps the .blend source at
~/dev/3d/semisim/trailer.blend.

Coordinates match docs/physics-spec.md exactly: X lateral, Y up, -Z forward.
The trailer model origin IS its kingpin, so the model root sits at the world
origin and every anchor below is trailer-local, measured from the kingpin.
Pinned numbers from scripts/physics/PHYSICS_CONSTANTS.gd (not negotiable):
  - Cargo box: 2.59 x 4.07 x 16.15, center (0.0, 2.035, 5.675), so the box
    spans z -2.40..+13.75 and y 0.0..4.07
  - Bogie axle anchors (0, 0.563, 9.60) and (0, 0.563, 10.40); wheel track
    half width 1.05, rolling radius 0.563
  - Kingpin (0, 1.30, 0.0)
  - trailer_ref pivot (0, 1.60, 6.00)
  - landing_contact pivot (0, 0.35, -1.20): the spec pins the 0.35 m stroke
    height (LANDING_CONTACT_HEIGHT_M) but never the x and z. 1.20 m behind the
    kingpin plate is the standard 53 ft van landing gear position and it sits
    inside the box footprint. Logged as DEVIATIONS D46.

Two pipeline rules that cost a rebuild to learn (DEVIATIONS D44, D45):
  - No node or pivot name may end in the word wheel: Godot 4.7.2's glTF
    importer turns any node whose name ends in `_wheel` or `-wheel` into a
    VehicleWheel3D and strips the suffix, so the name is gone and a physics
    node appears in its place.
  - Export through cityhaul_blender.export_glb, which uses export_yup=False.
    Never call bpy.ops.export_scene.gltf with export_yup=True on top of
    geometry already written in the Godot convention; the -90 deg X
    conversion lands an upright model nose down.

Budgets (docs/asset-pipeline.md, hard caps): LOD0 35,000 tris, LOD1 18,000.
Materials: plain PBR metallic and roughness only, no procedural nodes in the
exported file, no third-party texture in this slice.
"""

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cityhaul_blender as cb  # noqa: E402  (helper lives next to this script)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.dirname(os.path.dirname(SCRIPT_DIR))
BLEND_DIR = os.path.expanduser("~/dev/3d/semisim")
BLEND_PATH = os.path.join(BLEND_DIR, "trailer.blend")
LOD0_PATH = os.path.join(REPO_ROOT, "models", "trailer.glb")
LOD1_PATH = os.path.join(REPO_ROOT, "models", "trailer_lod1.glb")

# Pinned anchors (PHYSICS_CONSTANTS.gd section 5.1; DEVIATIONS D3, D46).
BOX_SIZE = (2.59, 4.07, 16.15)
BOX_CENTER = (0.0, 2.035, 5.675)
KINGPIN = (0.0, 1.30, 0.0)
TRAILER_REF = (0.0, 1.60, 6.00)
# D46: x and z are a decision (see module docstring); y is the pinned stroke.
LANDING_CONTACT = (0.0, 0.35, -1.20)
BOGIE_Z_FRONT = 9.60
BOGIE_Z_REAR = 10.40
WHEEL_Y = 0.563
WHEEL_X = 1.05
WHEEL_R = 0.563
WHEEL_W = 0.285


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


def apply_all(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    cb.apply_modifiers(obj)


def join(objects, name):
    """Join parts into one mesh object so the GLB node inventory stays exact."""
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.object.join()
    objects[0].name = name
    return objects[0]


def build_trailer():
    cb.fresh_scene()

    van = make_material("TrailerVan", (0.85, 0.86, 0.88), 0.0, 0.40)
    tire = make_material("TireRubber", (0.05, 0.05, 0.05), 0.0, 0.9)
    alum = make_material("BareAluminum", (0.72, 0.74, 0.76), 0.9, 0.35)
    steel = make_material("KingpinSteel", (0.35, 0.36, 0.38), 0.85, 0.35)

    # Root at the origin. The trailer origin IS its kingpin, so world and
    # trailer-local coordinates coincide and everything is measured from it.
    trailer = cb.pivot_empty("Trailer", (0.0, 0.0, 0.0))

    # Cargo box: the full physics envelope, bottom on the ground plane y 0,
    # top at y 4.07, front face z -2.40, rear face z +13.75.
    cargo = cb.box("CargoBox", BOX_SIZE, BOX_CENTER)
    set_material(cargo, van)

    # Tandem bogie wheels. Front axle z 9.60, rear axle z 10.40 (both behind
    # the kingpin; the trailer rear is +Z). Axle center y 0.563 so the tire
    # bottom rests on the ground plane. L = -X, R = +X, the same side
    # convention as build_tractor.py.
    wheel_fl = cb.cylinder("TrailerWheelFL", WHEEL_R, WHEEL_W,
                           (-WHEEL_X, WHEEL_Y, BOGIE_Z_FRONT), axis="X")
    wheel_fr = cb.cylinder("TrailerWheelFR", WHEEL_R, WHEEL_W,
                           (WHEEL_X, WHEEL_Y, BOGIE_Z_FRONT), axis="X")
    wheel_rl = cb.cylinder("TrailerWheelRL", WHEEL_R, WHEEL_W,
                           (-WHEEL_X, WHEEL_Y, BOGIE_Z_REAR), axis="X")
    wheel_rr = cb.cylinder("TrailerWheelRR", WHEEL_R, WHEEL_W,
                           (WHEEL_X, WHEEL_Y, BOGIE_Z_REAR), axis="X")
    for w in (wheel_fl, wheel_fr, wheel_rl, wheel_rr):
        set_material(w, tire)

    # Kingpin: bearing plate under the tractor fifth wheel (top face y 1.25,
    # meeting the fifth wheel plate top at y 1.30) with the pin rising to the
    # kingpin point (0, 1.30, 0.0). Joined into the single contract node.
    plate = cb.box("KingpinPlate", (1.0, 0.10, 0.7), (0.0, 1.20, 0.0))
    set_material(plate, alum)
    pin = cb.cylinder("KingpinPin", 0.09, 0.10, (KINGPIN[0], KINGPIN[1], KINGPIN[2]),
                      axis="Y")
    set_material(pin, steel)
    kingpin_mesh = join([plate, pin], "TrailerKingpin")

    # Landing gear at the D46 point: frame plus two legs whose bottom sits at
    # the pinned stroke height y 0.35, under the box front.
    frame = cb.box("LandingFrame", (0.5, 0.12, 0.5), (0.0, 0.85, LANDING_CONTACT[2]))
    set_material(frame, alum)
    leg_l = cb.cylinder("LegL", 0.05, 0.45, (-0.18, 0.575, LANDING_CONTACT[2]),
                        axis="Y")
    leg_r = cb.cylinder("LegR", 0.05, 0.45, (0.18, 0.575, LANDING_CONTACT[2]),
                        axis="Y")
    for leg in (leg_l, leg_r):
        set_material(leg, alum)
    landing_mesh = join([frame, leg_l, leg_r], "LandingGear")

    # Contract pivot empties. Each must be a leaf node (no children) so the
    # report counts it as a pivot empty.
    kingpin = cb.pivot_empty("kingpin", KINGPIN)
    landing_contact = cb.pivot_empty("landing_contact", LANDING_CONTACT)
    trailer_ref = cb.pivot_empty("trailer_ref", TRAILER_REF)

    # Parent every object under the Trailer root (at the origin, so world
    # coordinates are preserved).
    meshes = [cargo, wheel_fl, wheel_fr, wheel_rl, wheel_rr,
              kingpin_mesh, landing_mesh]
    empties = [kingpin, landing_contact, trailer_ref]
    for o in meshes + empties:
        cb.parent_to(o, trailer)

    # No compensating rotation. The helper exports with export_yup=False, so
    # the scene's Godot convention (X lateral, Y up, -Z forward) passes
    # through unchanged. Adding a root rotation on top of that would put the
    # trailer nose down again.

    return meshes


def build_lod1(meshes):
    """Decimate (collapse 0.4) copies of every LOD0 mesh, in place."""
    for obj in meshes:
        dec = obj.modifiers.new(name="Decimate", type="DECIMATE")
        dec.decimate_type = "COLLAPSE"
        dec.ratio = 0.4
        apply_all(obj)


def main():
    meshes = build_trailer()

    # Budget guard: the hard caps are 35,000 (LOD0) and 18,000 (LOD1).
    tris0 = cb.scene_triangles()
    assert tris0 <= 35000, "LOD0 over budget: " + str(tris0) + " tris"

    os.makedirs(BLEND_DIR, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    cb.export_glb(LOD0_PATH)

    build_lod1(meshes)
    tris1 = cb.scene_triangles()
    assert tris1 <= 18000, "LOD1 over budget: " + str(tris1) + " tris"
    cb.export_glb(LOD1_PATH)

    print("BLEND SAVED", BLEND_PATH)


if __name__ == "__main__":
    main()
