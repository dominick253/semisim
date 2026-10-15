extends GutTest
## S1 alley-reverse scenario pin (A12). AS4p re-point: the scenario now runs
## the pinned acceptance definition (phase1 prompt sections 7/9/15/19):
## spawn at the pinned alley challenge spawn (SPAWN_ALLEY_POS /
## SPAWN_ALLEY_HEADING_DEG, read from PHYSICS_CONSTANTS), reverse the full
## 67 m drive-axle crossing from z = -22.0 to the north gate line
## z = ALLEY_MAX_Z (+45.0) -- the 60 m alley plus the 7 m approach from the
## spawn to its open south end -- and RESULT = PASS gates on: gate line
## crossed, simulated crossing time under 120 s, 0 wall contacts, strictly
## positive clearance on both walls, in bounds.
##
## Measured (5231bd5 + re-point): gate line crossed at tick 2820 = 23.500 s
## (limit 120 s) in every process -- the longitudinal motion is stable: drive
## axle -22.00 -> +45.00 (67.00 m, ~+0.003 m past the line), peak reverse
## 3.4520 m/s. The lateral sweep varies by process (Jolt cross-process
## variance, D58 family): swept width 2.5960..3.0424 m across six runs
## (fresh GUT, three standalone, two full-suite GUT), east clearance measured
## 2.5940..2.7003 m in the five runs whose sweep was <= 2.825 m, and ~2.27 m
## in the widest-sweep run (derived: the west-side min x -37.31 m is stable
## across all six processes) -- hence the percentage-style band, not a tight
## pin. Wall contacts 0 (hence 0 strikes, D19 proxy), out_of_bounds false,
## RESULT = PASS in every run.

const _SCENARIO: String = "res://tests/sim/scenario_s1_alley.gd"


