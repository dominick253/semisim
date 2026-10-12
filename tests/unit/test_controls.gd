extends GutTest
## Task 21: complete control map (section 11) including the no-op rules that
## must produce a HUD reason flash, and the trailer path prediction math that
## the G overlay draws.

const InputMapSetup := preload("res://scripts/input/input_map_setup.gd")
const NoopRules := preload("res://scripts/input/noop_rules.gd")
const TrailerPath := preload("res://scripts/vehicles/trailer_path.gd")

const REQUIRED_ACTIONS: Array[String] = [
	"throttle",
	"brake",
	"clutch",
	"steer_left",
	"steer_right",
	"gear_1",
	"gear_2",
	"gear_3",
	"gear_4",
	"gear_5",
	"gear_6",
	"gear_7",
	"gear_8",
	"gear_9",
	"gear_10",
	"reverse",
	"neutral",
	"range_toggle",
	"retarder_up",
	"retarder_down",
	"parking_brake",
	"coupler_unlock",
	"landing_gear",
	"camera_cycle",
	"trailer_path_overlay",
	"transmission_mode",
	"debug_overlay",
	"context_help",
	"pause_menu",
	"gamepad_throttle",
	"gamepad_brake",
	"gamepad_steer",
	"gamepad_clutch",
	"gamepad_gear_up",
	"gamepad_gear_down",
	"gamepad_range",
	"gamepad_parking_brake",
	"gamepad_retarder_left",
	"gamepad_retarder_right",
	"gamepad_landing_up",
	"gamepad_landing_down",
	"gamepad_camera",
	"gamepad_camera_cycle",
	"gamepad_pause",
]


func before_each() -> void:
	InputMapSetup.install()


# ---------------------------------------------------------------------------
# Action coverage
# ---------------------------------------------------------------------------


func test_every_section_11_action_exists() -> void:
	for action in REQUIRED_ACTIONS:
		assert_true(InputMap.has_action(action), "missing action: %s" % action)


func test_no_extra_actions_beyond_section_11() -> void:
	var extra: Array[String] = []
	for action in InputMap.get_actions():
		var s: String = String(action)
		if s.begins_with("ui_"):
			continue  # engine built-ins
		if not REQUIRED_ACTIONS.has(s):
			extra.append(s)
	assert_eq(extra.size(), 0, "actions outside the pinned map: %s" % ", ".join(extra))


func test_keyboard_bindings_match_spec() -> void:
	var expected: Dictionary = {
		"throttle": KEY_W,
		"brake": KEY_S,
		"clutch": KEY_SHIFT,
		"gear_1": KEY_1,
		"gear_2": KEY_2,
		"gear_3": KEY_3,
		"gear_4": KEY_4,
		"gear_5": KEY_5,
		"gear_6": KEY_6,
		"gear_7": KEY_7,
		"gear_8": KEY_8,
		"gear_9": KEY_9,
		"gear_10": KEY_0,
		"reverse": KEY_R,
		"neutral": KEY_N,
		"range_toggle": KEY_E,
		"retarder_up": KEY_Z,
		"retarder_down": KEY_X,
		"parking_brake": KEY_SPACE,
		"coupler_unlock": KEY_U,
		"landing_gear": KEY_L,
		"camera_cycle": KEY_TAB,
		"trailer_path_overlay": KEY_G,
		"transmission_mode": KEY_V,
		"debug_overlay": KEY_F3,
		"context_help": KEY_F1,
		"pause_menu": KEY_ESCAPE,
	}
	for action in expected:
		var keys: Array[int] = _physical_keys_for(action)
		assert_true(keys.has(int(expected[action])), "%s must bind %s" % [action, expected[action]])


func test_steer_binds_both_ad_and_arrows() -> void:
	var left: Array[int] = _physical_keys_for("steer_left")
	var right: Array[int] = _physical_keys_for("steer_right")
	assert_true(left.has(KEY_A), "steer_left needs A")
	assert_true(left.has(KEY_LEFT), "steer_left needs Left arrow")
	assert_true(right.has(KEY_D), "steer_right needs D")
	assert_true(right.has(KEY_RIGHT), "steer_right needs Right arrow")


func test_control_map_lives_in_code_not_project_godot() -> void:
	## The pinned map is installed by InputMapSetup so it cannot drift into a
	## hand-edited project.godot [input] block.
	var cfg: String = FileAccess.get_file_as_string("res://project.godot")
	assert_false(cfg.contains("[input]"), "project.godot must not hand-author the map")


func test_install_is_idempotent() -> void:
	InputMapSetup.install()
	InputMapSetup.install()
	var count: int = _physical_keys_for("throttle").size()
	assert_eq(count, 1, "re-install must not duplicate bindings")


