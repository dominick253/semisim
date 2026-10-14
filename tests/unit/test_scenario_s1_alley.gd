extends GutTest
## S1 alley-reverse scenario pin (A9). AS4o re-point: with the drivetrain
## reverse-direction fix (D59, gear R sign-flips the drive-wheel torque in
## combination_controller.gd) this test asserts the REAL maneuver instead of the
## old honest infeasibility: a completed backup down the 8.0 m alley.
##
## Measured (b95f299 + fix, standalone): delta_z -11.818 m over 900 ticks, peak
## reverse speed 3.3885 m/s, swept width 2.5935 m, min clearance west 2.7043 m /
## east 2.7022 m, wall contacts 0, trailer end-of-pass z 19.43..35.58 (inside the
## -15..+45 alley), out_of_bounds false, RESULT = PASS. The swept width from this
## real backup is the number docs/world-spec.md section 4 needs for the minimum
## street width: ~2.59 m (body-width dominated, straight pass, zero steer).

const _SCENARIO: String = "res://tests/sim/scenario_s1_alley.gd"


func test_s1_alley_reverse_completes_the_backup() -> void:
	var sc: Node = load(_SCENARIO).new()
	add_child(sc)
	await get_tree().process_frame
	var r: Dictionary = await sc.run(sc)
	sc.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print(
		(
			(
				"S1 ALLEY (AS4o re-point): delta_z=%+.3f m peak_reverse=%.4f m/s swept_width=%.4f m "
				+ "clear_w=%.4f clear_e=%.4f contacts=%d trailer_in_alley=%s oob=%s"
			)
			% [
				r["delta_z_m"],
				r["peak_reverse_speed_m_s"],
				r["swept_width_m"],
				r["min_clear_west_m"],
				r["min_clear_east_m"],
				r["wall_contacts"],
				str(r["trailer_in_alley"]),
				str(r["out_of_bounds"]),
			]
		)
	)

	# The reverse speed gate engaged from rest (speed <= 0.5 m/s), first attempt.
	assert_true(r["reverse_engaged"], "reverse must engage from rest (speed gate)")
	assert_eq(r["reverse_reject"], "", "reverse must not be rejected from rest")
	assert_lt(
		r["pre_shift_speed_m_s"],
		PHYSICS_CONSTANTS.REVERSE_MAX_SPEED_M_S,
		"pre-shift speed below the reverse gate"
	)

	# The real backup: the rig backs down the alley past the 1.0 m target and
	# the trailer ends inside the alley.
	assert_true(r["reverse_completed"], "the backup completes: delta_z <= -1.0 m in 900 ticks")
	assert_lt(r["delta_z_m"], -1.0, "the drive axle backed down the alley (negative delta_z)")
	assert_gt(r["peak_reverse_speed_m_s"], 0.5, "a real reverse speed was measured")
	assert_lt(r["peak_forward_speed_m_s"], 0.1, "the rig never drives forward")
	assert_true(
		r["trailer_in_alley"],
		"the trailer ends inside the alley (z and x box corners within the pinned walls)"
	)

	# No wall contact, strictly positive clearance on both walls (the alley
	# straight-passage fits), and the run stayed in bounds.
	assert_eq(r["wall_contacts"], 0, "no wall contact during the backup pass")
	assert_gt(r["min_clear_west_m"], 0.0, "clearance to the west wall strictly positive")
	assert_gt(r["min_clear_east_m"], 0.0, "clearance to the east wall strictly positive")
	assert_true(r["fits_8m"], "the measured sweep fits the pinned 8.0 m alley")
	assert_false(r["out_of_bounds"], "the run stayed in bounds")

	# The swept width from the real backup: body-width dominated (~2.59 m
	# trailer), far below the 8.0 m alley. Pinned against the measured value with
	# a 2 percent band (cross-process runs drift at the third significant digit).
	assert_almost_eq(r["swept_width_m"], 2.59, 0.05, "swept width is the measured ~2.59 m")
	assert_lt(r["swept_width_m"], 8.0, "the swept width is far below the 8.0 m alley")
	assert_almost_eq(
		r["min_width_with_margin_m"],
		r["swept_width_m"] + 2.0 * r["fit_margin_m"],
		1e-3,
		"fitted width = swept width + 2 x stated margin"
	)
	assert_true(r["pass"], "scenario RESULT = PASS (measured, real backup)")
