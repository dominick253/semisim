class_name MCPResourceAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("resource.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"resource.load":
			var path := str(B.param(params, "path", ""))
			var res := load(path)
			return {"loaded": res != null, "path": path, "type": res.get_class() if res else ""}
		"resource.save":
			return B.err("resource.save: use filesystem.write for text resources")
		"resource.create":
			var path := str(B.param(params, "path", ""))
			var type_name := str(B.param(params, "type", "Resource"))
			if not ClassDB.class_exists(type_name):
				return B.err("unknown resource type")
			var res: Resource = ClassDB.instantiate(type_name)
			return {"created": ResourceSaver.save(res, path) == OK, "path": path}
		"resource.inspect":
			var path := str(B.param(params, "path", ""))
			var res := load(path)
			if res == null:
				return B.err("resource not found")
			return {"class": res.get_class(), "path": path}
		"resource.list":
			var path := str(B.param(params, "path", "res://"))
			return {"resources": _list_res(path)}
		"resource.delete":
			var path := str(B.param(params, "path", ""))
			var abs := ProjectSettings.globalize_path(path)
			return {"deleted": DirAccess.remove_absolute(abs) == OK}
	return B.err("unsupported: %s" % method)


static func _list_res(path: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir() and not f.begins_with("."):
			out.append_array(_list_res(full))
		elif f.contains("."):
			out.append(full)
		f = dir.get_next()
	dir.list_dir_end()
	return out
