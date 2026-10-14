class_name Transmission
## 10-speed transmission rules (spec section 5.3 and 14). Pure logic.
## Gear indices: 0 = N, 1..5 high range, 6..10 low range, -1 = R.

enum GearRange { HIGH, LOW }

## HUD reason for the AS4l2 (D57) over-rev shift guard. Local to this class
## (scripts/input/noop_rules.gd is the shared no-op table but is out of scope
## for this slice; the string is the one value a new row needs).
const REASON_OVERREV: String = "SHIFT WOULD EXCEED REDLINE"

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
	var reason: String = NoopRules.gear_change_reason(
		automatic, speed_m_s, clutch_depressed, gear, new_gear
	)
	if reason != "":
		last_reject_reason = reason
		return false
	# AS4l2 (D57): the driveline is an always-rigid coupling (D51: the rpm path
	# in combination_controller.gd does not respect the clutch pedal), so a gear
	# change that would map the current wheel rate through the candidate ratio
	# past the pinned redline over-revs the engine on the first tick, clamps to
	# the 1900 rpm shutdown, and -- because the rpm then stays above the D54 idle
	# floor -- never restarts. Refuse the over-rev shift at the shift point, as
	# a real transmission/driver would for a shift that instantly past-redlines.
	# A downshift that stays inside the rev range is unaffected. No new constant:
	# this compares against the pinned ENGINE_REDLINE_RPM using the pinned
	# GEAR_RATIOS / TIRE_DRIVE and the same DrivelineModel conversion as D51.
	var over_reject: String = _overrev_reason(speed_m_s, new_gear)
	if over_reject != "":
		last_reject_reason = over_reject
		return false
	gear = new_gear
	if new_gear >= 1 and new_gear <= 5:
		range = GearRange.HIGH
	elif new_gear >= 6 and new_gear <= 10:
		range = GearRange.LOW
	last_reject_reason = ""
	return true


func _overrev_reason(speed_m_s: float, new_gear: int) -> String:
	## The engine rpm the rigid driveline (D51) would demand if the wheel kept
	## its current rate through the candidate ratio -- the same conversion the
	## rpm coupling uses. Past the pinned redline the shift is refused (D57).
	## Neutral (0) never over-revs forward, and reverse (-1) is speed-gated by
	## reverse_reason, so both fall through to their own rules.
	if new_gear <= 0:
		return ""
	var wheel_rate: float = absf(speed_m_s) / PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
	var rpm: float = DrivelineModel.engine_rpm_from_wheel_rate(wheel_rate, ratio_for(new_gear))
	if rpm > PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM:
		return REASON_OVERREV
	return ""


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
