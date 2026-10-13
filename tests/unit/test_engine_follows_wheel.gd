extends GutTest
## AS4g: the engine is dragged by the spinning wheel, so wheel spin-up is bounded.
##
## Measured defect (pre-fix, tests/scratch/wheel_saturation_probe.gd, ice, 4 s full
## throttle then brake pinned, t=0.0 brake-start):
##
##   SAT t=0.0 speed=1.61 omega=200.000 v_over_r=2.854 slip=+69.0761 abs=true
##         adhesion_n=14394 demand_n=21314
##
## `engine_rpm` was derived from vehicle speed only (combination_controller.gd:
## `engine_rpm = _engine_rpm(drive_speed)` -> the gear-ratio path), so while the
## drive tyre is saturated and the wheel spins far faster than the body moves, the
## engine still delivers torque at the vehicle-speed rpm and the wheel runs to the
## 200 rad/s integrator clamp.
##
## The clutch is engaged (automatic path), so the driveline rigidly couples engine
## and wheel: the engine runs at whichever side spins faster. The fix makes
## engine_rpm the maximum of the vehicle-speed rpm and the wheel-speed rpm (same
## idle/shutdown clamps), so the engine follows the wheel. No new clamp, damping or
## fudge factor; no PHYSICS_CONSTANTS value changes; the gripping branch and the
## AS4f curve are untouched.
##
## Measured behaviour (post-fix, derived with a probe, not hand-computed):
##   * The one-tick-lag startup transient spikes the low-inertia wheel to ~22.9
##     rad/s on the FIRST drive tick (the engine reads the previous tick's wheel
##     speed, so tick 1 applies full idle torque and the wheel jumps ~23 rad/s
##     before the engine can react). The engine then reads omega 22.9 -> 1900 rpm
##     and shuts down on tick 2, so the wheel decays back to ~0.
##   * On ice the vehicle sits at ~0.03-0.07 m/s (idle rpm) for the whole launch,
##     so the 1900 rpm SHUTDOWN is the binding bound, not a torque-curve
##     equilibrium at the gear-1 shutdown-implied 11.12 rad/s.
##   * Dry is byte-identical to AS4f: the wheel is never faster than the road, so
##     engine_rpm == the vehicle-speed rpm and the spin probe is unchanged.
##
## These tests prove:
##   1. On ice, full throttle from rest: the drive omega never reaches the 200
##      rad/s clamp, the sustained spin is at or below 1.25 x the shutdown-implied
##      bound (computed from the ratio at the settled tick), and the engine tracked
##      the wheel up to the 1900 rpm shutdown. Fails pre-fix (omega 200.000, engine
##      stuck at the vehicle rpm).
##   2. engine_rpm exceeds the vehicle-speed rpm while the wheel is spinning.
##   3. Torque collapse: the wheel drove the engine past its torque-peak rpm, where
##      the curve has fallen off, so the drive-axle torque at that rpm is below the
##      peak. Fails pre-fix (the engine never leaves the vehicle/idle rpm).
##   4. Dry regression: a 360-tick full-throttle launch keeps abs_engaged false,
##      |slip| < 0.05, and engine_rpm equal to the vehicle-speed rpm, so the dry
##      path is provably untouched.
##   5. No new allocation in the engine step: the added lines construct no String,
##      Array or Dictionary per tick (guarded against the source directly).
##
## AS4h additions (the redline fuel cut): the torque curve is flat from the 1800
## redline to the 1900 shutdown, so without a cut the redline has no mechanical
## effect. _drive_wheel_torque now returns 0.0 when throttle > 0.0 and
## engine_rpm >= ENGINE_REDLINE_RPM. No new constant, no hysteresis (the cut
## re-arms the tick rpm falls back below the redline); the closed-throttle
## engine-brake branch is untouched.
##   6. Dry 1200-tick full-throttle launch: engine_rpm never reaches the redline
##      (peak 1551.6 rpm, capped by the 1550 upshift), so the cut is a no-op and
##      the launch matches the AS4g numbers within 0.3 percent (v 6.839 m/s,
##      omega 12.142 rad/s, gear 2).
##   7. Gradual spin-up on dry in locked gear 1 from 5.27 m/s (1600 rpm): the
##      wheel drags the engine into the redline band and the cut pins it in a
##      1800-1802 rpm limit cycle (measured max 1802), the engine never reaches
##      the 1900 shutdown, and the combination keeps pulling (5.93 m/s at 6 s).
##      Counterfactual (cut disabled): the engine dies on tick 150 and the
##      combination coasts to 3.59 m/s. This is the regime the cut exists for.
##   8. Engine braking is untouched: at 1900 rpm with throttle 0.0 the torque is
##      still the negative engine-brake torque (measured -6725 Nm, not 0.0); the
##      cut only fires under throttle (1850 rpm at full throttle: 0.0; 1799 rpm
##      at full throttle: +26,942 Nm).
##
## Measured and unchanged by AS4h (tests 1-3): the one-tick ice startup transient
## still jumps 700 -> 1900 rpm in a single tick, through the whole redline window
## the cut sits in, so the from-rest ice launch still shuts the engine down on
## tick 2 (reported in the re-pointed tests in test_tire_slip_curve.gd and
## test_wheel_surfaces.gd; see docs/evidence/phase1/engine_wheel_speed.txt).

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const CONTROLLER_SRC: String = "res://scripts/vehicles/combination_controller.gd"
const SETTLE_TICKS: int = 240
const ICE_DRIVE_TICKS: int = 480
## The settled window for the sustained-spin bound: the last N ticks of the drive
## (the one-tick startup transient is excluded from the sustained peak).
const SETTLED_WINDOW: int = 240
const DRY_LAUNCH_TICKS: int = 360
const DRY_LAUNCH_1200_TICKS: int = 1200
const GRADUAL_SPIN_TICKS: int = 720
## 1600 rpm no-slip in gear 1 (5.27 / 0.563 * 4.834 * 3.70 * 9.5493), 200 rpm
## below the redline, so the gradual rise crosses the 1800-1900 band.
const GRADUAL_START_SPEED_M_S: float = 5.27

