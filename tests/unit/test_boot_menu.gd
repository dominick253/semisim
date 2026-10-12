extends GutTest
## W1 boot and menu. The boot scene (the project main scene) loads the main
## menu and prints BOOT OK; the menu is a Control with three keyboard-drivable
## entries (Test Yard, Settings, Quit). entries() and selected_index() are
## public so a headless test can read them, and the menu is driven through
## _unhandled_input with constructed key events, so no display is needed.

const BOOT_SCENE: String = "res://scenes/boot.tscn"
const MENU_SCENE: String = "res://scenes/main_menu.tscn"

var _menu: MainMenu


func before_all() -> void:
	var scene: PackedScene = load(MENU_SCENE)
	_menu = scene.instantiate()
	add_child(_menu)
	await get_tree().physics_frame


func after_all() -> void:
	if is_instance_valid(_menu):
		_menu.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame


func test_boot_scene_resource_exists_and_loads() -> void:
	var res: Resource = load(BOOT_SCENE)
	assert_not_null(res, "boot.tscn must exist and load")
	assert_true(res is PackedScene, "boot.tscn must be a PackedScene")
	var root: Node = (res as PackedScene).instantiate()
	assert_true(root is BootFlow, "boot scene root must be a BootFlow")
	root.free()


func test_menu_scene_resource_exists_and_loads() -> void:
	var res: Resource = load(MENU_SCENE)
	assert_not_null(res, "main_menu.tscn must exist and load")
	assert_true(res is PackedScene, "main_menu.tscn must be a PackedScene")
	var root: Node = (res as PackedScene).instantiate()
	assert_true(root is MainMenu, "menu scene root must be a MainMenu")
	root.free()


func test_menu_exposes_the_three_entries_in_order() -> void:
	var want: PackedStringArray = PackedStringArray(["Test Yard", "Settings", "Quit"])
	assert_eq(_menu.entries(), want, "entries are pinned in order")


func test_selection_moves_with_the_up_and_down_keys() -> void:
	assert_eq(_menu.selected_index(), 0, "selection starts on the first entry")
	_press(_menu, KEY_DOWN)
	assert_eq(_menu.selected_index(), 1, "down moves to Settings")
	_press(_menu, KEY_DOWN)
	assert_eq(_menu.selected_index(), 2, "down wraps to Quit")
	_press(_menu, KEY_UP)
	assert_eq(_menu.selected_index(), 1, "up moves back to Settings")
	_press(_menu, KEY_UP)
	assert_eq(_menu.selected_index(), 0, "up wraps to Test Yard")


func _press(menu: MainMenu, key: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = key
	ev.pressed = true
	# SceneTree.call_input does not reach _unhandled_input in a headless GUT run
	# (verified: the selection assertions fail with it), so the event is handed to
	# the handler the same way the tree hands it.
	menu._unhandled_input(ev)
