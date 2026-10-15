extends GutTest
## S3 braking scenario pin (A9). phase1 prompt section 15 / section 19:
## "S3 braking: 80 km/h, full service brake plus retarder stage 5, stop
## distance 24..34 m. A9: S3 passes: stop distance 24..34 m from 80 km/h."
##
## The scenario (tests/sim/scenario_s3_braking.gd) measures the stop twice in
## one process: the PINNED scenario (loaded combination, CARGO_MASS_MAX_KG,
## manual gear 4 so the retarder is live, full service brake + retarder stage
## 5) and the naive automatic variant (D56: the auto gearbox holds gear 5 at
## 80 km/h, where the spec's own "gears 1-4" gate turns the retarder off, so the
## run is service-brake-only). Measured (925b871, standalone processes): pinned
## 28.96..28.98 m in ~391 ticks = 3.25 s (in the 24..34 m window with ~5 m of
## margin on each side), gear 4, retarder live at brake = true, no sustained
## wheel lock, out_of_bounds false, RESULT = PASS; naive auto 47.48 m, gear 5,
## retarder live at brake = false. The D56 default-cargo auto cross-check is
## 40.50 m (tests/unit/test_braking_distance.gd).
##
## Cross-process runs are not byte-identical (Jolt is not bit-deterministic,
## D58 family), so the distance is gated on the spec's own 24..34 m band, not a
## tight point value.

const _SCENARIO: String = "res://tests/sim/scenario_s3_braking.gd"


func test_s3_braking_script_is_fixed_data() -> void:
	## The per-step braking input is a fixed array of records (no RNG), so its
	## checksum is stable and non-trivial. Pure math, no physics. The scenario
	## instance is freed immediately so the test leaves no orphan node behind.
	var sc: Node = load(_SCENARIO).new()
	var a: int = sc.script_checksum()
	var b: int = sc.script_checksum()
	sc.free()
	assert_eq(a, b, "the S3 braking input script is fixed data and must checksum identically")
	assert_ne(a, 0, "the S3 braking input script checksum must be non-trivial")


func test_s3_braking_a9_stop_in_window() -> void:
	var sc: Node = load(_SCENARIO).new()
	add_child(sc)
	await get_tree().process_frame
	var r: Dictionary = await sc.run(sc)
	sc.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var p: Dictionary = r["pinned"]
	var a: Dictionary = r["auto"]
	print(
		(
			"S3 BRKING (A9): pinned stop=%.2f m (%d ticks, %.3f s) gear=%d retarder_live=%s "
			% [
				p["stop_distance_m"],
				p["stop_ticks"],
				p["stop_seconds"],
				p["gear_at_brake"],
				str(p["retarder_live_at_brake"]),
			]
		)
	)
	print(
		(
			"  auto (D56) stop=%.2f m gear=%d retarder_live=%s  peak_decel_pinned=%.3f m/s^2 "
			% [
				a["stop_distance_m"],
				a["gear_at_brake"],
				str(a["retarder_live_at_brake"]),
				p["peak_decel_m_s2"],
			]
		)
	)

	# The pinned scenario stops, within budget, and the stop is a real, finite
	# measured distance (not a runaway that hit the tick budget).
	assert_true(p["stopped_within_budget"], "the pinned scenario actually stopped")
	assert_gt(p["stop_ticks"], 0, "a positive number of stop ticks was measured")

	# A9: the stop distance is inside the spec's 24..34 m window.
	assert_between(
		p["stop_distance_m"],
		r["a9_min_m"],
		r["a9_max_m"],
		"A9: 80 km/h full brake + retarder must stop in 24-34 m; got %.2f m" % p["stop_distance_m"]
	)

	# The rig is at rest at the end (the D37 brake-hold rule keeps it there).
	assert_true(p["at_rest"], "the pinned scenario's rig is at rest at the end")

	# No sustained wheel lock (a real lock, not the ABS pulse) and in bounds.
	assert_false(p["wheel_locked_sustained"], "no sustained wheel lock during the stop")
	assert_false(p["out_of_bounds"], "the stop run stayed in bounds")

	# The D56 trap, reported not hidden: the pinned scenario holds gear 4 (the top
	# of the "gears 1-4" retarder window), so the retarder IS live at 80 km/h.
	assert_eq(p["gear_at_brake"], 4, "the pinned scenario holds the top retarder gear (4)")
	assert_true(p["retarder_live_at_brake"], "the retarder is live in gear 4 at 80 km/h (D56)")
	assert_eq(p["retarder_stage"], 5, "the retarder is commanded at stage 5")

	# The naive automatic variant is the D56 service-brake-only number: the auto
	# gearbox holds gear 5 at 80 km/h, where the spec's own gate turns the
	# retarder off, so it stops longer than the pinned (retarder-live) run.
	assert_eq(a["gear_at_brake"], 5, "the naive auto run holds gear 5 at 80 km/h (D56)")
	assert_false(a["retarder_live_at_brake"], "the retarder is gated off in gear 5 (D56)")
	assert_gt(
		a["stop_distance_m"],
		p["stop_distance_m"],
		"the naive auto (retarder off) stop is longer than the pinned (retarder live) stop"
	)

	# The scenario's own acceptance gate: A9.
	assert_true(r["pass"], "scenario RESULT = PASS (A9: stop distance 24..34 m from 80 km/h)")
