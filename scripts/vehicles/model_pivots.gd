class_name ModelPivots
extends RefCounted
## The named pivot empties the GLB models carry (AS1: cab_eye, kingpin,
## fifth_plate and the four wheel anchors; AS2: trailer_ref, landing_contact
## and kingpin) and the lookup the camera rig uses in place of the pinned
## placeholder vectors (DEVIATIONS D31, D47).


static func find_pivot(root: Node, pivot_name: String) -> Node3D:
	## Walks root's descendants depth first and returns the first Node3D whose
	## name matches pivot_name, or null when no descendant has that name.
	if root == null:
		return null
	var stack: Array[Node] = []
	for i in range(root.get_child_count() - 1, -1, -1):
		stack.push_back(root.get_child(i))
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Node3D and node.name == pivot_name:
			return node as Node3D
		for i in range(node.get_child_count() - 1, -1, -1):
			stack.push_back(node.get_child(i))
	return null


static func pivot_global_position(root: Node, pivot_name: String) -> Vector3:
	## Returns the global_position of the first descendant named pivot_name,
	## or Vector3.INF when no such pivot exists. Vector3.INF is the not-found
	## sentinel: compare against it before using the result, never as a position.
	var pivot: Node3D = find_pivot(root, pivot_name)
	if pivot == null:
		return Vector3.INF
	return pivot.global_position
