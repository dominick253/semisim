extends GutTest
## Task 23 part 1: the pinned camera geometry and the mode cycle (section 10).
##
## Asserts the pinned arm lengths, heights, pitch, damping, cab eye offset,
## mouse look limits, orbit radius and rate, mirror viewport size, the cycle
## order Chase -> Cab -> Trailer -> Free, and that exactly one camera is current
## at any time.

const CameraRig := preload("res://scripts/camera/camera_rig.gd")

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


# ---------------------------------------------------------------------------
# Pinned geometry
# ---------------------------------------------------------------------------


func test_chase_arm_is_14_m_behind_5_m_above_with_minus_45_pitch() -> void:
	assert_eq(PHYSICS_CONSTANTS.CHASE_ARM_LENGTH_M, 14.0, "arm length")
	assert_eq(PHYSICS_CONSTANTS.CHASE_HEIGHT_M, 5.0, "height above the ref")
	assert_almost_eq(
		deg_to_rad(PHYSICS_CONSTANTS.CHASE_PITCH_DEG), deg_to_rad(-45.0), 1e-9, "pitch"
	)
	assert_almost_eq(PHYSICS_CONSTANTS.CHASE_DAMPING_S, 0.25, 1e-9, "damping")


func test_trailer_spring_arm_is_12_m() -> void:
	assert_eq(PHYSICS_CONSTANTS.TRAILER_ARM_LENGTH_M, 12.0, "trailer arm")


func test_cab_eye_offset_is_the_pinned_cab_local_point() -> void:
	assert_eq(PHYSICS_CONSTANTS.CAB_EYE_LOCAL, Vector3(0.35, 1.15, -0.20), "cab eye")


func test_mouse_look_limits_are_pinned() -> void:
	assert_eq(PHYSICS_CONSTANTS.CAB_LOOK_YAW_LIMIT_DEG, 30.0, "yaw limit")
	assert_eq(PHYSICS_CONSTANTS.CAB_LOOK_PITCH_MIN_DEG, -10.0, "pitch min")
	assert_eq(PHYSICS_CONSTANTS.CAB_LOOK_PITCH_MAX_DEG, 20.0, "pitch max")


func test_free_orbit_radius_is_20_m() -> void:
	assert_eq(PHYSICS_CONSTANTS.FREE_ORBIT_RADIUS_M, 20.0, "orbit radius")


func test_mirror_viewports_are_480x270() -> void:
	assert_eq(PHYSICS_CONSTANTS.MIRROR_VIEWPORT_WIDTH, 480, "mirror width")
	assert_eq(PHYSICS_CONSTANTS.MIRROR_VIEWPORT_HEIGHT, 270, "mirror height")


func test_free_orbit_rate_and_stick_deadzone_are_pinned() -> void:
	## DEVIATIONS D32: the spec pins the radius but not the orbit rate.
	assert_eq(PHYSICS_CONSTANTS.FREE_ORBIT_RATE_RAD_S, 1.4, "orbit rate")
	var before: float = _rig.free_orbit_yaw_rad
	_rig.orbit_from_stick(0.05, 0.05, 1.0 / 60.0)
	assert_eq(_rig.free_orbit_yaw_rad, before, "inside the deadzone nothing moves")
	_rig.orbit_from_stick(1.0, 0.0, 1.0)
	assert_almost_eq(
		_rig.free_orbit_yaw_rad - before,
		PHYSICS_CONSTANTS.FREE_ORBIT_RATE_RAD_S,
		1e-6,
		"full stick is the pinned rate"
	)


# ---------------------------------------------------------------------------
# Cycle and mode exclusivity
# ---------------------------------------------------------------------------


func test_cycle_order_is_chase_cab_trailer_free() -> void:
	assert_eq(CameraRig.MODE_ORDER[0], CameraRig.Mode.CHASE, "first mode")
	assert_eq(CameraRig.MODE_ORDER[1], CameraRig.Mode.CAB, "second mode")
	assert_eq(CameraRig.MODE_ORDER[2], CameraRig.Mode.TRAILER, "third mode")
	assert_eq(CameraRig.MODE_ORDER[3], CameraRig.Mode.FREE, "fourth mode")
	assert_eq(CameraRig.MODE_ORDER.size(), 4, "exactly 4 modes")


func test_starts_in_chase() -> void:
	assert_eq(_rig.mode, CameraRig.Mode.CHASE, "start mode")
	assert_eq(_rig.mode_name(), "CHASE", "start name")


func test_cycle_steps_through_all_four_and_wraps() -> void:
	var seen: Array[String] = [_rig.mode_name()]
	for _i in 4:
		_rig.cycle()
		seen.append(_rig.mode_name())
	assert_eq(seen, ["CHASE", "CAB", "TRAILER", "FREE", "CHASE"], "cycle order")


func test_exactly_one_camera_is_current() -> void:
	for _i in 4:
		var current: Array[Camera3D] = _rig.current_cameras()
		assert_eq(current.size(), 1, "one current camera in %s" % _rig.mode_name())
		for c in current:
			assert_true(c.current, "flag set")
		_rig.cycle()


func test_mirrors_are_active_only_in_cab_mode() -> void:
	assert_eq(_rig.mirror_cameras().size(), 2, "two mirror cameras exist")
	for c in _rig.mirror_cameras():
		assert_false(c.current, "mirrors off in chase")
	_rig.set_mode(CameraRig.Mode.CAB)
	for c in _rig.mirror_cameras():
		assert_true(c.current, "mirrors on in cab")
	_rig.set_mode(CameraRig.Mode.TRAILER)
	for c in _rig.mirror_cameras():
		assert_false(c.current, "mirrors off again")


func test_mirror_subviewports_are_480x270_size_override() -> void:
	for vp in _rig.mirror_viewports():
		assert_eq(int(vp.size.x), PHYSICS_CONSTANTS.MIRROR_VIEWPORT_WIDTH, "w")
		assert_eq(int(vp.size.y), PHYSICS_CONSTANTS.MIRROR_VIEWPORT_HEIGHT, "h")
		assert_true(vp is SubViewport, "SubViewport")


func test_steering_wheel_rotation_uses_the_2p5_turn_ratio() -> void:
	## Full lock is 2.5 steering wheel turns from center (section 5.7), so the
	## wheel spin scales with the steer angle ratio.
	var max_steer: float = deg_to_rad(PHYSICS_CONSTANTS.STEER_MAX_ANGLE_DEG)
	var wheel_rad: float = CameraRig.steering_wheel_angle_rad(max_steer)
	assert_almost_eq(
		rad_to_deg(wheel_rad),
		PHYSICS_CONSTANTS.STEERING_WHEEL_TURNS * 360.0,
		0.01,
		"full lock is 2.5 turns"
	)
	assert_almost_eq(CameraRig.steering_wheel_angle_rad(0.0), 0.0, 1e-9, "centered")
	assert_almost_eq(
		CameraRig.steering_wheel_angle_rad(max_steer * 0.5),
		wheel_rad * 0.5,
		1e-6,
		"linear in steer angle"
	)


func test_camera_rig_has_no_rng() -> void:
	## Determinism rule (section 15): no RNG in physics-adjacent code.
	var src: String = FileAccess.get_file_as_string("res://scripts/camera/camera_rig.gd")
	assert_false(src.contains("randf"), "no randf")
	assert_false(src.contains("RandomNumberGenerator"), "no RNG object")
