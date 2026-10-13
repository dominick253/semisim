class_name AirSystem
## Air brake system state machine (spec section 5.4). Pure logic, no nodes.

enum AirState { OK, WARNING, SPRING_BRAKE }

var pressure_psi: float = 0.0
var state: int = AirState.OK
var spring_brake_engaged: bool = false
var engine_running: bool = false
## Spec 5.4's second release condition: once a restart releases the spring
## brake below 40 psi, that release persists until the pressure recovers
## past the 60 psi release point (D55). A plain sub-40-psi refresh must not
## cancel it, or the restart could never do the one thing the spec asks of it.
var _restart_released: bool = false


func reset(start_pressure_psi: float, running: bool) -> void:
	pressure_psi = start_pressure_psi
	engine_running = running
	_restart_released = false
	_refresh_state()


func fill_rate_psi_s(rpm: float) -> float:
	## 2.22 * (rpm / 700) psi/s.
	return PHYSICS_CONSTANTS.AIR_FILL_BASE_PSI_S * (rpm / PHYSICS_CONSTANTS.ENGINE_IDLE_RPM)


func step(dt_s: float, rpm: float) -> void:
	if engine_running and rpm > 0.0:
		pressure_psi = minf(
			pressure_psi + fill_rate_psi_s(rpm) * dt_s, PHYSICS_CONSTANTS.AIR_NOMINAL_PSI
		)
	_refresh_state()


func consume_psi(psi: float) -> void:
	pressure_psi = maxf(0.0, pressure_psi - psi)
	_refresh_state()


func _refresh_state() -> void:
	if pressure_psi < PHYSICS_CONSTANTS.AIR_SPRING_BRAKE_PSI:
		if _restart_released:
			# The restart's release (D55) survives the sub-40-psi window until
			# the compressor refills past the 60 psi release point. Below the
			# 60 psi warning threshold the state stays WARNING.
			state = AirState.WARNING
		else:
			state = AirState.SPRING_BRAKE
			spring_brake_engaged = true
	elif spring_brake_engaged:
		# Spring brake releases only above 60 psi or on engine restart.
		if pressure_psi >= PHYSICS_CONSTANTS.AIR_SPRING_BRAKE_RELEASE_PSI:
			spring_brake_engaged = false
			state = (
				AirState.OK if pressure_psi >= PHYSICS_CONSTANTS.AIR_WARN_PSI else AirState.WARNING
			)
		else:
			state = AirState.SPRING_BRAKE
	elif pressure_psi < PHYSICS_CONSTANTS.AIR_WARN_PSI:
		state = AirState.WARNING
	else:
		state = AirState.OK
		# Pressure recovered past the 60 psi release point: the ladder is
		# whole again, a later sub-40-psi drop re-engages the brake.
		_restart_released = false


func restart_engine() -> void:
	engine_running = true
	spring_brake_engaged = false
	_restart_released = true
	_refresh_state()


func warning_active() -> bool:
	return pressure_psi < PHYSICS_CONSTANTS.AIR_WARN_PSI
