extends GutTest
## AS4j2: the pinned restart path gets its caller (D54, D55).
##
## Spec 5.4: the spring brake "applies automatically below 40 psi: drive and
## trailer axles lock until pressure recovers above 60 psi or the engine is
## restarted." Spec section 6 (jackknife): "Recovery only via restart."
##
## Defect 1 (pre-fix): AirSystem.restart_engine() had zero production
## callers, and CombinationController set engine_running = false at the 1900
## rpm shutdown with nothing ever setting it true again: one over-rev left a
## permanently dead truck with a stopped compressor (probe: run=false and
## 0.02-0.04 m/s for all 30 s, tests/scratch/engine_restart_probe.gd).
## Defect 2 (pre-fix): restart_engine() set spring_brake_engaged = false and
## then called _refresh_state(), which re-engaged the brake below 40 psi --
## at any pressure below 40 psi the release was immediately cancelled.
##
## These tests prove:
##   1. Forced shutdown, combination at rest, throttle 0.0: the engine is
##      running again within 3 s and engine_rpm >= the idle floor.
##      RED pre-fix (no restart path existed).
##   2. Forced shutdown with throttle held at 1.0: no restart while the
##      throttle is held (the rule's throttle term), with the rpm already at
##      the idle floor.
##   3. air.reset(30.0, false) then air.restart_engine(): the spring brake
##      is released afterwards and the state stays WARNING below the 60 psi
##      warning threshold, not SPRING_BRAKE. RED pre-fix.
##   4. Normal running untouched: a dry launch keeps engine_running true on
##      every tick (the saturation numbers are gate-checked against the
##      baseline by wheel_saturation_probe.gd within 0.5 percent).

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const SETTLE_TICKS: int = 240
const RESTART_WINDOW_TICKS: int = 360  # 3 s at 120 Hz
const HELD_THROTTLE_TICKS: int = 600  # 5 s of held throttle
const DRY_LAUNCH_TICKS: int = 360

var _harness: Node


func _drive_wheel(c: Node) -> WheelRig:
	for w in c.wheels:
		if w.role == "drive":
			return w
	return null


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
	# would leak its harness into the next test's tree.
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
	_harness = null


# --- 1. Forced shutdown at rest, throttle 0.0: the engine restarts ----------


func test_shutdown_at_rest_restarts_within_3_s() -> void:
	_harness = await _make_harness()
	var c: Node = _harness.controller
	assert_true(c.engine_running, "harness starts with the engine running")
	c.throttle = 0.0
	c.engine_running = false  # forced shutdown (the 1900 rpm over-rev, in miniature)
	var first_running_tick: int = -1
	for i in RESTART_WINDOW_TICKS:
		await get_tree().physics_frame
		if c.engine_running:
			first_running_tick = i + 1
			break
	print(
		(
			"AS4j2 restart at rest: first_running_tick=%d (window %d) rpm=%.1f"
			% [first_running_tick, RESTART_WINDOW_TICKS, c.engine_rpm]
		)
	)
	assert_gte(
		first_running_tick,
		1,
		"engine never restarted within 3 s of a forced shutdown at rest, throttle 0.0"
	)
	assert_gte(
		c.engine_rpm,
		PHYSICS_CONSTANTS.ENGINE_IDLE_RPM,
		"engine_rpm %.1f below the idle floor after the restart" % c.engine_rpm
	)
	assert_true(c.engine_running, "engine not running at the end of the 3 s window")
	await _free_harness()


# --- 2. Held throttle blocks the restart ------------------------------------


func test_held_throttle_blocks_the_restart() -> void:
	_harness = await _make_harness()
	var c: Node = _harness.controller
	# At rest with the engine forced off, both rpm paths are already at the
	# idle floor (the wheel rate and the vehicle speed both clamp to at least
	# idle), so the throttle term is the only thing standing between the rule
	# and a restart: holding throttle 1.0 must block it. (The spinning-wheel
	# variant of this scenario is the ice launch, covered by the probe.)
	c.throttle = 1.0
	c.engine_running = false
	var run_ticks: int = 0
	for _i in HELD_THROTTLE_TICKS:
		await get_tree().physics_frame
		if c.engine_running:
			run_ticks += 1
	print(
		"AS4j2 held throttle: run_ticks=%d of %d (throttle 1.0)" % [run_ticks, HELD_THROTTLE_TICKS]
	)
	assert_eq(
		run_ticks, 0, "engine restarted while the throttle was held (run_ticks %d)" % run_ticks
	)
	await _free_harness()


# --- 3. restart_engine releases the spring brake below 40 psi (defect 2) ----


func test_restart_engine_releases_the_spring_brake_below_40_psi() -> void:
	var air: AirSystem = AirSystem.new()
	air.reset(30.0, false)
	print(
		(
			"AS4j2 air pre:  pressure=%.1f state=%d engaged=%s"
			% [air.pressure_psi, air.state, str(air.spring_brake_engaged)]
		)
	)
	assert_true(
		air.spring_brake_engaged,
		"precondition: spring brake must be engaged at 30 psi with the engine off"
	)
	air.restart_engine()
	print(
		(
			"AS4j2 air post: pressure=%.1f state=%d engaged=%s"
			% [air.pressure_psi, air.state, str(air.spring_brake_engaged)]
		)
	)
	assert_true(air.engine_running, "restart_engine must set engine_running")
	assert_false(
		air.spring_brake_engaged,
		"spring brake re-engaged below 40 psi: the restart undid its own release (defect 2)"
	)
	assert_ne(
		air.state,
		AirSystem.AirState.SPRING_BRAKE,
		"state must not stay SPRING_BRAKE while spring_brake_engaged is false"
	)
	assert_eq(
		air.state,
		AirSystem.AirState.WARNING,
		"30 psi is below the 60 psi warning threshold: state must be WARNING (got %d)" % air.state
	)


# --- 4. Normal running untouched: the dry launch ----------------------------


func test_dry_launch_keeps_the_engine_running_every_tick() -> void:
	_harness = await _make_harness()
	var drive: WheelRig = _drive_wheel(_harness.controller)
	var c: Node = _harness.controller
	c.throttle = 1.0
	c.brake_pedal = 0.0
	var dead_ticks: int = 0
	var max_slip: float = 0.0
	var v_final: float = 0.0
	for _i in DRY_LAUNCH_TICKS:
		await get_tree().physics_frame
		if not c.engine_running:
			dead_ticks += 1
		max_slip = maxf(max_slip, absf(drive.slip_ratio))
		v_final = c.tractor.linear_velocity.dot(-c.tractor.global_basis.z)
	print(
		(
			"AS4j2 dry: v_final=%.4f m/s dead_ticks=%d max_slip=%.4f (%d ticks)"
			% [v_final, dead_ticks, max_slip, DRY_LAUNCH_TICKS]
		)
	)
	assert_eq(dead_ticks, 0, "engine died on %d ticks during the dry launch" % dead_ticks)
	assert_gt(v_final, 1.0, "dry launch did not move: v_final %.3f m/s" % v_final)
	await _free_harness()
