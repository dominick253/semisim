extends Node3D
## Scene-based combination harness: builds the ground, the CombinationController
## and both vehicle scenes at runtime (in _ready, inside the tree). Joints built
## during SceneTree._initialize() do not connect in Godot 4.7, so every
## combination test must be scene-based.

var controller: Node3D
var tractor: RigidBody3D
var trailer: RigidBody3D
var ticks: int = 0
var log_every: int = 60
var max_ticks: int = 600


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	log_every = int(args[0]) if args.size() > 0 else 60
	max_ticks = int(args[1]) if args.size() > 1 else 600
	var variant: String = args[2] if args.size() > 2 else "default"

	var floor_body := StaticBody3D.new()
	floor_body.name = "Ground"
	floor_body.collision_layer = 4
	floor_body.collision_mask = 3
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(300.0, 2.0, 300.0)
	fshape.shape = fbox
	fshape.position = Vector3(0.0, -1.0, 0.0)
	floor_body.add_child(fshape)
	add_child(floor_body)

	controller = load("res://scripts/vehicles/combination_controller.gd").new()
	controller.name = "Combination"
	var tractor_scene: Node3D = load("res://scenes/vehicles/tractor.tscn").instantiate()
	var trailer_scene: Node3D = load("res://scenes/vehicles/trailer.tscn").instantiate()
	tractor_scene.position = Vector3(0.0, 0.0, 0.0)
	trailer_scene.position = Vector3(0.0, 0.0, -1.0)
	# Children must exist before the controller enters the tree: _ready and
	# @onready resolve at enter time.
	controller.add_child(tractor_scene)
	controller.add_child(trailer_scene)
	add_child(controller)
	controller.place_at_rest()
	if variant == "pr_free":
		controller.joint.set("angular_limit_x/enabled", false)
		controller.joint.set("angular_limit_z/enabled", false)
	elif variant == "pr_small":
		for axis in ["x", "z"]:
			controller.joint.set("angular_limit_%s/enabled" % axis, true)
			controller.joint.set("angular_limit_%s/lower_angle" % axis, -deg_to_rad(3.0))
			controller.joint.set("angular_limit_%s/upper_angle" % axis, deg_to_rad(3.0))
	elif variant == "ang_off":
		for axis in ["x", "z"]:
			controller.joint.set("angular_limit_%s/enabled" % axis, false)
		controller.joint.set("angular_limit_y/enabled", false)
	elif variant == "defaults":
		for axis in ["x", "y", "z"]:
			controller.joint.set("linear_limit_%s/softness" % axis, 0.7)
			controller.joint.set("linear_limit_%s/damping" % axis, 1.0)
			controller.joint.set("linear_limit_%s/restitution" % axis, 0.5)
		for axis in ["x", "y", "z"]:
			controller.joint.set("angular_limit_%s/softness" % axis, 0.5)
			controller.joint.set("angular_limit_%s/force_limit" % axis, 1.0e12)
			controller.joint.set("angular_limit_%s/erp" % axis, 0.5)
	elif variant == "torque_cap":
		for axis in ["x", "z"]:
			controller.joint.set("angular_limit_%s/force_limit" % axis, 1.0e12)
	elif variant == "nojoint":
		controller.joint.queue_free()
	elif variant == "pin":
		controller.joint.free()
		var pin := PinJoint3D.new()
		controller.add_child(pin)
		pin.node_a = controller.tractor.get_path()
		pin.node_b = controller.trailer.get_path()
		pin.exclude_nodes_from_collision = true
		pin.global_position = (
			controller.tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
		)
		controller.joint = pin
	print("variant=", variant)
	tractor = controller.get_node("Tractor")
	trailer = controller.get_node("Trailer")
	print("harness ready: joint=", controller.joint, " tractor=", tractor, " trailer=", trailer)


func _physics_process(_delta: float) -> void:
	ticks += 1
	if ticks % log_every == 0:
		report()
	if ticks >= max_ticks:
		get_tree().quit()


func report() -> void:
	var sum_n: float = 0.0
	for w in controller.wheels:
		sum_n += w.normal_n
	var kp: Vector3 = trailer.global_transform * PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL
	var fw: Vector3 = tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	var weight: float = (tractor.mass + trailer.mass) * PHYSICS_CONSTANTS.GRAVITY_M_S2
	print(
		"T",
		ticks,
		" ty=",
		snappedf(tractor.global_position.y, 0.0001),
		" vy=",
		snappedf(trailer.global_position.y, 0.0001),
		" kp=",
		snappedf(kp.distance_to(fw), 0.001),
		" sumN=",
		snappedf(sum_n, 0.0),
		" ratio=",
		snappedf(sum_n / weight, 0.01),
		" speed=",
		snappedf(controller.speed(), 0.01),
		" pitch=",
		snappedf(tractor.rotation.x, 0.001),
		" roll=",
		snappedf(tractor.rotation.z, 0.001)
	)
