extends GutTest
## AS4d: the drive axle must roll. Before the fix the controller integrated one
## scalar `wheel_omega_rad_s` from the contact torque imbalance, which is ~0
## every tick while the tyre grips (delivered force == torque demand), so the
## drive wheels never spun and the drive-wheel slip ratio read -1.0 (a
## locked-wheel value) at speed. The pinned fix sets `wheel_omega_rad_s` to the
## no-slip relation `v_forward_wheel / radius` while the tyre grips, keeps the
## integrator only when the friction ellipse saturates, and gives each axle its
## own visual spin rate scaled by its rolling radius.
##
## Written RED first: every assertion below fails on the pre-fix code
## (omega 0.000, slip -1.0, node spin 0.0 deg).

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const DRIVE_RADIUS: float = PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
const STEER_RADIUS: float = PHYSICS_CONSTANTS.TIRE_STEER["rolling_radius_m"]
const DT: float = 1.0 / float(PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
const SETTLE_TICKS: int = 120
# Enough full-throttle ticks to be well into a grip roll (not still wheel-spinning
# from launch) before measuring. 480 ticks = 4 s of full throttle.
const DRIVE_TICKS: int = 480
# Per-tick measurement windows. Measuring the local rotation in per-tick increments
# keeps every individual angle_to below 180 deg, so the accumulated rotation never
# wraps even if the total spin exceeds a half turn.
const MEASURE_TICKS: int = 48

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


func _drive_ticks(ticks: int, throttle: float, steer: float = 0.0) -> void:
	for _i in ticks:
		_c.throttle = throttle
		_c.steer_input_axis = steer
		_c.brake_pedal = 0.0
		await get_tree().physics_frame


func _wheel(role: String) -> WheelRig:
	for w in _c.wheels:
		if w.role == role:
			return w
	return null


func _drive_node() -> Node3D:
	return ModelPivots.find_pivot(_c.tractor, "WheelDriveL")


func _steer_node() -> Node3D:
	return ModelPivots.find_pivot(_c.tractor, "WheelSteerL")


## Tractor forward speed along its own heading (m/s).
func _drive_forward_speed() -> float:
	var fwd: Vector3 = -_c.tractor.global_basis.z
	return _c.tractor.linear_velocity.dot(fwd)


## Recompute the drive wheel's `v_forward_wheel` exactly the way `_step_wheel`
## does: the contact-patch velocity dotted with the wheel's (unsteered) heading.
func _drive_v_forward_wheel() -> float:
	var w: WheelRig = _wheel("drive")
	var body: RigidBody3D = _c.tractor
	var offset: Vector3 = w.contact_global - body.global_position
	var v_contact: Vector3 = body.linear_velocity + body.angular_velocity.cross(offset)
	v_contact.y = 0.0
	var fwd: Vector3 = -body.global_basis.z
	return v_contact.dot(fwd)


# ---------------------------------------------------------------------------


func test_steady_drive_matches_the_no_slip_relation() -> void:
	## While the tyre grips, omega must equal v_forward_wheel / radius (the
	## no-slip relation) and the drive-wheel slip ratio must read ~0, not the
	## locked -1.0 the pre-fix integrator pinned it at.
	_build_harness()
	await _harness.settle(SETTLE_TICKS)
	await _drive_ticks(DRIVE_TICKS, 1.0)
	var w: WheelRig = _wheel("drive")
	assert_true(w.grounded, "the drive wheel is on the ground")
	var v: float = _drive_v_forward_wheel()
	assert_gt(v, 1.0, "the combination is actually rolling: %.2f m/s" % v)
	assert_almost_eq(
		_c.wheel_omega_rad_s,
		v / DRIVE_RADIUS,
		0.05,
		"omega tracks v/r: %.3f vs %.3f rad/s" % [_c.wheel_omega_rad_s, v / DRIVE_RADIUS]
	)
	assert_lt(absf(w.slip_ratio), 0.05, "drive slip ~0 (not -1.0): %.4f" % w.slip_ratio)


func test_drive_wheel_rotation_matches_traveled_distance() -> void:
	## Visual proof the tyre rolls rather than slides: over a measured window,
	## the drive wheel node's accumulated local rotation (rad) times the drive
	## rolling radius must equal the distance the tractor travelled, within 2
	## percent.
	_build_harness()
	await _harness.settle(SETTLE_TICKS)
	await _drive_ticks(DRIVE_TICKS, 1.0)
	var node: Node3D = _drive_node()
	assert_true(node != null, "the drive wheel node resolves")
	var fwd: Vector3 = -_c.tractor.global_basis.z
	var q_prev: Quaternion = node.basis.get_rotation_quaternion()
	var pos_prev: Vector3 = _c.tractor.global_position
	var spin_total: float = 0.0
	var dist_total: float = 0.0
	for _i in MEASURE_TICKS:
		_c.throttle = 1.0
		_c.steer_input_axis = 0.0
		_c.brake_pedal = 0.0
		await get_tree().physics_frame
		var q_now: Quaternion = node.basis.get_rotation_quaternion()
		spin_total += q_prev.angle_to(q_now)
		q_prev = q_now
		var pos_now: Vector3 = _c.tractor.global_position
		dist_total += (pos_now - pos_prev).dot(fwd)
		pos_prev = pos_now
	assert_gt(dist_total, 0.2, "the tractor actually moved: %.3f m" % dist_total)
	assert_almost_eq(
		spin_total * DRIVE_RADIUS,
		dist_total,
		0.02 * dist_total,
		(
			"wheel roll == distance travelled: %.3f m vs %.3f m"
			% [spin_total * DRIVE_RADIUS, dist_total]
		)
	)


func test_steer_axle_spins_at_the_radius_ratio() -> void:
	## The steer tyres (0.554 m) are smaller than the drive tyres (0.563 m), so a
	## single shared spin rate under-spins them. With the combination rolling,
	## the steer wheel's accumulated rotation must exceed the drive wheel's by
	## drive_radius / steer_radius, within 1 percent.
	_build_harness()
	await _harness.settle(SETTLE_TICKS)
	await _drive_ticks(DRIVE_TICKS, 1.0)
	var d_node: Node3D = _drive_node()
	var s_node: Node3D = _steer_node()
	assert_true(d_node != null and s_node != null, "both wheel nodes resolve")
	var d_q_prev: Quaternion = d_node.basis.get_rotation_quaternion()
	var s_q_prev: Quaternion = s_node.basis.get_rotation_quaternion()
	var drive_spin: float = 0.0
	var steer_spin: float = 0.0
	for _i in MEASURE_TICKS:
		_c.throttle = 1.0
		_c.steer_input_axis = 0.0
		_c.brake_pedal = 0.0
		await get_tree().physics_frame
		var d_q_now: Quaternion = d_node.basis.get_rotation_quaternion()
		drive_spin += d_q_prev.angle_to(d_q_now)
		d_q_prev = d_q_now
		var s_q_now: Quaternion = s_node.basis.get_rotation_quaternion()
		steer_spin += s_q_prev.angle_to(s_q_now)
		s_q_prev = s_q_now
	assert_gt(drive_spin, 0.1, "the drive wheel actually spun: %.3f rad" % drive_spin)
	var ratio: float = steer_spin / drive_spin
	var expected: float = DRIVE_RADIUS / STEER_RADIUS
	assert_almost_eq(
		ratio, expected, 0.01 * expected, "steer/drive spin ratio %.4f vs %.4f" % [ratio, expected]
	)


func test_omega_stays_positive_and_falls_while_coasting() -> void:
	## With throttle 0 and brake 0 the drive wheel free-rolls: omega must stay
	## positive while the combination still moves forward, keep tracking v/r,
	## and fall toward 0 as the combination stops. The pre-fix integrator held
	## whatever was last set (0.0), so this pins the coasting behaviour.
	_build_harness()
	await _harness.settle(SETTLE_TICKS)
	await _drive_ticks(DRIVE_TICKS, 1.0)
	var omega_start: float = _c.wheel_omega_rad_s
	var v_start: float = _drive_forward_speed()
	assert_gt(v_start, 1.0, "the combination is moving before coast: %.2f m/s" % v_start)
	assert_gt(
		omega_start, 1.0, "the driveline was producing a real roll rate: %.2f rad/s" % omega_start
	)
	var min_omega: float = INF
	var samples: int = 0
	for _i in 240:
		_c.throttle = 0.0
		_c.brake_pedal = 0.0
		await get_tree().physics_frame
		var v: float = _drive_forward_speed()
		if v > 0.2:
			min_omega = minf(min_omega, _c.wheel_omega_rad_s)
			samples += 1
	assert_gt(samples, 20, "measured the coast while still moving: %d ticks" % samples)
	assert_gt(min_omega, 0.0, "omega stayed positive while moving forward: %.3f rad/s" % min_omega)
	assert_lt(
		_c.wheel_omega_rad_s,
		omega_start,
		(
			"omega fell as the combination stopped: %.3f < %.3f rad/s"
			% [_c.wheel_omega_rad_s, omega_start]
		)
	)
	assert_almost_eq(
		_c.wheel_omega_rad_s,
		_drive_forward_speed() / DRIVE_RADIUS,
		0.05,
		(
			"omega still tracks v/r while coasting: %.3f vs %.3f rad/s"
			% [_c.wheel_omega_rad_s, _drive_forward_speed() / DRIVE_RADIUS]
		)
	)
