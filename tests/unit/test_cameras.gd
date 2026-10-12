extends GutTest
## Task 23 part 2: camera follow behaviour against the live combination, the
## mirror quads, and the wiring from the pinned section 11 actions to the rig.

const CameraRig := preload("res://scripts/camera/camera_rig.gd")
const ControlLayer := preload("res://scripts/input/control_layer.gd")
const InputMapSetup := preload("res://scripts/input/input_map_setup.gd")

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

var _harness: Node = null
var _rig: Node = null


func before_each() -> void:
	_harness = load(HARNESS_SCENE).instantiate()
	add_child(_harness)
	_rig = CameraRig.new()
	_rig.name = "CameraRig"
	_rig.bind(_harness.controller)
	add_child(_rig)


func after_each() -> void:
	_rig.queue_free()
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame


func _settle_and_drive(ticks: int) -> void:
	await _harness.settle(120)
	for _i in ticks:
		_harness.controller.throttle = 0.4
		await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Follow behaviour
# ---------------------------------------------------------------------------


func test_chase_camera_sits_behind_and_above_the_tractor_ref() -> void:
	await _settle_and_drive(60)
	_rig.set_mode(CameraRig.Mode.CHASE)
	for _i in 60:
		await get_tree().physics_frame
	var cam: Camera3D = _rig.current_cameras()[0]
	var ref: Vector3 = _rig.tractor_ref_global()
	var offset: Vector3 = cam.global_position - ref
	# Section 10 pins the arm as two separate offsets: 14 m behind in the ground
	# plane and 5 m above. Assert each axis rather than the diagonal (D33).
	var horizontal: Vector2 = Vector2(offset.x, offset.z)
	assert_almost_eq(
		horizontal.length(),
		PHYSICS_CONSTANTS.CHASE_ARM_LENGTH_M,
		0.6,
		"14 m behind in the ground plane"
	)
	assert_almost_eq(offset.y, PHYSICS_CONSTANTS.CHASE_HEIGHT_M, 0.6, "5 m above")
	assert_gt(offset.z, 4.0, "behind a tractor facing -Z")


func test_trailer_camera_tracks_the_trailer_ref() -> void:
	await _settle_and_drive(40)
	_rig.set_mode(CameraRig.Mode.TRAILER)
	for _i in 60:
		await get_tree().physics_frame
	var cam: Camera3D = _rig.current_cameras()[0]
	var ref: Vector3 = _rig.trailer_ref_global()
	var offset: Vector3 = cam.global_position - ref
	var horizontal: Vector2 = Vector2(offset.x, offset.z)
	assert_almost_eq(
		horizontal.length(),
		PHYSICS_CONSTANTS.TRAILER_ARM_LENGTH_M,
		0.7,
		"12 m behind the trailer ref in the ground plane"
	)
	assert_gt(offset.y, 2.0, "camera above the trailer ref")


func test_free_camera_holds_a_20_m_orbit() -> void:
	await _settle_and_drive(20)
	_rig.set_mode(CameraRig.Mode.FREE)
	for _i in 60:
		await get_tree().physics_frame
	var cam: Camera3D = _rig.current_cameras()[0]
	var dist: float = cam.global_position.distance_to(_rig.tractor_ref_global())
	assert_almost_eq(dist, PHYSICS_CONSTANTS.FREE_ORBIT_RADIUS_M, 0.6, "orbit radius")


func test_cab_camera_sits_at_the_cab_eye() -> void:
	await _settle_and_drive(20)
	_rig.set_mode(CameraRig.Mode.CAB)
	for _i in 30:
		await get_tree().physics_frame
	var cam: Camera3D = _rig.current_cameras()[0]
	var eye: Vector3 = _rig.cab_eye_global()
	assert_lt(cam.global_position.distance_to(eye), 0.35, "camera at cab eye")


func test_cab_look_clamps_to_the_pinned_limits() -> void:
	_rig.set_mode(CameraRig.Mode.CAB)
	_rig.add_cab_look(500.0, 500.0)
	assert_almost_eq(
		_rig.cab_look_yaw_deg, PHYSICS_CONSTANTS.CAB_LOOK_YAW_LIMIT_DEG, 1e-6, "yaw clamped high"
	)
	assert_almost_eq(
		_rig.cab_look_pitch_deg,
		PHYSICS_CONSTANTS.CAB_LOOK_PITCH_MAX_DEG,
		1e-6,
		"pitch clamped high"
	)
	_rig.add_cab_look(-900.0, -900.0)
	assert_almost_eq(
		_rig.cab_look_yaw_deg, -PHYSICS_CONSTANTS.CAB_LOOK_YAW_LIMIT_DEG, 1e-6, "yaw clamped low"
	)
	assert_almost_eq(
		_rig.cab_look_pitch_deg, PHYSICS_CONSTANTS.CAB_LOOK_PITCH_MIN_DEG, 1e-6, "pitch clamped low"
	)