var _harness: Node


func _drive_wheel(c: Node) -> WheelRig:
	for w in c.wheels:
		if w.role == "drive":
			return w
	return null


func _swap_ground(surface: String) -> void:
	## Replace the harness ground with a tagged one (same 300 x 300 box, top at
	## y = 0). The meta goes on the StaticBody3D because intersect_ray's `collider`
	## key is the collision object. Add-then-free so the vehicle never drops onto
	## the new ground (would ring the suspension).
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
	# ground) into the tree, where the next test's vehicle lands on the leftover
	# ground and reads the wrong surface.
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
	_harness = null


func _ice_drive_wheel() -> WheelRig:
	await _swap_ground("ice")
	await _harness.settle(180)
	return _drive_wheel(_harness.controller)


## The wheel rate (rad/s) the driveline cannot push the engine past before the
## 1900 rpm shutdown, for a given total driveline ratio: shutdown rpm is
## shutdown_rpm * 2*pi/60 rad/s of crank, divided by the total ratio.
func _shutdown_bound(ratio: float) -> float:
	return (
		(PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM * 2.0 * PI / 60.0)
		/ (ratio * PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO)
	)


## The engine torque curve's peak control point: {rpm, torque}. The curve is
## piecewise linear over ENGINE_TORQUE_CURVE; the peak is the max-torque point.
func _peak_torque_point() -> Dictionary:
	var curve: Array = PHYSICS_CONSTANTS.ENGINE_TORQUE_CURVE
	var best_rpm: float = curve[0][0]
	var best_nm: float = curve[0][1]
	for p in curve:
		if p[1] > best_nm:
			best_nm = p[1]
			best_rpm = p[0]
	return {"rpm": best_rpm, "torque": best_nm}


## The drive-axle torque (Nm) the engine would deliver at `rpm` at full throttle
## with the clutch engaged: the curve value through the driveline, mirroring
## _drive_wheel_torque (no governor, no clutch release in these tests).
func _drive_torque_at_rpm(c: Node, rpm: float) -> float:
	var engagement: float = 1.0 - c._clutch_engagement()
	return (
		TireModel.engine_torque_nm(rpm)
		* c.transmission.ratio()
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
		* engagement
	)


