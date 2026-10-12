extends GutTest
## Test yard geometry (section 7). Every dimension is asserted against
## PHYSICS_CONSTANTS so the scene cannot drift from the pinned meters.
## The yard is built by script from the constants, so a wrong constant or a
## wrong builder both show up here.

const YARD_SCENE: String = "res://scenes/world/test_yard.tscn"

var _yard: Node3D
var _bodies: Array = []  # [{name, aabb, layer, kind}]


func before_all() -> void:
	_yard = load(YARD_SCENE).instantiate()
	add_child(_yard)
	await get_tree().physics_frame
	_bodies = _collect_bodies(_yard)


func after_all() -> void:
	if is_instance_valid(_yard):
		_yard.queue_free()
		# queue_free is deferred; without a frame the yard and its children
		# outlive the script and GUT reports them as unfreed.
		await get_tree().physics_frame
		await get_tree().physics_frame


# --- helpers ---------------------------------------------------------------


func _collect_bodies(root: Node) -> Array:
	var out: Array = []
	for n in _all_descendants(root):
		if not (n is CollisionShape3D):
			continue
		var shape: CollisionShape3D = n
		if shape.disabled:
			continue
		var body_node: Node = shape.get_parent()
		(
			out
			. append(
				{
					"name": String(body_node.name),
					"aabb": _global_aabb(shape),
					"layer":
					int(body_node.collision_layer) if body_node is CollisionObject3D else 0,
					"shape": shape,
				}
			)
		)
	return out


func _all_descendants(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_all_descendants(child))
	return out


func _global_aabb(shape: CollisionShape3D) -> AABB:
	var local: AABB = _shape_aabb(shape.get_shape())
	var xform: Transform3D = shape.get_global_transform()
	var result := AABB(xform * local.position, Vector3.ZERO)
	for xi in [local.position.x, local.end.x]:
		for yi in [local.position.y, local.end.y]:
			for zi in [local.position.z, local.end.z]:
				result = result.expand(xform * Vector3(xi, yi, zi))
	return result


func _shape_aabb(shape: Shape3D) -> AABB:
	## Shape3D has no get_aabb in Godot 4.7; derive the local box from the
	## primitive parameters the yard actually uses.
	if shape is BoxShape3D:
		var size: Vector3 = (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is CylinderShape3D:
		var cyl: CylinderShape3D = shape
		var d: float = cyl.radius * 2.0
		return AABB(Vector3(-cyl.radius, -cyl.height * 0.5, -cyl.radius), Vector3(d, cyl.height, d))
	if shape is SphereShape3D:
		var r: float = (shape as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r * 2.0, r * 2.0, r * 2.0))
	push_error("unsupported shape for aabb probe: %s" % shape.get_class())
	return AABB()


func _find(kind: String) -> Dictionary:
	for b in _bodies:
		if b["name"] == kind:
			return b
	return {}


func _assert_span(
	b: Dictionary, min_x: float, max_x: float, min_z: float, max_z: float, label: String
) -> void:
	var a: AABB = b["aabb"]
	assert_almost_eq(a.position.x, min_x, 0.02, "%s west face" % label)
	assert_almost_eq(a.end.x, max_x, 0.02, "%s east face" % label)
	assert_almost_eq(a.position.z, min_z, 0.02, "%s south face" % label)
	assert_almost_eq(a.end.z, max_z, 0.02, "%s north face" % label)


# --- ground ----------------------------------------------------------------


func test_ground_is_flat_and_covers_the_yard() -> void:
	var g: Dictionary = _find("Ground")
	assert_false(g.is_empty(), "Ground body missing")
	var a: AABB = g["aabb"]
	assert_almost_eq(a.position.x, PHYSICS_CONSTANTS.YARD_MIN_X, 0.05, "ground west edge")
	assert_almost_eq(a.end.x, PHYSICS_CONSTANTS.YARD_MAX_X, 0.05, "ground east edge")
	assert_almost_eq(a.position.z, PHYSICS_CONSTANTS.YARD_MIN_Z, 0.05, "ground south edge")
	assert_almost_eq(a.end.z, PHYSICS_CONSTANTS.YARD_MAX_Z, 0.05, "ground north edge")
	# Everything flat: the playing surface is a single level plane at y = 0.
	assert_almost_eq(a.end.y, 0.0, 0.001, "ground surface height (flat, no crown)")
	assert_eq(int(g["layer"]), PHYSICS_CONSTANTS.LAYER_GROUND, "ground collision layer")


