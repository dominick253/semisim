class_name RoadGraph
## Data driven road network for Phase 2 (docs/world-spec.md). The graph is pure
## data: intersections, streets, widths, kinds. Collision geometry is built from
## it by CityBuilder, never the other way round.
##
## is_fully_connected is named that way on purpose: Object.is_connected is a
## signal-introspection method on every RefCounted, and GDScript resolves the
## base member first, which is a parse error rather than an override.
##
## Everything here is deterministic by construction: fixed iteration order,
## sorted neighbour lists, and a Dijkstra that breaks distance ties by
## intersection id. No RNG anywhere, because route generation is asserted
## identical across runs in tests/unit/test_road_graph.gd.

const INF: float = 1.0e12
const EPS: float = 1.0e-9

var _positions: Dictionary = {}
var _ids: PackedStringArray = []
var _streets: Dictionary = {}
var _adjacency: Dictionary = {}
var _destinations: PackedStringArray = []
var _spawn_id: String = ""


func add_intersection(id: String, position: Vector3) -> void:
	if not _positions.has(id):
		_ids.append(id)
		_adjacency[id] = PackedStringArray()
	_positions[id] = position


func add_street(from_id: String, to_id: String, width_m: float, kind: String) -> void:
	if from_id == to_id:
		return
	if not _positions.has(from_id) or not _positions.has(to_id):
		return
	var key: String = _key(from_id, to_id)
	if _streets.has(key):
		return
	var from_pos: Vector3 = _positions[from_id]
	var to_pos: Vector3 = _positions[to_id]
	_streets[key] = {
		"from": from_id,
		"to": to_id,
		"kind": kind,
		"width_m": width_m,
		"length_m": from_pos.distance_to(to_pos),
	}
	_link(from_id, to_id)
	_link(to_id, from_id)


func mark_destination(id: String) -> void:
	if not _destinations.has(id):
		_destinations.append(id)


func set_spawn(id: String) -> void:
	_spawn_id = id


func spawn_id() -> String:
	return _spawn_id


func destinations() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_destinations)
	out.sort()
	return out


func intersection_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray(_ids)
	out.sort()
	return out


func position_of(id: String) -> Vector3:
	if _positions.has(id):
		return _positions[id]
	return Vector3.INF


func neighbours(id: String) -> PackedStringArray:
	if not _adjacency.has(id):
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray(_adjacency[id])
	out.sort()
	return out


func street_for(from_id: String, to_id: String) -> Dictionary:
	return _streets.get(_key(from_id, to_id), {})


func total_length_m() -> float:
	var total: float = 0.0
	for key: String in _streets:
		total += _streets[key]["length_m"]
	return total


func is_fully_connected() -> bool:
	if _ids.is_empty():
		return false
	var seen: Dictionary = {}
	var queue: PackedStringArray = PackedStringArray([_ids[0]])
	seen[_ids[0]] = true
	var head: int = 0
	while head < queue.size():
		var current: String = queue[head]
		head += 1
		for next_id: String in neighbours(current):
			if not seen.has(next_id):
				seen[next_id] = true
				queue.append(next_id)
	return seen.size() == _ids.size()


func shortest_path(from_id: String, to_id: String) -> PackedStringArray:
	if not _positions.has(from_id) or not _positions.has(to_id):
		return PackedStringArray()
	var dist: Dictionary = {}
	var prev: Dictionary = {}
	var visited: Dictionary = {}
	for id: String in _ids:
		dist[id] = INF
	dist[from_id] = 0.0
	while true:
		var current: String = _closest_unvisited(dist, visited)
		if current == "" or dist[current] >= INF:
			break
		if current == to_id:
			break
		visited[current] = true
		for next_id: String in neighbours(current):
			if visited.has(next_id):
				continue
			var street: Dictionary = street_for(current, next_id)
			var candidate: float = dist[current] + street["length_m"]
			if _is_better(candidate, dist[next_id], current, next_id, prev):
				dist[next_id] = candidate
				prev[next_id] = current
	if to_id != from_id and not prev.has(to_id):
		return PackedStringArray()
	return _reconstruct(prev, from_id, to_id)


