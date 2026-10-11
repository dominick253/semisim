@tool
extends Node

const Router = preload("res://addons/godot_mcp/rpc_router.gd")
const PermissionManager = preload("res://addons/godot_mcp/permission_manager.gd")

const DEFAULT_URL := "ws://127.0.0.1:6505/ws"
const RECONNECT_SECONDS := 3.0

var _socket := WebSocketPeer.new()
var _reconnect_timer := 0.0
var _url := DEFAULT_URL


func _ready() -> void:
	var env_url := OS.get_environment("GODOT_MCP_BRIDGE_URL")
	if not env_url.is_empty():
		_url = env_url
	set_process(true)
	_connect()


func _process(delta: float) -> void:
	_socket.poll()
	var state := _socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _socket.get_available_packet_count() > 0:
			_handle_message(_socket.get_packet().get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSED:
		_reconnect_timer += delta
		if _reconnect_timer >= RECONNECT_SECONDS:
			_reconnect_timer = 0.0
			_connect()


func _connect() -> void:
	if _socket.get_ready_state() in [WebSocketPeer.STATE_OPEN, WebSocketPeer.STATE_CONNECTING]:
		return
	_socket = WebSocketPeer.new()
	var err := _socket.connect_to_url(_url)
	if err != OK:
		push_warning("Godot MCP: connect failed %s (%d)" % [_url, err])


func emit_event(event_type: String, data: Dictionary = {}) -> void:
	if _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_socket.send_text(JSON.stringify({
		"jsonrpc": "2.0",
		"method": "event",
		"params": {"type": event_type, "data": data},
	}))


func _handle_message(raw: String) -> void:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var request: Dictionary = json.get_data()
	if request.get("jsonrpc", "") != "2.0":
		return
	var method := str(request.get("method", ""))
	var id := str(request.get("id", ""))
	var params: Variant = request.get("params", {})
	if params == null:
		params = {}
	if method == "permission.request":
		_handle_permission_request(id, params)
		return
	var result: Variant = Router.dispatch(method, params)
	if typeof(result) == TYPE_DICTIONARY and (result as Dictionary).has("error"):
		_send_error(id, -32000, str((result as Dictionary)["error"]))
	else:
		_send_json({"jsonrpc": "2.0", "id": id, "result": result})


func _handle_permission_request(id: String, params: Variant) -> void:
	_handle_permission_request_async(id, params)


func _handle_permission_request_async(id: String, params: Variant) -> void:
	var result: Variant = await PermissionManager.request(params)
	if typeof(result) == TYPE_DICTIONARY and (result as Dictionary).has("error"):
		_send_error(id, -32000, str((result as Dictionary)["error"]))
	else:
		_send_json({"jsonrpc": "2.0", "id": id, "result": result})


func _send_error(id: String, code: int, message: String) -> void:
	_send_json({"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}})


func _send_json(payload: Dictionary) -> void:
	if _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(payload))
