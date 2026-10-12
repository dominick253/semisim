extends GutTest
## The 90 degree turn envelope from docs/world-spec.md section 2. These numbers
## are pinned from measured Phase 1 facts, so the assertions carry the
## measurements they came from.

const MEASURED_BOGIE_RADIUS_M_15M: float = 11.18
const MEASURED_KINGPIN_PATH_M_15M: float = 15.0
const CLEARANCE_TOLERANCE_M: float = 0.02


func test_clearance_is_built_from_pinned_constants() -> void:
	var half_trailer_width: float = PHYSICS_CONSTANTS.TRAILER_BOX.x * 0.5
	var expected: float = (
		half_trailer_width
		+ PHYSICS_CONSTANTS.KINGPIN_MAX_PLATE_ERROR_M
		+ WorldConstants.HANDLING_MARGIN_M
	)
	assert_almost_eq(
		TurnEnvelope.CLEARANCE_M,
		expected,
		CLEARANCE_TOLERANCE_M,
		"clearance is half trailer width plus the accepted plate error plus margin"
	)


func test_bogie_radius_matches_the_measured_15_m_circle() -> void:
	# D27 measured a bogie path radius of 11.18 m on the 15 m circle. The model
	# must reproduce that number or the street widths built from it are fiction.
	var radius: float = TurnEnvelope.bogie_radius_m(MEASURED_KINGPIN_PATH_M_15M)
	assert_almost_eq(radius, MEASURED_BOGIE_RADIUS_M_15M, 0.01, "bogie cuts the inside path")


func test_bogie_radius_is_impossible_below_the_kingpin_to_bogie_distance() -> void:
	assert_eq(TurnEnvelope.bogie_radius_m(9.0), -1.0, "a 10 m lever cannot turn inside a 9 m path")


func test_min_street_width_for_the_pinned_fillets() -> void:
	assert_almost_eq(TurnEnvelope.min_street_width_m(8.0), 8.65, 0.02, "arterial fillet")
	assert_almost_eq(TurnEnvelope.min_street_width_m(6.0), 9.29, 0.02, "local fillet")
	assert_almost_eq(TurnEnvelope.min_street_width_m(9.0), 8.38, 0.02, "tight fillet")


func test_min_street_width_grows_when_the_fillet_sharpens() -> void:
	assert_lt(
		TurnEnvelope.min_street_width_m(9.0),
		TurnEnvelope.min_street_width_m(4.0),
		"a wider corner lets a narrower street turn"
	)


func test_turn_fits_uses_the_street_width_and_the_corner_fillet() -> void:
	assert_true(TurnEnvelope.turn_fits(14.0, 8.0), "arterial turns comfortably")
	assert_true(TurnEnvelope.turn_fits(11.0, 6.0), "local turns with margin")
	assert_true(TurnEnvelope.turn_fits(9.0, 9.0), "tight turns with a wide corner")
	assert_false(TurnEnvelope.turn_fits(8.0, 4.0), "an 8 m street with a 4 m corner is blocked")
	assert_false(TurnEnvelope.turn_fits(8.0, 0.0), "an 8 m alley never turns")


func test_pinned_street_classes_all_pass_the_rule_they_were_sized_with() -> void:
	for kind: String in WorldConstants.STREET_WIDTH_M:
		var width: float = WorldConstants.STREET_WIDTH_M[kind]
		var fillet: float = WorldConstants.CORNER_FILLET_M[kind]
		if kind == "alley":
			continue
		assert_true(
			TurnEnvelope.turn_fits(width, fillet),
			"street class %s must satisfy the turn envelope" % kind
		)
