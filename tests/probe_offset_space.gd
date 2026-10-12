extends SceneTree
## Unambiguous probe of apply_force position-offset space on Jolt.
## Body rotated +90 deg about Y. Force is +Y (identical in local and world).
## Offset given as (1, 0, 0):
##   offset LOCAL -> r_world = (0,0,-1) -> torque r x F = (+1000, 0, 0) -> +X
##   offset WORLD -> r_world = (1,0,0)  -> torque r x F = (0, 0, +1000) -> +Z

var body: RigidBody3D
var ticks: int = 0


func _initialize() -> void:
	body = RigidBody3D.new()
	body.mass = 1000.0
	body.collision_layer = 1
	body.collision_mask = 0
	body.gravity_scale = 0.0
	body.freeze = true
	root.add_child(body)
	body.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	body.freeze = false
	body.apply_force(Vector3(0.0, 1000.0, 0.0), Vector3(1.0, 0.0, 0.0))


func _physics_process(_delta: float) -> bool:
	ticks += 1
	if ticks == 5:
		print("ang_vel=", body.angular_velocity)
		print("ang +X => offset is LOCAL space; ang +Z => offset is WORLD space")
		quit()
	return false
