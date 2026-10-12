extends Node3D
## Why does Generic6DOFJoint3D not hold a dynamic body?
## Hypothesis: limit softness default is 1.0 (fully soft) in Godot-Jolt.
## Hang has collision_mask 0, so the joint is its only possible support.

var anchor: RigidBody3D
var hang: RigidBody3D
var joint: Joint3D
var ticks: int = 0
var mode: String = "defaults"


func _ready() -> void:
	mode = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "defaults"

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
	hang.position = Vector3(0.0, 1.0, -6.0)
	var hshape := CollisionShape3D.new()
	var hbox := BoxShape3D.new()
	hbox.size = Vector3(2.5, 2.0, 8.0)
	hshape.shape = hbox
	hang.add_child(hshape)
	add_child(hang)

	var g := Generic6DOFJoint3D.new()
	add_child(g)
	g.global_position = anchor.position + Vector3(0.0, 0.0, -1.0)
	g.node_a = anchor.get_path()
	g.node_b = hang.get_path()
	joint = g

	print(
		"DEFAULTS lin_y: enabled=",
		g.get("linear_limit_y/enabled"),
		" lower=",
		g.get("linear_limit_y/lower_distance"),
		" upper=",
		g.get("linear_limit_y/upper_distance"),
		" softness=",
		g.get("linear_limit_y/softness"),
		" damping=",
		g.get("linear_limit_y/damping"),
		" restitution=",
		g.get("linear_limit_y/restitution")
	)
	print(
		"DEFAULTS ang_y: enabled=",
		g.get("angular_limit_y/enabled"),
		" lower=",
		g.get("angular_limit_y/lower_angle"),
		" upper=",
		g.get("angular_limit_y/upper_angle"),
		" softness=",
		g.get("angular_limit_y/softness"),
		" force_limit=",
		g.get("angular_limit_y/force_limit"),
		" erp=",
		g.get("angular_limit_y/erp")
	)

	if mode == "defaults":
		pass  # leave limits disabled entirely (engine defaults)
	elif mode == "hard":
		for axis in ["x", "y", "z"]:
			g.set("linear_limit_%s/enabled" % axis, true)
			g.set("linear_limit_%s/lower_distance" % axis, 0.0)
			g.set("linear_limit_%s/upper_distance" % axis, 0.0)
			g.set("linear_limit_%s/softness" % axis, 0.0)
			g.set("linear_limit_%s/damping" % axis, 0.0)
			g.set("linear_limit_%s/restitution" % axis, 0.0)
	elif mode == "soft":
		for axis in ["x", "y", "z"]:
			g.set("linear_limit_%s/enabled" % axis, true)
			g.set("linear_limit_%s/lower_distance" % axis, 0.0)
			g.set("linear_limit_%s/upper_distance" % axis, 0.0)
	elif mode == "spring":
		# Linear spring instead of limits: a soft but load-bearing connection.
		for axis in ["x", "y", "z"]:
			g.set("linear_spring_%s/enabled" % axis, true)
			g.set("linear_spring_%s/stiffness" % axis, 1.0e7)
			g.set("linear_spring_%s/damping" % axis, 2.0e5)
			g.set("linear_spring_%s/equilibrium_point" % axis, 0.0)
	elif mode == "pin":
		var p := PinJoint3D.new()
		add_child(p)
		p.global_position = anchor.position + Vector3(0.0, 0.0, -1.0)
		p.node_a = anchor.get_path()
		p.node_b = hang.get_path()
		remove_child(g)
		g.queue_free()
		joint = p
	print("mode=", mode)


func _physics_process(_delta: float) -> void:
	ticks += 1
	if ticks % 20 == 0:
		print(
			"T",
			ticks,
			" a_y=",
			snappedf(anchor.global_position.y, 0.001),
			" h_y=",
			snappedf(hang.global_position.y, 0.001),
			" dy=",
			snappedf(hang.global_position.y - anchor.global_position.y, 0.001),
			" dz=",
			snappedf(hang.global_position.z - anchor.global_position.z, 0.001),
			" h_rot_x=",
			snappedf(hang.rotation_degrees.x, 0.1)
		)
	if ticks >= 120:
		get_tree().quit()