# ---------------------------------------------------------------------------
# Gear key mapping (1..5 high range, 6..0 low range)
# ---------------------------------------------------------------------------


func test_gear_key_index_maps_to_pinned_gears() -> void:
	var expected: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	for i in 10:
		assert_eq(InputMapSetup.gear_for_key_index(i), expected[i], "gear key %d" % i)


func test_low_range_keys_land_in_low_range() -> void:
	var t := Transmission.new()
	t.automatic = false
	t.select_gear(InputMapSetup.gear_for_key_index(9), 0.0, true)
	assert_eq(t.gear, 10, "key 0 is tenth gear")
	assert_eq(t.range, Transmission.GearRange.LOW, "tenth gear is low range")
	t.select_gear(InputMapSetup.gear_for_key_index(4), 0.0, true)
	assert_eq(t.gear, 5, "key 5 is fifth gear")
	assert_eq(t.range, Transmission.GearRange.HIGH, "fifth gear is high range")


# ---------------------------------------------------------------------------
# No-op rules (every one must produce a reason string for the HUD flash)
# ---------------------------------------------------------------------------


func test_gear_change_without_clutch_in_manual_is_a_noop() -> void:
	var reason: String = NoopRules.gear_change_reason(false, 0.0, false, 3, 4)
	assert_eq(reason, "SHIFT NEEDS CLUTCH OR AUTO MODE", "manual shift without clutch")
	assert_eq(NoopRules.gear_change_reason(true, 0.0, false, 3, 4), "", "auto mode is allowed")
	assert_eq(
		NoopRules.gear_change_reason(false, 0.0, true, 3, 4), "", "clutch depressed is allowed"
	)


func test_reverse_above_half_meter_per_second_is_a_noop() -> void:
	assert_eq(NoopRules.reverse_reason(0.51), "REVERSE NEEDS SPEED BELOW 0.5 M/S", "0.51 m/s")
	assert_eq(NoopRules.reverse_reason(0.49), "", "0.49 m/s is allowed")
	assert_eq(NoopRules.reverse_reason(0.5), "", "boundary 0.5 is allowed")


func test_retarder_low_range_is_a_noop() -> void:
	var reason: String = NoopRules.retarder_reason(Transmission.GearRange.LOW, 3, 20.0, 2)
	assert_eq(reason, "RETARDER NEEDS HIGH RANGE, GEAR 1-4, ABOVE 15 KM/H", "low range")


func test_retarder_above_gear_four_is_a_noop() -> void:
	assert_eq(
		NoopRules.retarder_reason(Transmission.GearRange.HIGH, 5, 20.0, 2),
		"RETARDER NEEDS HIGH RANGE, GEAR 1-4, ABOVE 15 KM/H",
		"fifth gear"
	)


func test_retarder_below_15_kmh_is_a_noop() -> void:
	assert_eq(
		NoopRules.retarder_reason(Transmission.GearRange.HIGH, 2, 4.0, 2),
		"RETARDER NEEDS HIGH RANGE, GEAR 1-4, ABOVE 15 KM/H",
		"below 15 km/h"
	)
	assert_eq(
		NoopRules.retarder_reason(Transmission.GearRange.HIGH, 2, 4.2, 2), "", "above 15 km/h"
	)
	assert_eq(
		NoopRules.retarder_reason(Transmission.GearRange.HIGH, 4, 20.0, 2),
		"",
		"fourth gear allowed"
	)


func test_unlock_while_moving_is_a_noop() -> void:
	assert_eq(NoopRules.unlock_reason(0.5, true), "UNLOCK NEEDS SPEED BELOW 0.1 M/S", "moving")
	assert_eq(NoopRules.unlock_reason(0.0, false), "UNLOCK NEEDS PARKING BRAKE", "no parking brake")
	assert_eq(NoopRules.unlock_reason(0.0, true), "", "stopped with parking brake")


func test_landing_gear_while_attached_or_moving_is_a_noop() -> void:
	assert_eq(
		NoopRules.landing_reason(true, 0.0), "LANDING GEAR NEEDS DETACHED TRAILER", "attached"
	)
	assert_eq(NoopRules.landing_reason(false, 0.5), "LANDING GEAR NEEDS STOPPED TRAILER", "moving")
	assert_eq(NoopRules.landing_reason(false, 0.0), "", "detached and stopped")


# ---------------------------------------------------------------------------
# Trailer path overlay prediction (section 11, G)
# ---------------------------------------------------------------------------


