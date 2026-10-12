extends Node
## CITYHAUL physics constants. Single source of truth for all physics values.
## Changing a constant here requires updating docs/physics-spec.md in the same
## commit (see AGENTS.md). Every value that diverges from the build spec is
## marked DEVIATION with an ID pointing to docs/DEVIATIONS.md.
##
## Coordinate convention (docs/physics-spec.md section 0):
## Godot world: -Z forward, +Y up, +X left. Body-local: -Z forward, +Z rearward,
## +X left, +Y up.
## Tractor origin: drive (rear) axle contact patch.
## Trailer origin: kingpin, trailer body extending toward +Z (rearward).

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
# DEVIATION D1: spec CoM z -0.75 (0.75 m ahead of the drive axle) puts 91
# percent of the tractor weight on the steer axle and leaves the drive axle
# almost no traction. -4.20 (4.2 m ahead of the drive axle) is the real tandem
# tractor position and, with D2, reproduces the spec's own T14 steer targets.
const TRACTOR_COM: Vector3 = Vector3(0.0, 1.30, -4.20)
# DEVIATION D2: spec fifth wheel center z -7.45 is 0.95 m AHEAD of the steer
# axle (-6.50), geometrically impossible. -1.00 is the real tandem position:
# 1 m ahead of the drive axle, 5.5 m behind the steer axle.
const FIFTH_WHEEL_CENTER: Vector3 = Vector3(0.0, 1.30, -1.00)
const TRACTOR_BOX: Vector3 = Vector3(2.50, 3.30, 10.50)
# Box origin offset: the 10.50 m box spans z -3.00..+7.50 from the drive axle.
const TRACTOR_BOX_CENTER: Vector3 = Vector3(0.0, 1.65, 2.25)
# DEVIATION D8: spec values 32,133 / 30,975 / 9,758 are not the uniform box of
# 8,400 kg over 2.50 x 3.30 x 10.50 m. Recomputed from the spec's own method.
const TRACTOR_IX_KG_M2: float = 84798.0
const TRACTOR_IY_KG_M2: float = 81550.0
const TRACTOR_IZ_KG_M2: float = 11998.0

# ---------------------------------------------------------------------------
# Trailer (section 5.1)
# ---------------------------------------------------------------------------
const TRAILER_MASS_EMPTY_KG: float = 7000.0
# DEVIATION D3: spec bogie axles at z 11.80/12.60 (mean 12.20) sit too far
# behind the kingpin for the spec CoM, which sends 26,786 kg through the
# kingpin at full load and tips the combination onto the steer axle.
# 9.60/10.40 (mean 10.00 m) is the real 53 ft van kingpin-to-bogie distance.
const TRAILER_BOGIE_AXLE_1: Vector3 = Vector3(0.0, 0.563, 9.60)
const TRAILER_BOGIE_AXLE_2: Vector3 = Vector3(0.0, 0.563, 10.40)
# DEVIATION D4: spec z -7.70 lies outside the trailer box (z -2.40..+13.75
# from the kingpin) and 19.9 m ahead of the bogie. Real 53 ft van empty CoM:
# 6.00 m rearward of the kingpin.
const TRAILER_COM_EMPTY: Vector3 = Vector3(0.0, 1.55, 6.00)
const TRAILER_BOX: Vector3 = Vector3(2.59, 4.07, 16.15)
# Box origin offset: the 16.15 m box spans z -2.40..+13.75 from the kingpin.
const TRAILER_BOX_CENTER: Vector3 = Vector3(0.0, 2.035, 5.675)
# DEVIATION D9: spec values 415,000 / 331,000 / 113,600 are not the uniform box
# of 7,000 kg over 2.59 x 4.07 x 16.15 m. Recomputed from the spec's own method.
const TRAILER_IX_EMPTY_KG_M2: float = 161809.0
const TRAILER_IY_EMPTY_KG_M2: float = 156060.0
const TRAILER_IZ_EMPTY_KG_M2: float = 13576.0
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
# DEVIATION D20: the retarder is a driveline device but the spec never says how
# its stage force (D13: read as N) reaches the ground. Confining it to the two
# drive tires skids them, so the stage force is distributed over all eight tires
# in proportion to each wheel's static load share and capped by the friction
# ellipse like any other brake demand. With the pinned mu values the loaded
# combination stops in 27..28 m from 80 km/h at stage 5 plus service brake, the
# middle of the spec S3 window.
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
const GEAR_RATIOS: Array = [
	0.0, 4.834, 2.857, 1.840, 1.290, 1.000, 9.015, 5.324, 3.427, 2.403, 1.864
]
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

# DEVIATION D16: the spec has no coast-down mechanism (no drag, no rolling
# resistance), so a throttled combination accelerates without bound below the
# governor and the governor becomes the only speed limit. Standard truck air
# drag and rolling resistance added so idle/coast behavior is physical.
const DRAG_CDA_M2: float = 3.0
const ROLLING_RESISTANCE_C: float = 0.008
const AIR_DENSITY_KG_M3: float = 1.225

