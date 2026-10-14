extends GutTest
## AS4l2 (D57): a gear change at speed must not over-rev the rigid driveline
## into the permanent 1900 rpm shutdown.
##
## Defect, measured in tests/scratch/downshift_probe.gd (loaded combination,
## 80 km/h, hard downshift to gear 1, throttle and brake closed):
##   - `engine_rpm` is the max of the vehicle-speed rpm and the wheel-rate rpm,
##     both through the current gear ratio (D51). Selecting gear 1 (ratio 4.834)
##     at 22.2222 m/s maps the 39.47 rad/s drive-axle rate to ~6,742 rpm, clamped
##     to the 1900 rpm shutdown on the first tick.
##   - The engine then stays dead for the rest of the run: `engine_rpm` remains
##     clamped at 1900, which is far above the 700 rpm idle floor the D54
##     restart rule requires, so `engine_running` never returns to true. A
##     downshift at speed is a permanent kill with no recovery.
##
## Fix (smallest honest rule, option 2 of the brief): refuse a gear change that
## would drive the engine past the pinned redline (1800) through the candidate
## ratio. The driveline is an always-rigid coupling in this model (D51, the rpm
## path in combination_controller.gd does not respect the clutch pedal), so a
## gear change that over-revs over-revs the engine regardless of the clutch
## state; refusing it at the shift point is what a real transmission / driver
## does for a shift that would instantly past-redline the engine. A downshift
## that stays inside the rev range is unaffected (see test 3). No pinned
## constant changed and none added: the guard compares against the pinned
## ENGINE_REDLINE_RPM using the pinned GEAR_RATIOS and TIRE_DRIVE table and the
## same DrivelineModel conversion the rpm coupling already uses.
##
## The ground half-extent in tests/sim/combination_rest_harness.gd was raised to
## 800 m (v_max x t = 22.2222 m/s x 30 s = 666.67 m, plus the 6.5 m steer-axle
## overhang) and an out_of_bounds() report added, so the 10 s run below is well
## inside the play area and a silent map departure is a visible failure.

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const SETTLE_TICKS: int = 240
const V0_OVERREV_M_S: float = 22.2222  # 80 km/h: gear 1 maps to ~6,742 rpm (over-rev)
const V0_LEGIT_M_S: float = 19.0  # 68.4 km/h: gear 4 maps to ~1,538 rpm (in range)
const RUN_TICKS: int = 10 * 120  # 10 s at the 120 Hz physics step

var _harness: Node


func before_each() -> void:
	_harness = load(HARNESS_SCENE).instantiate()
	add_child(_harness)
	# The loaded combination (CARGO_MASS_MAX_KG = 29,000 kg), re-seated at the
	# loaded rest heights so the static axle shares carry the full load.
	_harness.controller.apply_cargo(PHYSICS_CONSTANTS.CARGO_MASS_MAX_KG)
	_harness.controller.place_at_rest()
	await _harness.settle(SETTLE_TICKS)


func after_each() -> void:
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame


## Seed both bodies at speed v along the tractor heading.
func _seed_at(v: float) -> void:
	var c: Node = _harness.controller
	var heading: Vector3 = -c.tractor.global_basis.z
	c.tractor.linear_velocity = heading * v
	c.trailer.linear_velocity = heading * v


## Establish the pre-shift state: 80 km/h (or a lower speed) in the natural
## high gear (gear 5), manual mode so the auto transmission does not downshift
## the seeded rig mid-test.
func _drive_in_gear_5(v: float) -> void:
	var c: Node = _harness.controller
	c.transmission.automatic = false
	c.transmission.gear = 5
	_seed_at(v)
	await _harness.settle(8)


func test_hard_downshift_at_speed_keeps_engine_alive_and_on_ground() -> void:
	var c: Node = _harness.controller
	_drive_in_gear_5(V0_OVERREV_M_S)
	c.throttle = 0.0
	c.brake_pedal = 0.0
	# Driver depresses the clutch and hard-selects gear 1. The clutch is
	# satisfied, so the over-rev guard (not the no-clutch rule) is the active
	# refuser: through ratio 4.834 the 39.47 rad/s wheel rate is ~6,742 rpm.
	c.clutch_pedal = 1.0
	var accepted: bool = c.transmission.select_gear(1, c.speed(), c.clutch_pedal > 0.5)
	assert_false(
		accepted,
		(
			"an over-rev downshift to gear 1 at 80 km/h must be refused; pre-fix it "
			+ "over-revved to the 1900 rpm shutdown and the engine stayed dead"
		)
	)
	assert_eq(
		c.transmission.gear,
		5,
		"the refused over-rev shift must leave the rig in gear 5 (got %d)" % c.transmission.gear
	)
	# 10 s (well inside the 800 m ground half-extent): the engine must never
	# reach the 1900 rpm shutdown and must still be running at the end, and the
	# rig must stay on the ground at every sampled tick.
	var max_rpm: float = 0.0
	for i in RUN_TICKS:
		await get_tree().physics_frame
		max_rpm = maxf(max_rpm, c.engine_rpm)
		assert_false(
			_harness.out_of_bounds(),
			(
				"rig left the ground at tick %d (silent map departure, z=%.1f)"
				% [i, c.tractor.global_position.z]
			)
		)
	assert_lt(
		max_rpm,
		PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM,
		"engine_rpm reached the shutdown (%.0f rpm) after a downshift at speed" % max_rpm
	)
	assert_true(
		c.engine_running, "engine still dead 10 s after a downshift at speed (permanent kill)"
	)


func test_legitimate_downshift_inside_rev_range_still_works() -> void:
	var c: Node = _harness.controller
	# 68.4 km/h: gear 5 is the natural gear, and gear 4 maps the wheel rate to
	# ~1,538 rpm -- inside the rev range, so the over-rev guard must not
	# disable shifting.
	_drive_in_gear_5(V0_LEGIT_M_S)
	c.throttle = 0.0
	c.brake_pedal = 0.0
	c.clutch_pedal = 1.0
	var accepted: bool = c.transmission.select_gear(4, c.speed(), c.clutch_pedal > 0.5)
	assert_true(
		accepted,
		(
			"an in-rev-range downshift to gear 4 must be accepted (the fix must not "
			+ "disable shifting)"
		)
	)
	assert_eq(
		c.transmission.gear,
		4,
		"the accepted downshift must take effect (got gear %d)" % c.transmission.gear
	)
	await _harness.settle(8)
	assert_true(
		c.engine_running,
		"engine must stay alive after an in-rev-range downshift (rpm=%.0f)" % c.engine_rpm
	)
	assert_false(_harness.out_of_bounds(), "rig left the ground after the downshift")
