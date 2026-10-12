extends Node3D
## Renders the test yard and combination through all four camera modes and
## writes one PNG per mode so the cameras can be inspected, not only asserted.
## Uses the CPU-only godot wrapper (opengl3/llvmpipe) under xvfb.

const CameraRig := preload("res://scripts/camera/camera_rig.gd")
const OUT_DIR: String = "res://docs/evidence/phase1"
const SETTLE_TICKS: int = 240
const MODE_NAMES: Array[String] = ["chase", "cab", "trailer", "free"]

var _rig: Node3D
var _controller: Node3D


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.10, 0.11, 0.13))
	var yard: Node3D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	_controller = load("res://scripts/vehicles/combination_controller.gd").new()
	_controller.name = "Combination"
	_controller.add_child(load("res://scenes/vehicles/tractor.tscn").instantiate())
	_controller.add_child(load("res://scenes/vehicles/trailer.tscn").instantiate())
	add_child(_controller)
	_controller.place_at_rest()

	_rig = CameraRig.new()
	_rig.name = "CameraRig"
	_rig.bind(_controller)
	add_child(_rig)

	var hud: Hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(hud)
	hud.bind(_controller)
	hud.set_objective("CAMERA EVIDENCE PASS")

	# Drive forward with a lane change so articulation and speed are visible.
	# Automatic mode plus an explicit drive gear: throttle alone in neutral does
	# nothing, and the evidence has to show a moving combination.
	_controller.transmission.automatic = true
	for i in SETTLE_TICKS:
		await get_tree().physics_frame
		if i == SETTLE_TICKS / 3:
			_controller.request_gear(4)
		_controller.throttle = 0.85 if i > SETTLE_TICKS / 3 else 0.0
		_controller.steer_input_axis = 0.7 if i > SETTLE_TICKS * 2 / 3 else 0.0
		hud.refresh(1.0 / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)

	var dir := DirAccess.open("res://")
	dir.make_dir("docs/evidence")
	dir.make_dir(OUT_DIR.replace("res://", ""))
	for mode_i in CameraRig.MODE_ORDER.size():
		_rig.set_mode(CameraRig.MODE_ORDER[mode_i])
		for _i in 40:
			await get_tree().physics_frame
			hud.refresh(1.0 / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
		await get_tree().process_frame
		await get_tree().process_frame
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = "%s/camera_%s.png" % [OUT_DIR, MODE_NAMES[mode_i]]
		var err: int = image.save_png(path)
		var cam: Camera3D = _rig.current_cameras()[0]
		var tractor_center: Vector3 = (_controller.tractor as RigidBody3D).global_position
		var trailer_center: Vector3 = (_controller.trailer as RigidBody3D).global_position
		print(
			"SHOT mode=",
			_rig.mode_name(),
			" err=",
			err,
			" pos=",
			cam.global_position,
			" dist_tractor=",
			cam.global_position.distance_to(_rig.tractor_ref_global()),
			" tractor_in_frustum=",
			cam.is_position_in_frustum(tractor_center),
			" trailer_in_frustum=",
			cam.is_position_in_frustum(trailer_center),
			" mirrors=",
			_rig.mirror_cameras()[0].current
		)
	print("CAMERA SHOTS DONE")
	get_tree().quit()
