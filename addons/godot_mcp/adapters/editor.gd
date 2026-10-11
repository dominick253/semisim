class_name MCPEditorAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("editor.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"editor.selection":
			var nodes := EditorInterface.get_selection().get_selected_nodes()
			var out: Array = []
			for n in nodes:
				out.append(B.object_from_node(n, true))
			return {"selection": out}
		"editor.focus":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("node not found")
			EditorInterface.get_selection().clear()
			EditorInterface.get_selection().add_node(node)
			EditorInterface.edit_node(node)
			return {"focused": str(node.get_path())}
		"editor.undo":
			var ur := B.global_undo_redo()
			if ur:
				ur.undo()
			return {"undo": true}
		"editor.redo":
			var ur := B.global_undo_redo()
			if ur:
				ur.redo()
			return {"redo": true}
		"editor.refresh":
			EditorInterface.get_resource_filesystem().scan()
			return {"refreshed": true}
	return B.err("unsupported: %s" % method)