func test_path_is_30_m_long_and_sampled_every_2_m() -> void:
	var pts: PackedVector2Array = TrailerPath.path_points(Vector2.ZERO, 0.0, 0.0, 0.0)
	assert_eq(pts.size(), PHYSICS_CONSTANTS.TRAILER_PATH_SAMPLES + 1, "sample count")
	var arc_len: float = 0.0
	for i in range(1, pts.size()):
		arc_len += pts[i].distance_to(pts[i - 1])
	assert_almost_eq(arc_len, PHYSICS_CONSTANTS.TRAILER_PATH_LENGTH_M, 0.001, "30 m path")
	assert_almost_eq(
		TrailerPath.SAMPLE_STEP_M,
		PHYSICS_CONSTANTS.TRAILER_PATH_LENGTH_M / PHYSICS_CONSTANTS.TRAILER_PATH_SAMPLES,
		0.001,
		"2 m sampling"
	)


func test_straight_path_stays_on_the_heading_line() -> void:
	var pts: PackedVector2Array = TrailerPath.path_points(Vector2.ZERO, 0.0, 0.0, 0.0)
	for p in pts:
		assert_almost_eq(p.y, 0.0, 0.02, "straight path stays on axis")
	assert_almost_eq(
		pts[0].x,
		-PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M,
		0.001,
		"first point is behind the bogie"
	)


func test_path_curves_inside_the_tractor_path() -> void:
	# 15 m tractor radius at 12 km/h is the pinned off-tracking case (section 9).
	# A 53 ft trailer cuts the corner: the bicycle model gives a bogie radius of
	# sqrt(R_kingpin^2 - L_bogie^2), which is smaller than the tractor radius.
	var speed: float = 12.0 / 3.6
	var steer: float = atan2(PHYSICS_CONSTANTS.WHEELBASE_TRACTOR_M, 15.0)
	var artic: float = TrailerPath.steady_state_articulation_rad(steer)
	var tractor_pts: PackedVector2Array = TrailerPath.tractor_path_points(Vector2.ZERO, 0.0, steer)
	var pts: PackedVector2Array = TrailerPath.path_points(Vector2.ZERO, 0.0, artic, steer)
	assert_eq(pts.size(), tractor_pts.size(), "same sample count")
	assert_ne(0.0, pts[pts.size() - 1].y, "steered path leaves the straight line")
	var r_tractor: float = _arc_radius(tractor_pts)
	var r_trailer: float = _arc_radius(pts)
	assert_lt(r_trailer, r_tractor, "trailer path must cut the corner")
	var expected: float = sqrt(
		(
			15.0 * 15.0
			- (
				PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M
				* PHYSICS_CONSTANTS.TRAILER_KINGPIN_TO_BOGIE_M
			)
		)
	)
	assert_almost_eq(r_trailer, expected, 0.25, "predicted bogie radius follows the bicycle model")
	assert_almost_eq(
		TrailerPath.bogie_radius_m(steer, artic),
		expected,
		0.001,
		"closed form bogie radius matches the sampled arc"
	)
	# DEVIATION D27: the pinned 1.2 m off-tracking target is unreachable on a
	# 15 m circle with the pinned 6.5 m tractor wheelbase and 10.0 m
	# kingpin-to-bogie distance. The bicycle model puts the bogie at 11.18 m,
	# a 3.82 m shortfall against the 15.00 m kingpin path (5.14 m against the
	# 16.32 m steer axle path), and the shortfall only shrinks as the radius
	# grows. The measured geometric value is asserted instead of the target.
	assert_almost_eq(
		15.0 - expected,
		PHYSICS_CONSTANTS.OFF_TRACKING_GEOMETRIC_M_15M,
		0.02,
		"15 m circle off-tracking (DEVIATION D27)"
	)
	assert_gt(speed, 0.0, "speed only sets the recompute cadence, not the geometry")


func test_path_recompute_period_is_pinned() -> void:
	assert_almost_eq(
		PHYSICS_CONSTANTS.TRAILER_PATH_RECOMPUTE_S, 0.25, 0.001, "recompute every 0.25 s"
	)
	assert_almost_eq(PHYSICS_CONSTANTS.TRAILER_PATH_LENGTH_M, 30.0, 0.001, "30 m path")


func _arc_radius(pts: PackedVector2Array) -> float:
	## Circumradius through three points spread across the arc.
	var a: Vector2 = pts[0]
	var b: Vector2 = pts[pts.size() / 2]
	var c: Vector2 = pts[pts.size() - 1]
	var ab: float = a.distance_to(b)
	var bc: float = b.distance_to(c)
	var ca: float = c.distance_to(a)
	var area2: float = absf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y))
	if area2 < 1e-6:
		return INF
	# area2 is twice the triangle area; the circumradius is abc / 4A.
	return (ab * bc * ca) / (2.0 * area2)


func _physical_keys_for(action: String) -> Array[int]:
	var out: Array[int] = []
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			out.append(int((ev as InputEventKey).physical_keycode))
	return out
