class_name CouplingController
## Coupling and landing gear rules (spec section 8). Pure logic.

enum LandingState { RAISED, LOWERING, DEPLOYED, RAISING }

var landing_state: int = LandingState.RAISED
var landing_height_m: float = 0.0  # contact gap; 0 = deployed contact at 0.35 m spec
var last_reject_reason: String = ""


func kingpin_distance_m(kingpin_global: Vector3, fifth_wheel_global: Vector3) -> float:
	return kingpin_global.distance_to(fifth_wheel_global)


func aligning(kingpin_distance: float) -> bool:
	return kingpin_distance <= PHYSICS_CONSTANTS.ALIGNING_DISTANCE_M


func can_auto_lock(kingpin_distance: float, articulation_deg: float, rel_speed_m_s: float) -> bool:
	## Kingpin within 0.30 m, articulation within +/- 12 deg, rel speed < 0.5 m/s.
	return (
		kingpin_distance <= PHYSICS_CONSTANTS.COUPLE_DISTANCE_M
		and absf(articulation_deg) <= PHYSICS_CONSTANTS.COUPLE_MAX_ANGLE_DEG
		and rel_speed_m_s < PHYSICS_CONSTANTS.COUPLE_MAX_SPEED_M_S
	)


func can_unlock(speed_m_s: float, parking_brake_applied: bool) -> bool:
	## Manual unlock U: speed below 0.1 m/s and parking brake applied.
	var reason: String = NoopRules.unlock_reason(speed_m_s, parking_brake_applied)
	if reason != "":
		last_reject_reason = reason
		return false
	last_reject_reason = ""
	return true


func can_toggle_landing(attached: bool, speed_m_s: float) -> bool:
	## Deploy or raise only when detached and stopped.
	var reason: String = NoopRules.landing_reason(attached, speed_m_s)
	if reason != "":
		last_reject_reason = reason
		return false
	last_reject_reason = ""
	return true


func step_landing(dt_s: float) -> void:
	## 0.4 m/s travel over 0.35 m of stroke.
	var stroke: float = PHYSICS_CONSTANTS.LANDING_CONTACT_HEIGHT_M
	var travel: float = PHYSICS_CONSTANTS.LANDING_GEAR_SPEED_M_S * dt_s
	if landing_state == LandingState.LOWERING:
		landing_height_m = maxf(0.0, landing_height_m - travel)
		if landing_height_m <= 0.0:
			landing_state = LandingState.DEPLOYED
	elif landing_state == LandingState.RAISING:
		landing_height_m = minf(stroke, landing_height_m + travel)
		if landing_height_m >= stroke:
			landing_state = LandingState.RAISED


func toggle_landing(attached: bool, speed_m_s: float) -> bool:
	if not can_toggle_landing(attached, speed_m_s):
		return false
	if landing_state == LandingState.DEPLOYED or landing_state == LandingState.LOWERING:
		landing_state = LandingState.RAISING
	else:
		landing_state = LandingState.LOWERING
	return true


func deployed() -> bool:
	return landing_state == LandingState.DEPLOYED