func test_ground_is_one_draw_call() -> void:
	var meshes: Array = []
	for n in _all_descendants(_yard):
		if n is MeshInstance3D and n.get_mesh() != null:
			meshes.append(n)
	assert_lte(
		meshes.size(),
		PHYSICS_CONSTANTS.YARD_DRAW_CALL_BUDGET,
		"yard static mesh count must stay under the draw-call budget"
	)


# --- perimeter walls -------------------------------------------------------


func test_walls_are_spec_height_and_thickness() -> void:
	for name in ["WallSouth", "WallWest", "WallEast", "WallNorthWest", "WallNorthMid"]:
		var b: Dictionary = _find(name)
		assert_false(b.is_empty(), "%s missing" % name)
		var a: AABB = b["aabb"]
		assert_almost_eq(a.size.y, PHYSICS_CONSTANTS.WALL_HEIGHT_M, 0.02, "%s height" % name)
		var thin: float = minf(a.size.x, a.size.z)
		assert_almost_eq(thin, PHYSICS_CONSTANTS.WALL_THICKNESS_M, 0.02, "%s thickness" % name)
		assert_eq(int(b["layer"]), PHYSICS_CONSTANTS.LAYER_STRUCTURES, "%s layer" % name)


func test_perimeter_closes_the_yard_bounds() -> void:
	# Every wall body sits outside the yard bounds, so its inner face is the
	# boundary-facing side: max z for the south wall, max x for the west wall,
	# min x for the east wall.
	var south: Dictionary = _find("WallSouth")
	assert_almost_eq(
		south["aabb"].end.z, PHYSICS_CONSTANTS.YARD_MIN_Z, 0.02, "south wall inner face"
	)
	var west: Dictionary = _find("WallWest")
	assert_almost_eq(west["aabb"].end.x, PHYSICS_CONSTANTS.YARD_MIN_X, 0.02, "west wall inner face")
	var east: Dictionary = _find("WallEast")
	assert_almost_eq(
		east["aabb"].position.x, PHYSICS_CONSTANTS.YARD_MAX_X, 0.02, "east wall inner face"
	)
	# North boundary: warehouse shell plus wall segments, with the alley gate open.
	assert_almost_eq(
		_find("WallNorthWest")["aabb"].end.x,
		PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST,
		0.02,
		"north wall stops at the alley gate west edge"
	)
	assert_almost_eq(
		_find("WallNorthMid")["aabb"].position.x,
		PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST,
		0.02,
		"north wall resumes at the alley gate east edge"
	)
	assert_almost_eq(
		_find("WallNorthMid")["aabb"].end.x,
		PHYSICS_CONSTANTS.WAREHOUSE_MIN_X,
		0.02,
		"north wall meets the warehouse west face"
	)


# --- warehouse and docks ---------------------------------------------------


func test_warehouse_shell_matches_the_spec_box() -> void:
	var w: Dictionary = _find("Warehouse")
	assert_false(w.is_empty(), "Warehouse body missing")
	_assert_span(
		w,
		PHYSICS_CONSTANTS.WAREHOUSE_MIN_X,
		PHYSICS_CONSTANTS.WAREHOUSE_MAX_X,
		PHYSICS_CONSTANTS.WAREHOUSE_MIN_Z,
		PHYSICS_CONSTANTS.WAREHOUSE_MAX_Z,
		"warehouse"
	)
	var a: AABB = w["aabb"]
	var expected_height: float = (
		PHYSICS_CONSTANTS.STORY_HEIGHT_M * PHYSICS_CONSTANTS.WAREHOUSE_STORIES
	)
	assert_almost_eq(a.size.y, expected_height, 0.02, "warehouse 4-story height")


func test_five_dock_bumpers_at_the_pinned_line() -> void:
	var found: int = 0
	for i in PHYSICS_CONSTANTS.DOCK_SLOT_CENTERS_X.size():
		var slot_x: float = float(PHYSICS_CONSTANTS.DOCK_SLOT_CENTERS_X[i])
		var b: Dictionary = _find("DockBumper%d" % (i + 1))
		if b.is_empty():
			continue
		found += 1
		var a: AABB = b["aabb"]
		assert_almost_eq(
			a.position.x + a.size.x * 0.5, slot_x, 0.02, "dock slot %d center x" % (i + 1)
		)
		assert_almost_eq(
			a.size.x, PHYSICS_CONSTANTS.DOCK_SLOT_WIDTH_M, 0.02, "dock slot %d width" % (i + 1)
		)
		# Bumper face sits on the pinned dock line, protruding into the yard.
		assert_almost_eq(
			a.position.z,
			PHYSICS_CONSTANTS.DOCK_BUMPER_Z,
			0.02,
			"dock slot %d bumper face z" % (i + 1)
		)
	assert_eq(found, PHYSICS_CONSTANTS.DOCK_SLOT_CENTERS_X.size(), "dock bumper count")


