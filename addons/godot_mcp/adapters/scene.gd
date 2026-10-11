class_name MCPSceneAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("scene.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"scene.list":
			return {"scenes": _list_scenes("res://")}
		"scene.current":
			var root := B.edited_root()
			if root == null:
				return {"scene": null}
			return {"scene": root.scene_file_path, "root": root.name}
		"scene.open":
			var path := str(B.param(params, "path", ""))
			if path.is_empty():
				return B.err("path required")
			# open_scene_from_path() returns void; there's no direct success signal.
			EditorInterface.open_scene_from_path(path)
			return {"opened": true, "path": path}
		"scene.save":
			if B.edited_root() == null:
				return B.err("no scene open")
			var save_path := str(B.param(params, "path", ""))
			if save_path.is_empty():
				var err := EditorInterface.save_scene()
				return {"saved": err == OK, "path": B.edited_root().scene_file_path}
			# save_scene_as() returns void; there's no direct success signal.
			EditorInterface.save_scene_as(save_path, true)
			return {"saved": true, "path": save_path}
		"scene.create":
			var scene_name := str(B.param(params, "name", "NewScene"))
			var scene_path := str(B.param(params, "path", "res://%s.tscn" % scene_name))
			var root := Node2D.new()
			root.name = scene_name
			var packed := PackedScene.new()
			if packed.pack(root) != OK:
				return B.err("failed to pack scene")
			if ResourceSaver.save(packed, scene_path) != OK:
				return B.err("failed to save scene to %s" % scene_path)
			EditorInterface.open_scene_from_path(scene_path)
			B.log_info("created scene %s" % scene_path)
			return {"created": true, "path": scene_path, "name": scene_name}
		"scene.reload":
			var root := B.edited_root()
			if root == null or root.scene_file_path.is_empty():
				return B.err("no saved scene")
			EditorInterface.open_scene_from_path(root.scene_file_path)
			return {"reloaded": true}
		"scene.close":
			# EditorInterface has no public API to close a scene tab in this Godot version.
			return B.err("scene.close is not supported by this Godot version's EditorInterface API")
	return B.err("unsupported: %s" % method)


static func _list_scenes(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir() and not f.begins_with("."):
			out.append_array(_list_scenes(full))
		elif f.ends_with(".tscn") or f.ends_with(".scn"):
			out.append(full)
		f = dir.get_next()
	dir.list_dir_end()
	return out
