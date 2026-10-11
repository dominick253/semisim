class_name MCPSkillsAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")
const NodeAdapter = preload("res://addons/godot_mcp/adapters/node.gd")


static func handles(method: String) -> bool:
	return method.begins_with("skill.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"skill.create_player":
			var parent_path := str(B.param(params, "parent_path", ""))
			if parent_path.is_empty():
				var root := B.edited_root()
				parent_path = str(root.get_path()) if root else ""
			NodeAdapter.dispatch("node.create", {"parent_path": parent_path, "type": "CharacterBody2D", "name": "Player"})
			var player_path := parent_path.path_join("Player") if not parent_path.is_empty() else "Player"
			NodeAdapter.dispatch("node.create", {"parent_path": player_path, "type": "CollisionShape2D", "name": "Collision"})
			NodeAdapter.dispatch("node.create", {"parent_path": player_path, "type": "Sprite2D", "name": "Sprite"})
			return {"created": true, "player_path": player_path}
		"skill.create_scene":
			var name := str(B.param(params, "name", "NewScene"))
			var path := str(B.param(params, "path", "res://%s.tscn" % name))
			var root := Node2D.new()
			root.name = name
			var packed := PackedScene.new()
			packed.pack(root)
			ResourceSaver.save(packed, path)
			EditorInterface.open_scene_from_path(path)
			return {"created": true, "path": path}
		"skill.optimize_project":
			var hints: Array = []
			if ProjectSettings.get_setting("application/run/main_scene", "") == "":
				hints.append("Set a main scene in Project Settings")
			if B.errors.size() > 0:
				hints.append("Fix %d recent errors" % B.errors.size())
			return {"hints": hints, "error_count": B.errors.size()}
		"skill.analyze_error":
			var recent: Array = B.errors.slice(max(0, B.errors.size() - 5))
			return {"errors": recent, "suggestion": "Review stack traces in Godot Output panel"}
	return B.err("unsupported: %s" % method)
