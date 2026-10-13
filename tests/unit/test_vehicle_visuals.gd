extends GutTest
## AS4b: the placeholder box visuals are replaced by the imported GLBs, parented
## under the physics bodies, and the eight wheel visuals spin and steer from the
## GLB nodes instead of the placeholder nodes.
##
## Written RED first. Once the GLBs are parented under the bodies but before
## _update_wheel_visuals() is re-pointed at them, the steer and spin assertions
## fail: the controller still resolves the wheels with get_node_or_null, which
## returns null for the now-nested GLB nodes, so nothing spins or steers. The
## geometry assertions (presence, no placeholders, anchor) pass as soon as the
## swap lands, so the red tests are exactly the two the controller change fixes.

const TRACTOR_SCENE: String = "res://scenes/vehicles/tractor.tscn"
const TRAILER_SCENE: String = "res://scenes/vehicles/trailer.tscn"
const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

# Pinned tractor steer-axle anchor (DEVIATIONS D48): |x| 1.10, y 0.554, z -6.500.
const STEER_ANCHOR_LOCAL: Vector3 = Vector3(1.10, 0.554, -6.500)
const ANCHOR_TOL: float = 0.001
const SPIN_WINDOW_TICKS: int = 12
# Phase B measures the drive wheel's spin over this window and compares it against
# the integral of the controller's own wheel_omega_rad_s. The spin now comes from
# driving (AS4d fixed the integrator so the driveline produces a real roll rate
# from the no-slip relation instead of leaving it at 0.000); per-tick measurement
# keeps the accumulated rotation below 180 deg so it never wraps.
const SPIN_TOL_RAD: float = 0.15
# Extra straight-drive ticks Phase B runs before measuring, so the driveline is
# well into a roll (speed and omega comfortably above the no-slip floor).
const SPIN_DRIVE_TICKS: int = 240
# Steer node rotation.y must track the applied steer angle this closely, and the
# steer angle must actually have engaged so the comparison is not 0 == 0.
const STEER_TRACK_TOL: float = 0.001
const STEER_ENGAGE_MIN_RAD: float = 0.0873  # 5 degrees
# Ticks to let the steer ramp engage under throttle + steering.
const STEER_TICKS: int = 120

var _harness: Node = null
var _c: Node3D = null


func _build_harness() -> void:
	_harness = load(HARNESS_SCENE).instantiate()
	add_child(_harness)
	_c = _harness.controller


func after_each() -> void:
	if is_instance_valid(_harness):
		_harness.queue_free()
		_harness = null
		_c = null
		await get_tree().physics_frame
		await get_tree().physics_frame


func _has_descendant_named(root: Node, name: String) -> bool:
	return root.find_child(name, true, false) != null


func _resolve_wheel(body: Node3D, name: String) -> Node3D:
	return ModelPivots.find_pivot(body, name)


# ---------------------------------------------------------------------------


func test_tractor_scene_instantiates_the_glb_and_drops_the_placeholders() -> void:
	var scene: Node = load(TRACTOR_SCENE).instantiate()
	add_child(scene)
	assert_true(_has_descendant_named(scene, "cab_eye"), "tractor GLB carries the cab_eye empty")
	assert_true(_has_descendant_named(scene, "kingpin"), "tractor GLB carries the kingpin empty")
	assert_true(
		_has_descendant_named(scene, "fifth_plate"), "tractor GLB carries the fifth_plate empty"
	)
	assert_false(_has_descendant_named(scene, "BodyVisual"), "placeholder BodyVisual is deleted")
	scene.queue_free()
	await get_tree().physics_frame


func test_trailer_scene_instantiates_the_glb_and_drops_the_placeholders() -> void:
	var scene: Node = load(TRAILER_SCENE).instantiate()
	add_child(scene)
	assert_true(
		_has_descendant_named(scene, "trailer_ref"), "trailer GLB carries the trailer_ref empty"
	)
	assert_true(
		_has_descendant_named(scene, "landing_contact"),
		"trailer GLB carries the landing_contact empty"
	)
	assert_false(_has_descendant_named(scene, "VanVisual"), "placeholder VanVisual is deleted")
	scene.queue_free()
	await get_tree().physics_frame