# --- 1. Ice: the spin is bounded, not pinned at the 200 rad/s clamp -----------


func test_ice_launch_omega_bounded_by_shutdown() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = await _ice_drive_wheel()
	var c: Node = _harness.controller
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var peak_omega: float = 0.0
	var peak_slip: float = 0.0
	var peak_gear: int = c.transmission.gear
	var peak_ratio: float = c.transmission.ratio()
	var max_engine_rpm: float = 0.0
	var settled_omega: float = 0.0
	var settled_ratio: float = c.transmission.ratio()
	for i in ICE_DRIVE_TICKS:
		await get_tree().physics_frame
		var omega: float = c.wheel_omega_rad_s
		if omega > peak_omega:
			peak_omega = omega
			peak_slip = drive.slip_ratio
			peak_gear = c.transmission.gear
			peak_ratio = c.transmission.ratio()
		max_engine_rpm = maxf(max_engine_rpm, c.engine_rpm)
		if i >= ICE_DRIVE_TICKS - SETTLED_WINDOW:
			settled_omega = maxf(settled_omega, omega)
			settled_ratio = c.transmission.ratio()
	var bound: float = _shutdown_bound(peak_ratio)
	var settled_bound: float = _shutdown_bound(settled_ratio)
	print(
		(
			(
				"AS4g ice: peak_omega=%.3f (clamp=200) peak_slip=%+.4f gear=%d ratio=%.3f "
				+ "bound=%.3f; settled_omega=%.3f settled_bound=%.3f (1.25x=%.3f); max_engine_rpm=%.0f"
			)
			% [
				peak_omega,
				peak_slip,
				peak_gear,
				peak_ratio,
				bound,
				settled_omega,
				settled_bound,
				1.25 * settled_bound,
				max_engine_rpm,
			]
		)
	)
	# The core fix: the wheel no longer runs to (or pins at) the 200 rad/s clamp.
	# Pre-fix the sustained omega is 200.000; post-fix it is a ~22.9 single-tick
	# transient that decays to ~0.
	assert_lt(
		peak_omega,
		200.0,
		(
			"AS4g: drive omega %.3f reached the 200 rad/s integrator clamp (spin not bounded)"
			% peak_omega
		)
	)
	# The sustained spin (the one-tick startup transient excluded) is at or below
	# 1.25 x the shutdown-implied bound for the gear at the settled tick. This is
	# the physical bound the fix provides: the engine follows the wheel and shuts
	# down before the wheel can keep spinning.
	assert_lt(
		settled_omega,
		1.25 * settled_bound,
		(
			"AS4g: sustained omega %.3f exceeds 1.25 x shutdown bound %.3f (gear %d ratio %.3f)"
			% [settled_omega, 1.25 * settled_bound, c.transmission.gear, settled_ratio]
		)
	)
	# The engine tracked the wheel up to the shutdown, which is what stops the
	# sustained spin. Pre-fix the engine sat at the vehicle (idle) rpm.
	assert_gte(
		max_engine_rpm,
		PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM,
		(
			"AS4g: engine_rpm never reached the %.0f rpm shutdown (max %.0f); wheel not following engine"
			% [PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM, max_engine_rpm]
		)
	)
	await _free_harness()


# --- 2. Engine rpm follows the wheel above the vehicle-speed rpm --------------


func test_engine_rpm_exceeds_vehicle_rpm_while_spinning() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = await _ice_drive_wheel()
	var c: Node = _harness.controller
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var max_delta: float = 0.0
	var sample_engine_rpm: float = 0.0
	var sample_vehicle_rpm: float = 0.0
	var sample_omega: float = 0.0
	for _i in ICE_DRIVE_TICKS:
		await get_tree().physics_frame
		var vehicle_rpm: float = c._engine_rpm(c._drive_forward_speed())
		var delta: float = c.engine_rpm - vehicle_rpm
		if delta > max_delta:
			max_delta = delta
			sample_engine_rpm = c.engine_rpm
			sample_vehicle_rpm = vehicle_rpm
			sample_omega = c.wheel_omega_rad_s
	print(
		(
			"AS4g rpm: max(engine-vehicle)=%.1f rpm at engine=%.0f vehicle=%.0f omega=%.3f"
			% [max_delta, sample_engine_rpm, sample_vehicle_rpm, sample_omega]
		)
	)
	assert_gt(
		max_delta,
		0.0,
		(
			"AS4g: engine_rpm never exceeded vehicle rpm while spinning (max delta %.1f rpm)"
			% max_delta
		)
	)
	await _free_harness()


