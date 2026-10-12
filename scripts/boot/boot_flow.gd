class_name BootFlow
extends Node
## The boot scene (the project main scene). Loads the main menu and prints
## BOOT OK once on stdout, so a headless boot is machine-checkable.

const MENU_SCENE: String = "res://scenes/main_menu.tscn"


func _ready() -> void:
	var scene: PackedScene = load(MENU_SCENE) as PackedScene
	var menu: Control = scene.instantiate()
	add_child(menu)
	print("BOOT OK")
