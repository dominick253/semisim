@tool
extends EditorPlugin

const BridgeScript = preload("res://addons/godot_mcp/bridge.gd")
const AdapterBase = preload("res://addons/godot_mcp/adapter_base.gd")

var _bridge: Node


func _enter_tree() -> void:
	_bridge = BridgeScript.new()
	add_child(_bridge)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	AdapterBase.set_undo_redo(get_undo_redo())


func _exit_tree() -> void:
	if EditorInterface.get_selection().selection_changed.is_connected(_on_selection_changed):
		EditorInterface.get_selection().selection_changed.disconnect(_on_selection_changed)
	if _bridge:
		_bridge.queue_free()


func _on_selection_changed() -> void:
	if _bridge == null:
		return
	var nodes := EditorInterface.get_selection().get_selected_nodes()
	var data := {"path": "", "name": ""}
	if not nodes.is_empty():
		data = {"path": str(nodes[0].get_path()), "name": nodes[0].name}
	_bridge.emit_event("node.selected", data)