# --- alley -----------------------------------------------------------------


func test_alley_corridor_is_8_m_between_the_inner_faces() -> void:
	var west: Dictionary = _find("AlleyWallWest")
	var east: Dictionary = _find("AlleyWallEast")
	assert_false(west.is_empty(), "alley west wall missing")
	assert_false(east.is_empty(), "alley east wall missing")
	assert_almost_eq(
		west["aabb"].end.x, PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST, 0.02, "alley west inner face"
	)
	assert_almost_eq(
		east["aabb"].position.x, PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST, 0.02, "alley east inner face"
	)
	var width: float = PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST - PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST
	assert_almost_eq(
		east["aabb"].position.x - west["aabb"].end.x, width, 0.02, "alley corridor width"
	)
	assert_almost_eq(
		west["aabb"].size.x, PHYSICS_CONSTANTS.WALL_THICKNESS_M, 0.02, "alley west thickness"
	)
	# Corridor runs z -15..45 (60 m of reversing distance to the north gate line).
	_assert_span(
		west,
		PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST - PHYSICS_CONSTANTS.WALL_THICKNESS_M,
		PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST,
		PHYSICS_CONSTANTS.ALLEY_MIN_Z,
		PHYSICS_CONSTANTS.ALLEY_MAX_Z,
		"alley west wall"
	)


func test_alley_south_end_is_an_open_gate() -> void:
	# A ray straight north through the alley mouth must be clear at the south
	# gate and blocked only by the alley walls on the sides.
	assert_true(
		_ray_clear(Vector3(-36.0, 1.0, -25.0), Vector3(-36.0, 1.0, -14.0)),
		"alley south gate is blocked"
	)
	assert_false(
		_ray_clear(Vector3(-36.0, 1.0, -10.0), Vector3(-41.0, 1.0, -10.0)),
		"alley west wall does not block sideways escape"
	)


func test_north_gate_at_the_alley_mouth_is_open() -> void:
	# The alley challenge goal line is z = 45 at the alley center, so the north
	# boundary must be open there.
	assert_true(
		_ray_clear(Vector3(-36.0, 1.0, 40.0), Vector3(-36.0, 1.0, 48.0)),
		"north gate at the alley mouth is blocked"
	)
	assert_false(
		_ray_clear(Vector3(-55.0, 1.0, 40.0), Vector3(-55.0, 1.0, 48.0)),
		"north wall west of the gate is missing"
	)


# --- cones -----------------------------------------------------------------


func test_twelve_cones_at_the_exact_positions() -> void:
	var expected: Array = _expected_cone_positions()
	assert_eq(expected.size(), PHYSICS_CONSTANTS.CONE_COUNT, "expected cone count")
	var bodies: Array = []
	for n in _all_descendants(_yard):
		if n is StaticBody3D and String(n.name).begins_with("Cone"):
			bodies.append(n)
	assert_eq(bodies.size(), PHYSICS_CONSTANTS.CONE_COUNT, "cone physics body count")
	var positions: Array = []
	for b in bodies:
		positions.append((b as Node3D).global_position)
		# Every cone pillar must be grounded: its collider bottom on y = 0.
		var cs: CollisionShape3D = b.get_children().filter(func(c): return c is CollisionShape3D)[0]
		var a: AABB = _global_aabb(cs)
		assert_almost_eq(a.position.y, 0.0, 0.02, "%s collider grounded" % b.name)
	for want in expected:
		var hit: bool = false
		for got in positions:
			if (got as Vector3).distance_to(want as Vector3) < 0.02:
				hit = true
				break
		assert_true(hit, "cone missing at %s" % str(want))


