class_name MainMenu
extends Control
## The main menu. A Control with three keyboard-drivable entries in pinned
## order: Test Yard, Settings, Quit. Up and Down move the selection (wrapping),
## Enter activates it, and the selected entry is highlighted by color. Driven by
## raw key events in _unhandled_input, so no new InputMap action is required.

const TEST_YARD_SCENE: String = "res://scenes/world/test_yard.tscn"

const _ITEMS: PackedStringArray = ["Test Yard", "Settings", "Quit"]

const _SELECTED_COLOR := Color(1.0, 1.0, 1.0)
const _NORMAL_COLOR := Color(0.62, 0.66, 0.70)

var _labels: Array[Label] = []
var _selected_index: int = 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh()


func entries() -> PackedStringArray:
	return _ITEMS


func selected_index() -> int:
	return _selected_index


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key: InputEventKey = event
	if not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_UP:
			_move_selection(-1)
		KEY_DOWN:
			_move_selection(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate_selected()


func _move_selection(delta: int) -> void:
	var count: int = _ITEMS.size()
	_selected_index = (_selected_index + delta) % count
	if _selected_index < 0:
		_selected_index += count
	_refresh()


func _activate_selected() -> void:
	match _ITEMS[_selected_index]:
		"Test Yard":
			get_tree().change_scene_to_file(TEST_YARD_SCENE)
		"Settings":
			print("MENU NOT_IMPLEMENTED")
		"Quit":
			get_tree().quit()


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.add_theme_constant_override("separation", 18)
	add_child(box)
	for item in _ITEMS:
		var label := Label.new()
		label.text = item
		label.add_theme_font_size_override("font_size", 40)
		box.add_child(label)
		_labels.append(label)


func _refresh() -> void:
	for i in _labels.size():
		var label: Label = _labels[i]
		var color: Color = _SELECTED_COLOR if i == _selected_index else _NORMAL_COLOR
		label.add_theme_color_override("font_color", color)
