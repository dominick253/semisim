extends Node3D
## Which linear DOF does Godot-Jolt's Generic6DOFJoint3D actually enforce?
## Anchor rests on the ground. Hang has collision_mask 0: the joint is its only
## possible support. Hang is offset along ONE axis from the joint; if that axis
## is enforced, the hang must hold its height instead of free-falling.
## Modes: up | down | plus_x | plus_z | minus_x | minus_z

var anchor: RigidBody3D
var hang: RigidBody3D
var joint: Generic6DOFJoint3D
var ticks: int = 0
var mode: String = "up"


func _ready() -> void:
	mode = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "up"

	var ground := StaticBody3D.new()
	ground.collision_layer = 4
	ground.collision_mask = 0
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
	add_child(hang)

	match mode:
		"up":
			hang.position = Vector3(0.0, 6.0, 0.0)
		"down":
			hang.position = Vector3(0.0, -4.0, 0.0)
		"plus_x":
			hang.position = Vector3(5.0, 1.0, 0.0)
		"minus_x":
			hang.position = Vector3(-5.0, 1.0, 0.0)
		"plus_z":
			hang.position = Vector3(0.0, 1.0, 5.0)
		"minus_z":
			hang.position = Vector3(0.0, 1.0, -5.0)

	joint = Generic6DOFJoint3D.new()
	add_child(joint)
	joint.global_position = anchor.global_position
	joint.node_a = anchor.get_path()
	joint.node_b = hang.get_path()
	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, true)
		joint.set("linear_limit_%s/lower_distance" % axis, 0.0)
		joint.set("linear_limit_%s/upper_distance" % axis, 0.0)
		joint.set("angular_limit_%s/enabled" % axis, true)
		joint.set("angular_limit_%s/lower_angle" % axis, 0.0)
		joint.set("angular_limit_%s/upper_angle" % axis, 0.0)
	print("mode=", mode, " joint=", joint.global_position, " hang=", hang.position)


func _physics_process(_delta: float) -> void:
	ticks += 1
	if ticks % 20 == 0:
		print(
			"T",
			ticks,
			" a_y=",
			snappedf(anchor.global_position.y, 0.001),
			" h_pos=",
			snappedf(hang.global_position.x, 0.01),
			" ",
			snappedf(hang.global_position.y, 0.01),
			" ",
			snappedf(hang.global_position.z, 0.01),
			" h_vy=",
			snappedf(hang.linear_velocity.y, 0.01)
		)
	if ticks >= 100:
		get_tree().quit()