func test_cones_are_instanced_with_multimesh() -> void:
	var instances: Array = []
	for n in _all_descendants(_yard):
		if n is MultiMeshInstance3D:
			instances.append(n)
	assert_eq(instances.size(), 1, "cones must be one instanced draw call")
	var mm: MultiMeshInstance3D = instances[0]
	assert_not_null(mm.multimesh, "cone MultiMesh missing")
	assert_eq(mm.multimesh.instance_count, PHYSICS_CONSTANTS.CONE_COUNT, "cone instances")
	# The instance transforms come from the yard's own pure placement function,
	# which is what the physics pillars are built from too. MultiMesh does not
	# allocate its CPU transform buffer under the headless dummy renderer, so the
	# placement is verified through that function and the colliders, not by
	# reading the buffer back.
	var script: GDScript = _yard.get_script()
	var placed: Array = script.cone_positions()
	assert_eq(placed.size(), PHYSICS_CONSTANTS.CONE_COUNT, "placement function count")
	var expected: Array = _expected_cone_positions()
	for i in expected.size():
		assert_lt(
			(placed[i] as Vector3).distance_to(expected[i] as Vector3),
			0.001,
			"placement function position %d" % i
		)


func test_cone_model_is_0p7_tall_with_0p36_base() -> void:
	var mesh: Mesh = null
	for n in _all_descendants(_yard):
		var mmi: MultiMeshInstance3D = n as MultiMeshInstance3D
		if mmi != null and mmi.multimesh != null and mmi.multimesh.mesh != null:
			mesh = mmi.multimesh.mesh
			break
	assert_not_null(mesh, "cone mesh missing")
	var a: AABB = mesh.get_aabb()
	assert_almost_eq(a.size.y, PHYSICS_CONSTANTS.CONE_HEIGHT_M, 0.02, "cone height")
	assert_almost_eq(a.size.x, PHYSICS_CONSTANTS.CONE_BASE_DIAMETER_M, 0.05, "cone base width")
	assert_almost_eq(a.size.z, PHYSICS_CONSTANTS.CONE_BASE_DIAMETER_M, 0.05, "cone base depth")


func test_cones_are_on_the_cone_layer_and_collidable() -> void:
	for n in _all_descendants(_yard):
		if n is StaticBody3D and String(n.name).begins_with("Cone"):
			var body: StaticBody3D = n
			assert_eq(
				int(body.collision_layer), PHYSICS_CONSTANTS.LAYER_CONES, "%s layer" % body.name
			)
			assert_true(
				(body.collision_mask & PHYSICS_CONSTANTS.LAYER_TRACTOR) != 0,
				"%s must collide with the tractor" % body.name
			)
			assert_true(
				(body.collision_mask & PHYSICS_CONSTANTS.LAYER_TRAILER) != 0,
				"%s must collide with the trailer" % body.name
			)


# --- staging pad and spawns ------------------------------------------------


func test_staging_pad_is_22x14_at_the_pinned_center() -> void:
	var pad: Node3D = _yard.get_node_or_null("StagingPad")
	assert_not_null(pad, "StagingPad marker missing")
	var mesh: MeshInstance3D = pad.get_node_or_null("Mesh")
	assert_not_null(mesh, "StagingPad mesh missing")
	var a: AABB = mesh.get_aabb()
	assert_almost_eq(a.size.x, PHYSICS_CONSTANTS.STAGING_PAD_WIDTH_X_M, 0.02, "pad width")
	assert_almost_eq(a.size.z, PHYSICS_CONSTANTS.STAGING_PAD_LENGTH_Z_M, 0.02, "pad length")
	assert_almost_eq(
		pad.global_position.x, PHYSICS_CONSTANTS.STAGING_PAD_CENTER.x, 0.02, "pad center x"
	)
	assert_almost_eq(
		pad.global_position.z, PHYSICS_CONSTANTS.STAGING_PAD_CENTER.z, 0.02, "pad center z"
	)


func test_all_four_spawns_are_inside_the_yard_and_clear() -> void:
	var spawns: Array = [
		PHYSICS_CONSTANTS.SPAWN_FREE_POS,
		PHYSICS_CONSTANTS.SPAWN_DOCK_POS,
		PHYSICS_CONSTANTS.SPAWN_ALLEY_POS,
		PHYSICS_CONSTANTS.SPAWN_SERPENTINE_POS,
	]
	for p in spawns:
		var pos: Vector3 = p
		assert_between(
			pos.x,
			PHYSICS_CONSTANTS.YARD_MIN_X,
			PHYSICS_CONSTANTS.YARD_MAX_X,
			"spawn %s inside yard x" % str(pos)
		)
		assert_between(
			pos.z,
			PHYSICS_CONSTANTS.YARD_MIN_Z,
			PHYSICS_CONSTANTS.YARD_MAX_Z,
			"spawn %s inside yard z" % str(pos)
		)
		# A spawn must not sit inside a structure: probe the tractor footprint.
		assert_true(_spawn_clear(pos), "spawn %s overlaps a structure" % str(pos))