# DEVIATION D18: automatic mode must not lug the engine. Auto downshift is
# only allowed when the target gear's idle speed is still above current speed,
# and auto mode never upshifts into the low range above 15 km/h (low range is
# for starting and crawling; the retarder rule already assumes this).
const AUTO_LOW_RANGE_MAX_SPEED_M_S: float = 4.1667  # 15 km/h

# ---------------------------------------------------------------------------
# Kingpin and articulation (section 5.5)
# ---------------------------------------------------------------------------
const KINGPIN_HARD_LIMIT_DEG: float = 75.0
const JACKKNIFE_WARN_DEG: float = 60.0
# DEVIATION D22: Godot-Jolt angular limits default to force_limit 0.0, and a
# zero ceiling makes the angular constraint apply no torque at all
# (tests/probe_angular.gd). The kingpin lock therefore needs an explicit
# reaction-torque ceiling. It must exceed the fifth wheel moment: fully loaded
# the trailer pushes 1.7e6 N m down on the kingpin (36,000 kg trailer at a
# 6.4 m bogie lever), so 2.0e7 N m gives an order of magnitude of headroom
# while staying far below the point where the solver starts trading stability
# for penetration.
const KINGPIN_LOCK_TORQUE_N_M: float = 2.0e7
# DEVIATION D23: the spec locks pitch and roll at exactly 0 degrees. A rigid
# pitch lock couples the tractor and trailer suspensions into one statically
# indeterminate system: the joint transmits a parasitic pitch moment, and the
# live steer axle load rises to 8,056 kg, above the pinned 7,711 kg cap
# (tests/sim/probe_kingpin_window.gd). A real fifth wheel bearing is not a
# rigid weld; it has a small pitch/roll give before the plates bind. A 0.15 deg
# window reproduces the pinned static axle shares to within 2 percent
# (steer 1.01, drive 0.98, bogie 1.00) and holds the steer axle at 7,031 kg.
const KINGPIN_PITCH_ROLL_WINDOW_DEG: float = 0.15
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
# DEVIATION D5: spec value (0, 1.70, -5.80). Sign corrected to the bogie side
# (same error as D4). z 6.51 m rearward is the loaded 53 ft van cargo position
# that reproduces the spec's own T14 target: 7,416 kg steer axle at full cargo
# (spec target 7,417, 0.02 percent off).
const CARGO_COM: Vector3 = Vector3(0.0, 1.70, 6.51)
# Spec pins this as the steer axle cap. Note: 7,711 kg (17,000 lb) is the US
# legal limit for a single axle group / fifth wheel; the US steer axle limit is
# 5,443 kg. The spec value is retained as pinned and applied to the steer axle.
const STEER_AXLE_LEGAL_CAP_KG: float = 7711.0

# ---------------------------------------------------------------------------
# Suspension and steering (section 5.7)
# ---------------------------------------------------------------------------
# DEVIATION D12: spec spring rates (55/65 kN/m) sag 0.5..1.7 m under the spec
# masses, far beyond the pinned +/- 0.12 m travel. Rates scaled x20 so static
# compression lands at 0.03..0.09 m, inside travel, matching real truck steel
# and air spring stiffness. Damper scaled with the spring rate to about 20
# percent of critical damping per corner (spec 3,500 N s/m is 1.5 percent of
# critical at the scaled spring rate and rings for seconds).
const SUSPENSION_SPRING_STEER_N_M: float = 1100000.0
const SUSPENSION_SPRING_DRIVE_TRAILER_N_M: float = 1300000.0
const SUSPENSION_DAMPER_STEER_N_S_M: float = 30000.0
const SUSPENSION_DAMPER_DRIVE_N_S_M: float = 46000.0
const SUSPENSION_DAMPER_TRAILER_N_S_M: float = 42000.0
const SUSPENSION_TRAVEL_M: float = 0.12
# DEVIATION D21: the spec body boxes span ground to roof. If the collider
# bottom sits at the ground plane, Jolt contacts (with contact friction) carry
# the vehicle and the suspension carries nothing; braking then happens through
# collider friction instead of the tire model. Collider bottoms are inset to
# real structural heights (tractor frame rail 0.30 m, trailer deck 1.20 m) and
# the spring forces are applied to the body at the wheel anchors, so the
# suspension carries the vehicle and the tires do the braking. Box sizes used
# for inertia (D8/D9) are unchanged.
const TRACTOR_COLLIDER_BOTTOM_M: float = 0.30
const TRAILER_COLLIDER_BOTTOM_M: float = 1.20
const ARB_TRACTOR_FRONT_N_M: float = 600000.0
const ARB_TRACTOR_REAR_N_M: float = 900000.0
const ARB_TRAILER_BOGIE_N_M: float = 700000.0
# Derived (not spec-pinned): wheel rotational inertia for ABS slip dynamics.
const WHEEL_INERTIA_KG_M2: float = 2.0

