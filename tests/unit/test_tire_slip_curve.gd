extends GutTest
## AS4f: the saturated branch delivers the spec's longitudinal mu-slip curve
## instead of a flat adhesion cap, and ABS release runs every tick.
##
## Two measured defects (docs/evidence/phase1/wheel_surfaces.txt):
##   1. TireModel.longitudinal_force is spec-pinned but has no caller, so the
##      saturated branch caps delivered force at mu * normal_n (14,389 N on
##      ice), a constant with no slip dependence. Measured: the drive wheel
##      pins to the 200 rad/s omega clamp with slip +65.4483.
##   2. The ABS release check sits inside the saturated branch, but at rest the
##      engine-brake demand (375 N) is far below adhesion, so the wheel is in
##      the gripping branch and the release never runs: abs_engaged stays true
##      forever after an ice stop.
##
## These tests prove:
##   1. The pinned curve's peak sits at kappa = tan(pi / (2 * 1.40)) / Bx with
##      force peak mu*fz, and the curve is flat past its peak (~0.86-0.87 of
##      peak at kappa 1.0).
##   2. The saturated branch actually calls the curve: last_longitudinal_n
##      matches the curve within 2 percent. Fails on the flat cap.
##   3. (measurement) the ice launch still delivers ~82 percent of peak at the
##      observed settled slip, so the curve alone does NOT stop the runaway.
##   4. ABS releases once slip drops below ABS_RELEASE_SLIP after an ice stop.
##      Fails while the release check is trapped in the saturated branch.
##   5. Dry is unchanged: no ABS, slip stays under 0.05, speed 6.0-6.5 m/s.

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const SETTLE_TICKS: int = 240
const ICE_DRIVE_TICKS: int = 480
const ICE_SETTLE_EXTRA: int = 120
const BRAKE_TICKS: int = 720
# Max tick budget for the dry launch test. The brief says "360 ticks" (that is
# test_wheel_surfaces' LAUNCH_TICKS, which only needs v > 1.0 m/s). Reaching the
# AS4e measured dry speed of ~6.26 m/s actually takes ~1100 ticks (spin probe:
# 360 ticks -> 2.0 m/s, 1080 ticks -> 5.95 m/s, ~1200 ticks -> 6.26 m/s), so the
# test launches to a 6.0 m/s target within this budget.
const DRY_LAUNCH_TICKS: int = 1440

var _harness: Node


func _drive_wheel(c: Node) -> WheelRig:
	for w in c.wheels:
		if w.role == "drive":
			return w
	return null


func _swap_ground(surface: String) -> void:
	## Replace the harness ground with a tagged one (same 300 x 300 box, top at
	## y = 0). The meta goes on the StaticBody3D because intersect_ray's
	## `collider` key is the collision object. Add-then-free so the vehicle
	## never drops onto the new ground (would ring the suspension).
	var old: Node = _harness.get_node_or_null("Ground")
	var body := StaticBody3D.new()
	body.name = "GroundSwap"
	body.collision_layer = PHYSICS_CONSTANTS.LAYER_GROUND
	body.collision_mask = PHYSICS_CONSTANTS.LAYER_VEHICLE_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 2.0, 300.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	if surface != "":
		body.set_meta("surface", surface)
	_harness.add_child(body)
	await _harness.settle(3)
	if old != null:
		old.queue_free()
	await _harness.settle(3)


func _make_harness() -> Node:
	var h: Node = load(HARNESS_SCENE).instantiate()
	add_child(h)
	await h.settle(SETTLE_TICKS)
	return h


func _free_harness() -> void:
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
	_harness = null


func after_each() -> void:
	# Guaranteed cleanup: a test that errors before reaching _free_harness()
	# would otherwise leak its harness (and, for the ice tests, its tagged
	# ground) into the tree, where the next test's vehicle lands on the
	# leftover ground and reads the wrong surface.
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
	_harness = null


func _ice_drive_wheel() -> WheelRig:
	await _swap_ground("ice")
	await _harness.settle(180)
	return _drive_wheel(_harness.controller)


# --- 1. Pure math: the pinned curve's peak and flat top ---------------------


