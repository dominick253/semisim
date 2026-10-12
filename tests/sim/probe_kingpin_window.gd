extends Node3D
## Sweep the kingpin pitch/roll limit window and measure the resting axle load
## split. Rigid pitch/lock couples the two suspensions into one statically
## indeterminate system and pushes the live steer axle load above the pinned
## legal cap; a small window models the real kingpin bearing's limited pitch
## moment capacity. Prints per-pair sums so the choice is evidence-based.

const TICKS: int = 240


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var pitch_deg: float = float(args[0]) if args.size() > 0 else 0.0
	var roll_deg: float = float(args[1]) if args.size() > 1 else 0.0
	var pitch_torque: float = (
		float(args[2]) if args.size() > 2 else PHYSICS_CONSTANTS.KINGPIN_LOCK_TORQUE_N_M
	)

	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 4
	floor_body.collision_mask = 3
	var fshape := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(300.0, 2.0, 300.0)
	fshape.shape = fbox
	fshape.position = Vector3(0.0, -1.0, 0.0)
	floor_body.add_child(fshape)
	add_child(floor_body)

	var controller: Node3D = load("res://scripts/vehicles/combination_controller.gd").new()
	controller.name = "Combination"
	var tractor_scene: Node3D = load("res://scenes/vehicles/tractor.tscn").instantiate()
	var trailer_scene: Node3D = load("res://scenes/vehicles/trailer.tscn").instantiate()
	tractor_scene.position = Vector3(0.0, 0.0, 0.0)
	trailer_scene.position = Vector3(0.0, 0.0, -1.0)
	controller.add_child(tractor_scene)
	controller.add_child(trailer_scene)
	add_child(controller)
	controller.joint.set("angular_limit_x/lower_angle", -deg_to_rad(pitch_deg))
	controller.joint.set("angular_limit_x/upper_angle", deg_to_rad(pitch_deg))
	controller.joint.set("angular_limit_x/force_limit", pitch_torque)
	controller.joint.set("angular_limit_z/lower_angle", -deg_to_rad(roll_deg))
	controller.joint.set("angular_limit_z/upper_angle", deg_to_rad(roll_deg))
	controller.joint.set("angular_limit_z/force_limit", pitch_torque)
	controller.place_at_rest()
	print(
		"pitch_deg=",
		pitch_deg,
		" roll_deg=",
		roll_deg,
		" torque=",
		pitch_torque,
		" shares=",
		snappedf(controller.fifth_wheel_load_n, 1.0)
	)
	for _i in TICKS:
		await get_tree().physics_frame
	var sums: Dictionary = {"steer": 0.0, "drive": 0.0, "bogie": 0.0}
	var shares: Dictionary = {"steer": 0.0, "drive": 0.0, "bogie": 0.0}
	for w in controller.wheels:
		sums[w.role] += w.normal_n
		shares[w.role] += w.static_share_n
	var steer_kg: float = sums["steer"] / PHYSICS_CONSTANTS.GRAVITY_M_S2
	print(
		"  steer kg=",
		snappedf(steer_kg, 1.0),
		" cap=",
		PHYSICS_CONSTANTS.STEER_AXLE_LEGAL_CAP_KG,
		" ok=",
		steer_kg <= PHYSICS_CONSTANTS.STEER_AXLE_LEGAL_CAP_KG
	)
	for role in ["steer", "drive", "bogie"]:
		print(
			"  ",
			role,
			" live=",
			snappedf(sums[role], 1.0),
			" static=",
			snappedf(shares[role], 1.0),
			" ratio=",
			snappedf(sums[role] / shares[role], 0.01)
		)
	print(
		"  kp_gap=",
		snappedf(
			(
				(controller.trailer.global_transform * PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL)
				. distance_to(
					controller.tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
				)
			),
			0.001
		),
		" tr_pitch=",
		snappedf(controller.trailer.rotation.x, 0.0001),
		" t_pitch=",
		snappedf(controller.tractor.rotation.x, 0.0001),
		" tr_roll=",
		snappedf(controller.trailer.rotation.z, 0.0001),
		" sumN/weight=",
		snappedf(
			(
				(sums["steer"] + sums["drive"] + sums["bogie"])
				/ (
					(controller.tractor.mass + controller.trailer.mass)
					* PHYSICS_CONSTANTS.GRAVITY_M_S2
				)
			),
			0.001
		)
	)
	get_tree().quit()
