extends Node
## CITYHAUL physics constants. Single source of truth for all physics values.
## Changing a constant here requires updating docs/physics-spec.md in the same
## commit (see AGENTS.md). Values mirror docs/physics-spec.md exactly.

# ---------------------------------------------------------------------------
# World / engine
# ---------------------------------------------------------------------------
const GRAVITY_M_S2: float = 9.81
const PHYSICS_TICKS_PER_SECOND: int = 120

# ---------------------------------------------------------------------------
# Tractor (section 5.1)
# ---------------------------------------------------------------------------
const TRACTOR_MASS_KG: float = 8400.0
const TRACTOR_REAR_AXLE: Vector3 = Vector3(0.0, 0.563, 0.0)
const TRACTOR_FRONT_AXLE: Vector3 = Vector3(0.0, 0.554, -6.50)
const TRACTOR_COM: Vector3 = Vector3(0.0, 1.30, -0.75)
const FIFTH_WHEEL_CENTER: Vector3 = Vector3(0.0, 1.30, -7.45)
const TRACTOR_BOX: Vector3 = Vector3(2.50, 3.30, 10.50)
const TRACTOR_IX_KG_M2: float = 32133.0
const TRACTOR_IY_KG_M2: float = 30975.0
const TRACTOR_IZ_KG_M2: float = 9758.0

# ---------------------------------------------------------------------------
# Trailer (section 5.1)
# ---------------------------------------------------------------------------
const TRAILER_MASS_EMPTY_KG: float = 7000.0
const TRAILER_BOGIE_AXLE_1: Vector3 = Vector3(0.0, 0.563, 11.80)
const TRAILER_BOGIE_AXLE_2: Vector3 = Vector3(0.0, 0.563, 12.60)
const TRAILER_COM_EMPTY: Vector3 = Vector3(0.0, 1.55, -7.70)
const TRAILER_BOX: Vector3 = Vector3(2.59, 4.07, 16.15)
const TRAILER_IX_EMPTY_KG_M2: float = 415000.0
const TRAILER_IY_EMPTY_KG_M2: float = 331000.0
const TRAILER_IZ_EMPTY_KG_M2: float = 113600.0
const KINGPIN_TRAILER_LOCAL: Vector3 = Vector3(0.0, 1.30, 0.0)

# ---------------------------------------------------------------------------
# Tire model (section 5.2)
# ---------------------------------------------------------------------------
const TIRE_B: float = 10.0
const TIRE_C: float = 1.60
const TIRE_BX_DRIVE: float = 12.0
const TIRE_CX: float = 1.40
const TIRE_BX_BRAKE: float = 14.0
const TIRE_ALPHA_CLAMP_RAD: float = 1.4
const ABS_ENGAGE_SLIP: float = 0.15
const ABS_RELEASE_SLIP: float = 0.08
const LOAD_TRANSFER_CAP: float = 0.18
const WHEEL_LOAD_MIN_FRACTION: float = 0.05
const ROLLOVER_LATERAL_G: float = 0.45

# Tire table: position -> {size, width_m, rolling_radius_m, mu_dry, mu_wet, mu_ice}
const TIRE_STEER: Dictionary = {
	"size": "295/75R22.5",
	"width_m": 0.295,
	"rolling_radius_m": 0.554,
	"mu_dry": 1.10,
	"mu_wet": 0.70,
	"mu_ice": 0.25,
}
const TIRE_DRIVE: Dictionary = {
	"size": "11R22.5",
	"width_m": 0.285,
	"rolling_radius_m": 0.563,
	"mu_dry": 1.15,
	"mu_wet": 0.72,
	"mu_ice": 0.25,
}
const TIRE_TRAILER: Dictionary = {
	"size": "11R22.5",
	"width_m": 0.285,
	"rolling_radius_m": 0.563,
	"mu_dry": 1.10,
	"mu_wet": 0.70,
	"mu_ice": 0.25,
}

# ---------------------------------------------------------------------------
# Engine, transmission, retarder (section 5.3)
# ---------------------------------------------------------------------------
# Engine torque curve control points: rpm -> Nm
const ENGINE_TORQUE_CURVE: Array = [
	[0.0, 0.0],
	[700.0, 1200.0],
	[1000.0, 2100.0],
	[1400.0, 2230.0],
	[1600.0, 2100.0],
	[1800.0, 1600.0],
]
const ENGINE_IDLE_RPM: float = 700.0
const ENGINE_REDLINE_RPM: float = 1800.0
const ENGINE_SHUTDOWN_RPM: float = 1900.0
const ENGINE_BRAKE_TORQUE_HIGH_NM: float = 400.0
const ENGINE_BRAKE_TORQUE_LOW_NM: float = 120.0
const FLYWHEEL_INERTIA_KG_M2: float = 1.2

const CLUTCH_CAPACITY_NM: float = 3500.0
const CLUTCH_TRAVEL_START: float = 0.20
const CLUTCH_TRAVEL_END: float = 0.80