func test_longitudinal_force_peak_and_flat_top() -> void:
	var fz: float = 50000.0
	var mu: float = 1.0
	var cases: Array = [
		{"braking": false, "k_peak": 0.1730, "at_one": 0.8718},
		{"braking": true, "k_peak": 0.1483, "at_one": 0.8636},
	]
	for c in cases:
		var braking: bool = c.braking
		var bx: float = (
			PHYSICS_CONSTANTS.TIRE_BX_BRAKE if braking else PHYSICS_CONSTANTS.TIRE_BX_DRIVE
		)
		# Sample the curve on a fine grid and find its peak.
		var peak_force: float = 0.0
		var peak_kappa: float = 0.0
		var k: float = 0.0
		while k <= 0.5:
			var f: float = TireModel.longitudinal_force(k, fz, mu, braking)
			if f > peak_force:
				peak_force = f
				peak_kappa = k
			k += 0.0005
		var label: String = "brake(Bx=%.0f)" % bx if braking else "drive(Bx=%.0f)" % bx
		assert_almost_eq(
			peak_kappa,
			c.k_peak,
			0.001,
			(
				"%s: sampled peak kappa %.4f, want %.4f (+/- 0.001, grid step 0.0005)"
				% [label, peak_kappa, c.k_peak]
			)
		)
		assert_almost_eq(
			peak_force,
			mu * fz,
			0.005 * mu * fz,
			"%s: peak force %.1f N, want mu*fz %.1f N (+/- 0.5%%)" % [label, peak_force, mu * fz]
		)
		var at_one: float = TireModel.longitudinal_force(1.0, fz, mu, braking) / (mu * fz)
		assert_almost_eq(
			at_one,
			c.at_one,
			0.001,
			(
				"%s: curve at kappa 1.0 is %.4f of peak, want %.4f (+/- 0.001, flat past peak)"
				% [label, at_one, c.at_one]
			)
		)
		print(
			(
				"AS4f curve %s: peak_kappa=%.4f (want %.4f) peak_force=%.1f at1.0=%.4f"
				% [label, peak_kappa, c.k_peak, peak_force, at_one]
			)
		)


# --- 2. The curve is wired into the saturated branch ------------------------


func test_curve_is_wired_into_saturated_delivery() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = await _ice_drive_wheel()
	var c: Node = _harness.controller
	# Full throttle until the spin settles at the clamp.
	c.throttle = 1.0
	c.brake_pedal = 0.0
	for _i in ICE_DRIVE_TICKS + ICE_SETTLE_EXTRA:
		await get_tree().physics_frame
	# Same braking predicate the controller uses: the demand opposes the
	# wheel's direction of travel (demand * v_forward < 0).
	var v: float = c.tractor.linear_velocity.dot(-c.tractor.global_basis.z)
	var motion: float = 1.0 if v > PHYSICS_CONSTANTS.BRAKE_HOLD_SPEED_M_S else 0.0
	var radius: float = drive.rolling_radius()
	var demand: float = (
		(c._drive_wheel_torque() * 0.5 - float(c._brake_wheel_torques().get("drive", 0.0)) * motion)
		/ radius
	)
	var braking: bool = demand * v < 0.0
	var adhesion: float = drive.mu() * drive.normal_n
	assert_gt(
		absf(demand),
		adhesion,
		(
			"drive wheel not saturated at the settled state: |demand| %.0f N vs adhesion %.0f N"
			% [absf(demand), adhesion]
		)
	)
	var expected: float = TireModel.longitudinal_force(
		drive.slip_ratio, drive.normal_n, drive.mu(), braking
	)
	print(
		(
			"AS4f wiring: slip=%.4f omega=%.3f demand=%.0f adh=%.0f del=%.1f curve=%.1f"
			% [
				drive.slip_ratio,
				c.wheel_omega_rad_s,
				absf(demand),
				adhesion,
				drive.last_longitudinal_n,
				expected,
			]
		)
	)
	assert_true(
		absf(drive.last_longitudinal_n - expected) / maxf(absf(expected), 1.0) < 0.02,
		(
			"AS4f: last_longitudinal_n %.1f N does not match the curve %.1f N within 2%% (slip %.4f)"
			% [drive.last_longitudinal_n, expected, drive.slip_ratio]
		)
	)
	await _free_harness()


# --- 3. Measurement: the curve is flat past its peak ------------------------


