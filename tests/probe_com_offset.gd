extends Node3D
## Is apply_force's position offset in LOCAL axes or WORLD axes (relative to the
## body origin)? Body rotated +90 about Y: local +Z maps to world +X.
## Force +X 1000 N, offset (0,0,1).
##   LOCAL  -> world point (1,0,0), parallel to F -> torque 0
##   WORLD  -> world point (0,0,1), r x F = (0,+1000,0) -> torque +Y

var body: RigidBody3D
var ticks: int = 0


func _ready() -> void:
	body = RigidBody3D.new()
	body.mass = 1000.0
	body.collision_layer = 1
	body.collision_mask = 0
	body.gravity_scale = 0.0
	add_child(body)
	body.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	body.force_update_transform()
	print("basis.z (world dir of local +Z) = ", body.global_basis.z)
	body.apply_force(Vector3(1000.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0))


func _physics_process(_delta: float) -> void:
	ticks += 1
	if ticks == 10:
		print("ang_vel=", body.angular_velocity)
		print("ang ~ 0      => offset is LOCAL axes")
		print("ang ~ (0,+,0) => offset is WORLD axes")
		get_tree().quit()
