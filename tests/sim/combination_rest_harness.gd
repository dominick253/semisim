extends Node3D
## Reusable combination harness for integration tests: flat ground, the
## CombinationController, both vehicle scenes, and helpers that report the
## physical state the tests assert on.
##
## _ready must NOT be a coroutine: GUT calls helper methods on the harness
## immediately after add_child, so every reference has to be resolved during
## node entry. settle() and push_* are the awaitable parts.

var controller: Node3D
var tractor: RigidBody3D
var trailer: RigidBody3D
var rest_trailer_y: float = 0.0
var rest_tractor_y: float = 0.0
var _held_torques: Array[HeldTorque] = []


class HeldTorque:
	var body: RigidBody3D
	var torque: Vector3
	var ticks_left: int

	func _init(p_body: RigidBody3D, p_torque: Vector3, p_ticks: int) -> void:
		body = p_body
		torque = p_torque
		ticks_left = p_ticks


func _ready() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Ground"
	# Godot 4 collision is mutual: the ground must mask the vehicle layers or
	# the bodies fall through it (this mistake cost a long debug session).
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
	# Children must exist before the controller enters the tree so its _ready
	# and @onready references resolve.
	controller.add_child(tractor_scene)
	controller.add_child(trailer_scene)
	add_child(controller)
	controller.place_at_rest()
	tractor = controller.tractor
	trailer = controller.trailer
	rest_tractor_y = tractor.global_position.y
	rest_trailer_y = trailer.global_position.y


func _physics_process(_delta: float) -> void:
	var keep: Array[HeldTorque] = []
	for h in _held_torques:
		h.body.apply_torque(h.torque)
		h.ticks_left -= 1
		if h.ticks_left > 0:
			keep.append(h)
	_held_torques = keep


func settle(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame


func hold_torque(body: RigidBody3D, torque: Vector3, ticks: int) -> void:
	_held_torques.append(HeldTorque.new(body, torque, ticks))


func push_yaw(torque_nm: float, ticks: int) -> void:
	hold_torque(trailer, Vector3(0.0, torque_nm, 0.0), ticks)


func push_pitch(torque_nm: float, ticks: int) -> void:
	hold_torque(trailer, Vector3(torque_nm, 0.0, 0.0), ticks)


func kingpin_gap_m() -> float:
	var kp: Vector3 = trailer.global_transform * PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL
	var fw: Vector3 = tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	return kp.distance_to(fw)


func trailer_sink_m() -> float:
	return trailer.global_position.y - rest_trailer_y


func normal_force_weight_ratio() -> float:
	var sum_n: float = 0.0
	for w in controller.wheels:
		sum_n += w.normal_n
	var weight: float = (tractor.mass + trailer.mass) * PHYSICS_CONSTANTS.GRAVITY_M_S2
	return sum_n / weight
