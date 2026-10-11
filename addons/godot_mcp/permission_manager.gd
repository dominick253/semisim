class_name MCPPermissionManager
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")

static var _session_always: Dictionary = {}


static func request(params: Variant) -> Dictionary:
	if typeof(params) != TYPE_DICTIONARY:
		return {"approved": false, "remember": "none"}

	var rpc := str((params as Dictionary).get("rpc", ""))
	if rpc.is_empty():
		return B.err("permission.request requires rpc")

	if _session_always.has(rpc):
		return {"approved": true, "remember": "always"}

	var level := str((params as Dictionary).get("level", ""))
	if level == "destructive" and OS.get_environment("GODOT_MCP_ALLOW_DESTRUCTIVE") == "1":
		return {"approved": true, "remember": "always"}
	if rpc == "script.execute" and OS.get_environment("GODOT_MCP_ALLOW_SCRIPT_EXEC") == "1":
		return {"approved": true, "remember": "always"}

	return await _show_dialog(params as Dictionary)


static func _show_dialog(params: Dictionary) -> Dictionary:
	var tool := str(params.get("tool", "unknown"))
	var rpc := str(params.get("rpc", ""))
	var level := str(params.get("level", ""))

	var dialog := ConfirmationDialog.new()
	dialog.title = "Godot MCP — Permission Request"
	dialog.dialog_text = _format_message(tool, rpc, level, params.get("details", {}))
	dialog.ok_button_text = "Allow Once"
	dialog.cancel_button_text = "Deny"
	dialog.add_button("Allow Always", false, "always")

	var base := EditorInterface.get_base_control()
	base.add_child(dialog)
	dialog.popup_centered()

	var choice := await _wait_for_choice(dialog)
	dialog.queue_free()

	match choice:
		"once":
			return {"approved": true, "remember": "once"}
		"always":
			_session_always[rpc] = true
			return {"approved": true, "remember": "always"}
		_:
			return {"approved": false, "remember": "none"}


static func _format_message(tool: String, rpc: String, level: String, _details: Variant) -> String:
	return (
		"An AI assistant wants to run a sensitive action in your project.\n\n"
		+ "Tool: %s\nRPC: %s\nRisk: %s\n\nAllow this action?"
		% [tool, rpc, level]
	)


static func _wait_for_choice(dialog: ConfirmationDialog) -> String:
	var choice := ["pending"]
	dialog.confirmed.connect(func() -> void: choice[0] = "once", CONNECT_ONE_SHOT)
	dialog.canceled.connect(func() -> void: choice[0] = "deny", CONNECT_ONE_SHOT)
	dialog.custom_action.connect(func(action: String) -> void: choice[0] = action, CONNECT_ONE_SHOT)
	while choice[0] == "pending":
		await Engine.get_main_loop().process_frame
	return choice[0]
