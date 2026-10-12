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
	var rig: CameraRig = CameraRig.new()
	rig.name = "CameraRig"
	rig.bind(controller)
	add_child(rig)
	rig.connect_control_layer(layer)
	var audio: Node = load("res://scripts/audio/audio_director.gd").new()
	audio.name = "AudioDirector"
	audio.bind(controller)
	add_child(audio)
	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	hud.bind(controller)
	var modes: Array[String] = []
	for i in 60:
		await get_tree().physics_frame
		layer.sample()
		hud.refresh(1.0 / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
		if i % 15 == 0:
			Input.action_press("camera_cycle")
			await get_tree().physics_frame
			layer.sample()
			Input.action_release("camera_cycle")
			modes.append(rig.mode_name())
			assert(rig.current_cameras().size() == 1, "one current camera")
	print(
		"SMOKE actions=",
		InputMap.get_actions().size(),
		" speed=%.3f" % controller.speed(),
		" gear=",
		controller.transmission.gear,
		" cameras=",
		",".join(modes),
		" audio_samples=",
		audio.sample_index,
		" audio_hiss=",
		audio.hiss_active
	)
	print("SMOKE OK")
	get_tree().quit()
