extends Node3D
## Does Generic6DOFJoint3D lock ANGULAR DOF on Jolt? Default angular_limit_*/
## force_limit is 0.0, which may mean the constraint may apply zero torque.
## Hang CoM sits 5 m behind the joint and hang has collision_mask 0, so an
## enforced angular X lock is the ONLY thing that can keep the hang level.
## Modes: fl_zero | fl_big | fl_mid

var anchor: RigidBody3D
var hang: RigidBody3D
var joint: Generic6DOFJoint3D
var ticks: int = 0
var force_limit: float = 0.0


func _ready() -> void:
	var mode: String = (
		OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "fl_zero"
	)
	match mode:
		"fl_big":
			force_limit = 1.0e9
		"fl_mid":
			force_limit = 1.0e6
		_:
			force_limit = 0.0

	var ground := StaticBody3D.new()
	ground.collision_layer = 4
	ground.collision_mask = 3
	var gshape := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(100.0, 2.0, 100.0)
	gshape.shape = gbox
	gshape.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(gshape)
	add_child(ground)

	anchor = RigidBody3D.new()
	anchor.mass = 8400.0
	anchor.collision_layer = 1
	anchor.collision_mask = 4
	anchor.position = Vector3(0.0, 1.0, 0.0)
	var ashape := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(2.5, 2.0, 6.0)
	ashape.shape = abox
	anchor.add_child(ashape)
	add_child(anchor)

	hang = RigidBody3D.new()
	hang.mass = 27000.0
	hang.collision_layer = 2
	hang.collision_mask = 0
	hang.position = Vector3(0.0, 1.0, -6.0)
	var hshape := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(2.5, 2.0, 8.0)
	hshape.shape = hbox
	hang.add_child(hshape)
	add_child(hang)

	joint = Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_position = Vector3(0.0, 1.0, -1.0)
	joint.node_a = anchor.get_path()
	joint.node_b = hang.get_path()
	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, true)
		joint.set("linear_limit_%s/lower_distance" % axis, 0.0)
		joint.set("linear_limit_%s/upper_distance" % axis, 0.0)
	for axis in ["x", "z"]:
		joint.set("angular_limit_%s/enabled" % axis, true)
		joint.set("angular_limit_%s/lower_angle" % axis, 0.0)
		joint.set("angular_limit_%s/upper_angle" % axis, 0.0)
		joint.set("angular_limit_%s/force_limit" % axis, force_limit)
	print("force_limit=", force_limit)


func _physics_process(_delta: float) -> void:
	ticks += 1
	if ticks % 20 == 0:
		print(
			"T",
			ticks,
			" h_y=",
			snappedf(hang.global_position.y, 0.001),
			" h_rot_x=",
			snappedf(hang.rotation_degrees.x, 0.01),
			" a_rot_x=",
			snappedf(anchor.rotation_degrees.x, 0.01),
			" a_y=",
			snappedf(anchor.global_position.y, 0.001)
		)
	if ticks >= 120:
		get_tree().quit()
