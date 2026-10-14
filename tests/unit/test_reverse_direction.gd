extends GutTest
## AS4o (D59): gear R must drive the combination BACKWARD, against its heading.
##
## Measured defect (docs/DEVIATIONS.md D59, pre-fix): Transmission.ratio_for(-1)
## returns the pinned REVERSE_RATIO = 8.315 positive and the drive-axle torque
## is applied with no sign flip, so gear R with throttle drives the
## combination FORWARD along its heading. Measured in the S1 alley scenario at
## HEAD: delta_z +11.82 m out through the +45 gate, peak backward speed 0.0022
## m/s, peak forward 3.3893 m/s.
##
## These tests pin the direction contract (RED pre-fix, GREEN post-fix):
##   1. The pinned magnitude is untouched: ratio_for(-1) is still 8.315
##      (the fix sign-flips the torque, it does not negate the constant).
##   2. Gear R with throttle: the drive-wheel torque opposes the heading
##      (negative), so the contact-patch demand pushes backward.
##   3. Engine braking in gear R opposes the direction of travel: with the
##      throttle closed and the combination rolling backward, the drive
##      torque is along +heading (positive), slowing the backup.
##   4. A short scripted run from rest at heading 180 deg (forward = +Z):
##      the drive-wheel angular rate is negative, the velocity along the
##      heading is negative, and tractor.global_position.z decreases -- the
##      rig actually travels backward. engine_rpm stays inside the
##      idle..shutdown band and the engine never dies.
##   5. The reverse speed gate is untouched: R is refused above 0.5 m/s and
##      accepted below.

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const THROTTLE: float = 0.3
const SETTLE_TICKS: int = 240
const RUN_TICKS: int = 360  # 3 s at 120 Hz
## The backward displacement the 3 s run must produce (a real backup, not a
## creep toward zero).
const BACKUP_DECREASE_M: float = 0.5

var _harness: Node


func _make_harness(heading_deg: float) -> Node:
	var h: Node = load(HARNESS_SCENE).instantiate()
	add_child(h)
	await h.settle(30)
	var c: Node = h.controller
	c.global_position = Vector3.ZERO
	c.rotation = Vector3(0.0, deg_to_rad(heading_deg), 0.0)
	c.place_at_rest()
	await h.settle(SETTLE_TICKS)
	return h


func _engage_reverse(c: Node) -> String:
	c.request_gear(-1)
	return c.transmission.last_reject_reason


func after_each() -> void:
	# Guaranteed cleanup (same pattern as test_engine_follows_wheel.gd).
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
	_harness = null


# --- 1. The pinned magnitude is untouched -----------------------------------


func test_reverse_ratio_magnitude_stays_pinned() -> void:
	var t: Transmission = Transmission.new()
	assert_almost_eq(
		t.ratio_for(-1),
		PHYSICS_CONSTANTS.REVERSE_RATIO,
		1e-9,
		"ratio_for(-1) keeps the pinned 8.315 magnitude (spec 5.3)"
	)
	assert_gt(t.ratio_for(-1), 0.0, "the constant stays positive; the sign lives in the torque")


# --- 2. Drive torque with throttle opposes the heading ----------------------


func test_gear_r_drive_torque_opposes_heading() -> void:
	_harness = await _make_harness(180.0)
	var c: Node = _harness.controller
	var reject: String = _engage_reverse(c)
	assert_eq(c.transmission.gear, -1, "reverse engaged from rest")
	assert_eq(reject, "", "no reject reason")
	c.throttle = THROTTLE
	var torque: float = c._drive_wheel_torque()
	print("AS4o torque: gear R throttle %.1f -> _drive_wheel_torque = %.1f Nm" % [THROTTLE, torque])
	assert_lt(
		torque,
		0.0,
		"gear R with throttle: the drive-wheel torque must oppose the heading (negative)"
	)


# --- 3. Engine braking in reverse opposes the travel direction --------------