# Gear ratios indexed 1..10 (1..5 high range, 6..10 low range)
const GEAR_RATIOS: Array = [0.0, 4.834, 2.857, 1.840, 1.290, 1.000, 9.015, 5.324, 3.427, 2.403, 1.864]
const REVERSE_RATIO: float = 8.315
const AUTO_UPSHIFT_RPM: float = 1550.0
const AUTO_DOWNSHIFT_RPM: float = 1150.0

const FINAL_DRIVE_RATIO: float = 3.70
const DRIVELINE_EFFICIENCY: float = 0.94
const DRIVELINE_INERTIA_KG_M2: float = 0.5
const TOP_SPEED_GOVERNOR_M_S: float = 33.333  # 120 km/h fuel cut

const RETARDER_STAGES_KN: Array = [0.0, 50000.0, 100000.0, 150000.0, 200000.0, 250000.0]
const RETARDER_MAX_GEAR: int = 4
const RETARDER_MIN_SPEED_M_S: float = 4.1667  # 15 km/h

# ---------------------------------------------------------------------------
# Brakes and air system (section 5.4)
# ---------------------------------------------------------------------------
const BRAKE_TORQUE_FRONT_NM: float = 9000.0
const BRAKE_TORQUE_TRAILER_NM: float = 10000.0
const BRAKE_TORQUE_DRIVE_NM: float = 12000.0
const PARKING_BRAKE_TORQUE_NM: float = 12000.0

const AIR_NOMINAL_PSI: float = 100.0
const AIR_FILL_BASE_PSI_S: float = 2.22  # at 700 rpm
const AIR_WARN_PSI: float = 60.0
const AIR_SPRING_BRAKE_PSI: float = 40.0
const AIR_SPRING_BRAKE_RELEASE_PSI: float = 60.0

# ---------------------------------------------------------------------------
# Kingpin and articulation (section 5.5)
# ---------------------------------------------------------------------------
const KINGPIN_HARD_LIMIT_DEG: float = 75.0
const JACKKNIFE_WARN_DEG: float = 60.0
const KINGPIN_SPRING_NM_PER_RAD: float = 8000.0
const KINGPIN_DAMPING_NM_PER_RAD_S: float = 12000.0
const KINGPIN_FRICTION_STATIC_NM: float = 15000.0
const KINGPIN_FRICTION_KINETIC_NM: float = 10000.0
const KINGPIN_STRIBECK_RATE_RAD_S: float = 0.05
const JACKKNIFE_ANGLE_DEG: float = 70.0
const JACKKNIFE_RATE_DEG_S: float = 25.0
const JACKKNIFE_RATE_ANGLE_DEG: float = 55.0

# ---------------------------------------------------------------------------
# Loading (section 5.6)
# ---------------------------------------------------------------------------
const CARGO_MASS_MAX_KG: float = 29000.0
const CARGO_MASS_DEFAULT_KG: float = 20000.0
const CARGO_COM: Vector3 = Vector3(0.0, 1.70, -5.80)
const STEER_AXLE_LEGAL_CAP_KG: float = 7711.0

# ---------------------------------------------------------------------------
# Suspension and steering (section 5.7)
# ---------------------------------------------------------------------------
const SUSPENSION_SPRING_STEER_N_M: float = 55000.0
const SUSPENSION_SPRING_DRIVE_TRAILER_N_M: float = 65000.0
const SUSPENSION_DAMPER_N_S_M: float = 3500.0
const SUSPENSION_TRAVEL_M: float = 0.12
const ARB_TRACTOR_FRONT_N_M: float = 30000.0
const ARB_TRACTOR_REAR_N_M: float = 45000.0
const ARB_TRAILER_BOGIE_N_M: float = 35000.0

const STEER_MAX_ANGLE_DEG: float = 35.0
const STEER_SPEED_FALLOFF_M_S: float = 55.0
const STEER_MIN_FACTOR: float = 0.35
const KEYBOARD_STEER_RATE_DEG_S: float = 120.0
const GAMEPAD_STEER_RATE_DEG_S: float = 90.0
const KINGPIN_INCLINATION_DEG: float = 7.7
const SCRUB_RADIUS_M: float = 0.025
const STEERING_WHEEL_TURNS: float = 2.5

# ---------------------------------------------------------------------------
# Collision and damage (section 5.8)
# ---------------------------------------------------------------------------
const STRIKE_FORCE_N: float = 15000.0
const MAX_STRIKES: int = 3

# ---------------------------------------------------------------------------
# Coupling (section 8)
# ---------------------------------------------------------------------------
const COUPLE_DISTANCE_M: float = 0.30
const COUPLE_MAX_ANGLE_DEG: float = 12.0
const COUPLE_MAX_SPEED_M_S: float = 0.5
const ALIGNING_DISTANCE_M: float = 1.5
const UNLOCK_MAX_SPEED_M_S: float = 0.1
const LANDING_GEAR_SPEED_M_S: float = 0.4
const LANDING_CONTACT_HEIGHT_M: float = 0.35

# ---------------------------------------------------------------------------
# Challenges (section 9)
# ---------------------------------------------------------------------------
const DOCK_TARGET_ERROR_M: float = 0.30
const DOCK_HEADING_ERROR_DEG: float = 3.0
