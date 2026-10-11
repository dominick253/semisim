class_name MCPRuntimeAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("runtime.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"runtime.run":
			EditorInterface.play_main_scene()
			return {"running": true}
		"runtime.stop":
			EditorInterface.stop_playing_scene()
			return {"stopped": true}
		"runtime.pause", "runtime.resume":
			# EditorInterface has no public API to pause/resume the running scene in this Godot version.
			return B.err("%s is not supported by this Godot version's EditorInterface API" % method)
		"runtime.status":
			return {
				"playing": EditorInterface.is_playing_scene(),
				"fps": Engine.get_frames_per_second(),
			}
		"runtime.restart":
			EditorInterface.stop_playing_scene()
			EditorInterface.play_main_scene()
			return {"restarted": true}
	return B.err("unsupported: %s" % method)
