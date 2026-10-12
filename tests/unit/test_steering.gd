extends GutTest
## Regression cover for the gap that let a steering bug survive: nothing asserted
## that turning the wheel actually turns the combination. The slip angle must be
## measured in the steered wheel's frame, otherwise a steered wheel on a
## straight-running tractor reads zero slip and yaw never develops.

const HARNESS_YARD: String = "res://scenes/world/test_yard.tscn"
const CONTROLLER: String = "res://scripts/vehicles/combination_controller.gd"

var _harness: Node3D = null
var _c: Node3D = null


func before_each() -> void:
	_harness = Node3D.new()
	_harness.name = "SteerHarness"
	add_child(_harness)
	_harness.add_child(load(HARNESS_YARD).instantiate())
	_c = load(CONTROLLER).new()
	_c.name = "Combination"
	_c.add_child(load("res://scenes/vehicles/tractor.tscn").instantiate())
	_c.add_child(load("res://scenes/vehicles/trailer.tscn").instantiate())
	_harness.add_child(_c)
	_c.place_at_rest()
	_c.transmission.automatic = true


func after_each() -> void:
	_harness.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _drive(ticks: int, steer: float, brake: float = 0.0) -> void:
	for _i in ticks:
		_c.throttle = 1.0
		_c.steer_input_axis = steer
		_c.brake_pedal = brake
		await get_tree().physics_frame


# ---------------------------------------------------------------------------


func test_straight_run_keeps_the_combination_straight() -> void:
	await _drive(360, 0.0)
	assert_lt(absf(rad_to_deg(_c.tractor.global_basis.get_euler().y)), 1.0, "tractor yaw")
	assert_lt(absf(_c.articulation_deg()), 1.0, "articulation")
	assert_gt(_c.speed(), 1.0, "it is actually rolling")


func test_steering_at_speed_yaws_the_tractor() -> void:
	await _drive(360, 0.0)
	var yaw_before: float = rad_to_deg(_c.tractor.global_basis.get_euler().y)
	await _drive(300, 1.0)
	var yaw_after: float = rad_to_deg(_c.tractor.global_basis.get_euler().y)
	assert_gt(absf(yaw_after - yaw_before), 5.0, "steering turns the tractor: %s" % [yaw_after])


func test_steering_creates_articulation_between_the_units() -> void:
	await _drive(360, 0.0)
	await _drive(300, 1.0)
	assert_gt(absf(_c.articulation_deg()), 5.0, "the trailer lags the tractor")
	assert_true(
		absf(_c.articulation_deg()) < PHYSICS_CONSTANTS.KINGPIN_HARD_LIMIT_DEG + 1.0,
		"articulation stays inside the hard limit"
	)


func test_a_steered_stop_drives_slip_past_the_squeal_gate() -> void:
	## Section 13 gates tire squeal on lateral slip ratio > 0.12. Braking with the
	## steering loaded is the maneuver that reaches it in this model, so the gate
	## has to be provably reachable rather than only pinned.
	_c.transmission.automatic = true
	for i in 800:
		_c.throttle = 1.0
		await get_tree().physics_frame
	var peak: float = 0.0
	for i in 400:
		_c.throttle = 1.0
		_c.steer_input_axis = 1.0
		if i > 200:
			_c.brake_pedal = 1.0
		await get_tree().physics_frame
		peak = maxf(peak, _c.max_lateral_slip)
	assert_gt(peak, PHYSICS_CONSTANTS.SQUEAL_SLIP_THRESHOLD, "squeal gate reachable: %s" % peak)
