extends Node3D
## Test yard (section 7). The whole yard is built from PHYSICS_CONSTANTS at
## runtime so every dimension is traceable to the pinned source of truth and no
## coordinate can drift into a hand-authored scene file. Everything is flat: the
## playing surface is one level plane at y = 0 (DEVIATIONS D24).
##
## Draw calls (section 7 budget 80): 15 static meshes. The 12 cones are one
## MultiMeshInstance3D; their collision is 12 thin StaticBody3D pillars.

const MAT_ASPHALT: String = "asphalt"
const MAT_CONCRETE: String = "concrete"
const MAT_PAD: String = "pad"
const MAT_WALL: String = "wall"
const MAT_CONE: String = "cone"

var _materials: Dictionary = {}


func _ready() -> void:
	_build_materials()
	_build_environment()
	_build_ground()
	_build_walls()
	_build_warehouse_and_docks()
	_build_alley()
	_build_staging_pad()
	_build_cones()
	_build_spawns()


# ---------------------------------------------------------------------------
# Geometry
# ---------------------------------------------------------------------------


func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = PHYSICS_CONSTANTS.LAYER_GROUND
	# Godot 4 collision is mutual: a static body only collides with a vehicle
	# that its own mask names. Ground must mask both vehicle layers.
	body.collision_mask = (PHYSICS_CONSTANTS.LAYER_TRACTOR | PHYSICS_CONSTANTS.LAYER_TRAILER)
	_add_box_collider(body, _yard_size(), _ground_center(_yard_size()))
	add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "GroundMesh"
	var box := BoxMesh.new()
	box.size = _yard_size()
	mesh.mesh = box
	mesh.position = _ground_center(_yard_size())
	mesh.material_override = _mat(MAT_ASPHALT)
	body.add_child(mesh)


func _build_walls() -> void:
	var t: float = PHYSICS_CONSTANTS.WALL_THICKNESS_M
	var h: float = PHYSICS_CONSTANTS.WALL_HEIGHT_M
	# Wall bodies sit outside the yard bounds so every inner face lands exactly
	# on a pinned boundary coordinate (the drivable area is the full 140 x 90).
	_add_wall(
		"WallSouth",
		Vector3(PHYSICS_CONSTANTS.YARD_MIN_X - t, 0.0, PHYSICS_CONSTANTS.YARD_MIN_Z - t),
		Vector3(PHYSICS_CONSTANTS.YARD_MAX_X + t, h, PHYSICS_CONSTANTS.YARD_MIN_Z)
	)
	_add_wall(
		"WallWest",
		Vector3(PHYSICS_CONSTANTS.YARD_MIN_X - t, 0.0, PHYSICS_CONSTANTS.YARD_MIN_Z - t),
		Vector3(PHYSICS_CONSTANTS.YARD_MIN_X, h, PHYSICS_CONSTANTS.YARD_MAX_Z + t)
	)
	_add_wall(
		"WallEast",
		Vector3(PHYSICS_CONSTANTS.YARD_MAX_X, 0.0, PHYSICS_CONSTANTS.YARD_MIN_Z - t),
		Vector3(PHYSICS_CONSTANTS.YARD_MAX_X + t, h, PHYSICS_CONSTANTS.YARD_MAX_Z + t)
	)
	# North boundary, broken open at the alley gate (x -40..-32) and closed by
	# the warehouse shell from x -20 eastward.
	_add_wall(
		"WallNorthWest",
		Vector3(PHYSICS_CONSTANTS.YARD_MIN_X - t, 0.0, PHYSICS_CONSTANTS.YARD_MAX_Z),
		Vector3(PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST, h, PHYSICS_CONSTANTS.YARD_MAX_Z + t)
	)
	_add_wall(
		"WallNorthMid",
		Vector3(PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST, 0.0, PHYSICS_CONSTANTS.YARD_MAX_Z),
		Vector3(PHYSICS_CONSTANTS.WAREHOUSE_MIN_X, h, PHYSICS_CONSTANTS.YARD_MAX_Z + t)
	)


