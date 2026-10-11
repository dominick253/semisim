class_name MCPScriptAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("script.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"script.read":
			var path := str(B.param(params, "path", ""))
			var f := FileAccess.open(path, FileAccess.READ)
			if f == null:
				return B.err("script not found")
			return {"path": path, "source": f.get_as_text()}
		"script.create":
			var path := str(B.param(params, "path", ""))
			var source := str(B.param(params, "source", "extends Node\n"))
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return B.err("cannot create script")
			f.store_string(source)
			return {"created": true, "path": path}
		"script.update":
			var path := str(B.param(params, "path", ""))
			var source := str(B.param(params, "source", ""))
			var f := FileAccess.open(path, FileAccess.WRITE)
			if f == null:
				return B.err("cannot update script")
			f.store_string(source)
			return {"updated": true, "path": path}
		"script.attach":
			var node := B.find_node(str(B.param(params, "path", "")))
			var script_path := str(B.param(params, "script_path", ""))
			if node == null:
				return B.err("node not found")
			var scr := load(script_path)
			if scr == null:
				return B.err("script not found")
			node.set_script(scr)
			return {"attached": true}
		"script.detach":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("node not found")
			node.set_script(null)
			return {"detached": true}
		"script.execute":
			var source := str(B.param(params, "source", ""))
			if source.is_empty():
				return B.err("source is required")
			var expr := Expression.new()
			var parse_err := expr.parse(source)
			if parse_err != OK:
				return B.err("parse error: %s" % expr.get_error_text())
			var root := B.edited_root()
			var result = expr.execute([], root, false)
			if expr.has_execute_failed():
				return B.err(expr.get_error_text())
			return {"result": result, "executed": true}
	return B.err("unsupported: %s" % method)
