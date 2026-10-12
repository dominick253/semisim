extends RigidBody3D
## Tractor body node. Mass, CoM and inertia are applied by
## CombinationController.apply_cargo() from PHYSICS_CONSTANTS (single source of
## truth). This script only guards the defaults so the scene is valid on its
## own (editor preview, unit scenes).


func _ready() -> void:
	if mass < 1000.0:
		mass = PHYSICS_CONSTANTS.TRACTOR_MASS_KG
	if center_of_mass == Vector3.ZERO:
		center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		center_of_mass = PHYSICS_CONSTANTS.TRACTOR_COM