func _build_warehouse_and_docks() -> void:
	var height: float = PHYSICS_CONSTANTS.STORY_HEIGHT_M * PHYSICS_CONSTANTS.WAREHOUSE_STORIES
	var body := StaticBody3D.new()
	body.name = "Warehouse"
	body.collision_layer = PHYSICS_CONSTANTS.LAYER_STRUCTURES
	body.collision_mask = PHYSICS_CONSTANTS.LAYER_VEHICLE_MASK
	body.add_to_group("building")
	var size := Vector3(
		PHYSICS_CONSTANTS.WAREHOUSE_MAX_X - PHYSICS_CONSTANTS.WAREHOUSE_MIN_X,
		height,
		PHYSICS_CONSTANTS.WAREHOUSE_MAX_Z - PHYSICS_CONSTANTS.WAREHOUSE_MIN_Z
	)
	_add_box_collider(
		body,
		size,
		_mid_of_box(
			Vector3(PHYSICS_CONSTANTS.WAREHOUSE_MIN_X, 0.0, PHYSICS_CONSTANTS.WAREHOUSE_MIN_Z), size
		)
	)
	add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(MAT_CONCRETE)
	body.add_child(mesh)

	# Dock slots B1..B5: a 4.0 m wide bumper block protruding into the yard with
	# its face on the pinned dock line z = 44.8.
	for i in PHYSICS_CONSTANTS.DOCK_SLOT_CENTERS_X.size():
		var slot_x: float = float(PHYSICS_CONSTANTS.DOCK_SLOT_CENTERS_X[i])
		var half_w: float = PHYSICS_CONSTANTS.DOCK_SLOT_WIDTH_M * 0.5
		var bumper := StaticBody3D.new()
		bumper.name = "DockBumper%d" % (i + 1)
		bumper.collision_layer = PHYSICS_CONSTANTS.LAYER_STRUCTURES
		bumper.collision_mask = 0
		bumper.add_to_group("building")
		var bmin := Vector3(slot_x - half_w, 0.0, PHYSICS_CONSTANTS.DOCK_BUMPER_Z)
		var bsize := Vector3(
			PHYSICS_CONSTANTS.DOCK_SLOT_WIDTH_M,
			1.2,
			(
				PHYSICS_CONSTANTS.WAREHOUSE_MIN_Z
				- PHYSICS_CONSTANTS.DOCK_BUMPER_Z
				+ PHYSICS_CONSTANTS.WALL_THICKNESS_M
			)
		)
		_add_box_collider(bumper, bsize, _mid_of_box(bmin, bsize))
		add_child(bumper)
		var bmesh := MeshInstance3D.new()
		bmesh.name = "Mesh"
		var bbox := BoxMesh.new()
		bbox.size = bsize
		bmesh.mesh = bbox
		bmesh.material_override = _mat(MAT_CONCRETE)
		bumper.add_child(bmesh)


func _build_alley() -> void:
	var t: float = PHYSICS_CONSTANTS.WALL_THICKNESS_M
	var h: float = PHYSICS_CONSTANTS.WALL_HEIGHT_M
	_add_wall(
		"AlleyWallWest",
		Vector3(PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST - t, 0.0, PHYSICS_CONSTANTS.ALLEY_MIN_Z),
		Vector3(PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST, h, PHYSICS_CONSTANTS.ALLEY_MAX_Z)
	)
	_add_wall(
		"AlleyWallEast",
		Vector3(PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST, 0.0, PHYSICS_CONSTANTS.ALLEY_MIN_Z),
		Vector3(PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST + t, h, PHYSICS_CONSTANTS.ALLEY_MAX_Z)
	)


func _build_staging_pad() -> void:
	var pad := Node3D.new()
	pad.name = "StagingPad"
	pad.position = PHYSICS_CONSTANTS.STAGING_PAD_CENTER
	add_child(pad)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = Vector3(
		PHYSICS_CONSTANTS.STAGING_PAD_WIDTH_X_M, 0.02, PHYSICS_CONSTANTS.STAGING_PAD_LENGTH_Z_M
	)
	mesh.mesh = box
	mesh.position = Vector3(0.0, 0.011, 0.0)
	mesh.material_override = _mat(MAT_PAD)
	pad.add_child(mesh)


func _build_cones() -> void:
	var positions: Array[Vector3] = cone_positions()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = PHYSICS_CONSTANTS.CONE_BASE_DIAMETER_M * 0.5
	mesh.height = PHYSICS_CONSTANTS.CONE_HEIGHT_M

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = positions.size()
	for i in positions.size():
		var basis := Basis.IDENTITY.scaled(Vector3.ONE)
		multimesh.set_instance_transform(i, Transform3D(basis, positions[i]))
	var instance := MultiMeshInstance3D.new()
	instance.name = "Cones"
	instance.multimesh = multimesh
	instance.material_override = _mat(MAT_CONE)
	add_child(instance)

	# Collision: one thin static pillar per cone so contact counting works
	# exactly (DEVIATIONS D19 counts contacts, it does not ray-test visuals).
	for i in positions.size():
		var body := StaticBody3D.new()
		body.name = "Cone%02d" % i
		body.collision_layer = PHYSICS_CONSTANTS.LAYER_CONES
		body.collision_mask = PHYSICS_CONSTANTS.LAYER_VEHICLE_MASK
		body.add_to_group("cone")
		body.position = positions[i]
		var shape_node := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = PHYSICS_CONSTANTS.CONE_BASE_DIAMETER_M * 0.5
		cyl.height = PHYSICS_CONSTANTS.CONE_HEIGHT_M
		shape_node.shape = cyl
		body.add_child(shape_node)
		add_child(body)


