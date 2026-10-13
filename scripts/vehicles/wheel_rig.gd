class_name WheelRig
## One wheel: raycast suspension anchor, tire data and last-step state
## (spec section 5.2 and 5.7). Plain data; CombinationController steps it.

var role: String = "steer"  # steer | drive | bogie
var side: int = 1  # +1 left (+X), -1 right (-X)
var local_pos: Vector3 = Vector3.ZERO  # body-local wheel center at rest
var tire: Dictionary = {}
var spring_k_n_m: float = 1300000.0
var damper_n_s_m: float = 35000.0
var static_share_n: float = 0.0
var normal_n: float = 0.0
var compression_m: float = 0.0
var slip_angle_rad: float = 0.0
var slip_ratio: float = 0.0
var contact_global: Vector3 = Vector3.ZERO
var grounded: bool = false
var ang_vel_rad_s: float = 0.0
var last_lateral_n: float = 0.0
var last_longitudinal_n: float = 0.0
var abs_engaged: bool = false
## Ground surface this wheel last touched: "dry", "wet" or "ice". The
## controller writes it from the suspension ray hit's collider meta (AS4e).
var surface: String = "dry"
## RID of the collider the suspension ray last hit. The surface meta read is
## gated on a change of this RID: String(...) from a Variant allocates, and the
## wheel step runs eight times per tick at 120 Hz.
var ground_rid: RID
var _warned_surfaces: Dictionary = {}


func rolling_radius() -> float:
	return tire["rolling_radius_m"]


func mu() -> float:
	if tire.has("mu_" + surface):
		return tire["mu_" + surface]
	# Unknown surface name: fall back to dry rather than crash, and warn once
	# per name instead of every tick.
	if not _warned_surfaces.has(surface):
		_warned_surfaces[surface] = true
		push_warning("WheelRig.mu: no 'mu_%s' in tire table, falling back to mu_dry" % surface)
	return tire["mu_dry"]


func is_drive() -> bool:
	return role == "drive"