func route_length_m(route: PackedStringArray) -> float:
	var total: float = 0.0
	for i: int in range(route.size() - 1):
		var street: Dictionary = street_for(route[i], route[i + 1])
		if street.is_empty():
			return -1.0
		total += street["length_m"]
	return total


func route_is_drivable(route: PackedStringArray) -> bool:
	if route.size() < 2:
		return false
	for i: int in range(1, route.size() - 1):
		var inbound: Dictionary = street_for(route[i - 1], route[i])
		var outbound: Dictionary = street_for(route[i], route[i + 1])
		if inbound.is_empty() or outbound.is_empty():
			return false
		var angle: float = TurnEnvelope.turn_angle_deg(
			position_of(route[i - 1]), position_of(route[i]), position_of(route[i + 1])
		)
		if angle <= TurnEnvelope.STRAIGHT_ANGLE_DEG:
			continue
		if not TurnEnvelope.junction_fits(
			inbound["kind"], inbound["width_m"], outbound["kind"], outbound["width_m"]
		):
			return false
	return true


static func town_profile_ids() -> PackedStringArray:
	return WorldConstants.TOWN_PROFILES


static func build_city() -> RoadGraph:
	var graph: RoadGraph = RoadGraph.new()
	var cols: int = WorldConstants.CITY_COLS
	var rows: int = WorldConstants.CITY_ROWS
	for c: int in cols:
		for r: int in rows:
			graph.add_intersection(
				_grid_id(c, r),
				_grid_pos(
					c, r, cols, rows, WorldConstants.CITY_BLOCK_W_M, WorldConstants.CITY_BLOCK_H_M
				)
			)
	for c: int in range(cols - 1):
		for r: int in rows:
			var row_kind: String = _kind_for_index(r)
			graph.add_street(
				_grid_id(c, r), _grid_id(c + 1, r), TurnEnvelope.street_width_m(row_kind), row_kind
			)
	for c: int in cols:
		for r: int in range(rows - 1):
			var col_kind: String = _kind_for_index(c)
			graph.add_street(
				_grid_id(c, r), _grid_id(c, r + 1), TurnEnvelope.street_width_m(col_kind), col_kind
			)
	_add_city_alleys(graph)
	graph.set_spawn(_grid_id(0, 0))
	for c: int in range(0, cols, WorldConstants.ARTERIAL_EVERY_N):
		graph.mark_destination(_grid_id(c, rows - 1))
	return graph


static func build_town(profile_id: String) -> RoadGraph:
	var graph: RoadGraph = RoadGraph.new()
	var cols: int = WorldConstants.TOWN_COLS
	var rows: int = WorldConstants.TOWN_ROWS
	for c: int in cols:
		for r: int in rows:
			graph.add_intersection(
				_grid_id(c, r),
				_grid_pos(
					c, r, cols, rows, WorldConstants.TOWN_BLOCK_W_M, WorldConstants.TOWN_BLOCK_H_M
				)
			)
	for c: int in range(cols - 1):
		for r: int in rows:
			var kind: String = "arterial" if r == 0 or r == rows - 1 else "local"
			graph.add_street(
				_grid_id(c, r), _grid_id(c + 1, r), TurnEnvelope.street_width_m(kind), kind
			)
	for c: int in cols:
		for r: int in range(rows - 1):
			var kind: String = "arterial" if c == 0 or c == cols - 1 else "local"
			graph.add_street(
				_grid_id(c, r), _grid_id(c, r + 1), TurnEnvelope.street_width_m(kind), kind
			)
	# gdtoolkit 4.5.0, the version CI pins, cannot parse the integer division
	# operator, so halves are computed as scaled ints.
	var half_cols: int = int(cols * 0.5)
	var half_rows: int = int(rows * 0.5)
	var hub: String = _grid_id(half_cols, half_rows)
	var farm: String = "farm_" + profile_id
	var anchor: String = _grid_id(cols - 1, half_rows)
	graph.add_intersection(
		farm,
		Vector3(
			(cols - 1) * 0.5 * WorldConstants.TOWN_BLOCK_W_M + WorldConstants.FARM_APPROACH_M,
			0.0,
			0.0
		)
	)
	graph.add_street(anchor, farm, TurnEnvelope.street_width_m("local"), "route")
	graph.set_spawn(_grid_id(0, 0))
	graph.mark_destination(hub)
	graph.mark_destination(farm)
	return graph


