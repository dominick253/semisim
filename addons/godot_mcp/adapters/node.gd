class_name MCPNodeAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("node.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"node.list":
			var root := B.edited_root()
			return {"nodes": _tree(root) if root else []}
		"node.create":
			var parent_path := str(B.param(params, "parent_path", ""))
			var type_name := str(B.param(params, "type", "Node"))
			var node_name := str(B.param(params, "name", "Node"))
			var parent: Node = null
			if parent_path.is_empty():
				parent = B.edited_root()
			else:
				parent = B.find_node(parent_path)
			if parent == null:
				return B.err("parent not found — open a scene or provide parent_path")
			if node_name.is_empty():
				return B.err("name is required")
			if not ClassDB.class_exists(type_name):
				return B.err("unknown class: %s" % type_name)
			var node: Node = ClassDB.instantiate(type_name)
			node.name = node_name
			parent.add_child(node)
			node.owner = B.edited_root()
			return B.object_from_node(node)
		"node.delete":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("node not found")
			var p := str(node.get_path())
			node.queue_free()
			return {"deleted": true, "path": p}
		"node.rename":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("node not found")
			node.name = str(B.param(params, "new_name", node.name))
			return B.object_from_node(node)
		"node.move":
			var node := B.find_node(str(B.param(params, "path", "")))
			var parent := B.find_node(str(B.param(params, "new_parent_path", "")))
			if node == null or parent == null:
				return B.err("node or parent not found")
			if node.get_parent():
				node.get_parent().remove_child(node)
			parent.add_child(node)
			node.owner = B.edited_root()
			return B.object_from_node(node)
		"node.duplicate":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("node not found")
			var dup := node.duplicate()
			node.get_parent().add_child(dup)
			dup.owner = B.edited_root()
			return B.object_from_node(dup)
		"node.get_property":
			var node := B.find_node(str(B.param(params, "path", "")))
			var prop := str(B.param(params, "property", ""))
			if node == null:
				return B.err("node not found")
			return {"path": str(node.get_path()), "property": prop, "value": node.get(prop)}
		"node.set_property":
			var node := B.find_node(str(B.param(params, "path", "")))
			var prop := str(B.param(params, "property", ""))
			if node == null:
				return B.err("node not found")
			node.set(prop, B.coerce_value(node, prop, B.param(params, "value", null)))
			return {"path": str(node.get_path()), "property": prop, "value": node.get(prop)}
		"node.children":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("node not found")
			var kids: Array = []
			for c in node.get_children():
				kids.append(B.object_from_node(c))
			return {"children": kids}
		"node.parent":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null or node.get_parent() == null:
				return {"parent": null}
			return {"parent": B.object_from_node(node.get_parent())}
	return B.err("unsupported: %s" % method)


static func _tree(node: Node) -> Array:
	if node == null:
		return []
	var item := B.object_from_node(node)
	var kids: Array = []
	for c in node.get_children():
		kids.append_array(_tree(c))
	item["children"] = kids
	return [item]
