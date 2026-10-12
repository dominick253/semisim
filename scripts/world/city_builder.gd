class_name CityBuilder
## Turns a RoadGraph into placed geometry: one road slab per street and one
## junction pad per intersection. The graph is the source of truth, so the city
## and the three towns are the same code with different profiles, which is what
## A24 asserts.
##
## This file produces placement data only. Nodes, collision shapes and MultiMesh
## props are built from it by the city scene, so the placement math stays unit
## testable without a physics world.

const ROAD_THICKNESS_M: float = 0.10
const PAD_FILLET_CAP_M: float = 12.0
const PAD_MIN_NEIGHBOURS: int = 2


static func road_segments(graph: RoadGraph) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	for id: String in graph.intersection_ids():
		for other: String in graph.neighbours(id):
			# Each edge is visited from its lexicographically smaller endpoint, so
			# a street produces exactly one slab.
			if other < id:
				continue
			var street: Dictionary = graph.street_for(id, other)
			var from_pos: Vector3 = graph.position_of(id)
			var to_pos: Vector3 = graph.position_of(other)
			var kind: String = street["kind"]
			var width_m: float = street["width_m"]
			var extend_from: float = _junction_reach_m(graph, id)
			var extend_to: float = _junction_reach_m(graph, other)
			var span: Vector3 = to_pos - from_pos
			span.y = 0.0
			var street_length: float = span.length()
			var length_m: float = street_length + extend_from + extend_to
			var center: Vector3 = (from_pos + to_pos) * 0.5
			(
				segments
				. append(
					{
						"id": "%s__%s" % [id, other],
						"from": id,
						"to": other,
						"kind": kind,
						"center": center,
						"length_m": length_m,
						"width_m": width_m,
						"fillet_m": TurnEnvelope.corner_fillet_m(kind),
						"size": Vector3(length_m, ROAD_THICKNESS_M, width_m),
						"rotation_y": atan2(span.x, span.z),
					}
				)
			)
	return segments


static func junction_pads(graph: RoadGraph) -> Array[Dictionary]:
	var pads: Array[Dictionary] = []
	for id: String in graph.intersection_ids():
		var neighbours: PackedStringArray = graph.neighbours(id)
		if neighbours.size() < PAD_MIN_NEIGHBOURS:
			continue
		var widest_m: float = 0.0
		var fillet_m: float = 0.0
		for neighbour: String in neighbours:
			var street: Dictionary = graph.street_for(id, neighbour)
			widest_m = max(widest_m, street["width_m"])
			fillet_m = max(fillet_m, TurnEnvelope.corner_fillet_m(street["kind"]))
		(
			pads
			. append(
				{
					"id": id,
					"center": graph.position_of(id),
					"radius_m": widest_m * 0.5 + min(fillet_m, PAD_FILLET_CAP_M),
					"street_count": neighbours.size(),
				}
			)
		)
	return pads


static func _junction_reach_m(graph: RoadGraph, id: String) -> float:
	var widest_m: float = 0.0
	for neighbour: String in graph.neighbours(id):
		widest_m = max(widest_m, graph.street_for(id, neighbour)["width_m"])
	return widest_m * 0.5
