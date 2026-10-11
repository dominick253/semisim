class_name MCPAdapterBase
extends RefCounted

const MAX_LOGS := 300

static var logs: Array = []
static var errors: Array = []
static var _undo_redo: EditorUndoRedoManager


static func set_undo_redo(ur: EditorUndoRedoManager) -> void:
	_undo_redo = ur


# EditorInterface has no direct undo()/redo(); the manager exposes per-object
# history, so we operate on the shared GLOBAL_HISTORY like the Edit menu does.
static func global_undo_redo() -> UndoRedo:
	if _undo_redo == null:
		return null
	return _undo_redo.get_history_undo_redo(EditorUndoRedoManager.GLOBAL_HISTORY)


static func log_info(message: String) -> void:
	_append_log("info", message)


static func log_error(message: String, source: String = "") -> void:
	errors.append({"message": message, "source": source})
	if errors.size() > MAX_LOGS:
		errors.pop_front()
	_append_log("error", message)


static func _append_log(level: String, message: String) -> void:
	logs.append({"level": level, "message": message})
	if logs.size() > MAX_LOGS:
		logs.pop_front()


static func param(params: Variant, key: String, default: Variant = "") -> Variant:
	if typeof(params) != TYPE_DICTIONARY:
		return default
	return (params as Dictionary).get(key, default)


static func err(message: String) -> Dictionary:
	log_error(message)
	return {"error": message}


static func edited_root() -> Node:
	return EditorInterface.get_edited_scene_root()


static func find_node(path: String) -> Node:
	var root := edited_root()
	if root == null:
		return null
	if root.has_node(path):
		return root.get_node(path)
	var tree := root.get_tree()
	if tree and tree.root.has_node(path):
		return tree.root.get_node(path)
	return null


static func node_object(node: Node) -> Dictionary:
	return {
		"class": node.get_class(),
		"path": str(node.get_path()),
		"name": node.name,
		"properties": {},
	}


static func object_from_node(node: Node, include_props: bool = false) -> Dictionary:
	var obj := node_object(node)
	if include_props:
		var props := {}
		for info in node.get_property_list():
			if info.usage & PROPERTY_USAGE_EDITOR:
				props[info.name] = node.get(info.name)
		obj["properties"] = props
	return obj


static func coerce_value(node: Node, property: String, value: Variant) -> Variant:
	var current = node.get(property)
	match typeof(current):
		TYPE_INT: return int(value)
		TYPE_FLOAT: return float(value)
		TYPE_BOOL: return bool(value)
		TYPE_VECTOR2:
			if typeof(value) == TYPE_DICTIONARY:
				return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
		TYPE_VECTOR3:
			if typeof(value) == TYPE_DICTIONARY:
				return Vector3(float(value.get("x", 0)), float(value.get("y", 0)), float(value.get("z", 0)))
	return value
