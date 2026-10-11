class_name KingpinModel
## Kingpin articulation torques and jackknife rules (spec section 5.5).
## Pure math. theta is trailer yaw relative to tractor; theta_rate rad/s.


static func spring_torque_nm(theta_rad: float) -> float:
	## Self-centering spring T = -8000 * theta.
	return -PHYSICS_CONSTANTS.KINGPIN_SPRING_NM_PER_RAD * theta_rad


static func damping_torque_nm(theta_rate_rad_s: float) -> float:
	## T = -12000 * theta_rate.
	return -PHYSICS_CONSTANTS.KINGPIN_DAMPING_NM_PER_RAD_S * theta_rate_rad_s


static func friction_torque_nm(theta_rate_rad_s: float) -> float:
	## Stribeck: 15,000 Nm static at rate 0, 10,000 Nm kinetic at and beyond
	## the 0.05 rad/s transition. Returns the resisting torque (opposes rate).
	var rate: float = absf(theta_rate_rad_s)
	var static_t: float = PHYSICS_CONSTANTS.KINGPIN_FRICTION_STATIC_NM
	var kinetic_t: float = PHYSICS_CONSTANTS.KINGPIN_FRICTION_KINETIC_NM
	if rate <= 0.0:
		return 0.0  # static friction only resists applied torque; see static_friction_max
	var t: float = kinetic_t
	if rate < PHYSICS_CONSTANTS.KINGPIN_STRIBECK_RATE_RAD_S:
		var f: float = rate / PHYSICS_CONSTANTS.KINGPIN_STRIBECK_RATE_RAD_S
		t = lerpf(static_t, kinetic_t, f)
	return -signf(theta_rate_rad_s) * t


static func static_friction_max_nm() -> float:
	## Maximum torque static kingpin friction can hold.
	return PHYSICS_CONSTANTS.KINGPIN_FRICTION_STATIC_NM


static func is_jackknife(theta_deg: float, theta_rate_deg_s: float) -> bool:
	## |theta| > 70 deg, or |theta| > 55 deg with |theta_rate| > 25 deg/s.
	var a: float = absf(theta_deg)
	var r: float = absf(theta_rate_deg_s)
	if a > PHYSICS_CONSTANTS.JACKKNIFE_ANGLE_DEG:
		return true
	return a > PHYSICS_CONSTANTS.JACKKNIFE_RATE_ANGLE_DEG and r > PHYSICS_CONSTANTS.JACKKNIFE_RATE_DEG_S


static func clamp_angle(theta_rad: float) -> float:
	var limit: float = deg_to_rad(PHYSICS_CONSTANTS.KINGPIN_HARD_LIMIT_DEG)
	return clampf(theta_rad, -limit, limit)