func test_spawn_headings_are_pinned() -> void:
	assert_eq(int(PHYSICS_CONSTANTS.SPAWN_FREE_HEADING_DEG), 15, "free drive heading")
	assert_eq(int(PHYSICS_CONSTANTS.SPAWN_DOCK_HEADING_DEG), 180, "dock heading")
	assert_eq(int(PHYSICS_CONSTANTS.SPAWN_ALLEY_HEADING_DEG), 0, "alley heading")
	assert_eq(int(PHYSICS_CONSTANTS.SPAWN_SERPENTINE_HEADING_DEG), 0, "serpentine heading")


# --- lighting --------------------------------------------------------------


func test_one_directional_light_with_shadows() -> void:
	var lights: Array = []
	for n in _all_descendants(_yard):
		if n is DirectionalLight3D:
			lights.append(n)
	assert_eq(lights.size(), 1, "exactly one directional light")
	var sun: DirectionalLight3D = lights[0]
	assert_true(sun.shadow_enabled, "sun shadows must be enabled")
	assert_almost_eq(
		rad_to_deg(-sun.rotation.x), PHYSICS_CONSTANTS.SUN_ELEVATION_DEG, 1.0, "sun elevation"
	)
	assert_almost_eq(
		sun.directional_shadow_max_distance,
		PHYSICS_CONSTANTS.SUN_SHADOW_FADE_FROM_M,
		0.01,
		"shadow fade distance"
	)
	assert_eq(
		int(
			ProjectSettings.get_setting_with_override(
				"rendering/lights_and_shadows/directional_shadow/size"
			)
		),
		PHYSICS_CONSTANTS.SUN_SHADOW_MAP_SIZE,
		"directional shadow map size"
	)
	var env: WorldEnvironment = _yard.get_node_or_null("Environment")
	assert_not_null(env, "WorldEnvironment missing")
	assert_not_null(env.environment, "Environment resource missing")
	assert_not_null(env.environment.sky, "procedural sky missing")
	assert_true(
		env.environment.sky.sky_material is ProceduralSkyMaterial,
		"sky must use a ProceduralSkyMaterial"
	)


# --- internal helpers ------------------------------------------------------


func _expected_cone_positions() -> Array:
	var out: Array = []
	for i in PHYSICS_CONSTANTS.SERPENTINE_CONE_X.size():
		var x: float = float(PHYSICS_CONSTANTS.SERPENTINE_CONE_X[i])
		var z: float = PHYSICS_CONSTANTS.SERPENTINE_CONE_Z_ABS_M
		if i % 2 == 1:
			z = -z
		out.append(Vector3(x, PHYSICS_CONSTANTS.CONE_HEIGHT_M * 0.5, z))
	for x in PHYSICS_CONSTANTS.DOCK_CONE_X:
		for z in PHYSICS_CONSTANTS.DOCK_CONE_Z:
			out.append(Vector3(float(x), PHYSICS_CONSTANTS.CONE_HEIGHT_M * 0.5, float(z)))
	return out


func _ray_clear(from_v: Vector3, to_v: Vector3) -> bool:
	var space: PhysicsDirectSpaceState3D = _yard.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		from_v, to_v, PHYSICS_CONSTANTS.LAYER_STRUCTURES | PHYSICS_CONSTANTS.LAYER_CONES
	)
	return space.intersect_ray(query).is_empty()


func _spawn_clear(pos: Vector3) -> bool:
	## Probe a 2.6 x 2.6 m column at the spawn against structures and cones.
	var space: PhysicsDirectSpaceState3D = _yard.get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.4
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 1.0, 0.0))
	query.collision_mask = (PHYSICS_CONSTANTS.LAYER_STRUCTURES | PHYSICS_CONSTANTS.LAYER_CONES)
	query.collide_with_bodies = true
	query.collide_with_areas = false
	return space.intersect_shape(query, 8).is_empty()
