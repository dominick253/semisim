class_name MCPConsoleAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("console.") or method.begins_with("errors.") or method.begins_with("profiler.")


static func dispatch(method: String, _params: Variant) -> Variant:
	match method:
		"console.logs":
			return {"logs": B.logs.duplicate()}
		"console.clear":
			B.logs.clear()
			return {"cleared": true}
		"errors.list":
			return {"errors": B.errors.duplicate()}
		"errors.clear":
			B.errors.clear()
			return {"cleared": true}
		"profiler.stats":
			return {
				"fps": Engine.get_frames_per_second(),
				"playing": EditorInterface.is_playing_scene(),
				"memory": Performance.get_monitor(Performance.MEMORY_STATIC),
			}
	return B.err("unsupported: %s" % method)
