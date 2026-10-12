extends Node3D
## Renders the test yard, the combination and the HUD, then writes a PNG so the
## HUD can be inspected rather than only asserted. Uses the CPU-only godot
## wrapper (opengl3/llvmpipe) under xvfb; never a GPU device.

const OUT_PATH: String = "res://docs/evidence/phase1/hud_overlay.png"
const SETTLE_TICKS: int = 240

var _hud: Hud


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.10, 0.11, 0.13))
	var yard: Node3D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	var controller: Node3D = load("res://scripts/vehicles/combination_controller.gd").new()
	controller.name = "Combination"
	controller.add_child(load("res://scenes/vehicles/tractor.tscn").instantiate())
	controller.add_child(load("res://scenes/vehicles/trailer.tscn").instantiate())
	add_child(controller)
	controller.place_at_rest()

	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)
	_hud.bind(controller)
	_hud.set_objective("BACK-IN DOCK: TARGET SLOT B3, ERROR UNDER 0.30 M")
	_hud.set_debug_visible(true)

	var camera := Camera3D.new()
	camera.name = "HudCamera"
	camera.position = Vector3(-14.0, 6.0, -16.0)
	camera.look_at(Vector3(0.0, 1.5, 2.0), Vector3.UP)
	add_child(camera)
	camera.current = true

	# Drive a little so the gauges are not all zero, and push the articulation
	# into the warning band so the color thresholds are visible.
	for i in SETTLE_TICKS:
		await get_tree().physics_frame
		controller.throttle = 0.35
		controller.steer_input_axis = 0.6
		controller.retarder_stage = 2
		controller.parking_brake = (i > SETTLE_TICKS / 2)
		controller.air.pressure_psi = 55.0
		_hud.refresh(1.0 / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
	GAME_STATE.flash("RETARDER NEEDS HIGH RANGE, GEAR 1-4, ABOVE 15 KM/H")
	_hud.refresh(1.0 / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
	await get_tree().process_frame
	await get_tree().process_frame
	_save_screenshot()


func _save_screenshot() -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var dir := DirAccess.open("res://")
	dir.make_dir("docs/evidence")
	dir.make_dir("docs/evidence/phase1")
	var err: int = image.save_png(OUT_PATH)
	print("SHOT err=", err, " size=", image.get_width(), "x", image.get_height())
	print(
		"SHOT HUD speed=",
		_hud.label_text("Speed"),
		" tach=",
		_hud.label_text("Tach"),
		" gear=",
		_hud.label_text("Gear"),
		" air=",
		_hud.label_text("Air"),
		" artic=",
		_hud.label_text("Articulation"),
		" flash=",
		_hud.label_text("Flash")
	)
	print("SHOT debug=", _hud.debug_lines())
	get_tree().quit()