func test_gear_r_engine_braking_opposes_backward_travel() -> void:
	_harness = await _make_harness(180.0)
	var c: Node = _harness.controller
	_engage_reverse(c)
	c.throttle = 0.0
	# Rolling backward at 1 m/s: the rigid driveline (D51) maps the wheel rate
	# through the reverse ratio; below the idle-crossover speed the clamp holds
	# the engine at the idle floor, where the brake torque is the pinned 120 Nm.
	c.wheel_omega_rad_s = -(1.0 / PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"])
	c.engine_rpm = DrivelineModel.engine_rpm_from_wheel_rate(
		c.wheel_omega_rad_s, c.transmission.ratio()
	)
	var torque: float = c._drive_wheel_torque()
	var expected_magnitude: float = (
		TireModel.engine_brake_torque_nm(c.engine_rpm)
		* PHYSICS_CONSTANTS.REVERSE_RATIO
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
	)
	print(
		(
			(
				"AS4o engine brake: gear R, 1 m/s backward, rpm=%.0f -> torque = %.1f Nm "
				+ "(magnitude %.1f)"
			)
			% [c.engine_rpm, torque, expected_magnitude]
		)
	)
	assert_almost_eq(
		absf(torque),
		expected_magnitude,
		1.0,
		"the brake magnitude is the curve value through the driveline"
	)
	assert_gt(
		torque,
		0.0,
		"engine braking in gear R must push along +heading, opposing the backward travel"
	)


# --- 4. The real backward run ------------------------------------------------


func test_gear_r_from_rest_backs_up() -> void:
	_harness = await _make_harness(180.0)  # heading +Z: backward is -Z
	var c: Node = _harness.controller
	var reject: String = _engage_reverse(c)
	assert_eq(c.transmission.gear, -1, "reverse engaged from rest")
	assert_eq(reject, "", "no reject reason")
	var start_z: float = c.tractor.global_position.z
	c.throttle = THROTTLE
	c.brake_pedal = 0.0
	var max_vdot: float = 0.0
	var min_vdot: float = 0.0
	var min_rpm: float = INF
	var max_rpm: float = 0.0
	var ever_dead: bool = false
	for _i in RUN_TICKS:
		await get_tree().physics_frame
		var fwd: Vector3 = -c.tractor.global_basis.z
		var vdot: float = c.tractor.linear_velocity.dot(fwd)
		max_vdot = maxf(max_vdot, vdot)
		min_vdot = minf(min_vdot, vdot)
		min_rpm = minf(min_rpm, c.engine_rpm)
		max_rpm = maxf(max_rpm, c.engine_rpm)
		if not c.engine_running:
			ever_dead = true
	var end_z: float = c.tractor.global_position.z
	var delta_z: float = end_z - start_z
	var end_vdot: float = c.tractor.linear_velocity.dot(-c.tractor.global_basis.z)
	print(
		(
			(
				"AS4o run: %d ticks -> delta_z=%+.4f m (%.4f -> %.4f) end vdot=%+.4f m/s "
				+ "max forward vdot=%+.4f peak backward vdot=%+.4f omega=%+.4f rpm=%.0f..%.0f dead=%s"
			)
			% [
				RUN_TICKS,
				delta_z,
				start_z,
				end_z,
				end_vdot,
				max_vdot,
				min_vdot,
				c.wheel_omega_rad_s,
				min_rpm,
				max_rpm,
				str(ever_dead),
			]
		)
	)
	assert_lt(
		delta_z,
		-BACKUP_DECREASE_M,
		"the rig actually travels backward: z decreases by >= %.1f m" % BACKUP_DECREASE_M
	)
	assert_lt(end_vdot, 0.0, "velocity along the heading is negative (backward) at the end")
	assert_lt(c.wheel_omega_rad_s, 0.0, "the drive-wheel angular rate is negative (reverse spin)")
	assert_lt(max_vdot, 0.1, "no meaningful forward velocity at any tick")
	assert_gte(
		min_rpm,
		PHYSICS_CONSTANTS.ENGINE_IDLE_RPM,
		"engine rpm never below the idle floor while rolling backward"
	)
	assert_lte(
		max_rpm,
		PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM,
		"engine rpm never trips the 1900 rpm shutdown while rolling backward"
	)
	assert_false(ever_dead, "the engine stays alive the whole backward run")


# --- 5. The reverse speed gate is untouched ----------------------------------


func test_reverse_speed_gate_still_refuses_above_half_m_s() -> void:
	var t: Transmission = Transmission.new()
	t.reset()
	t.gear = 1
	t.automatic = false
	var accepted: bool = t.select_gear(-1, 1.0, true)
	assert_false(accepted, "R refused at 1.0 m/s (above REVERSE_MAX_SPEED_M_S)")
	assert_eq(t.gear, 1, "the gear is unchanged by the refusal")
	assert_eq(t.last_reject_reason, NoopRules.REASON_REVERSE_SPEED, "the pinned reason string")
	var ok: bool = t.select_gear(-1, 0.4, true)
	assert_true(ok, "R accepted at 0.4 m/s (below the gate)")
	assert_eq(t.gear, -1, "the gear is R")
