extends Node3D
## Headless smoke: the yard loads, the INPUT_SETUP autoload installs the pinned
## map, and the control layer samples without errors.


func _ready() -> void:
	var yard: Node3D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var controller: Node3D = load("res://scripts/vehicles/combination_controller.gd").new()
	controller.name = "Combination"
	controller.add_child(load("res://scenes/vehicles/tractor.tscn").instantiate())
	controller.add_child(load("res://scenes/vehicles/trailer.tscn").instantiate())
	add_child(controller)
	controller.place_at_rest()
	var layer: ControlLayer = ControlLayer.new(controller)
	for i in 60:
		await get_tree().physics_frame
		layer.sample()
	print(
		"SMOKE actions=",
		InputMap.get_actions().size(),
		" speed=%.3f" % controller.speed(),
		" gear=",
		controller.transmission.gear
	)
	print("SMOKE OK")
	get_tree().quit()
