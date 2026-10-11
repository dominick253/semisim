class_name MCPFilesystemAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("filesystem.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"filesystem.list":
			var path := str(B.param(params, "path", "res://"))
			var entries: Array = []
			var dir := DirAccess.open(path)
			if dir:
				dir.list_dir_begin()
				var f := dir.get_next()
				while f != "":
					if not f.begins_with("."):
						entries.append({"name": f, "dir": dir.current_is_dir()})
					f = dir.get_next()
				dir.list_dir_end()
			return {"path": path, "entries": entries}
		"filesystem.read":
			var path := str(B.param(params, "path", ""))
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				return B.err("cannot read file")
			return {"path": path, "content": f.get_as_text()}
		"filesystem.write":
			var path := str(B.param(params, "path", ""))
			var content := str(B.param(params, "content", ""))
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return B.err("cannot write file")
			f.store_string(content)
			return {"path": path, "written": true}
		"filesystem.create":
			var path := str(B.param(params, "path", ""))
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return B.err("cannot create file")
			f.store_string("")
			return {"created": true, "path": path}
		"filesystem.delete":
			var path := str(B.param(params, "path", ""))
			return {"deleted": DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK}
		"filesystem.mkdir":
			var path := str(B.param(params, "path", ""))
			return {"created": DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path)) == OK}
	return B.err("unsupported: %s" % method)