# --- 3. Torque collapse: the wheel drives the engine past the torque peak ------


func test_torque_collapses_past_peak() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = await _ice_drive_wheel()
	var c: Node = _harness.controller
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var max_engine_rpm: float = 0.0
	var ratio_at_max_rpm: float = c.transmission.ratio()
	for _i in ICE_DRIVE_TICKS:
		await get_tree().physics_frame
		if c.engine_rpm > max_engine_rpm:
			max_engine_rpm = c.engine_rpm
			ratio_at_max_rpm = c.transmission.ratio()
	var peak: Dictionary = _peak_torque_point()
	var peak_rpm: float = peak.rpm
	var peak_nm: float = peak.torque
	# The drive-axle torque the engine would deliver at the peak-torque rpm versus
	# at the rpm the wheel actually drove it to. Both at the same ratio, so this
	# isolates the curve fall-off.
	var torque_at_peak_rpm: float = (
		TireModel.engine_torque_nm(peak_rpm)
		* ratio_at_max_rpm
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
	)
	var torque_at_max_rpm: float = (
		TireModel.engine_torque_nm(max_engine_rpm)
		* ratio_at_max_rpm
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
	)
	print(
		(
			"AS4g torque: max_rpm=%.0f (peak=%.0f) tq@max=%.0f tq@peak=%.0f ratio=%.3f"
			% [max_engine_rpm, peak_rpm, torque_at_max_rpm, torque_at_peak_rpm, ratio_at_max_rpm]
		)
	)
	# The wheel must actually drag the engine past the torque-peak rpm for there to
	# be any collapse. Pre-fix the engine sits at the vehicle (idle) rpm, never
	# past the peak, so this fails.
	assert_gt(
		max_engine_rpm,
		peak_rpm,
		(
			"AS4g: wheel never drove engine past torque peak (max %.0f <= %.0f)"
			% [max_engine_rpm, peak_rpm]
		)
	)
	# Past the peak the curve falls off, so the drive-axle torque available at the
	# wheel-driven rpm is below the peak. This is the torque fall-off that (with the
	# shutdown) bounds the spin.
	assert_lt(
		torque_at_max_rpm,
		torque_at_peak_rpm,
		(
			"AS4g: drive torque at wheel-driven rpm %.0f (%.0f Nm) not below peak-rpm torque %.0f Nm"
			% [max_engine_rpm, torque_at_max_rpm, torque_at_peak_rpm]
		)
	)
	await _free_harness()


# --- 4. Dry regression: the untouched dry path --------------------------------