func _build_spawns() -> void:
	var spawns: Array[Dictionary] = [
		{
			"name": "SpawnFree",
			"pos": PHYSICS_CONSTANTS.SPAWN_FREE_POS,
			"heading": PHYSICS_CONSTANTS.SPAWN_FREE_HEADING_DEG
		},
		{
			"name": "SpawnDock",
			"pos": PHYSICS_CONSTANTS.SPAWN_DOCK_POS,
			"heading": PHYSICS_CONSTANTS.SPAWN_DOCK_HEADING_DEG
		},
		{
			"name": "SpawnAlley",
			"pos": PHYSICS_CONSTANTS.SPAWN_ALLEY_POS,
			"heading": PHYSICS_CONSTANTS.SPAWN_ALLEY_HEADING_DEG
		},
		{
			"name": "SpawnSerpentine",
			"pos": PHYSICS_CONSTANTS.SPAWN_SERPENTINE_POS,
			"heading": PHYSICS_CONSTANTS.SPAWN_SERPENTINE_HEADING_DEG
		},
	]
	for s in spawns:
		var node := Node3D.new()
		node.name = String(s["name"])
		node.position = s["pos"] as Vector3
		node.rotation_degrees = Vector3(0.0, float(s["heading"]), 0.0)
		add_child(node)


# ---------------------------------------------------------------------------
# Lighting and environment (section 7)
# ---------------------------------------------------------------------------


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.34, 0.52, 0.78)
	sky_mat.sky_horizon_color = Color(0.66, 0.72, 0.80)
	sky_mat.ground_bottom_color = Color(0.20, 0.20, 0.22)
	sky_mat.ground_horizon_color = Color(0.66, 0.72, 0.80)
	sky.sky_material = sky_mat
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# 10:30 sun: 45 deg elevation, azimuth toward the south-west of the yard.
	sun.rotation_degrees = Vector3(-PHYSICS_CONSTANTS.SUN_ELEVATION_DEG, 35.0, 0.0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = PHYSICS_CONSTANTS.SUN_SHADOW_FADE_FROM_M
	sun.directional_shadow_fade_start = PHYSICS_CONSTANTS.SUN_SHADOW_FADE_FROM_M * 0.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)


# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------


func _build_materials() -> void:
	_materials[MAT_ASPHALT] = _make_albedo_material(Color(0.22, 0.22, 0.24))
	_materials[MAT_CONCRETE] = _make_albedo_material(Color(0.62, 0.62, 0.60))
	_materials[MAT_PAD] = _make_albedo_material(Color(0.75, 0.62, 0.12))
	_materials[MAT_WALL] = _make_albedo_material(Color(0.45, 0.46, 0.48))
	_materials[MAT_CONE] = _make_albedo_material(Color(0.90, 0.32, 0.05))


func _make_albedo_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	m.metallic = 0.0
	return m


func _mat(key: String) -> StandardMaterial3D:
	return _materials[key] as StandardMaterial3D


func _yard_size() -> Vector3:
	return Vector3(
		PHYSICS_CONSTANTS.YARD_MAX_X - PHYSICS_CONSTANTS.YARD_MIN_X,
		1.0,
		PHYSICS_CONSTANTS.YARD_MAX_Z - PHYSICS_CONSTANTS.YARD_MIN_Z
	)


func _ground_center(size: Vector3) -> Vector3:
	## Ground slab whose top face sits exactly on the y = 0 playing plane, so the
	## pinned spawn and axle heights are measured from the surface itself.
	return Vector3(0.0, -size.y * 0.5, 0.0)


func _mid_of_box(min_corner: Vector3, size: Vector3) -> Vector3:
	return min_corner + size * 0.5


func _add_box_collider(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = center
	body.add_child(shape_node)


func _add_wall(wall_name: String, min_corner: Vector3, max_corner: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = PHYSICS_CONSTANTS.LAYER_STRUCTURES
	body.collision_mask = PHYSICS_CONSTANTS.LAYER_VEHICLE_MASK
	body.add_to_group("wall")
	var size := max_corner - min_corner
	_add_box_collider(body, size, _mid_of_box(min_corner, size))
	add_child(body)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _mat(MAT_WALL)
	body.add_child(mesh)


## Cone positions (section 7): 8 serpentine cones at the pinned x values with z
## alternating +2 / -2, plus 4 cones at the dock B3 corners.
static func cone_positions() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var half_height: float = PHYSICS_CONSTANTS.CONE_HEIGHT_M * 0.5
	for i in PHYSICS_CONSTANTS.SERPENTINE_CONE_X.size():
		var z: float = PHYSICS_CONSTANTS.SERPENTINE_CONE_Z_ABS_M
		if i % 2 == 1:
			z = -z
		out.append(Vector3(float(PHYSICS_CONSTANTS.SERPENTINE_CONE_X[i]), half_height, z))
	for x in PHYSICS_CONSTANTS.DOCK_CONE_X:
		for z in PHYSICS_CONSTANTS.DOCK_CONE_Z:
			out.append(Vector3(float(x), half_height, float(z)))
	return out
