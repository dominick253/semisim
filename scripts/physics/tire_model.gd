class_name TireModel
## Pacejka magic formula tire model (spec section 5.2). Pure math, no node
## dependencies, no RNG. All constants come from PHYSICS_CONSTANTS.
## Sign convention: forces oppose slip angles (restoring), magnitudes are
## returned by the peak helpers.


static func lateral_force(alpha_rad: float, fz_n: float, mu: float) -> float:
	## Fy = D * sin(C * atan(B * alpha)), D = mu * Fz.
	## alpha clamped to +/- TIRE_ALPHA_CLAMP_RAD.
	var alpha: float = clampf(
		alpha_rad, -PHYSICS_CONSTANTS.TIRE_ALPHA_CLAMP_RAD, PHYSICS_CONSTANTS.TIRE_ALPHA_CLAMP_RAD
	)
	var d: float = mu * fz_n
	return -d * sin(PHYSICS_CONSTANTS.TIRE_C * atan(PHYSICS_CONSTANTS.TIRE_B * alpha))


static func lateral_peak(fz_n: float, mu: float) -> float:
	## Peak lateral force = D = mu * Fz (the magic formula peak asymptote).
	return mu * fz_n


static func longitudinal_force(kappa: float, fz_n: float, mu: float, braking: bool) -> float:
	## Fx = Dx * sin(Cx * atan(Bx * kappa)), Dx = mu * Fz.
	## Bx = 12.0 driving, 14.0 braking (spec section 5.2).
	var bx: float = PHYSICS_CONSTANTS.TIRE_BX_BRAKE if braking else PHYSICS_CONSTANTS.TIRE_BX_DRIVE
	var dx: float = mu * fz_n
	return dx * sin(PHYSICS_CONSTANTS.TIRE_CX * atan(bx * kappa))


static func lateral_available(fz_n: float, mu: float, fx_n: float) -> float:
	## Friction ellipse: Fy_avail = mu*Fz*sqrt(max(0, 1 - u_long^2)),
	## u_long = |Fx| / (mu*Fz) clamped to 1.0.
	var denom: float = mu * fz_n
	if denom <= 0.0:
		return 0.0
	var u_long: float = clampf(absf(fx_n) / denom, 0.0, 1.0)
	return denom * sqrt(maxf(0.0, 1.0 - u_long * u_long))


static func wheel_traction_torque(
	engine_nm: float, gear_ratio: float, final_drive: float, efficiency: float
) -> float:
	## Wheel torque = engine torque x gear x final drive x efficiency (Nm).
	## Divide by rolling radius for the contact patch force in N.
	return engine_nm * gear_ratio * final_drive * efficiency


static func wheel_traction_force(
	engine_nm: float,
	gear_ratio: float,
	final_drive: float,
	efficiency: float,
	rolling_radius_m: float
) -> float:
	## Contact patch force in N.
	return wheel_traction_torque(engine_nm, gear_ratio, final_drive, efficiency) / rolling_radius_m


static func engine_torque_nm(rpm: float) -> float:
	## Piecewise linear over PHYSICS_CONSTANTS.ENGINE_TORQUE_CURVE.
	var curve: Array = PHYSICS_CONSTANTS.ENGINE_TORQUE_CURVE
	if rpm <= curve[0][0]:
		return curve[0][1]
	for i in range(1, curve.size()):
		if rpm <= curve[i][0]:
			var t0: float = curve[i - 1][0]
			var t1: float = curve[i][0]
			var f: float = (rpm - t0) / (t1 - t0)
			return lerp(curve[i - 1][1], curve[i][1], f)
	return curve[curve.size() - 1][1]


static func engine_brake_torque_nm(rpm: float) -> float:
	## Throttle closed: 400 Nm at 1800 rpm linear to 120 Nm at 700 rpm.
	var lo: float = PHYSICS_CONSTANTS.ENGINE_IDLE_RPM
	var hi: float = PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM
	var rpm_c: float = clampf(rpm, lo, hi)
	var f: float = (rpm_c - lo) / (hi - lo)
	return lerp(
		PHYSICS_CONSTANTS.ENGINE_BRAKE_TORQUE_LOW_NM,
		PHYSICS_CONSTANTS.ENGINE_BRAKE_TORQUE_HIGH_NM,
		f
	)
