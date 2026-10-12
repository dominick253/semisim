extends SceneTree
## Headless model evidence tool: node inventory, mesh count, triangle count and
## the named pivot empties the asset pipeline requires.
##
## Run after an import pass:
##   godot-headless --path ~/dev/games/semisim --import
##   godot-headless --path ~/dev/games/semisim -s res://scripts/tools/model_report.gd \
##       -- --model res://models/tractor.glb
##
## Prints one line per measured quantity so acceptance evidence is grep-able.

const PIVOT_EMPTIES: Array[String] = [
	"wheel_steer_L",
	"wheel_steer_R",
	"wheel_drive_L",
	"wheel_drive_R",
	"kingpin",
	"fifth_wheel",
	"landing_contact",
	"cab_eye",
	"trailer_ref",
]


func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 2:
		print("MODEL FAIL missing --model <path>")
		quit(1)
		return
	var model_path: String = args[1]
	var model_root: Node = _load_scene(model_path)
	if model_root == null:
		print("MODEL FAIL cannot load ", model_path)
		quit(1)
		return
	# The loaded tree is parented to the scene tree root so the engine owns it.
	# An orphaned instantiated scene leaks ObjectDB instances and RIDs at exit,
	# which would put ERROR lines into the acceptance evidence.
	root.add_child(model_root)
	var total_tris: int = 0
	var mesh_count: int = 0
	var node_names: PackedStringArray = []
	var found_empties: PackedStringArray = []
	var stack: Array = [model_root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		node_names.append(node.name)
		if node is MeshInstance3D:
			var mesh: Mesh = (node as MeshInstance3D).mesh
			if mesh != null:
				mesh_count += 1
				total_tris += _mesh_triangles(mesh)
		if (
			node.get_child_count() == 0
			and not (node is MeshInstance3D)
			and PIVOT_EMPTIES.has(node.name)
		):
			found_empties.append(node.name)
		for child: Node in node.get_children():
			stack.append(child)
	print("MODEL ", model_path)
	print("NODE_COUNT ", node_names.size())
	print("NODE_NAMES ", ", ".join(node_names))
	print("MESHES ", mesh_count)
	print("TOTAL_TRIS ", total_tris)
	print("PIVOT_EMPTIES_FOUND ", found_empties.size(), " of ", PIVOT_EMPTIES.size())
	print("PIVOT_EMPTIES ", ", ".join(found_empties))
	print("MODEL REPORT OK")
	root.remove_child(model_root)
	model_root.free()
	quit(0)


func _load_scene(model_path: String) -> Node:
	var resource: Resource = load(model_path)
	if resource == null:
		return null
	if resource is PackedScene:
		return (resource as PackedScene).instantiate()
	var maybe_node: Object = resource
	if maybe_node is Node:
		return maybe_node as Node
	return null


func _mesh_triangles(mesh: Mesh) -> int:
	var tris: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.size() > 0:
			tris += indices.size() / 3
		else:
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			tris += verts.size() / 3
	return tris
