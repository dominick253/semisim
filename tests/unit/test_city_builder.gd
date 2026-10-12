extends GutTest
## CityBuilder turns the RoadGraph data into placed geometry. These tests are
## pure placement math on purpose: they prove the geometry matches the graph,
## and the live-harness rule in docs/phase2-plan.md means the driving proof
## happens in a scenario script, not here.

var _city: RoadGraph


func before_each() -> void:
	_city = RoadGraph.build_city()


func test_every_street_becomes_exactly_one_road_segment() -> void:
	var segments: Array[Dictionary] = CityBuilder.road_segments(_city)
	assert_eq(segments.size(), _city.street_count(), "one segment per street, no duplicates")


func test_segment_geometry_matches_the_graph_endpoints() -> void:
	for segment: Dictionary in CityBuilder.road_segments(_city):
		var from_pos: Vector3 = _city.position_of(segment["from"])
		var to_pos: Vector3 = _city.position_of(segment["to"])
		var expected_center: Vector3 = (from_pos + to_pos) * 0.5
		assert_lt(
			(segment["center"] as Vector3).distance_to(expected_center),
			0.001,
			"segment must sit on its street"
		)
		var expected_length: float = from_pos.distance_to(to_pos)
		assert_gt(segment["length_m"], expected_length - 0.001, "segment covers the street")
		assert_lt(segment["length_m"], expected_length + 20.0, "segment does not overrun")
		assert_gt(segment["width_m"], 0.0, "segment has width")


func test_segment_width_comes_from_the_street_kind() -> void:
	for segment: Dictionary in CityBuilder.road_segments(_city):
		var expected: float = TurnEnvelope.street_width_m(segment["kind"])
		assert_almost_eq(segment["width_m"], expected, 0.001, "width follows the kind")


func test_junction_pads_cover_the_widest_incident_street() -> void:
	var pads: Array[Dictionary] = CityBuilder.junction_pads(_city)
	assert_gt(pads.size(), 60, "the city grid has junctions to pad")
	for pad: Dictionary in pads:
		var id: String = pad["id"]
		var widest_half: float = 0.0
		for neighbour: String in _city.neighbours(id):
			var street: Dictionary = _city.street_for(id, neighbour)
			widest_half = max(widest_half, street["width_m"] * 0.5)
		assert_gt(pad["radius_m"], widest_half - 0.001, "pad must cover the widest street")
		assert_lt(pad["radius_m"], 25.0, "pad radius stays a real junction size")


func test_alley_segments_keep_the_straight_only_rule() -> void:
	var found: int = 0
	for segment: Dictionary in CityBuilder.road_segments(_city):
		if segment["kind"] != "alley":
			continue
		found += 1
		assert_eq(segment["fillet_m"], 0.0, "an alley has no corner fillet")
		# The slab spans the block plus the junction reach at each gate, and the
		# widest reach in the city grid is half an arterial.
		var reach: float = TurnEnvelope.street_width_m("arterial")
		assert_lt(
			segment["length_m"], WorldConstants.CITY_BLOCK_W_M + reach + 1.0, "alley fits a block"
		)
	assert_gt(found, 40, "the city must have alleys, not just streets")


func test_geometry_is_finite_and_positive() -> void:
	for segment: Dictionary in CityBuilder.road_segments(_city):
		var center: Vector3 = segment["center"]
		assert_true(center.is_finite(), "segment center must be finite")
		assert_gt(segment["size"].x, 0.0, "segment box has depth")
		assert_gt(segment["size"].z, 0.0, "segment box has width")
	for pad: Dictionary in CityBuilder.junction_pads(_city):
		assert_true((pad["center"] as Vector3).is_finite(), "pad center must be finite")
		assert_gt(pad["radius_m"], 0.0, "pad has a radius")


func test_town_geometry_comes_from_the_same_builder() -> void:
	for profile: String in RoadGraph.town_profile_ids():
		var town: RoadGraph = RoadGraph.build_town(profile)
		var segments: Array[Dictionary] = CityBuilder.road_segments(town)
		assert_eq(segments.size(), town.street_count(), "town %s builds every street" % profile)
		assert_gt(CityBuilder.junction_pads(town).size(), 10, "town %s has junctions" % profile)
