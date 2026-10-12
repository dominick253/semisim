extends GutTest
## Scene-based integration test for the coupled combination (task 18).
## Joints built inside SceneTree._initialize() never connect in Godot 4.7, so
## the combination must be tested with a real scene and real physics ticks.
##
## Asserts, after settling on flat ground:
##   - the kingpin point stays coincident (trailer does not fall or drift),
##   - total suspension normal force closes the weight within 2 percent,
##   - the combination is at rest (speed, pitch, roll),
##   - articulation yaw is free and stays inside the +/- 75 deg hard limits,
##   - pitch and roll are locked at the kingpin.

const SETTLE_TICKS: int = 240
const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

var _harness: Node


func before_each() -> void:
	_harness = load(HARNESS_SCENE).instantiate()
	add_child(_harness)
	await _harness.settle(SETTLE_TICKS)


func after_each() -> void:
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame


func test_kingpin_stays_coincident() -> void:
	var gap: float = _harness.kingpin_gap_m()
	assert_lt(gap, 0.05, "kingpin drift after settling: %.3f m" % gap)


func test_trailer_does_not_sink() -> void:
	var sink: float = _harness.trailer_sink_m()
	assert_lt(absf(sink), 0.20, "trailer origin sank %.3f m from its rest height" % sink)


func test_suspension_closes_the_weight() -> void:
	var ratio: float = _harness.normal_force_weight_ratio()
	assert_between(ratio, 0.98, 1.02, "summed normal force / weight = %.3f" % ratio)


func test_combination_is_at_rest() -> void:
	assert_lt(_harness.controller.speed(), 0.2, "combination still moving")
	assert_lt(absf(_harness.tractor.rotation.x), 0.01, "tractor pitch at rest")
	assert_lt(absf(_harness.tractor.rotation.z), 0.01, "tractor roll at rest")
	assert_lt(absf(_harness.trailer.rotation.x), 0.01, "trailer pitch at rest")
	assert_lt(absf(_harness.trailer.rotation.z), 0.01, "trailer roll at rest")


func test_all_eight_wheels_carry_load() -> void:
	var grounded: int = 0
	for w in _harness.controller.wheels:
		if w.grounded and w.normal_n > 1000.0:
			grounded += 1
	assert_eq(grounded, 8, "wheels carrying load after settling")


func test_live_axle_loads_match_the_static_model() -> void:
	# Each axle pair's live suspension sum must land within 10 percent of the
	# static share the pure-math suite pins (T14). This is the assertion that
	# caught the rigid pitch lock (DEVIATIONS D23): with a 0 deg pitch window the
	# steer pair came up 16 percent heavy and the drive pair 17 percent light.
	var sums: Dictionary = {}
	var shares: Dictionary = {}
	for w in _harness.controller.wheels:
		sums[w.role] = sums.get(w.role, 0.0) + w.normal_n
		shares[w.role] = shares.get(w.role, 0.0) + w.static_share_n
	for role in ["steer", "drive", "bogie"]:
		var ratio: float = sums[role] / maxf(shares[role], 1.0)
		assert_between(ratio, 0.90, 1.10, "%s axle live/static ratio %.3f" % [role, ratio])


func test_steer_axle_stays_under_the_legal_cap() -> void:
	# The live steer axle load, not just the static model, must respect the
	# pinned cap. This is the load that a real scale ticket would show.
	var steer_n: float = 0.0
	for w in _harness.controller.wheels:
		if w.role == "steer":
			steer_n += w.normal_n
	var steer_kg: float = steer_n / PHYSICS_CONSTANTS.GRAVITY_M_S2
	assert_lt(
		steer_kg,
		PHYSICS_CONSTANTS.STEER_AXLE_LEGAL_CAP_KG,
		"live steer axle load %.0f kg" % steer_kg
	)


func test_articulation_yaw_is_free() -> void:
	# 2e6 N m held for 60 ticks is the measured threshold: it swings the trailer
	# to about 15 deg of articulation, while a joint that locked yaw would hold
	# under 0.1 deg (tests/sim/probe_yaw_push.gd). The bogie tires resist yaw
	# hard, so the push must clear that resistance to prove the DOF is open.
	var before: float = _harness.controller.articulation_rad()
	_harness.push_yaw(2.0e6, 60)
	await _harness.settle(60)
	var during: float = _harness.controller.articulation_rad()
	assert_gt(absf(during - before), deg_to_rad(5.0), "articulation yaw is locked by the joint")
	assert_lt(
		absf(during),
		deg_to_rad(PHYSICS_CONSTANTS.KINGPIN_HARD_LIMIT_DEG),
		"articulation escaped the hard limit during the push: %.1f deg" % rad_to_deg(during)
	)


func test_pitch_and_roll_are_locked_at_the_kingpin() -> void:
	# A rigid kingpin transmits no pitch or roll: with a sustained nose-down
	# moment on the trailer, both bodies must keep the same pitch and roll.
	await _harness.push_pitch(5.0e6, 30)
	await _harness.settle(30)
	# Both bodies must stay within the documented pitch/roll window of each
	# other: the joint, not the suspension, decides their relative attitude.
	var window: float = deg_to_rad(PHYSICS_CONSTANTS.KINGPIN_PITCH_ROLL_WINDOW_DEG)
	var dpitch: float = absf(_harness.trailer.rotation.x - _harness.tractor.rotation.x)
	var droll: float = absf(_harness.trailer.rotation.z - _harness.tractor.rotation.z)
	assert_lt(dpitch, window + 0.002, "pitch unlocked at the kingpin: %.4f rad" % dpitch)
	assert_lt(droll, window + 0.002, "roll unlocked at the kingpin: %.4f rad" % droll)