func test_dry_launch_regression_untouched() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = _drive_wheel(_harness.controller)
	var c: Node = _harness.controller
	var radius: float = PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var abs_seen: bool = false
	var max_slip: float = 0.0
	var max_rpm_delta: float = 0.0
	var max_overspeed: float = 0.0
	for _i in DRY_LAUNCH_TICKS:
		await get_tree().physics_frame
		if drive.abs_engaged:
			abs_seen = true
		max_slip = maxf(max_slip, absf(drive.slip_ratio))
		max_rpm_delta = maxf(
			max_rpm_delta, absf(c.engine_rpm - c._engine_rpm(c._drive_forward_speed()))
		)
		# Wheel surface speed minus the road (body forward) speed: on dry the wheel
		# sits on the no-slip line, so this is ~0. A real overspin makes it large.
		max_overspeed = maxf(max_overspeed, c.wheel_omega_rad_s * radius - c._drive_forward_speed())
	print(
		(
			(
				"AS4g dry: v_final=%.2f m/s ticks=%d max|slip|=%.4f abs_seen=%s "
				+ "max_overspeed=%.4f m/s max|engine-vehicle_rpm|=%.2f rpm (one-tick artifact)"
			)
			% [c.speed(), DRY_LAUNCH_TICKS, max_slip, str(abs_seen), max_overspeed, max_rpm_delta]
		)
	)
	assert_false(abs_seen, "AS4g dry: abs_engaged became true (peak slip %.4f)" % max_slip)
	assert_false(drive.abs_engaged, "AS4g dry: drive wheel abs_engaged still true at end")
	assert_lt(max_slip, 0.05, "AS4g dry: slip left the no-slip line, max |slip| %.4f" % max_slip)
	# On dry the wheel is never faster than the road (no slip), so the max() in
	# engine_rpm is a no-op and engine_rpm is the vehicle-speed rpm: the dry path
	# is untouched. The wheel-overspeed is the direct physical measure of that
	# ("the wheel is never faster than the road on dry").
	assert_lt(
		max_overspeed,
		0.05,
		(
			"AS4g dry: the wheel ran faster than the road (max overspeed %.4f m/s); the dry path moved"
			% max_overspeed
		)
	)
	# The max_rpm_delta is a one-tick velocity-advance artifact: engine_rpm is set
	# mid-tick from the pre-integration speed, while the re-read of
	# _drive_forward_speed() is post-integration (one tick of speed advance ~2 rpm
	# at launch end). It is reported, not asserted, so a legitimate dry-path change
	# (the wheel genuinely outrunning the road) is caught by max_overspeed above.
	await _free_harness()


# --- 5. No new allocation in the engine step ----------------------------------


func test_engine_step_has_no_new_allocation() -> void:
	## The added rpm path must not construct a String, Array or Dictionary per
	## tick. Guard the source of the wheel-rpm helper and the engine_rpm
	## assignment directly so a future edit that reintroduces a per-tick
	## allocation (a % format, a String, an Array or a Dictionary literal, a
	## .new()) is caught.
	assert_true(
		FileAccess.file_exists(CONTROLLER_SRC), "AS4g: combination_controller.gd source missing"
	)
	var text: String = FileAccess.get_file_as_string(CONTROLLER_SRC)
	var helper: String = _extract_func(text, "_engine_rpm_from_wheel_rate")
	assert_true(
		helper != "", "AS4g: _engine_rpm_from_wheel_rate helper not found in the controller"
	)
	for bad in [
		"new(", "String", "Dictionary", "PackedStringArray", "Array[", " = [", " = {", "% "
	]:
		assert_false(
			helper.contains(bad),
			"AS4g: the wheel-rpm helper allocates (%s found in:\n%s)" % [bad, helper.strip_edges()]
		)
	# The engine_rpm assignment must be a pure maxf() of the two rpm sources.
	var assign_line: String = _extract_engine_rpm_assignment(text)
	assert_true(
		assign_line != "" and assign_line.contains("maxf"),
		"AS4g: engine_rpm is not assigned as a maxf() of the vehicle- and wheel-speed rpm"
	)
	for bad in ["new(", "String", "Dictionary", "% "]:
		assert_false(
			assign_line.contains(bad),
			(
				"AS4g: the engine_rpm assignment allocates (%s in: %s)"
				% [bad, assign_line.strip_edges()]
			)
		)


# --- 6. AS4h: the redline fuel cut is a no-op on the dry launch --------------


