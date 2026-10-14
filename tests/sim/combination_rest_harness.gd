extends Node3D
## Reusable combination harness for integration tests: flat ground, the
## CombinationController, both vehicle scenes, and helpers that report the
## physical state the tests assert on.
##
## _ready must NOT be a coroutine: GUT calls helper methods on the harness
## immediately after add_child, so every reference has to be resolved during
## node entry. settle() and push_* are the awaitable parts.

## Ground half-extent (m) -- the top of the ground box sits at y = 0 and spans
## +/- _GROUND_HALF_EXTENT_M in x and z (AS4l2, D57-adjacent).
##
## Sizing arithmetic: the longest planned run is 30 s (the downshift and
## stop-distance probes) at the probe speed v_max = 22.2222 m/s (80 km/h), so
## worst-case distance = v_max x t = 22.2222 x 30 = 666.67 m. The tractor's
## leading point (steer axle, 6.5 m ahead of the drive-axle origin) therefore
## reaches at most 666.67 + 6.5 = 673.17 m, and the rearmost trailer point
## (+12.75 m behind the origin) stays well inside that. The 1200-step city
## golden run (10 s) covers only 222.2 m. 800 m keeps every planned run at
## least ~127 m from the edge. The previous 150 m half-extent let the 30 s
## downshift probe cross z = -150 at t = 12 s and fall, reporting bogus
## free-fall numbers (suspension work -31.37 MJ in one second, then flat).
const _GROUND_HALF_EXTENT_M: float = 800.0

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
	fbox.size = Vector3(_GROUND_HALF_EXTENT_M * 2.0, 2.0, _GROUND_HALF_EXTENT_M * 2.0)
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


func out_of_bounds() -> bool:
	## True when either body's center has left the intended play area (the
	## ground box). Long probes and at-risk tests call this at the end (or every
	## sampled tick) so a silent map departure is a visible failure instead of a
	## bogus number (AS4l2). It is a report, not a containment: the ground box is
	## simply large enough that no planned run reaches the edge.
	var tp: Vector3 = tractor.global_position
	var vp: Vector3 = trailer.global_position
	return (
		absf(tp.x) > _GROUND_HALF_EXTENT_M
		or absf(tp.z) > _GROUND_HALF_EXTENT_M
		or absf(vp.x) > _GROUND_HALF_EXTENT_M
		or absf(vp.z) > _GROUND_HALF_EXTENT_M
	)
