extends Node
## GAME_STATE autoload: vehicle, coupling, transmission and challenge state
## machines plus current run metrics (section 14).

signal vehicle_state_changed(new_state: int)
signal coupling_state_changed(new_state: int)
signal challenge_state_changed(new_state: int)
signal hud_flash(message: String)

enum VehicleState { PARKED, COUPLING, DRIVING, JACKKNIFE, DESTROYED }
enum CouplingState { DETACHED, ALIGNING, LOCKED }
enum TransmissionState { NEUTRAL, ENGAGING, ENGAGED }
enum ChallengeState { IDLE, ACTIVE, COMPLETE, FAILED }

var vehicle_state: int = VehicleState.PARKED
var coupling_state: int = CouplingState.DETACHED
var transmission_state: int = TransmissionState.NEUTRAL
var challenge_state: int = ChallengeState.IDLE

var strikes: int = 0
var cone_contacts: int = 0
var jackknife_events: int = 0
var cargo_mass_kg: float = PHYSICS_CONSTANTS.CARGO_MASS_DEFAULT_KG
var challenge_elapsed_s: float = 0.0


func set_vehicle_state(new_state: int) -> void:
	if new_state == vehicle_state:
		return
	vehicle_state = new_state
	vehicle_state_changed.emit(new_state)


func set_coupling_state(new_state: int) -> void:
	if new_state == coupling_state:
		return
	coupling_state = new_state
	coupling_state_changed.emit(new_state)


func flash(message: String) -> void:
	hud_flash.emit(message)
	print("HUD FLASH: ", message)
