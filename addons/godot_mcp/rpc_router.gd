class_name MCPRpcRouter
extends RefCounted

const Base = preload("res://addons/godot_mcp/adapter_base.gd")
const ProjectAdapter = preload("res://addons/godot_mcp/adapters/project.gd")
const SceneAdapter = preload("res://addons/godot_mcp/adapters/scene.gd")
const NodeAdapter = preload("res://addons/godot_mcp/adapters/node.gd")
const ResourceAdapter = preload("res://addons/godot_mcp/adapters/resource.gd")
const FilesystemAdapter = preload("res://addons/godot_mcp/adapters/filesystem.gd")
const ScriptAdapter = preload("res://addons/godot_mcp/adapters/script.gd")
const RuntimeAdapter = preload("res://addons/godot_mcp/adapters/runtime.gd")
const ScreenshotAdapter = preload("res://addons/godot_mcp/adapters/screenshot.gd")
const EditorAdapter = preload("res://addons/godot_mcp/adapters/editor.gd")
const ConsoleAdapter = preload("res://addons/godot_mcp/adapters/console.gd")
const ReflectionAdapter = preload("res://addons/godot_mcp/adapters/reflection.gd")
const SkillsAdapter = preload("res://addons/godot_mcp/adapters/skills.gd")


static func dispatch(method: String, params: Variant) -> Variant:
	var adapters := [
		ProjectAdapter, SceneAdapter, NodeAdapter, ResourceAdapter,
		FilesystemAdapter, ScriptAdapter, RuntimeAdapter, ScreenshotAdapter,
		EditorAdapter, ConsoleAdapter, ReflectionAdapter, SkillsAdapter,
	]
	for adapter in adapters:
		if adapter.handles(method):
			return adapter.dispatch(method, params)
	return Base.err("unknown method: %s" % method)