func test_ice_launch_flat_top_ratio() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = await _ice_drive_wheel()
	var c: Node = _harness.controller
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var peak_delivered: float = 0.0
	var peak_omega: float = 0.0
	for _i in ICE_DRIVE_TICKS + ICE_SETTLE_EXTRA:
		await get_tree().physics_frame
		peak_delivered = maxf(peak_delivered, absf(drive.last_longitudinal_n))
		peak_omega = maxf(peak_omega, c.wheel_omega_rad_s)
	var adhesion: float = drive.mu() * drive.normal_n
	var settled_ratio: float = absf(drive.last_longitudinal_n) / maxf(adhesion, 1.0)
	print(
		(
			"AS4f flat top: pk_delivered=%.1f pk_omega=%.3f slip=%.4f ratio=%.4f"
			% [peak_delivered, peak_omega, drive.slip_ratio, settled_ratio]
		)
	)
	# The spin still pins to the omega clamp: the curve alone does not stop the
	# runaway (AS4g). It stays ~82 percent of peak at the observed slip, so
	# assert it did not collapse to a small value rather than forcing a target.
	# The controller clamps wheel_omega_rad_s to +/- 200.0 (hardcoded in
	# combination_controller.gd); there is no pinned constant for it.
	assert_true(
		peak_omega > 200.0 - 1.0,
		(
			"AS4f: peak omega %.3f rad/s, expected to pin to the 200.0 clamp (runaway is AS4g)"
			% peak_omega
		)
	)
	assert_true(
		settled_ratio > 0.80,
		(
			(
				"AS4f: settled delivered/peak %.4f, expected ~0.82 (flat past peak); the curve alone "
				+ "does not self-limit the spin"
			)
			% settled_ratio
		)
	)
	await _free_harness()


# --- 4. ABS release runs every tick -----------------------------------------


func test_abs_releases_after_ice_stop() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = await _ice_drive_wheel()
	var c: Node = _harness.controller
	# Phase 1: full drive (the saturation probe's drive phase plus settle);
	# track the first tick ABS engages.
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var engage_tick: int = -1
	var drive_ticks: int = ICE_DRIVE_TICKS + ICE_SETTLE_EXTRA
	for i in drive_ticks:
		await get_tree().physics_frame
		if drive.abs_engaged and engage_tick < 0:
			engage_tick = i
	assert_true(engage_tick >= 0, "AS4f: ABS never engaged during the ice launch")
	# Phase 2: cut throttle, hold the brake until the wheel regrips.
	c.throttle = 0.0
	c.brake_pedal = 1.0
	var release_tick: int = -1
	for i in BRAKE_TICKS:
		await get_tree().physics_frame
		if (not drive.abs_engaged) and absf(drive.slip_ratio) < PHYSICS_CONSTANTS.ABS_RELEASE_SLIP:
			release_tick = i
			break
	var total: int = (drive_ticks - engage_tick) + release_tick
	print(
		(
			"AS4f abs: engage tick %d, release %d into brake; e->r %d, slip=%.4f abs=%s"
			% [engage_tick, release_tick, total, drive.slip_ratio, str(drive.abs_engaged)]
		)
	)
	assert_true(
		release_tick >= 0,
		(
			"AS4f: abs_engaged stayed latched after the ice stop (slip %.4f, abs %s)"
			% [drive.slip_ratio, str(drive.abs_engaged)]
		)
	)
	await _free_harness()


# --- 5. Dry regression -------------------------------------------------------


func test_dry_launch_regression_unchanged() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = _drive_wheel(_harness.controller)
	var c: Node = _harness.controller
	# Full throttle until the combination reaches the AS4e dry speed (~6.2 m/s),
	# within a tick budget. A fixed 360-tick budget (test_wheel_surfaces'
	# LAUNCH_TICKS, which only needs v > 1.0 m/s) reaches only ~2.4 m/s; the
	# AS4e measured 6.26 m/s needs ~1100 ticks. Launching to a speed target
	# keeps the 6.0-6.5 assertion robust to tick-timing drift.
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var abs_seen: bool = false
	var max_slip: float = 0.0
	var tick: int = 0
	while tick < DRY_LAUNCH_TICKS and c.speed() < 6.0:
		await get_tree().physics_frame
		tick += 1
		if drive.abs_engaged:
			abs_seen = true
		max_slip = maxf(max_slip, absf(drive.slip_ratio))
	print(
		(
			"AS4f dry: v_final=%.2f m/s ticks=%d max|slip|=%.4f abs_seen=%s"
			% [c.speed(), tick, max_slip, str(abs_seen)]
		)
	)
	assert_false(abs_seen, "AS4f dry: abs_engaged became true (peak slip %.4f)" % max_slip)
	assert_false(drive.abs_engaged, "AS4f dry: drive wheel abs_engaged still true at end")
	assert_lt(max_slip, 0.05, "AS4f dry: slip left the no-slip line, max |slip| %.4f" % max_slip)
	assert_between(c.speed(), 6.0, 6.5, "AS4f dry: launch speed %.2f m/s, want 6.0-6.5" % c.speed())
	await _free_harness()
