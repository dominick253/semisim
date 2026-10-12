"""CITYHAUL Blender build helpers.

Used by the build scripts in this directory:

    blender --background --python tools/blender/build_tractor.py

CPU only. Run Blender through the `blender` wrapper, never the binary directly.
Coordinates follow the build spec: X is lateral, Y is up, Z is forward along the
vehicle, which is the same handedness `docs/physics-spec.md` uses. Godot imports
the GLB with +Y up.
"""

import os

import bpy  # provided by the Blender interpreter, not by system Python


def fresh_scene() -> None:
	"""Start from an empty scene so a rebuild is reproducible."""
	bpy.ops.wm.read_factory_settings(use_empty=True)


def box(name: str, size, location):
	"""Add a cube. size is (x, y, z) full extents in meters."""
	bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
	obj = bpy.context.active_object
	obj.name = name
	obj.scale = (size[0], size[1], size[2])
	bpy.ops.object.transform_apply(scale=True)
	return obj


def cylinder(name: str, radius: float, depth: float, location, axis: str = "X"):
	"""Add a cylinder. axis is the cylinder's own length direction."""
	bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, vertices=24)
	obj = bpy.context.active_object
	obj.name = name
	if axis == "X":
		obj.rotation_euler = (0.0, 1.5707963267948966, 0.0)
	elif axis == "Z":
		obj.rotation_euler = (0.0, 0.0, 0.0)
	else:
		obj.rotation_euler = (1.5707963267948966, 0.0, 0.0)
	bpy.ops.object.transform_apply(rotation=True)
	return obj


def pivot_empty(name: str, location):
	"""Add a named pivot empty. These are contract nodes, not decoration."""
	bpy.ops.object.empty_add(type="PLAIN_AXES", location=location)
	obj = bpy.context.active_object
	obj.name = name
	return obj


def apply_modifiers(obj) -> None:
	for modifier in list(obj.modifiers):
		bpy.ops.object.modifier_apply(modifier=modifier.name)


def triangles(obj) -> int:
	return sum(len(polygon.vertices) - 2 for polygon in obj.data.polygons)


def scene_triangles() -> int:
	total = 0
	for obj in bpy.context.scene.objects:
		if obj.type == "MESH":
			total += triangles(obj)
	return total


def parent_to(child, parent) -> None:
	child.parent = parent


def export_glb(filepath: str) -> str:
	"""Export the whole scene as a GLB with modifiers applied."""
	directory = os.path.dirname(filepath)
	if directory:
		os.makedirs(directory, exist_ok=True)
	bpy.ops.export_scene.gltf(
		filepath=filepath,
		export_format="GLB",
		export_apply=True,
		use_selection=False,
		export_yup=True,
	)
	size = os.path.getsize(filepath)
	if size == 0:
		raise RuntimeError("export produced an empty file: " + filepath)
	print("EXPORT OK", filepath, "bytes=", size, "scene_tris=", scene_triangles())
	return filepath
