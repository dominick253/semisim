class_name MCPReflectionAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method in ["object.inspect", "class.inspect", "property.list", "method.list"]


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"object.inspect":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("object not found")
			return B.object_from_node(node, true)
		"class.inspect":
			var cls := str(B.param(params, "class", ""))
			if not ClassDB.class_exists(cls):
				return B.err("class not found")
			var props: Array = []
			for p in ClassDB.class_get_property_list(cls, true):
				props.append({"name": p.name, "type": p.type})
			return {"class": cls, "properties": props}
		"property.list":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("object not found")
			var props: Array = []
			for info in node.get_property_list():
				props.append({"name": info.name, "type": info.type})
			return {"properties": props}
		"method.list":
			var node := B.find_node(str(B.param(params, "path", "")))
			if node == null:
				return B.err("object not found")
			var methods: Array = []
			for info in node.get_method_list():
				methods.append({"name": info.name})
			return {"methods": methods}
	return B.err("unsupported: %s" % method)
