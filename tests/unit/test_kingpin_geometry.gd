extends GutTest
## Geometry and energy guards for the kingpin joint.
##
## Two defects these tests exist because of:
## 1. The trailer body was placed with its origin on the tractor origin, so the
##    joint pinned the trailer 1.00 m BEHIND its own kingpin. Every trailer
##    dimension measured from the pivot (bogie lever, box, coupling distance)
##    was then 1 m further rearward than the pinned constants say.
## 2. The angular limit ceiling of 2.0e7 N m let the joint solver fling the
##    tractor to 400 km/h on a jackknife with the engine at idle rpm. A
##    constraint that adds energy is not a constraint.

const HARNESS_YARD: String = "res://scenes/world/test_yard.tscn"
const CONTROLLER: String = "res://scripts/vehicles/combination_controller.gd"

## A jackknifing rig must not exceed this. The measured pre-fix value was
## 399.8 km/h; the post-fix value is 30.8 km/h. 120 km/h sits well above any
## legitimate speed for this maneuver and well below the failure mode.
const JACKKNIFE_SPEED_CEILING_KMH: float = 120.0

var _harness: Node3D = null
var _c: Node3D = null


func before_each() -> void:
	_harness = Node3D.new()
	_harness.name = "KingpinHarness"
	add_child(_harness)
	_harness.add_child(load(HARNESS_YARD).instantiate())
	_c = load(CONTROLLER).new()
	_c.name = "Combination"
	_c.add_child(load("res://scenes/vehicles/tractor.tscn").instantiate())
	_c.add_child(load("res://scenes/vehicles/trailer.tscn").instantiate())
	_harness.add_child(_c)
	_c.place_at_rest()


func after_each() -> void:
	_harness.queue_free()
	await get_tree().physics_frame
	await get_tree().physics_frame


func _kingpin_error_m() -> float:
	var kingpin: Vector3 = _c.trailer.global_transform * PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL
	var fifth: Vector3 = _c.tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	return (kingpin - fifth).length()


# ---------------------------------------------------------------------------


func test_kingpin_sits_on_the_fifth_wheel_at_rest() -> void:
	assert_lt(_kingpin_error_m(), 0.05, "kingpin must land on the fifth wheel plate")


func test_kingpin_stays_on_the_fifth_wheel_while_driving_and_turning() -> void:
	_c.transmission.automatic = true
	var worst: float = 0.0
	for i in 600:
		_c.throttle = 1.0
		_c.steer_input_axis = 0.6 if i > 240 else 0.0
		await get_tree().physics_frame
		worst = maxf(worst, _kingpin_error_m())
	assert_lt(
		worst, PHYSICS_CONSTANTS.KINGPIN_MAX_PLATE_ERROR_M, "plate error under load: %s" % worst
	)


func test_bogie_lever_measured_from_the_pivot_matches_the_pinned_geometry() -> void:
	## The bogie lever is what every load and off-tracking number is built from,
	## so it is asserted through the pivot rather than through the constants.
	var pivot: Vector3 = _c.tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	var bogie_mid: Vector3 = (
		(
			_c.trailer.global_transform * PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_1
			+ _c.trailer.global_transform * PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_2
		)
		* 0.5
	)
	var lever: float = Vector2(pivot.x - bogie_mid.x, pivot.z - bogie_mid.z).length()
	assert_almost_eq(
		lever, PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M, 0.10, "kingpin to bogie lever"
	)


func _bring_to_stop() -> void:
	## Unlock needs speed below 0.1 m/s, so the harness has to actually stop the
	## rig before asking for it.
	_c.brake_pedal = 1.0
	_c.parking_brake = true
	for _i in 180:
		await get_tree().physics_frame
	_c.brake_pedal = 0.0


func test_unlock_releases_every_locked_dof() -> void:
	## Generic6DOFJoint3D has no top-level "enabled", so a joint that is merely
	## flagged disabled is still pinning the trailer.
	await _bring_to_stop()
	assert_lt(_c.speed(), 0.1, "the rig is stopped")
	_c.request_coupler_unlock()
	assert_false(_c.coupled, "unlock accepted")
	for axis in ["x", "y", "z"]:
		assert_false(
			bool(_c.joint.get("linear_limit_%s/enabled" % axis)), "linear %s released" % axis
		)
		assert_false(
			bool(_c.joint.get("angular_limit_%s/enabled" % axis)), "angular %s released" % axis
		)


func test_an_unlocked_trailer_separates_when_it_is_pushed_clear() -> void:
	## A stopped rig with the kingpin still on the plate re-locks on the next
	## tick, because that is exactly the section 11 auto-lock condition. So the
	## release is proven by moving the trailer clear of the auto-lock window
	## rather than by driving away from it.
	await _bring_to_stop()
	_c.request_coupler_unlock()
	assert_false(_c.coupled, "unlock accepted")
	_c.parking_brake = false
	_c.brake_pedal = 0.0
	_c.trailer.linear_velocity = Vector3(0.0, 0.0, 6.0)
	var worst: float = 0.0
	for _i in 120:
		await get_tree().physics_frame
		worst = maxf(worst, _kingpin_error_m())
	assert_gt(worst, 1.0, "the trailer separates once it is clear: %s" % worst)
	assert_false(_c.coupled, "the trailer is not re-locked while it is moving clear")


func test_a_jackknife_does_not_fling_the_tractor() -> void:
	_c.transmission.automatic = true
	var peak_kmh: float = 0.0
	for i in 1400:
		await get_tree().physics_frame
		_c.throttle = 1.0
		if i > 800:
			_c.steer_input_axis = 1.0
		peak_kmh = maxf(peak_kmh, _c.tractor.linear_velocity.length() * 3.6)
	assert_lt(peak_kmh, JACKKNIFE_SPEED_CEILING_KMH, "jackknife speed: %s" % peak_kmh)
	assert_gt(
		absf(_c.articulation_deg()),
		30.0,
		"the maneuver does swing the trailer: %s" % (_c.articulation_deg())
	)