static func _add_city_alleys(graph: RoadGraph) -> void:
	var cols: int = WorldConstants.CITY_COLS
	var rows: int = WorldConstants.CITY_ROWS
	var alley_width: float = WorldConstants.STREET_WIDTH_M["alley"]
	for c: int in range(cols - 1):
		for r: int in range(rows - 1):
			var west: String = "gate_%s_w" % _block_id(c, r)
			var east: String = "gate_%s_e" % _block_id(c, r)
			var mid_z: float = (
				0.5
				* (
					(
						_grid_pos(
							c,
							r,
							cols,
							rows,
							WorldConstants.CITY_BLOCK_W_M,
							WorldConstants.CITY_BLOCK_H_M
						)
						. z
					)
					+ (
						_grid_pos(
							c,
							r + 1,
							cols,
							rows,
							WorldConstants.CITY_BLOCK_W_M,
							WorldConstants.CITY_BLOCK_H_M
						)
						. z
					)
				)
			)
			graph.add_intersection(
				west, Vector3((c - 0.5 * (cols - 1)) * WorldConstants.CITY_BLOCK_W_M, 0.0, mid_z)
			)
			graph.add_intersection(
				east,
				Vector3((c + 1 - 0.5 * (cols - 1)) * WorldConstants.CITY_BLOCK_W_M, 0.0, mid_z)
			)
			graph.add_street(west, east, alley_width, "alley")
			graph.add_street(
				west,
				_grid_id(c, r),
				TurnEnvelope.street_width_m(_kind_for_index(c)),
				_kind_for_index(c)
			)
			graph.add_street(
				west,
				_grid_id(c, r + 1),
				TurnEnvelope.street_width_m(_kind_for_index(c)),
				_kind_for_index(c)
			)
			graph.add_street(
				east,
				_grid_id(c + 1, r),
				TurnEnvelope.street_width_m(_kind_for_index(c + 1)),
				_kind_for_index(c + 1)
			)
			graph.add_street(
				east,
				_grid_id(c + 1, r + 1),
				TurnEnvelope.street_width_m(_kind_for_index(c + 1)),
				_kind_for_index(c + 1)
			)


static func _grid_id(c: int, r: int) -> String:
	return "c%d_r%d" % [c, r]


static func _block_id(c: int, r: int) -> String:
	return "b%d_r%d" % [c, r]


static func _grid_pos(
	c: int, r: int, cols: int, rows: int, block_w: float, block_h: float
) -> Vector3:
	return Vector3((c - 0.5 * (cols - 1)) * block_w, 0.0, (r - 0.5 * (rows - 1)) * block_h)


static func _kind_for_index(index: int) -> String:
	var phase: int = index % WorldConstants.ARTERIAL_EVERY_N
	if phase == 0:
		return "arterial"
	if phase == 1:
		return "local"
	return "tight"


func _link(a: String, b: String) -> void:
	# PackedStringArray is a packed value type: reading it out of a Dictionary
	# returns a copy, so the mutated copy has to be written back or the edge is
	# silently lost.
	var list: PackedStringArray = PackedStringArray(_adjacency[a])
	list.append(b)
	_adjacency[a] = list


func _key(a: String, b: String) -> String:
	if a < b:
		return a + "|" + b
	return b + "|" + a


func _closest_unvisited(dist: Dictionary, visited: Dictionary) -> String:
	var best: String = ""
	var best_dist: float = INF
	for id: String in _ids:
		if visited.has(id):
			continue
		if dist[id] < best_dist - EPS:
			best_dist = dist[id]
			best = id
		elif absf(dist[id] - best_dist) <= EPS and id < best:
			best = id
	return best


func _is_better(
	candidate: float, current: float, via: String, next_id: String, prev: Dictionary
) -> bool:
	if candidate < current - EPS:
		return true
	if absf(candidate - current) <= EPS:
		if not prev.has(next_id):
			return true
		return via < prev[next_id]
	return false


func _reconstruct(prev: Dictionary, from_id: String, to_id: String) -> PackedStringArray:
	var path: PackedStringArray = PackedStringArray([to_id])
	var current: String = to_id
	while current != from_id:
		if not prev.has(current):
			return PackedStringArray()
		current = prev[current]
		path.append(current)
	path.reverse()
	return path
