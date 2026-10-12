class_name NoopRules
## The section 11 no-op rules, in one place, so the transmission, the coupling
## controller and the input layer all reject the same way and emit the same
## HUD reason string. Every function returns "" when the action is allowed and
## the reason string when it must be refused.

const REASON_GEAR_NO_CLUTCH: String = "SHIFT NEEDS CLUTCH OR AUTO MODE"
const REASON_REVERSE_SPEED: String = "REVERSE NEEDS SPEED BELOW 0.5 M/S"
const REASON_RETARDER: String = "RETARDER NEEDS HIGH RANGE, GEAR 1-4, ABOVE 15 KM/H"
const REASON_UNLOCK_SPEED: String = "UNLOCK NEEDS SPEED BELOW 0.1 M/S"
const REASON_UNLOCK_BRAKE: String = "UNLOCK NEEDS PARKING BRAKE"
const REASON_LANDING_ATTACHED: String = "LANDING GEAR NEEDS DETACHED TRAILER"
const REASON_LANDING_MOVING: String = "LANDING GEAR NEEDS STOPPED TRAILER"


static func gear_change_reason(
	automatic: bool, speed_m_s: float, clutch_depressed: bool, current_gear: int, new_gear: int
) -> String:
	## No-op rule: gear change without clutch in manual mode. R has its own speed
	## rule (reverse_reason).
	if new_gear == current_gear:
		return ""
	if new_gear == -1:
		return reverse_reason(speed_m_s)
	if not automatic and not clutch_depressed:
		return REASON_GEAR_NO_CLUTCH
	return ""


static func reverse_reason(speed_m_s: float) -> String:
	## No-op rule: R above 0.5 m/s.
	if speed_m_s > PHYSICS_CONSTANTS.REVERSE_MAX_SPEED_M_S:
		return REASON_REVERSE_SPEED
	return ""


static func retarder_reason(range: int, gear: int, speed_m_s: float, _stage: int) -> String:
	## No-op rule: retarder in low range, above gear 4, or below 15 km/h.
	## range is a gear range index. NoopRules must not reference the Transmission
	## class: Transmission calls back into this table, and a circular class_name
	## dependency breaks script loading in Godot 4.7.
	if range != PHYSICS_CONSTANTS.GEAR_RANGE_HIGH:
		return REASON_RETARDER
	if gear < 1 or gear > PHYSICS_CONSTANTS.RETARDER_MAX_GEAR:
		return REASON_RETARDER
	if speed_m_s < PHYSICS_CONSTANTS.RETARDER_MIN_SPEED_M_S:
		return REASON_RETARDER
	return ""


static func unlock_reason(speed_m_s: float, parking_brake_applied: bool) -> String:
	## No-op rule: U while moving.
	if speed_m_s >= PHYSICS_CONSTANTS.UNLOCK_MAX_SPEED_M_S:
		return REASON_UNLOCK_SPEED
	if not parking_brake_applied:
		return REASON_UNLOCK_BRAKE
	return ""


static func landing_reason(attached: bool, speed_m_s: float) -> String:
	## No-op rule: L while attached or moving.
	if attached:
		return REASON_LANDING_ATTACHED
	if speed_m_s > PHYSICS_CONSTANTS.LANDING_GEAR_SPEED_M_S:
		return REASON_LANDING_MOVING
	return ""
