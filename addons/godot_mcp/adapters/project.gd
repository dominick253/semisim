class_name MCPProjectAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")

static func handles(method: String) -> bool:
	return method.begins_with("project.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"project.info":
			var v := Engine.get_version_info()
			return {
				"plugin": "godot_mcp",
				"plugin_version": "1.0.0",
				"project_name": ProjectSettings.get_setting("application/config/name", ""),
				"godot_version": "%d.%d.%d" % [v.major, v.minor, v.patch],
				"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
			}
		"project.settings":
			return {
				"name": ProjectSettings.get_setting("application/config/name", ""),
				"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
				"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
			}
		"project.reload":
			EditorInterface.get_resource_filesystem().scan()
			return {"reloaded": true}
	return B.err("unsupported: %s" % method)