func test_limiter_dry_launch_is_a_noop() -> void:
	_harness = await _make_harness()
	var c: Node = _harness.controller
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var max_rpm: float = 0.0
	var rpm_at_max: int = 0
	for i in DRY_LAUNCH_1200_TICKS:
		await get_tree().physics_frame
		if c.engine_rpm > max_rpm:
			max_rpm = c.engine_rpm
			rpm_at_max = i + 1
	var v_final: float = c.speed()
	var omega_final: float = c.wheel_omega_rad_s
	print(
		(
			(
				"AS4h dry 1200: max_rpm=%.1f (tick %d) v_final=%.3f m/s omega_final=%.3f "
				+ "gear=%d redline=%.0f"
			)
			% [
				max_rpm,
				rpm_at_max,
				v_final,
				omega_final,
				c.transmission.gear,
				PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM,
			]
		)
	)
	# The cut gate is `engine_rpm >= 1800`. On dry the wheel never outruns the
	# road, so engine_rpm is the vehicle-speed rpm, and the 1550 rpm automatic
	# upshift caps it well below the redline (measured peak 1551.6, the tick the
	# upshift fires). The gate never opens, so this launch is byte-identical to
	# the AS4g launch: the reference numbers below are the AS4g numbers (the
	# counterfactual run with the cut disabled is byte-identical; see
	# docs/evidence/phase1/engine_wheel_speed.txt).
	assert_lt(
		max_rpm,
		PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM,
		(
			(
				"AS4h dry: engine_rpm reached the %.0f redline (peak %.1f at tick %d); the cut is no "
				+ "longer a no-op on dry"
			)
			% [PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM, max_rpm, rpm_at_max]
		)
	)
	# Measured end state (240-tick settle, 1200-tick launch, stable across runs):
	# v 6.839 m/s, omega 12.142 rad/s, gear 2, rpm 1226. 0.3 percent tolerance.
	assert_almost_eq(
		v_final,
		6.839,
		0.021,
		"AS4h dry: v_final %.4f m/s is not the AS4g 6.839 within 0.3 percent" % v_final
	)
	assert_almost_eq(
		omega_final,
		12.142,
		0.037,
		"AS4h dry: omega_final %.4f rad/s is not the AS4g 12.142 within 0.3 percent" % omega_final
	)
	await _free_harness()


# --- 7. AS4h: the cut pins the redline on a gradual rpm rise -----------------


func test_limiter_pins_redline_on_gradual_spin() -> void:
	_harness = await _make_harness()
	var c: Node = _harness.controller
	# Locked gear 1 on dry from 5.27 m/s: the no-slip engine rpm is
	# 5.27 / 0.563 * 4.834 * 3.70 * 9.5493 = 1600 rpm, 200 rpm below the
	# redline. Under full throttle in locked gear 1 (automatic off) the vehicle
	# speed itself carries the engine up through the redline band: 5.93 m/s is
	# 1800 rpm in gear 1. Without the cut the flat 1800-1900 curve lets the rpm
	# run on to the 1900 shutdown; with the cut the fuel cut at 1800 pins the
	# rpm in a limit cycle and the vehicle holds just above 5.93 m/s.
	c.transmission.automatic = false
	c.transmission.gear = 1
	var v0: float = GRADUAL_START_SPEED_M_S
	c.tractor.linear_velocity = Vector3(0.0, 0.0, -v0)
	c.trailer.linear_velocity = Vector3(0.0, 0.0, -v0)
	c.wheel_omega_rad_s = v0 / PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var max_rpm: float = 0.0
	var shutdown_tick: int = -1
	var v_final: float = 0.0
	for i in GRADUAL_SPIN_TICKS:
		await get_tree().physics_frame
		if c.engine_rpm > max_rpm:
			max_rpm = c.engine_rpm
		if not c.engine_running and shutdown_tick < 0:
			shutdown_tick = i + 1
		if (i + 1) % 120 == 0:
			print(
				(
					"AS4h gradual t=%.1f rpm=%.0f speed=%.3f run=%s"
					% [float(i + 1) / 120.0, c.engine_rpm, c.speed(), str(c.engine_running)]
				)
			)
		v_final = c.speed()
	print(
		(
			(
				"AS4h gradual: max_rpm=%.1f shutdown_tick=%d v_final=%.3f m/s (counterfactual with the "
				+ "cut disabled: shutdown at tick 150, max_rpm 1900, v_final 3.592 m/s)"
			)
			% [max_rpm, shutdown_tick, v_final]
		)
	)
	# The engine must actually reach the redline band: the cut has to engage.
	assert_gte(
		max_rpm,
		PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM,
		(
			"AS4h gradual: engine_rpm never reached the redline (max %.0f); the cut never engaged"
			% max_rpm
		)
	)
	# And it must never reach the 1900 shutdown: the cut is what keeps the
	# engine alive in the band (measured max 1802).
	assert_lt(
		max_rpm,
		PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM,
		(
			"AS4h gradual: engine_rpm reached the %.0f shutdown (max %.0f); the cut did not hold"
			% [PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM, max_rpm]
		)
	)
	assert_eq(shutdown_tick, -1, "AS4h gradual: engine shut down at tick %d" % shutdown_tick)
	# The combination keeps pulling instead of coasting (measured 5.932; the
	# counterfactual coasts to 3.592).
	assert_gt(
		v_final,
		5.0,
		(
			"AS4h gradual: the combination is not still pulling (v_final %.3f m/s, measured 5.932)"
			% v_final
		)
	)
	await _free_harness()


