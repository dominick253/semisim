class_name MCPScreenshotAdapter
extends RefCounted

const B = preload("res://addons/godot_mcp/adapter_base.gd")


static func handles(method: String) -> bool:
	return method.begins_with("screenshot.")


static func dispatch(method: String, params: Variant) -> Variant:
	match method:
		"screenshot.capture", "screenshot.viewport":
			var img := _capture()
			if img == null or img.is_empty():
				return B.err("capture failed")
			var png := img.save_png_to_buffer()
			return {
				"format": "png",
				"data": Marshalls.raw_to_base64(png),
				"width": img.get_width(),
				"height": img.get_height(),
			}
	return B.err("unsupported: %s" % method)


static func _capture() -> Image:
	# get_playing_scene() returns the scene's res:// path (a String), not a node —
	# the running game is a separate process, so its viewport isn't reachable here.
	for getter in [EditorInterface.get_editor_viewport_2d, EditorInterface.get_editor_viewport_3d]:
		var vp: SubViewport = getter.call()
		if vp:
			var tex: ViewportTexture = vp.get_texture()
			if tex:
				return tex.get_image()
	return null
