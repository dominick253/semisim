extends GutTest
## S1 alley-reverse scenario pin (A9). Runs the scripted alley-reverse maneuver
## and asserts the measured result honestly.
##
## MEASURED FINDING (docs/DEVIATIONS.md D59): the drivetrain's reverse ratio is
## positive, so gear R with throttle drives the combination FORWARD, not
## backward. A literal alley backup cannot complete. This test encodes that
## honestly: it asserts the reverse was engaged from rest (the speed gate passed),
## that the back-down did NOT complete (the rig drives the wrong way instead),
## that no wall was contacted, that the alley straight-passage clears both walls,
## and that the run stayed in bounds.

const _SCENARIO: String = "res://tests/sim/scenario_s1_alley.gd"


func test_s1_alley_reverse_cannot_back_down_drivetrain_reverse_drives_forward() -> void:
	var sc: Node = load(_SCENARIO).new()
	add_child(sc)
	await get_tree().process_frame
	var r: Dictionary = await sc.run(sc)
	sc.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# The reverse speed gate engaged from rest (speed <= 0.5 m/s), first attempt.
	assert_true(r["reverse_engaged"], "reverse must engage from rest (speed gate)")
	assert_eq(r["reverse_reject"], "", "reverse must not be rejected from rest")
	assert_lt(
		r["pre_shift_speed_m_s"],
		PHYSICS_CONSTANTS.REVERSE_MAX_SPEED_M_S,
		"pre-shift speed below the reverse gate"
	)

	# Honest failure: the back-down did NOT complete; the drivetrain drives the
	# rig forward (positive delta_z) instead of backing it toward -15.
	assert_false(
		r["reverse_completed"],
		"the alley backup does not complete (drivetrain reverse drives forward, D59)"
	)
	assert_gt(
		r["delta_z_m"],
		0.0,
		"the rig moved forward (+Z) instead of backing toward -15 (drivetrain reverse sign)"
	)
	assert_almost_eq(
		r["peak_reverse_speed_m_s"], 0.0, 0.05, "no backward (reverse) speed was ever produced"
	)

	# No wall contact, strictly positive clearance on both walls (the alley
	# straight-passage fits), and the run stayed in bounds.
	assert_eq(r["wall_contacts"], 0, "no wall contact")
	assert_gt(r["min_clear_west_m"], 0.0, "clearance to the west wall strictly positive")
	assert_gt(r["min_clear_east_m"], 0.0, "clearance to the east wall strictly positive")
	assert_true(r["fits_8m"], "the measured sweep fits the pinned 8.0 m alley")
	assert_false(r["out_of_bounds"], "the run stayed in bounds")

	# The fitted-width read is consistent and the sweep is well below 8.0 m.
	assert_gt(r["swept_width_m"], 0.0, "swept width is positive")
	assert_lt(r["swept_width_m"], 8.0, "the swept width is far below the 8.0 m alley")
	assert_almost_eq(
		r["min_width_with_margin_m"],
		r["swept_width_m"] + 2.0 * r["fit_margin_m"],
		1e-3,
		"fitted width = swept width + 2 x stated margin"
	)
	assert_true(r["pass"], "scenario RESULT = PASS (measured, honest)")
