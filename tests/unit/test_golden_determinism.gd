extends GutTest
## A14 (phase2-plan line 42 / section 6): the golden determinism harness,
## required to exist before AI traffic (M3). Drives the combination through a
## fixed 600-step script at the pinned 120 Hz step and hashes the transforms
## (position + basis of the tractor, the trailer and the eight wheel nodes).
##
## Godot 4.7's built-in Jolt is NOT bit-deterministic (the godot-jolt README
## says it makes no such guarantee, and there is no user-facing toggle), so two
## identical in-process runs are NOT byte-identical. Per the brief's honesty
## requirement, A14 therefore pins IN-PROCESS DETERMINISM WITH A STATED
## TOLERANCE: the two runs' transforms must agree within the measured Jolt noise
## envelope (GoldenRun.ENVELOPE_BOUND_M), and the run must stay in bounds. The
## two hashes are printed (they differ by the envelope); a recorded reference
## hash is in docs/evidence/phase1/determinism.txt as a gross-regression
## sentinel, not a byte-identity assert. Cross-process reproducibility is
## measured separately (tests/scratch/determinism_probe.gd) and recorded in
## DEVIATIONS D58 -- the test deliberately does not assert it.

const GOLDEN: String = "res://tests/sim/golden_run.gd"

var _runner: Node3D


func before_each() -> void:
	_runner = load(GOLDEN).new()
	add_child(_runner)


func after_each() -> void:
	if is_instance_valid(_runner):
		_runner.queue_free()
		await get_tree().physics_frame


func test_golden_script_is_fixed_data() -> void:
	## The per-step input is a fixed array of records (no RNG), so its checksum
	## is stable and non-trivial. Pure math, no physics.
	var a: int = _runner.script_checksum()
	var b: int = _runner.script_checksum()
	assert_eq(a, b, "the golden input script is fixed data and must checksum identically")
	assert_ne(a, 0, "the golden input script checksum must be non-trivial")


func test_golden_in_process_deterministic_and_in_bounds() -> void:
	## A14's pin: run the same 600-step script twice in this process. The two
	## runs' transforms must agree within the measured Jolt noise envelope (NOT
	## byte-identical -- Jolt is not bit-deterministic, see D58) and the run
	## must stay on the ground (AS4l2 out_of_bounds).
	var r: Dictionary = await _runner.run(self)
	assert_eq(r["steps"], 600, "the golden run is 600 steps")
	assert_eq(r["physics_hz"], 120, "the pinned 120 Hz physics step held")
	assert_false(r["out_of_bounds"], "the golden run must stay on the ground (AS4l2)")
	assert_true(
		r["envelope_m"] <= r["envelope_bound_m"],
		(
			"two-run transform envelope %.3f mm exceeds the bound %.0f mm"
			% [r["envelope_m"] * 1000.0, r["envelope_bound_m"] * 1000.0]
		)
	)
	assert_true(
		r["envelope_artic_rad"] <= r["artic_bound_rad"],
		(
			"two-run articulation envelope %.5f rad exceeds the bound %.4f rad"
			% [r["envelope_artic_rad"], r["artic_bound_rad"]]
		)
	)
	# The two hashes are NOT asserted byte-equal (impossible under Jolt). They
	# are printed for the record; when the runs differ (envelope > 0, the normal
	# case) the hashes must differ, which guards against a degenerate constant
	# hash that would silently pass the envelope gate.
	print("GOLDEN A14 hash[0] = %d" % r["hashes"][0])
	print("GOLDEN A14 hash[1] = %d" % r["hashes"][1])
	print(
		(
			"GOLDEN A14 envelope = %.3f mm (bound %.0f mm)"
			% [r["envelope_m"] * 1000.0, r["envelope_bound_m"] * 1000.0]
		)
	)
	if r["envelope_m"] > 0.0:
		assert_ne(
			r["hashes"][0],
			r["hashes"][1],
			"runs differ by %.3f mm, so the two hashes must differ" % (r["envelope_m"] * 1000.0)
		)