const STEER_MAX_ANGLE_DEG: float = 35.0
const STEER_SPEED_FALLOFF_M_S: float = 55.0
const STEER_MIN_FACTOR: float = 0.35
const KEYBOARD_STEER_RATE_DEG_S: float = 120.0
const GAMEPAD_STEER_RATE_DEG_S: float = 90.0
const KINGPIN_INCLINATION_DEG: float = 7.7
const SCRUB_RADIUS_M: float = 0.025
const STEERING_WHEEL_TURNS: float = 2.5

# Derived geometry (not spec-pinned; documented in docs/physics-spec.md):
# per-side track half widths used for the wheel anchors.
const TRACK_HALF_STEER_M: float = 1.10
const TRACK_HALF_DRIVE_M: float = 1.10
const TRACK_HALF_TRAILER_M: float = 1.05

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

# ---------------------------------------------------------------------------
# Collision layers (docs/physics-spec.md section 0). Values are bit masks.
# ---------------------------------------------------------------------------
const LAYER_TRACTOR: int = 1
const LAYER_TRAILER: int = 2
const LAYER_GROUND: int = 4
const LAYER_STRUCTURES: int = 8
const LAYER_CONES: int = 16
const LAYER_COUPLING: int = 32

# ---------------------------------------------------------------------------
# Test yard (section 7). Everything flat: the pinned surface is a single level
# plane (DEVIATION D24).
# ---------------------------------------------------------------------------
const YARD_MIN_X: float = -70.0
const YARD_MAX_X: float = 70.0
const YARD_MIN_Z: float = -45.0
const YARD_MAX_Z: float = 45.0
const WALL_HEIGHT_M: float = 3.0
const WALL_THICKNESS_M: float = 0.4
const WAREHOUSE_MIN_X: float = -20.0
const WAREHOUSE_MAX_X: float = 70.0
const WAREHOUSE_MIN_Z: float = 45.0
const WAREHOUSE_MAX_Z: float = 60.0
const STORY_HEIGHT_M: float = 3.0
const WAREHOUSE_STORIES: int = 4
const DOCK_SLOT_CENTERS_X: Array = [-10.0, 0.0, 10.0, 20.0, 30.0]
const DOCK_SLOT_WIDTH_M: float = 4.0
const DOCK_BUMPER_Z: float = 44.8
# DEVIATION D25: the spec numbers the slots B1..B5 at x -10, 0, 10, 20, 30 but
# puts the four dock challenge cones at x 28 and 32, which bracket the slot at
# x 30 (a 4.0 m slot centered on 30). The explicit cone meters are authoritative
# for the challenge target, so the dock challenge targets x 30. No coordinate is
# changed; only the label mapping is recorded here.
const DOCK_TARGET_X: float = 30.0
const ALLEY_INNER_X_WEST: float = -40.0
const ALLEY_INNER_X_EAST: float = -32.0
const ALLEY_MIN_Z: float = -15.0
const ALLEY_MAX_Z: float = 45.0
const STAGING_PAD_CENTER: Vector3 = Vector3(0.0, 0.0, -30.0)
const STAGING_PAD_WIDTH_X_M: float = 22.0
const STAGING_PAD_LENGTH_Z_M: float = 14.0
const SERPENTINE_CONE_X: Array = [-50.0, -35.0, -20.0, -5.0, 10.0, 25.0, 40.0, 55.0]
const SERPENTINE_CONE_Z_ABS_M: float = 2.0
const DOCK_CONE_X: Array = [28.0, 32.0]
const DOCK_CONE_Z: Array = [34.0, 42.0]
const CONE_HEIGHT_M: float = 0.7
const CONE_BASE_DIAMETER_M: float = 0.36
const CONE_COUNT: int = 12
const YARD_DRAW_CALL_BUDGET: int = 80
const SUN_ELEVATION_DEG: float = 45.0
const SUN_CLOCK_HOUR: float = 10.5
const SUN_SHADOW_MAP_SIZE: int = 2048
const SUN_SHADOW_FADE_FROM_M: float = 120.0

# Spawn points (section 7). Heading is rotation.y in Godot degrees: 0 faces
# -Z, 180 faces +Z.
const SPAWN_FREE_POS: Vector3 = Vector3(-55.0, 0.0, -35.0)
const SPAWN_FREE_HEADING_DEG: float = 15.0
const SPAWN_DOCK_POS: Vector3 = Vector3(0.0, 0.0, -30.0)
const SPAWN_DOCK_HEADING_DEG: float = 180.0
const SPAWN_ALLEY_POS: Vector3 = Vector3(-36.0, 0.0, -22.0)
const SPAWN_ALLEY_HEADING_DEG: float = 0.0
const SPAWN_SERPENTINE_POS: Vector3 = Vector3(-60.0, 0.0, 0.0)
const SPAWN_SERPENTINE_HEADING_DEG: float = 0.0