func test_each_mode_frames_its_intended_subject() -> void:
	## A camera that exists but frames nothing is not a camera mode. Assert the
	## subject point is inside each frustum rather than trusting a screenshot.
	await _settle_and_drive(40)
	for _i in 30:
		await get_tree().physics_frame
	_rig.set_mode(CameraRig.Mode.CHASE)
	await get_tree().physics_frame
	var chase: Camera3D = _rig.current_cameras()[0]
	assert_true(chase.is_position_in_frustum(_rig.tractor_ref_global()), "chase frames tractor ref")
	assert_true(chase.is_position_in_frustum(_rig.trailer_ref_global()), "chase frames trailer ref")

	_rig.set_mode(CameraRig.Mode.TRAILER)
	await get_tree().physics_frame
	var trailer_cam: Camera3D = _rig.current_cameras()[0]
	assert_true(
		trailer_cam.is_position_in_frustum(_rig.trailer_ref_global()),
		"trailer mode frames the trailer ref"
	)

	_rig.set_mode(CameraRig.Mode.FREE)
	await get_tree().physics_frame
	var free_cam: Camera3D = _rig.current_cameras()[0]
	assert_true(
		free_cam.is_position_in_frustum(_rig.tractor_ref_global()), "free mode frames tractor ref"
	)

	_rig.set_mode(CameraRig.Mode.CAB)
	await get_tree().physics_frame
	var cab_cam: Camera3D = _rig.current_cameras()[0]
	# Cab view is first person: the subject is the road ahead, not the tractor
	# body origin, which sits below and behind the eye point.
	var ahead: Vector3 = _rig.cab_eye_global() - Vector3(0.0, 0.4, 12.0)
	assert_true(cab_cam.is_position_in_frustum(ahead), "cab mode looks forward at the road")


# ---------------------------------------------------------------------------
# Mirror quads
# ---------------------------------------------------------------------------


func test_mirror_quads_use_the_subviewport_textures() -> void:
	var quads: Array[MeshInstance3D] = _rig.mirror_quads()
	assert_eq(quads.size(), 2, "two mirror quads")
	for quad in quads:
		var mat: StandardMaterial3D = quad.material_override as StandardMaterial3D
		assert_true(mat != null, "quad material")
		assert_true(mat.albedo_texture is ViewportTexture, "quad samples a SubViewport")
		# A ViewportTexture from SubViewport.get_texture() is bound by Rid rather
		# than by path, so identity is proven against the mirror viewports.
		var matches: bool = false
		for vp in _rig.mirror_viewports():
			if (vp as SubViewport).get_texture() == mat.albedo_texture:
				matches = true
		assert_true(matches, "quad samples a mirror viewport")
		assert_false(quad.visible, "quads hidden outside cab mode")
	_rig.set_mode(CameraRig.Mode.CAB)
	for quad in quads:
		assert_true(quad.visible, "quads visible in cab mode")


# ---------------------------------------------------------------------------
# Wiring to the pinned control map
# ---------------------------------------------------------------------------


func test_tab_press_cycles_the_rig_through_the_control_layer() -> void:
	## just_pressed only reads true across a frame boundary, so each press is
	## held for one physics tick and sampled the way smoke_controls.gd does.
	InputMapSetup.install()
	var layer: ControlLayer = ControlLayer.new(_harness.controller)
	_rig.connect_control_layer(layer)
	Input.action_press("camera_cycle")
	await get_tree().physics_frame
	layer.sample()
	assert_eq(_rig.mode, CameraRig.Mode.CAB, "Tab moved to CAB")
	Input.action_release("camera_cycle")
	await get_tree().physics_frame
	layer.sample()
	assert_eq(_rig.mode, CameraRig.Mode.CAB, "held release does not re-cycle")
	Input.action_press("camera_cycle")
	await get_tree().physics_frame
	layer.sample()
	Input.action_release("camera_cycle")
	assert_eq(_rig.mode, CameraRig.Mode.TRAILER, "second Tab moved to TRAILER")


func test_right_stick_jumps_to_free_instead_of_cycling() -> void:
	## Section 11 binds RS to "camera" and RB to "camera cycle", so RS must not
	## advance the cycle order.
	InputMapSetup.install()
	var layer: ControlLayer = ControlLayer.new(_harness.controller)
	_rig.connect_control_layer(layer)
	Input.action_press("gamepad_camera")
	await get_tree().physics_frame
	layer.sample()
	Input.action_release("gamepad_camera")
	assert_eq(_rig.mode, CameraRig.Mode.FREE, "RS jumps straight to FREE")
	Input.action_press("gamepad_camera_cycle")
	await get_tree().physics_frame
	layer.sample()
	Input.action_release("gamepad_camera_cycle")
	assert_eq(_rig.mode, CameraRig.Mode.CHASE, "RB cycles from FREE back to CHASE")
