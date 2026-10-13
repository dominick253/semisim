class_name DrivelineModel
## Driveline arithmetic shared by the combination controller (spec section 5.3).
## Pure functions of explicit arguments: no node state, no fields, so the
## controller keeps the state (engine_running, throttle, gear selection) and
## passes the numbers. Extracted verbatim from combination_controller.gd in
## AS4i; the saturated-branch wheel integrator additionally works against
## effective_inertia_kg_m2 (D53).


## wheel_rate (rad/s) -> engine rpm: * ratio * FINAL_DRIVE_RATIO * 60 / (2*PI),
## clamped to idle/shutdown. The single conversion both rpm paths share.
static func engine_rpm_from_wheel_rate(wheel_rate_rad_s: float, ratio: float) -> float:
	if ratio <= 0.0:
		return PHYSICS_CONSTANTS.ENGINE_IDLE_RPM
	var rpm: float = (
		absf(wheel_rate_rad_s) * ratio * PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO * 60.0 / (2.0 * PI)
	)
	return clampf(rpm, PHYSICS_CONSTANTS.ENGINE_IDLE_RPM, PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM)


## The inertia (kg m^2) the saturated-branch wheel integrator works against:
## the drive-wheel inertia plus the engine-side inertia (flywheel + driveline,
## section 4) reflected through the square of the total driveline ratio (gear x
## final drive). While the clutch is engaged, spinning the drive wheels spins
## the flywheel and the driveline up through the gearbox, so they resist the
## spin-up; without the reflection the integrator worked against the 2.0 kg m^2
## wheel alone and any torque step spiked the wheel (AS4i).
static func effective_inertia_kg_m2(ratio: float) -> float:
	return (
		PHYSICS_CONSTANTS.WHEEL_INERTIA_KG_M2
		+ (
			(PHYSICS_CONSTANTS.FLYWHEEL_INERTIA_KG_M2 + PHYSICS_CONSTANTS.DRIVELINE_INERTIA_KG_M2)
			* pow(ratio * PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO, 2.0)
		)
	)


## The drive-axle torque (Nm) from the engine torque: total ratio, final
## drive, driveline efficiency and clutch engagement, then the top speed
## governor fuel cut (120 km/h). The AS4h redline fuel cut is a fuel event
## applied to the engine torque by the caller (it zeroes it), so a cut engine
## arrives here as engine_torque_nm 0.0 and returns 0.0: the same 0.0 the cut
## returned in the controller before the split.
static func wheel_torque_nm(
	engine_torque_nm: float, throttle: float, ratio: float, engagement: float, forward_speed: float
) -> float:
	var torque: float = (
		engine_torque_nm
		* ratio
		* PHYSICS_CONSTANTS.FINAL_DRIVE_RATIO
		* PHYSICS_CONSTANTS.DRIVELINE_EFFICIENCY
		* engagement
	)
	if throttle > 0.0 and forward_speed > PHYSICS_CONSTANTS.TOP_SPEED_GOVERNOR_M_S:
		torque = 0.0  # top speed governor fuel cut
	return torque