func test_s1_alley_reverse_a12_full_crossing() -> void:
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
				"S1 ALLEY (A12 re-point): crossed=%s tick=%d time=%.3f s (limit %.0f s) "
				+ "distance=%.3f m gap=%+.3f m peak_reverse=%.4f m/s"
			)
			% [
				str(r["gate_crossed"]),
				r["crossing_tick"],
				r["crossing_time_s"],
				r["a12_limit_s"],
				r["distance_travelled_m"],
				r["drive_gate_gap_m"],
				r["peak_reverse_speed_m_s"],
			]
		)
	)
	print(
		(
			(
				"  swept_width=%.4f m clear_w=%.4f clear_e=%.4f contacts=%d "
				+ "trailer_z=%.3f..%.3f oob=%s"
			)
			% [
				r["swept_width_m"],
				r["min_clear_west_m"],
				r["min_clear_east_m"],
				r["wall_contacts"],
				r["trailer_min_z_m"],
				r["trailer_max_z_m"],
				str(r["out_of_bounds"]),
			]
		)
	)

	# Spawn: the pinned alley challenge spawn, not a restated literal.
	assert_eq(
		r["spawn_pos"], PHYSICS_CONSTANTS.SPAWN_ALLEY_POS, "spawns at the pinned SPAWN_ALLEY_POS"
	)
	assert_eq(
		r["spawn_heading_deg"],
		PHYSICS_CONSTANTS.SPAWN_ALLEY_HEADING_DEG,
		"spawns at the pinned SPAWN_ALLEY_HEADING_DEG"
	)

	# The reverse speed gate engaged from rest (speed <= 0.5 m/s), first attempt.
	assert_true(r["reverse_engaged"], "reverse must engage from rest (speed gate)")
	assert_eq(r["reverse_reject"], "", "reverse must not be rejected from rest")
	assert_lt(
		r["pre_shift_speed_m_s"],
		PHYSICS_CONSTANTS.REVERSE_MAX_SPEED_M_S,
		"pre-shift speed below the reverse gate"
	)

	# A12: the drive axle reaches the north gate line z = ALLEY_MAX_Z, and the
	# simulated crossing time is under the 120 s limit.
	assert_true(r["gate_crossed"], "the drive axle reaches the north gate line z = ALLEY_MAX_Z")
	assert_gte(r["crossing_tick"], 0, "a crossing tick was recorded")
	assert_gt(r["crossing_time_s"], 0.0, "a simulated crossing time was recorded")
	assert_lt(
		r["crossing_time_s"], r["a12_limit_s"], "simulated crossing time under the 120 s A12 limit"
	)
	assert_true(r["under_a12_limit"], "crossing time under the A12 limit (scenario's own gate)")

	# The full crossing: 67.0 m = 7.0 m approach + the 60.0 m alley (spawn
	# z=-22 to the gate line z=+45, both pinned constants).
	assert_almost_eq(
		r["distance_travelled_m"],
		PHYSICS_CONSTANTS.ALLEY_MAX_Z - PHYSICS_CONSTANTS.SPAWN_ALLEY_POS.z,
		0.1,
		"the drive axle travelled the full 67 m to the gate line"
	)
	assert_gte(r["distance_travelled_m"], 60.0, "the crossing covers the full 60 m alley")

	# A real reverse, never a forward drive.
	assert_gt(r["peak_reverse_speed_m_s"], 0.5, "a real reverse speed was measured")
	assert_lt(r["peak_forward_speed_m_s"], 0.1, "the rig never drives forward")

	# 0 strikes: 0 wall contacts (the stronger statement), and 0 under the
	# D19 speed proxy the production controller uses (Jolt exposes no
	# per-contact impulse to GDScript, so a wall contact above 1 m/s is the
	# game's strike definition; the scenario mirrors it).
	assert_eq(r["wall_contacts"], 0, "no wall contact during the reverse pass")
	assert_eq(r["strikes"], 0, "no strike (D19 speed proxy: no contact above 1 m/s)")

	# Strictly positive clearance on both walls: the straight pass fits.
	assert_gt(r["min_clear_west_m"], 0.0, "clearance to the west wall strictly positive")
	assert_gt(r["min_clear_east_m"], 0.0, "clearance to the east wall strictly positive")
	assert_true(r["fits_8m"], "the measured sweep fits the pinned 8.0 m alley")

	# The whole combination cleared: the trailer's rearmost point (the leading
	# point in reverse) is past the gate line too.
	assert_gt(
		r["trailer_max_z_m"],
		r["gate_line_z"],
		"the trailer's rear end cleared the gate line as well"
	)

	# The run stayed in bounds.
	assert_false(r["out_of_bounds"], "the run stayed in bounds")

	# The swept width over the FULL 67 m pass. It is body-width dominated
	# (~2.59 m trailer frame) plus a slow lateral drift that accumulates
	# differently in every process (Jolt cross-process variance; the brief
	# mandates percentage-tolerance comparison, never byte-identity). Observed
	# 2.5960..3.0424 m across six separate processes (fresh GUT, three
	# standalone, two full-suite GUT); the zero-drift floor is the 2.59 m
	# trailer frame. The band below brackets that range (0.20 m margin below
	# the observed minimum, 0.36 m above the observed maximum); the acceptance
	# statement is the alley-fit assert that follows.
	assert_between(
		r["swept_width_m"],
		2.4,
		3.4,
		"swept width stays body-width dominated (observed 2.60..3.04 across processes)"
	)
	assert_lt(r["swept_width_m"], 8.0, "the swept width is far below the 8.0 m alley")
	assert_almost_eq(
		r["min_width_with_margin_m"],
		r["swept_width_m"] + 2.0 * r["fit_margin_m"],
		1e-3,
		"fitted width = swept width + 2 x stated margin"
	)

	# The scenario's own acceptance gate: A12.
	assert_true(
		r["pass"], "scenario RESULT = PASS (A12: 60 m alley reverse, 0 strikes, under 120 s)"
	)