# --- 8. AS4h: closed-throttle engine braking is untouched -------------------


func test_engine_braking_not_cut_above_redline() -> void:
	_harness = await _make_harness()
	# The ice ground per the brief (same _swap_ground helper): the unit gate is
	# state-only, but the ground swap keeps the harness in the settled ice
	# state, where the rest state is identical to dry.
	await _ice_drive_wheel()
	var c: Node = _harness.controller
	var ratio1: float = c.transmission.ratio()
	# Throttle closed above the redline: the drive torque must still be the
	# negative engine-brake torque (the retarding torque that slows the
	# combination), not 0.0. The cut gate is `throttle > 0.0 and rpm >= 1800`,
	# so at throttle 0.0 it never fires.
	c.throttle = 0.0
	c.brake_pedal = 0.0
	c.engine_rpm = 1900.0
	var brake_torque: float = c._drive_wheel_torque()
	var expected_brake: float = (
		-TireModel.engine_brake_torque_nm(1900.0)
		* ratio1
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
	)
	# Under throttle the cut fires at and above the redline...
	c.engine_rpm = 1850.0
	c.throttle = 1.0
	var cut_torque: float = c._drive_wheel_torque()
	# ...and just below the redline the full curve torque is still delivered.
	c.engine_rpm = 1799.0
	var below_torque: float = c._drive_wheel_torque()
	var expected_below: float = (
		TireModel.engine_torque_nm(1799.0)
		* ratio1
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
	)
	print(
		(
			(
				"AS4h engine brake: tq@1900 rpm throttle 0 = %.1f Nm (expected %.1f); "
				+ "tq@1850 rpm full throttle = %.1f Nm (cut); tq@1799 rpm full throttle = %.1f Nm "
				+ "(expected %.1f)"
			)
			% [brake_torque, expected_brake, cut_torque, below_torque, expected_below]
		)
	)
	assert_lt(
		brake_torque,
		0.0,
		(
			(
				"AS4h: engine braking was cut above the redline (tq %.1f Nm at 1900 rpm throttle 0, "
				+ "expected the negative engine-brake torque)"
			)
			% [brake_torque]
		)
	)
	assert_almost_eq(
		brake_torque,
		expected_brake,
		1.0,
		(
			"AS4h: brake torque %.1f Nm is not the spec engine-brake torque %.1f Nm at 1900 rpm"
			% [brake_torque, expected_brake]
		)
	)
	assert_eq(
		cut_torque,
		0.0,
		"AS4h: torque at 1850 rpm full throttle is %.1f Nm, expected 0.0 (the cut)" % cut_torque
	)
	assert_gt(
		below_torque,
		0.0,
		(
			"AS4h: torque at 1799 rpm full throttle is %.1f Nm, expected the positive curve torque"
			% below_torque
		)
	)
	assert_almost_eq(
		below_torque,
		expected_below,
		1.0,
		(
			"AS4h: torque just below the redline %.1f Nm is not the curve value %.1f Nm"
			% [below_torque, expected_below]
		)
	)
	await _free_harness()


func _extract_func(src: String, name: String) -> String:
	var start: int = src.find("func %s(" % name)
	if start < 0:
		return ""
	var end: int = src.find("\nfunc ", start + 1)
	if end < 0:
		return src.substr(start)
	return src.substr(start, end - start)


func _extract_engine_rpm_assignment(src: String) -> String:
	for line in src.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("engine_rpm = maxf"):
			return t
	return ""