func test_steer_wheel_resolves_to_a_mesh_at_the_pinned_anchor() -> void:
	_build_harness()
	await _harness.settle(60)
	var wheel: Node3D = _resolve_wheel(_c.tractor, "WheelSteerL")
	assert_true(wheel != null, "the steer wheel node resolves through the model")
	assert_true(wheel is MeshInstance3D, "the GLB steer wheel is a MeshInstance3D")
	# Un-apply the body transform so the comparison is in the body frame: the
	# resolved wheel's local position must be the pinned steer anchor.
	var local: Vector3 = _c.tractor.to_local(wheel.global_position)
	assert_almost_eq(absf(local.x), STEER_ANCHOR_LOCAL.x, ANCHOR_TOL, "steer anchor |x| = 1.10")
	assert_almost_eq(local.y, STEER_ANCHOR_LOCAL.y, ANCHOR_TOL, "steer anchor y = 0.554")
	assert_almost_eq(local.z, STEER_ANCHOR_LOCAL.z, ANCHOR_TOL, "steer anchor z = -6.500")


func test_steering_and_spin_drive_the_glb_wheels() -> void:
	_build_harness()
	await _harness.settle(120)
	# Phase A: drive with throttle and steering (the brief's drive) so the steer
	# ramp engages. The steer node's rotation.y must track the applied angle.
	_c.throttle = 1.0
	_c.steer_input_axis = 1.0
	await _harness.settle(STEER_TICKS)
	var steer: Node3D = _resolve_wheel(_c.tractor, "WheelSteerL")
	assert_true(steer != null and steer is MeshInstance3D, "the steer wheel node resolves")
	assert_gt(
		_c.steer_angle_rad,
		STEER_ENGAGE_MIN_RAD,
		"steering actually engaged: %.1f deg" % rad_to_deg(_c.steer_angle_rad)
	)
	assert_almost_eq(
		steer.rotation.y,
		_c.steer_angle_rad,
		STEER_TRACK_TOL,
		"steer node rotation.y tracks the applied steer angle"
	)
	# Phase B: the drive wheel spins from driving, not from an injected rate.
	# Phase A already asserted the steer tracking; here the combination keeps
	# driving straight so the driveline is in a solid roll, and the drive wheel
	# must accumulate LOCAL rotation equal to the integral of the controller's own
	# wheel_omega_rad_s (the no-slip rate the driveline now produces, AS4d).
	# Per-tick measurement keeps the accumulated rotation below 180 deg. Local,
	# not global: the combination is still yawing, and a global reading would
	# change from body motion alone.
	_c.throttle = 1.0
	_c.steer_input_axis = 0.0
	_c.brake_pedal = 0.0
	await _harness.settle(SPIN_DRIVE_TICKS)
	var drive: Node3D = _resolve_wheel(_c.tractor, "WheelDriveL")
	assert_true(drive != null and drive is MeshInstance3D, "the drive wheel node resolves")
	var q_prev: Quaternion = drive.basis.get_rotation_quaternion()
	var spin_delta: float = 0.0
	var omega_integral: float = 0.0
	for _i in SPIN_WINDOW_TICKS:
		await get_tree().physics_frame
		var q_now: Quaternion = drive.basis.get_rotation_quaternion()
		spin_delta += q_prev.angle_to(q_now)
		q_prev = q_now
		omega_integral += _c.wheel_omega_rad_s * (1.0 / 120.0)
	assert_gt(spin_delta, 0.1, "the drive wheel spun from driving: %.4f rad" % spin_delta)
	assert_almost_eq(
		spin_delta,
		omega_integral,
		SPIN_TOL_RAD,
		(
			"drive wheel spins from driving: %.4f rad vs %.4f rad integral"
			% [spin_delta, omega_integral]
		)
	)
