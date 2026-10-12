class_name Transmission
## 10-speed transmission rules (spec section 5.3 and 14). Pure logic.
## Gear indices: 0 = N, 1..5 high range, 6..10 low range, -1 = R.

enum GearRange { HIGH, LOW }

var gear: int = 0
var range: int = GearRange.HIGH
var automatic: bool = true
var last_reject_reason: String = ""


func reset() -> void:
	gear = 0
	range = GearRange.HIGH
	last_reject_reason = ""


func select_gear(new_gear: int, speed_m_s: float, clutch_depressed: bool) -> bool:
	## Returns true when the shift is accepted. Rules (section 5.3):
	## R only below 0.5 m/s; any change needs clutch depressed or auto mode.
	if new_gear == gear:
		return true
	if new_gear == -1 and speed_m_s > 0.5:
		last_reject_reason = "REVERSE NEEDS SPEED BELOW 0.5 M/S"
		return false
	if not automatic and not clutch_depressed:
		last_reject_reason = "SHIFT NEEDS CLUTCH OR AUTO MODE"
		return false
	gear = new_gear
	if new_gear >= 1 and new_gear <= 5:
		range = GearRange.HIGH
	elif new_gear >= 6 and new_gear <= 10:
		range = GearRange.LOW
	last_reject_reason = ""
	return true


func toggle_range(speed_m_s: float, clutch_depressed: bool) -> bool:
	var target: int = gear
	if range == GearRange.HIGH:
		target = 6  # first low gear
		if gear == 0:
			target = 6
	else:
		target = 1  # first high gear
		if gear == 0:
			range = GearRange.HIGH
			return true
	return select_gear(target, speed_m_s, clutch_depressed)


func ratio_for(g: int) -> float:
	if g == -1:
		return PHYSICS_CONSTANTS.REVERSE_RATIO
	if g <= 0:
		return 0.0
	return PHYSICS_CONSTANTS.GEAR_RATIOS[g]


func ratio() -> float:
	return ratio_for(gear)


func speed_at_idle(g: int) -> float:
	## Vehicle speed (m/s) at engine idle rpm in gear g.
	var r: float = ratio_for(g)
	if r <= 0.0:
		return 0.0
	return (
		(PHYSICS_CONSTANTS.ENGINE_IDLE_RPM * 2.0 * PI / 60.0)
		* PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
		/ (r * PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO)
	)


func auto_shift(rpm: float, speed_m_s: float) -> void:
	## Automatic mode upshifts at 1550 rpm, downshifts at 1150 rpm.
	## DEVIATIONS D18: no lugging downshifts, no low-range upshifts above 15 km/h.
	if not automatic or gear <= 0:
		return
	if rpm >= PHYSICS_CONSTANTS.AUTO_UPSHIFT_RPM and gear < 10:
		if gear + 1 >= 6 and speed_m_s > PHYSICS_CONSTANTS.AUTO_LOW_RANGE_MAX_SPEED_M_S:
			return  # stay in high range while moving
		gear += 1
		if gear <= 5:
			range = GearRange.HIGH
		else:
			range = GearRange.LOW
	elif rpm <= PHYSICS_CONSTANTS.AUTO_DOWNSHIFT_RPM and gear > 1:
		if speed_at_idle(gear - 1) < speed_m_s:
			return  # would lug the engine
		gear -= 1
		if gear <= 5:
			range = GearRange.HIGH
		else:
			range = GearRange.LOW


func retarder_allowed(_stage: int, speed_m_s: float) -> bool:
	## Active only in high range, gears 1..4, speed above 15 km/h.
	if range != GearRange.HIGH or gear < 1 or gear > PHYSICS_CONSTANTS.RETARDER_MAX_GEAR:
		return false
	return speed_m_s >= PHYSICS_CONSTANTS.RETARDER_MIN_SPEED_M_S
