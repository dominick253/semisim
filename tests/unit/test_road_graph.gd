extends GutTest
## A21: the road graph loads headless, is connected, and every delivery
## destination is reachable. Route generation depends on the graph being
## deterministic, so the same build twice must produce the same path.

var _city: RoadGraph


func before_all() -> void:
	_city = RoadGraph.build_city()


func test_city_graph_loads_and_has_intersections() -> void:
	assert_not_null(_city, "the city graph must build")
	assert_gt(_city.intersection_ids().size(), 40, "a city needs blocks of streets")
	assert_gt(_city.total_length_m(), 5000.0, "the graph must be a real road network")


func test_city_graph_is_connected() -> void:
	assert_true(_city.is_fully_connected(), "every intersection must be reachable from the grid")


func test_every_destination_is_reachable_from_the_spawn() -> void:
	var spawn: String = _city.spawn_id()
	assert_ne(spawn, "", "the city must declare a spawn intersection")
	for dest: String in _city.destinations():
		var route: PackedStringArray = _city.shortest_path(spawn, dest)
		assert_gt(route.size(), 1, "destination %s must be reachable" % dest)
		assert_eq(route[0], spawn, "a route starts at the spawn")
		assert_eq(route[route.size() - 1], dest, "a route ends at its destination")


func test_shortest_path_is_deterministic_across_two_builds() -> void:
	var again: RoadGraph = RoadGraph.build_city()
	var spawn: String = _city.spawn_id()
	for dest: String in _city.destinations():
		var first: PackedStringArray = _city.shortest_path(spawn, dest)
		var second: PackedStringArray = again.shortest_path(again.spawn_id(), dest)
		assert_eq(first, second, "route generation must not vary between builds")


func test_shortest_path_is_never_longer_than_a_detour() -> void:
	var spawn: String = _city.spawn_id()
	var dest: String = _city.destinations()[0]
	var direct: PackedStringArray = _city.shortest_path(spawn, dest)
	var direct_length: float = _city.route_length_m(direct)
	var longer: float = _city.route_length_m(direct)
	for dest2: String in _city.destinations():
		var other: float = _city.route_length_m(_city.shortest_path(spawn, dest2))
		if other > 0.0:
			longer = max(longer, other)
	assert_lt(direct_length, longer + 0.001, "the shortest path is the shortest")


func test_unreachable_destination_returns_an_empty_route() -> void:
	var graph: RoadGraph = RoadGraph.new()
	graph.add_intersection("a", Vector3.ZERO)
	graph.add_intersection("b", Vector3(100.0, 0.0, 0.0))
	assert_eq(graph.shortest_path("a", "b"), PackedStringArray(), "no street means no route")
	assert_false(graph.is_fully_connected(), "two islands are not a connected graph")


func test_turn_validator_blocks_a_turn_the_combination_cannot_make() -> void:
	var graph: RoadGraph = RoadGraph.new()
	graph.add_intersection("west", Vector3(0.0, 0.0, 0.0))
	graph.add_intersection("corner", Vector3(60.0, 0.0, 0.0))
	graph.add_intersection("north", Vector3(60.0, 0.0, -60.0))
	graph.add_street("west", "corner", 8.0, "alley")
	graph.add_street("corner", "north", 8.0, "alley")
	assert_false(
		graph.route_is_drivable(PackedStringArray(["west", "corner", "north"])),
		"a 90 degree turn on an 8 m alley is outside the envelope"
	)


func test_turn_validator_allows_a_straight_run_and_a_wide_turn() -> void:
	var graph: RoadGraph = RoadGraph.new()
	graph.add_intersection("west", Vector3(0.0, 0.0, 0.0))
	graph.add_intersection("corner", Vector3(60.0, 0.0, 0.0))
	graph.add_intersection("north", Vector3(60.0, 0.0, -60.0))
	graph.add_street("west", "corner", 14.0, "arterial")
	graph.add_street("corner", "north", 14.0, "arterial")
	assert_true(
		graph.route_is_drivable(PackedStringArray(["west", "corner", "north"])),
		"an arterial turn is inside the envelope"
	)
	assert_true(
		graph.route_is_drivable(PackedStringArray(["west", "corner"])),
		"a straight run needs no turn allowance"
	)


func test_town_profiles_build_from_the_same_graph_code() -> void:
	for profile: String in RoadGraph.town_profile_ids():
		var town: RoadGraph = RoadGraph.build_town(profile)
		assert_not_null(town, "town profile %s must build" % profile)
		assert_true(town.is_fully_connected(), "town %s must be connected" % profile)
		assert_gt(town.destinations().size(), 0, "town %s must have destinations" % profile)
		var spawn: String = town.spawn_id()
		for dest: String in town.destinations():
			assert_gt(
				town.shortest_path(spawn, dest).size(),
				1,
				"town %s destination %s must be reachable" % [profile, dest]
			)


func test_alley_edges_exist_and_are_marked_as_alleys() -> void:
	var found: int = 0
	for id: String in _city.intersection_ids():
		for other: String in _city.neighbours(id):
			var street: Dictionary = _city.street_for(id, other)
			if street.get("kind", "") == "alley":
				found += 1
	assert_gt(found, 0, "the city grid must include alleys")
