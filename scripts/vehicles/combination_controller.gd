extends Node3D
## CombinationController: owns the tractor and trailer rigid bodies, the
## kingpin joint, the wheel rigs, the driveline and the air system, and drives
## them every physics tick (spec section 5).
##
## Determinism rules (section 15): fixed physics tick (120/s), no RNG, all
## constants from PHYSICS_CONSTANTS, fixed evaluation order, one _step per
## physics frame.

signal jackknife_occurred
signal strike_occurred(body_name: String)
signal coupling_locked
signal coupling_unlocked

const DT: float = 1.0 / float(PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)

@export var cargo_kg: float = PHYSICS_CONSTANTS.CARGO_MASS_DEFAULT_KG

var joint: Generic6DOFJoint3D
var wheels: Array = []
var transmission: Transmission = Transmission.new()
var air: AirSystem = AirSystem.new()
var coupling: CouplingController = CouplingController.new()

var steer_angle_rad: float = 0.0
var steer_input_axis: float = 0.0
var throttle: float = 0.0
var brake_pedal: float = 0.0
var clutch_pedal: float = 0.0
var parking_brake: bool = false
var retarder_stage: int = 0
var engine_running: bool = true
var jackknifed: bool = false
var rollover_flag: bool = false
var engine_rpm: float = PHYSICS_CONSTANTS.ENGINE_IDLE_RPM
var wheel_omega_rad_s: float = 0.0
var sim_ticks: int = 0
var max_lateral_slip: float = 0.0
var max_slip_energy: float = 0.0
var fifth_wheel_load_n: float = 0.0
var total_static_share_n: float = 0.0
var physics_step_ms: float = 0.0
var coupled: bool = true
var scripted_input: Callable = Callable()  # scenario scripts inject inputs here
## Per input device: keyboard 120 deg/s, gamepad 90 deg/s (section 11).
var steer_rate_deg_s: float = PHYSICS_CONSTANTS.KEYBOARD_STEER_RATE_DEG_S
var _prev_forward_speed: float = 0.0
var _prev_velocity: Vector3 = Vector3.ZERO
## Per-body wheel-node caches (D47 pattern, copies CameraRig._PivotCache): the
## tree is walked once per body per controller lifetime, not every tick.
var _steer_l_cache := _WheelNodeCache.new()
var _steer_r_cache := _WheelNodeCache.new()
var _drive_l_cache := _WheelNodeCache.new()
var _drive_r_cache := _WheelNodeCache.new()
var _trailer_fl_cache := _WheelNodeCache.new()
var _trailer_fr_cache := _WheelNodeCache.new()
var _trailer_rl_cache := _WheelNodeCache.new()
var _trailer_rr_cache := _WheelNodeCache.new()

@onready var tractor: RigidBody3D = $Tractor
@onready var trailer: RigidBody3D = $Trailer


func _ready() -> void:
	_build_wheels()
	# The bodies have to be seated BEFORE the joint is created: Godot captures
	# the joint frames from the body transforms at creation, and moving a body
	# afterwards does not move the pivot.
	seat_at_rest()
	_build_joint()
	apply_cargo(cargo_kg)
	air.reset(PHYSICS_CONSTANTS.AIR_NOMINAL_PSI, true)
	transmission.reset()
	transmission.automatic = true
	transmission.gear = 1
	GAME_STATE.coupling_state = GAME_STATE.CouplingState.LOCKED
	GAME_STATE.set_vehicle_state(GAME_STATE.VehicleState.PARKED)
	tractor.body_entered.connect(_on_body_entered)
	trailer.body_entered.connect(_on_body_entered)


func _build_wheels() -> void:
	wheels.clear()
	var half_steer: float = PHYSICS_CONSTANTS.TRACK_HALF_STEER_M
	var half_drive: float = PHYSICS_CONSTANTS.TRACK_HALF_DRIVE_M
	var half_trailer: float = PHYSICS_CONSTANTS.TRACK_HALF_TRAILER_M
	# Tractor wheels (body-local; tractor origin at the drive axle contact patch)
	for side_i in [1, -1]:
		var side: int = int(side_i)
		var w := WheelRig.new()
		w.role = "steer"
		w.side = side
		w.local_pos = Vector3(
			side * half_steer,
			PHYSICS_CONSTANTS.TRACTOR_FRONT_AXLE.y,
			PHYSICS_CONSTANTS.TRACTOR_FRONT_AXLE.z
		)
		w.tire = PHYSICS_CONSTANTS.TIRE_STEER
		w.spring_k_n_m = PHYSICS_CONSTANTS.SUSPENSION_SPRING_STEER_N_M
		w.damper_n_s_m = PHYSICS_CONSTANTS.SUSPENSION_DAMPER_STEER_N_S_M
		wheels.append(w)
	for side_i in [1, -1]:
		var side: int = int(side_i)
		var w := WheelRig.new()
		w.role = "drive"
		w.side = side
		w.local_pos = Vector3(
			side * half_drive,
			PHYSICS_CONSTANTS.TRACTOR_REAR_AXLE.y,
			PHYSICS_CONSTANTS.TRACTOR_REAR_AXLE.z
		)
		w.tire = PHYSICS_CONSTANTS.TIRE_DRIVE
		w.spring_k_n_m = PHYSICS_CONSTANTS.SUSPENSION_SPRING_DRIVE_TRAILER_N_M
		w.damper_n_s_m = PHYSICS_CONSTANTS.SUSPENSION_DAMPER_DRIVE_N_S_M
		wheels.append(w)
	# Trailer bogie wheels
	for axle_v in [PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_1, PHYSICS_CONSTANTS.TRAILER_BOGIE_AXLE_2]:
		var axle: Vector3 = axle_v
		for side_i in [1, -1]:
			var side: int = int(side_i)
			var w := WheelRig.new()
			w.role = "bogie"
			w.side = side
			w.local_pos = Vector3(side * half_trailer, axle.y, axle.z)
			w.tire = PHYSICS_CONSTANTS.TIRE_TRAILER
			w.spring_k_n_m = PHYSICS_CONSTANTS.SUSPENSION_SPRING_DRIVE_TRAILER_N_M
			w.damper_n_s_m = PHYSICS_CONSTANTS.SUSPENSION_DAMPER_TRAILER_N_S_M
			wheels.append(w)


func _build_joint() -> void:
	# Godot class for the spec's Generic6DOFSpringConstraint3D (DEVIATIONS D17).
	#
	# Two Godot-Jolt facts drive this code (probes: tests/probe_joint_axis.gd,
	# tests/probe_angular.gd, tests/probe_joint_hold.gd):
	#   1. angular_limit_*/force_limit defaults to 0.0, and a zero limit lets the
	#      angular constraint apply no torque at all: the trailer free-falls on a
	#      pendulum about the kingpin. The limit must be given a real torque
	#      ceiling to lock pitch and roll.
	#   2. softness / restitution / damping on the limits are unsupported by the
	#      Jolt backend (Godot "Using Jolt Physics" docs). Writing them, notably
	#      softness = 0, silently disables load carrying through the joint.
	#      They are therefore never written here.
	joint = Generic6DOFJoint3D.new()
	joint.name = "KingpinJoint"
	add_child(joint)
	joint.node_a = tractor.get_path()
	joint.node_b = trailer.get_path()
	joint.exclude_nodes_from_collision = true
	# Joint sits at the fifth wheel / kingpin coincidence.
	joint.global_position = tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	# Lock all three linear DOF (rigid kingpin connection): limits 0..0.
	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, true)
		joint.set("linear_limit_%s/lower_distance" % axis, 0.0)
		joint.set("linear_limit_%s/upper_distance" % axis, 0.0)
	# Angular: lock pitch (X) and roll (Z); bound yaw (Y) at the hard limit.
	# Joint-local Y is the vertical kingpin axis (bodies share orientation at
	# the joint, so joint Y is world Y). force_limit is the reaction torque the
	# joint may apply; it must exceed the fifth wheel moment, which is about
	# 1.7e6 N m fully loaded (27 t at a 6.4 m bogie lever).
	var limit_rad: float = deg_to_rad(PHYSICS_CONSTANTS.KINGPIN_HARD_LIMIT_DEG)
	# DEVIATION D23: pitch and roll get a small window instead of a rigid 0 deg
	# lock. A rigid pitch lock couples both suspensions into one statically
	# indeterminate system and pushes the live steer axle to 8,056 kg, over the
	# pinned 7,711 kg cap. 0.15 deg reproduces the pinned static shares within
	# 2 percent (tests/sim/probe_kingpin_window.gd).
	var pr_rad: float = deg_to_rad(PHYSICS_CONSTANTS.KINGPIN_PITCH_ROLL_WINDOW_DEG)
	var torque_ceiling: float = PHYSICS_CONSTANTS.KINGPIN_ANGULAR_LOCK_N_M
	for axis in ["x", "z"]:
		joint.set("angular_limit_%s/enabled" % axis, true)
		joint.set("angular_limit_%s/lower_angle" % axis, -pr_rad)
		joint.set("angular_limit_%s/upper_angle" % axis, pr_rad)
		joint.set("angular_limit_%s/force_limit" % axis, torque_ceiling)
	joint.set("angular_limit_y/enabled", true)
	joint.set("angular_limit_y/lower_angle", -limit_rad)
	joint.set("angular_limit_y/upper_angle", limit_rad)
	joint.set("angular_limit_y/force_limit", torque_ceiling)


func apply_cargo(new_cargo_kg: float) -> void:
	cargo_kg = clampf(new_cargo_kg, 0.0, PHYSICS_CONSTANTS.CARGO_MASS_MAX_KG)
	GAME_STATE.cargo_mass_kg = cargo_kg
	var m_trailer: float = LoadMath.trailer_mass_loaded(cargo_kg)
	var com: Vector3 = LoadMath.trailer_com_loaded(cargo_kg)
	var inertia: Vector3 = LoadMath.trailer_inertia_loaded(cargo_kg)
	trailer.mass = m_trailer
	trailer.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	trailer.center_of_mass = com
	trailer.inertia = inertia
	tractor.mass = PHYSICS_CONSTANTS.TRACTOR_MASS_KG
	tractor.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	tractor.center_of_mass = PHYSICS_CONSTANTS.TRACTOR_COM
	tractor.inertia = Vector3(
		PHYSICS_CONSTANTS.TRACTOR_IX_KG_M2,
		PHYSICS_CONSTANTS.TRACTOR_IY_KG_M2,
		PHYSICS_CONSTANTS.TRACTOR_IZ_KG_M2
	)
	_refresh_static_shares()


func spawn_y_for(body: StringName) -> float:
	## Rest height (m) of a body origin so the suspension starts at its static
	## compression instead of being dropped 0.5 m onto its bump stops.
	var lowest_anchor: float = 1e9
	var max_compression: float = 0.0
	for w in wheels:
		var w_body: StringName = (
			&"Tractor" if (w.role == "steer" or w.role == "drive") else &"Trailer"
		)
		if w_body != body:
			continue
		lowest_anchor = minf(lowest_anchor, w.local_pos.y)
		var share: float = (
			w.static_share_n
			if w.static_share_n > 0.0
			else (PHYSICS_CONSTANTS.TRACTOR_MASS_KG * PHYSICS_CONSTANTS.GRAVITY_M_S2 / 4.0)
		)
		var c: float = clampf(
			share / maxf(w.spring_k_n_m, 1.0), 0.0, PHYSICS_CONSTANTS.SUSPENSION_TRAVEL_M
		)
		max_compression = maxf(max_compression, c)
	if lowest_anchor > 1e8:
		return 0.0
	var radius: float = 0.563
	for w in wheels:
		var w_body: StringName = (
			&"Tractor" if (w.role == "steer" or w.role == "drive") else &"Trailer"
		)
		if w_body == body:
			radius = w.rolling_radius()
			break
	return lowest_anchor - radius - max_compression


func kingpin_error_m() -> float:
	## Distance between the trailer's kingpin point and the tractor's fifth wheel
	## plate center. It must be zero: the joint pins the two bodies at whichever
	## point the joint is seated at, so if the trailer is placed with its kingpin
	## anywhere else the whole trailer pivots about the wrong point.
	var kingpin: Vector3 = trailer.global_transform * PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL
	var fifth: Vector3 = tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	return (kingpin - fifth).length()


func seat_at_rest() -> void:
	## Position both bodies at their suspension rest heights.
	##
	## DEVIATION D34: the trailer's origin IS its kingpin (section 5.1), so it has to sit on the
	## fifth wheel plate rather than on the tractor origin. Without that offset
	## the joint pins the trailer 1.00 m behind its own kingpin and every
	## dimension measured from the pivot is 1 m off
	## (tests/unit/test_kingpin_geometry.gd).
	tractor.position = Vector3(tractor.position.x, spawn_y_for(&"Tractor"), tractor.position.z)
	var seat: Vector3 = (
		PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER - PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL
	)
	trailer.position = Vector3(
		tractor.position.x + seat.x, spawn_y_for(&"Trailer"), tractor.position.z + seat.z
	)


func _set_joint_limits_active(active: bool) -> void:
	## Generic6DOFJoint3D has no top-level "enabled" property in Godot 4.7:
	## assigning joint.enabled fails at runtime with "Invalid assignment of
	## property or key 'enabled'" and leaves the joint attached, so an unlocked
	## trailer was still physically pinned to the tractor. Every DOF has to be
	## released through its own limit (tests/unit/test_kingpin_geometry.gd).
	for axis in ["x", "y", "z"]:
		joint.set("linear_limit_%s/enabled" % axis, active)
		joint.set("angular_limit_%s/enabled" % axis, active)


func rebuild_joint() -> void:
	## Godot captures a Generic6DOFJoint3D's frames from the body transforms when
	## the joint enters the tree, so re-seating a body needs a fresh joint. Any
	## code that moves the combination (place_at_rest, auto coupling) calls this.
	if joint != null and joint.is_inside_tree():
		_set_joint_limits_active(false)
		remove_child(joint)
		joint.queue_free()
	_build_joint()


func place_at_rest() -> void:
	## Scenario scripts and the yard call this instead of guessing spawn heights.
	seat_at_rest()
	rebuild_joint()


func _refresh_static_shares() -> void:
	var g: float = PHYSICS_CONSTANTS.GRAVITY_M_S2
	var steer_n: float = LoadMath.steer_axle_load_kg(cargo_kg) * g
	var drive_n: float = LoadMath.drive_axle_load_kg(cargo_kg) * g
	var bogie_n: float = LoadMath.bogie_axle_load_kg(cargo_kg) * g
	fifth_wheel_load_n = LoadMath.fifth_wheel_load_kg(cargo_kg) * g
	total_static_share_n = 0.0
	for w in wheels:
		match w.role:
			"steer":
				w.static_share_n = steer_n * 0.5
			"drive":
				w.static_share_n = drive_n * 0.5
			"bogie":
				w.static_share_n = bogie_n * 0.25
		total_static_share_n += w.static_share_n


func _physics_process(_delta: float) -> void:
	var t0: int = Time.get_ticks_usec()
	sim_ticks += 1
	if scripted_input.is_valid():
		scripted_input.call()
	_step(DT)
	try_auto_coupling()
	_update_wheel_visuals()
	physics_step_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _step(dt: float) -> void:
	# 1. Steering (section 5.7): rate limited, speed-dependent max angle.
	var speed: float = tractor.linear_velocity.length()
	var max_steer: float = (
		deg_to_rad(PHYSICS_CONSTANTS.STEER_MAX_ANGLE_DEG)
		* maxf(
			PHYSICS_CONSTANTS.STEER_MIN_FACTOR,
			1.0 - speed / PHYSICS_CONSTANTS.STEER_SPEED_FALLOFF_M_S
		)
	)
	var rate: float = deg_to_rad(steer_rate_deg_s) * dt
	var target: float = clampf(steer_input_axis, -1.0, 1.0) * max_steer
	steer_angle_rad = clampf(
		steer_angle_rad + clampf(target - steer_angle_rad, -rate, rate), -max_steer, max_steer
	)

	# 2. Transmission, engine, air.
	var drive_speed: float = _drive_forward_speed()
	# Clutch engaged (automatic): the driveline rigidly couples engine and
	# wheel, so the engine follows the faster side (AS4g). No new clamp.
	engine_rpm = maxf(_engine_rpm(drive_speed), _engine_rpm_from_wheel_rate(wheel_omega_rad_s))
	transmission.auto_shift(engine_rpm, drive_speed)
	air.step(dt, engine_rpm if engine_running else 0.0)
	if engine_rpm >= PHYSICS_CONSTANTS.ENGINE_SHUTDOWN_RPM:
		engine_running = false

	# 3. Articulation state.
	var artic_rad: float = articulation_rad()
	var artic_rate: float = trailer.angular_velocity.y - tractor.angular_velocity.y

	# 4. Load transfer (section 5.2): quasi-static per axle pair, capped 18 percent.
	var transfer_long: float = _load_transfer(dt)

	# 5. Driveline and brake demands. The total ratio is read once per tick
	# here and passed as a plain number: the per-wheel loop must not touch the
	# transmission. The saturated integrator takes the wheel inertia plus the
	# engine-side inertia reflected through this ratio (D53).
	var drive_ratio: float = transmission.ratio()
	var drive_torque_nm: float = _drive_wheel_torque(drive_ratio)
	var wheel_inertia_kg_m2: float = DrivelineModel.effective_inertia_kg_m2(drive_ratio)
	var brake_torques: Dictionary = _brake_wheel_torques()
	var retarder_n: float = 0.0
	if transmission.retarder_allowed(retarder_stage, speed):
		retarder_n = PHYSICS_CONSTANTS.RETARDER_STAGES_KN[retarder_stage]

	max_lateral_slip = 0.0
	max_slip_energy = 0.0

	# 6. Per-wheel suspension and tire forces.
	for w in wheels:
		_step_wheel(
			w, dt, drive_torque_nm, brake_torques, retarder_n, transfer_long, wheel_inertia_kg_m2
		)

	# 7. Kingpin torques (section 5.5) applied to both bodies, equal/opposite.
	if coupled:
		var t_total: float = 0.0
		t_total += KingpinModel.spring_torque_nm(artic_rad)
		t_total += KingpinModel.damping_torque_nm(artic_rate)
		if absf(artic_rate) >= 0.001:
			t_total += KingpinModel.friction_torque_nm(artic_rate)
		else:
			var applied: float = (
				KingpinModel.spring_torque_nm(artic_rad)
				+ KingpinModel.damping_torque_nm(artic_rate)
			)
			t_total += -clampf(
				applied,
				-KingpinModel.static_friction_max_nm(),
				KingpinModel.static_friction_max_nm()
			)
		tractor.apply_torque(Vector3(0.0, -t_total, 0.0))
		trailer.apply_torque(Vector3(0.0, t_total, 0.0))

		# 7b. Coast-down drag and rolling resistance (DEVIATIONS D16), split by mass.
	_apply_coast_forces()

	# 8. Jackknife and rollover rules.
	if not jackknifed and KingpinModel.is_jackknife(rad_to_deg(artic_rad), rad_to_deg(artic_rate)):
		jackknifed = true
		throttle = 0.0
		GAME_STATE.jackknife_events += 1
		GAME_STATE.set_vehicle_state(GAME_STATE.VehicleState.JACKKNIFE)
		jackknife_occurred.emit()
	if absf(_lateral_accel_g()) > PHYSICS_CONSTANTS.ROLLOVER_LATERAL_G:
		rollover_flag = true

	# 8b. Static brake hold: a braked combination that has stopped stays stopped.
	# Brake force opposes motion, so at zero motion nothing holds the rig, and a
	# parked truck would creep off the brake. The hold releases as soon as real
	# motion appears (a shove, a slope, a jackknife).
	if _brakes_applied() and speed <= PHYSICS_CONSTANTS.BRAKE_HOLD_SPEED_M_S:
		tractor.linear_velocity = Vector3.ZERO
		tractor.angular_velocity = Vector3.ZERO
		trailer.linear_velocity = Vector3.ZERO
		trailer.angular_velocity = Vector3.ZERO

	_update_vehicle_state(speed)


func _point_velocity(body: RigidBody3D, global_point: Vector3) -> Vector3:
	## Godot 4.7 RigidBody3D has no get_velocity_at_point, so the rigid body
	## velocity at an offset is computed directly.
	## The lever arm has to be measured from the body's actual center of mass:
	## both bodies run with CENTER_OF_MASS_MODE_CUSTOM, so global_position is the
	## scene origin, not the CoM.
	return (
		body.linear_velocity + body.angular_velocity.cross(global_point - body.get_center_of_mass())
	)


func _step_wheel(
	w: WheelRig,
	dt: float,
	drive_torque_nm: float,
	brake_torques: Dictionary,
	retarder_n: float,
	transfer_long: float,
	wheel_inertia_kg_m2: float
) -> void:
	var body: RigidBody3D = tractor if (w.role == "steer" or w.role == "drive") else trailer
	var anchor_global: Vector3 = body.global_transform * w.local_pos
	var radius: float = w.rolling_radius()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var reach: float = radius + PHYSICS_CONSTANTS.SUSPENSION_TRAVEL_M + 0.5
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		anchor_global, anchor_global + Vector3(0.0, -reach, 0.0), 4, [body.get_rid()]
	)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		w.grounded = false
		w.ground_rid = RID()  # next contact re-reads the surface meta
		w.normal_n = 0.0
		return
	w.grounded = true
	var hit_pos: Vector3 = hit["position"]
	w.contact_global = hit_pos
	# Surface (AS4e): the ground this wheel sits on, tagged on the collider by
	# a "surface" meta. The meta read is gated on the hit collider's RID
	# changing: String(...) from a Variant allocates, and this step runs eight
	# times per tick at 120 Hz. No meta means "dry", so the untagged yard keeps
	# identical behaviour.
	var hit_rid: RID = hit["rid"]
	if hit_rid != w.ground_rid:
		w.ground_rid = hit_rid
		var collider: Object = hit["collider"]
		if collider != null:
			w.surface = String(collider.get_meta("surface", "dry"))
	var gap: float = anchor_global.y - hit_pos.y
	var compression: float = clampf(
		radius - gap, -PHYSICS_CONSTANTS.SUSPENSION_TRAVEL_M, PHYSICS_CONSTANTS.SUSPENSION_TRAVEL_M
	)
	w.compression_m = compression
	# Spring + damper force, applied to the body at the wheel anchor: the
	# suspension carries the vehicle (DEVIATIONS D21). The spring can pull as
	# well as push (rebound travel), so the applied force is signed; only the
	# tire load below it is clamped to non-negative.
	var anchor_vel: Vector3 = (
		body.linear_velocity + body.angular_velocity.cross(anchor_global - body.global_position)
	)
	var suspension_force: float = w.spring_k_n_m * compression - w.damper_n_s_m * anchor_vel.y
	w.normal_n = maxf(0.0, suspension_force)
	body.apply_force(Vector3(0.0, suspension_force, 0.0), _offset_from_origin(body, anchor_global))
	if w.normal_n < w.static_share_n * PHYSICS_CONSTANTS.WHEEL_LOAD_MIN_FRACTION:
		rollover_flag = true  # load drop triggers the rollover check (section 5.2)

	# Load transfer share for this pair (capped).
	var pair_sign: float = 1.0
	if (w.role == "steer" and transfer_long > 0.0) or (w.role != "steer" and transfer_long < 0.0):
		pair_sign = -1.0
	var transferred: float = (
		w.static_share_n * PHYSICS_CONSTANTS.LOAD_TRANSFER_CAP * pair_sign * absf(transfer_long)
	)
	var fz: float = maxf(0.0, w.normal_n + transferred)
	if fz <= 0.0:
		w.last_longitudinal_n = 0.0
		w.last_lateral_n = 0.0
		return

	# Wheel kinematics.
	var offset: Vector3 = w.contact_global - body.global_position
	var v_contact: Vector3 = body.linear_velocity + body.angular_velocity.cross(offset)
	v_contact.y = 0.0
	var heading: Vector3 = -body.global_basis.z  # Godot forward
	var right: Vector3 = body.global_basis.x
	# The slip angle is the angle between the wheel's own heading and its velocity
	# at the contact patch, so the steered axes have to be rotated by the steer
	# angle first. Measuring lateral velocity against the body axes instead makes a
	# steered wheel on a straight-running tractor read zero slip and the combination
	# never turns (found while building the audio evidence pass, which needs a real
	# slide to open the squeal gate).
	var wheel_heading: Vector3 = heading
	var wheel_right: Vector3 = right
	if w.role == "steer":
		wheel_heading = heading.rotated(Vector3.UP, steer_angle_rad)
		wheel_right = right.rotated(Vector3.UP, steer_angle_rad)
	var v_forward: float = v_contact.dot(heading)
	var v_forward_wheel: float = v_contact.dot(wheel_heading)
	var v_lateral_wheel: float = v_contact.dot(wheel_right)
	var speed_ref: float = maxf(absf(v_forward_wheel), 1.0)
	w.slip_angle_rad = atan2(v_lateral_wheel, speed_ref)

	# Longitudinal slip ratio.
	var surface_speed: float = 0.0
	if w.role == "drive":
		surface_speed = wheel_omega_rad_s * radius
	else:
		surface_speed = v_forward_wheel  # free rolling
	w.slip_ratio = (surface_speed - v_forward_wheel) / speed_ref

	var mu: float = w.mu()
	var adhesion: float = mu * fz

	# Longitudinal demand: drive torque and brake torque at the contact patch.
	# Each demand is capped by the friction ellipse below like any other force.
	## DEVIATION D37: a brake force at the contact patch always opposes the direction the tire is
	## actually travelling. Applied in a fixed direction it drags a stopped
	## combination rearward at a steady 2 m/s^2 with the pedal pinned and no
	## throttle: 21 km/h in 3 seconds (tests/scratch/probe_brake.tscn).
	var motion: float = (
		signf(v_forward_wheel)
		if absf(v_forward_wheel) > PHYSICS_CONSTANTS.BRAKE_HOLD_SPEED_M_S
		else 0.0
	)
	var demand_n: float = 0.0
	if w.role == "drive":
		demand_n = (
			(drive_torque_nm * 0.5 - float(brake_torques.get("drive", 0.0)) * motion) / radius
		)
	elif w.role == "steer":
		demand_n = -float(brake_torques.get("front", 0.0)) * motion / radius
	elif w.role == "bogie":
		demand_n = -float(brake_torques.get("bogie", 0.0)) * motion / radius

	# Retarder (DEVIATIONS D20): a driveline braking force that reaches the
	# ground through the combination braking system, so it is distributed over
	# all eight tires in proportion to each wheel's static load share.
	if retarder_n > 0.0 and total_static_share_n > 0.0:
		demand_n -= (
			retarder_n
			* (w.static_share_n / total_static_share_n)
			* signf(v_forward if absf(v_forward) > 0.1 else 1.0)
		)

	# Friction limit and ABS (section 5.2).
	var delivered_n: float = demand_n
	if absf(demand_n) > adhesion:
		var over: float = absf(demand_n) / maxf(adhesion, 1.0) - 1.0
		w.slip_ratio = (
			signf(w.slip_ratio if absf(w.slip_ratio) > 0.0 else demand_n)
			* maxf(absf(w.slip_ratio), over)
		)
		# AS4f: the flat adhesion cap is replaced by the spec's longitudinal
		# mu-slip curve (section 5.2), so the delivered force tracks the
		# wheel's slip instead of holding a constant. Past the curve's peak the
		# force falls, giving the counter-force that makes a spinning wheel
		# self-limiting. The old `adhesion * 0.85` ABS modulation is dropped:
		# the curve's fall past its peak now does that job physically.
		# `braking` selects the Bx column: the demand opposes the wheel's
		# direction of travel when demand_n * v_forward_wheel < 0 (a drive
		# demand and forward travel are same-sign; a brake demand opposes
		# forward travel). Deterministic: at rest both factors are ~0 and the
		# predicate is false (drive column).
		var braking: bool = demand_n * v_forward_wheel < 0.0
		delivered_n = TireModel.longitudinal_force(w.slip_ratio, fz, mu, braking)
		# No clamp needed: the curve is bounded by its own peak. With
		# TIRE_CX = 1.40 the argument Cx * atan(Bx * kappa) spans only
		# +/- 2.199 rad, so sin() reaches 1 exactly at
		# kappa = tan(pi / (2 * TIRE_CX)) / Bx (0.1730 drive, 0.1483 brake)
		# and never exceeds it. delivered_n therefore cannot pass mu * fz,
		# which is `adhesion` here. A clamp on top of that would be dead code.
		if absf(w.slip_ratio) > PHYSICS_CONSTANTS.ABS_ENGAGE_SLIP:
			w.abs_engaged = true
	# ABS release runs every tick for a grounded wheel, not only while
	# saturated: at rest the engine-brake demand is below adhesion, so the wheel
	# sits in the gripping branch and a release check inside the saturated
	# branch would never run, leaving abs_engaged latched after the vehicle
	# stops (AS4f defect 2).
	if w.abs_engaged and absf(w.slip_ratio) < PHYSICS_CONSTANTS.ABS_RELEASE_SLIP:
		w.abs_engaged = false

	w.last_longitudinal_n = delivered_n
	var fy_avail: float = TireModel.lateral_available(fz, mu, delivered_n)
	var fy: float = TireModel.lateral_force(w.slip_angle_rad, fz, mu)
	fy = clampf(fy, -fy_avail, fy_avail)
	w.last_lateral_n = fy

	var lateral_slip_ratio: float = absf(tan(clampf(w.slip_angle_rad, -1.3, 1.3)))
	if lateral_slip_ratio > max_lateral_slip:
		max_lateral_slip = lateral_slip_ratio
		max_slip_energy = lateral_slip_ratio * absf(v_forward)

	# Apply at the contact point (position offsets are global, per RigidBody3D docs).
	## The tire force lives in the wheel plane: longitudinal along the wheel
	## heading, lateral along the wheel right axis.
	var apply_vec: Vector3 = wheel_heading * delivered_n + wheel_right * fy
	body.apply_force(apply_vec, _offset_from_origin(body, w.contact_global))

	# Drive axle angular state for the next tick.
	#
	# The torque-demand model delivers exactly the demand force while the tyre
	# grips (delivered_n == demand_n), so the net torque an integrator sees is ~0
	# every tick and a pure integrator never accumulates (omega stayed 0.000 at
	# speed while the drive-wheel slip read -1.0). While gripping the wheel is on
	# the no-slip line by definition, so set it directly: omega = v_forward_wheel
	# / radius. Only when the friction ellipse saturates does a real torque
	# imbalance exist (the wheel can spin up or lock), so keep the integrator for
	# that transient only -- identical to the pre-fix behaviour in that case.
	# `wheel_inertia_kg_m2` is computed once per tick in _step and passed in as
	# a plain number; the saturated branch is the only place it is used (D53).
	if w.role == "drive":
		if absf(demand_n) <= adhesion:
			wheel_omega_rad_s = v_forward_wheel / radius
		else:
			var net_torque: float = (
				drive_torque_nm * 0.5
				- float(brake_torques.get("drive", 0.0))
				- delivered_n * radius
			)
			wheel_omega_rad_s += net_torque * dt / maxf(wheel_inertia_kg_m2, 0.1)
		wheel_omega_rad_s = clampf(wheel_omega_rad_s, -200.0, 200.0)


func _offset_from_origin(body: RigidBody3D, global_point: Vector3) -> Vector3:
	## Verified on this engine (tests/probe_com_offset.gd, tests/probe_offset_
	## space.gd): apply_force's position offset is in WORLD axes relative to the
	## body ORIGIN, and the resulting torque is taken about the center of mass.
	## Subtracting the CoM here (an earlier mistake) injects a 4.2 m phantom
	## lever arm on every tractor tire force and destabilizes the whole model.
	return global_point - body.global_position


func _update_wheel_visuals() -> void:
	# A5: all 8 wheel nodes steer or rotate. The GLB wheels are MeshInstance3D
	# whose origin sits on the axle (AS4a), so the node itself is the spin
	# target; a placeholder wheel is a Node3D carrying a child named Mesh, so
	# that child spins instead. Each wheel is resolved through
	# ModelPivots.find_pivot with a per-body cache so the tree is walked once
	# per body per lifetime, not every tick (D47, the CameraRig pattern).
	# wheel_omega_rad_s is the DRIVE-AXLE angular rate (rad/s at the drive
	# rolling radius). A wheel of a different rolling radius must spin
	# proportionally to cover the same ground distance:
	# spin_rate = omega * drive_radius / wheel_radius. The steer tyres (0.554 m)
	# are smaller than the drive and bogie tyres (0.563 m), so a single shared
	# rate under-spins the steer axle by 1.6 percent.
	var drive_radius: float = PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
	var steer_spin: float = (
		wheel_omega_rad_s * (drive_radius / PHYSICS_CONSTANTS.TIRE_STEER["rolling_radius_m"]) * DT
	)
	var drive_spin: float = wheel_omega_rad_s * DT  # drive + bogie share the drive radius
	var steer_rad: float = steer_angle_rad
	# Steer axle: spin the wheel first, then set the yaw last so rotation.y
	# reads back exactly the commanded steer angle even though the node itself
	# also spins (the placeholder keeps the identical end state: the child mesh
	# spins, the node's yaw is set).
	for node in [
		_steer_l_cache.resolve_for(tractor, "WheelSteerL"),
		_steer_r_cache.resolve_for(tractor, "WheelSteerR"),
	]:
		if node == null:
			continue
		_spin_wheel(node, steer_spin)
		node.rotation.y = steer_rad
	# Drive axle and trailer bogie: spin only (both share the drive radius).
	for node in [
		_drive_l_cache.resolve_for(tractor, "WheelDriveL"),
		_drive_r_cache.resolve_for(tractor, "WheelDriveR"),
		_trailer_fl_cache.resolve_for(trailer, "TrailerWheelFL"),
		_trailer_fr_cache.resolve_for(trailer, "TrailerWheelFR"),
		_trailer_rl_cache.resolve_for(trailer, "TrailerWheelRL"),
		_trailer_rr_cache.resolve_for(trailer, "TrailerWheelRR"),
	]:
		_spin_wheel(node, drive_spin)


func _spin_wheel(node: Node3D, spin: float) -> void:
	## Spin a wheel about its own axle. The GLB tyre's axle is local X
	## (measured from the build, D48: extents (0.29, 1.11, 1.11)), so a
	## MeshInstance3D wheel rotates about X. A placeholder wheel is a Node3D
	## with a child named Mesh whose cylinder axis is local Z (the mesh is
	## rotated 90 deg about X in the scene), so that child rotates about -Z --
	## the pre-slice behaviour, kept identical so nothing else breaks.
	if node == null:
		return
	if node is MeshInstance3D:
		node.rotate_object_local(Vector3(1.0, 0.0, 0.0), spin)
	else:
		var mesh: Node3D = node.get_node_or_null("Mesh")
		if mesh != null:
			mesh.rotate_object_local(Vector3(0.0, 0.0, -1.0), spin)


func _drive_forward_speed() -> float:
	var fwd: Vector3 = -tractor.global_basis.z
	return tractor.linear_velocity.dot(fwd)


func _engine_rpm_from_wheel_rate(wheel_rate_rad_s: float) -> float:
	# The conversion lives in DrivelineModel (AS4i); this wrapper keeps the
	# state, the current gear ratio, on the controller side.
	return DrivelineModel.engine_rpm_from_wheel_rate(wheel_rate_rad_s, transmission.ratio())


func _engine_rpm(drive_speed: float) -> float:
	var wheel_rate: float = absf(drive_speed) / PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
	return _engine_rpm_from_wheel_rate(wheel_rate)


func _drive_wheel_torque(total_ratio: float = 0.0) -> float:
	if not engine_running or jackknifed:
		return 0.0
	if transmission.gear == 0:
		return 0.0
	var ratio: float = total_ratio if total_ratio > 0.0 else transmission.ratio()
	var engine_nm: float = 0.0
	if throttle > 0.0:
		engine_nm = TireModel.engine_torque_nm(engine_rpm) * throttle
	else:
		engine_nm = -TireModel.engine_brake_torque_nm(engine_rpm)
	# AS4h rev limiter: fuel cut at the pinned redline (1800). The curve is flat
	# 1800-1900, so without it wheelspin drags the engine into the 1900 shutdown.
	# Gated on throttle > 0.0 (engine braking untouched); no hysteresis, no
	# constant.
	if throttle > 0.0 and engine_rpm >= PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM:
		return 0.0  # rev limiter: fuel cut at the pinned redline
	return DrivelineModel.wheel_torque_nm(
		engine_nm, throttle, ratio, 1.0 - _clutch_engagement(), _drive_forward_speed()
	)


func _clutch_engagement() -> float:
	## smoothstep over pedal travel 0.20..0.80 (section 5.3).
	var t: float = clampf(
		(
			(clutch_pedal - PHYSICS_CONSTANTS.CLUTCH_TRAVEL_START)
			/ (PHYSICS_CONSTANTS.CLUTCH_TRAVEL_END - PHYSICS_CONSTANTS.CLUTCH_TRAVEL_START)
		),
		0.0,
		1.0
	)
	return t * t * (3.0 - 2.0 * t)


func _brakes_applied() -> bool:
	return brake_pedal > 0.0 or parking_brake or air.spring_brake_engaged


func _brake_wheel_torques() -> Dictionary:
	var service: float = brake_pedal
	if air.spring_brake_engaged:
		service = 1.0  # spring brake locks drive and trailer axles
	var front: float = PHYSICS_CONSTANTS.BRAKE_TORQUE_FRONT_NM * service
	var drive: float = (
		PHYSICS_CONSTANTS.BRAKE_TORQUE_DRIVE_NM * (service + (1.0 if parking_brake else 0.0))
	)
	var bogie: float = PHYSICS_CONSTANTS.BRAKE_TORQUE_TRAILER_NM * service
	return {"front": front, "drive": drive, "bogie": bogie}


func _apply_coast_forces() -> void:
	## DEVIATIONS D16: air drag (quadratic) and rolling resistance (linear),
	## split across the two bodies by mass share, opposing each body's velocity.
	var m_tot: float = tractor.mass + trailer.mass
	if m_tot <= 0.0:
		return
	var speed: float = speed()
	if speed < 0.05:
		return
	var drag_total: float = (
		0.5 * PHYSICS_CONSTANTS.AIR_DENSITY_KG_M3 * PHYSICS_CONSTANTS.DRAG_CDA_M2 * speed * speed
	)
	var roll_total: float = (
		PHYSICS_CONSTANTS.ROLLING_RESISTANCE_C * m_tot * PHYSICS_CONSTANTS.GRAVITY_M_S2
	)
	var resist: float = drag_total + roll_total
	var share_t: float = tractor.mass / m_tot
	var v_t: Vector3 = tractor.linear_velocity
	var v_v: Vector3 = trailer.linear_velocity
	if v_t.length_squared() > 0.0001:
		tractor.apply_force(-v_t.normalized() * resist * share_t)
	if v_v.length_squared() > 0.0001:
		trailer.apply_force(-v_v.normalized() * resist * (1.0 - share_t))


func _load_transfer(dt: float) -> float:
	## Quasi-static longitudinal load transfer fraction, capped at 18 percent.
	## Positive means weight moves to the drive axle.
	if dt <= 0.0:
		return 0.0
	var fwd: Vector3 = -tractor.global_basis.z
	var now: float = tractor.linear_velocity.dot(fwd)
	var a_long: float = (now - _prev_forward_speed) / dt
	_prev_forward_speed = now
	var h_cg: float = maxf(PHYSICS_CONSTANTS.TRACTOR_COM.y, 1.0)
	var wheelbase: float = (
		PHYSICS_CONSTANTS.TRACTOR_REAR_AXLE.z - PHYSICS_CONSTANTS.TRACTOR_FRONT_AXLE.z
	)
	return clampf(a_long * h_cg / (PHYSICS_CONSTANTS.GRAVITY_M_S2 * wheelbase), -1.0, 1.0)


func _lateral_accel_g() -> float:
	var right: Vector3 = tractor.global_basis.x
	var a: Vector3 = (tractor.linear_velocity - _prev_velocity) / DT
	_prev_velocity = tractor.linear_velocity
	return absf(a.dot(right)) / PHYSICS_CONSTANTS.GRAVITY_M_S2


func articulation_rad() -> float:
	var ft: Vector3 = -tractor.global_basis.z
	var fv: Vector3 = -trailer.global_basis.z
	ft.y = 0.0
	fv.y = 0.0
	if ft.length_squared() < 0.01 or fv.length_squared() < 0.01:
		return 0.0
	var ang: float = atan2(ft.cross(fv).y, ft.dot(fv))
	return wrapf(ang, -PI, PI)


func articulation_deg() -> float:
	return rad_to_deg(articulation_rad())


func articulation_rate_deg_s() -> float:
	return rad_to_deg(trailer.angular_velocity.y - tractor.angular_velocity.y)


func speed() -> float:
	return tractor.linear_velocity.length()


func speed_kmh() -> float:
	return speed() * 3.6


func _update_vehicle_state(speed: float) -> void:
	if jackknifed or GAME_STATE.strikes >= PHYSICS_CONSTANTS.MAX_STRIKES:
		return
	if speed > 0.5 and transmission.gear != 0:
		GAME_STATE.set_vehicle_state(GAME_STATE.VehicleState.DRIVING)
	elif speed <= 0.1:
		GAME_STATE.set_vehicle_state(GAME_STATE.VehicleState.PARKED)


func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("cone"):
		GAME_STATE.cone_contacts += 1
	elif body.is_in_group("wall") or body.is_in_group("building"):
		# DEVIATIONS D19: Jolt does not expose per-contact impulse to GDScript,
		# so the 15 kN strike threshold is applied via a speed proxy: contacts
		# above 1 m/s count as strikes.
		if speed() > 1.0:
			GAME_STATE.strikes += 1
			strike_occurred.emit(String(body.name))
			if GAME_STATE.strikes >= PHYSICS_CONSTANTS.MAX_STRIKES:
				GAME_STATE.set_vehicle_state(GAME_STATE.VehicleState.DESTROYED)


# ---------------------------------------------------------------------------
# Input-facing commands implementing the section 11 no-op rules (all flash a
# HUD reason through GAME_STATE).
# ---------------------------------------------------------------------------


func request_gear(g: int) -> void:
	var clutch_down: bool = clutch_pedal > 0.5
	if not transmission.select_gear(g, speed(), clutch_down):
		GAME_STATE.flash(transmission.last_reject_reason)


func request_range_toggle() -> void:
	if not transmission.toggle_range(speed(), clutch_pedal > 0.5):
		GAME_STATE.flash(transmission.last_reject_reason)


func request_retarder(delta: int) -> void:
	var max_stage: int = PHYSICS_CONSTANTS.RETARDER_STAGES_KN.size() - 1
	var new_stage: int = clampi(retarder_stage + delta, 0, max_stage)
	if new_stage == retarder_stage:
		return
	var reason: String = NoopRules.retarder_reason(
		transmission.range, transmission.gear, speed(), new_stage
	)
	if reason != "":
		GAME_STATE.flash(reason)
		return
	retarder_stage = new_stage


func toggle_parking_brake() -> void:
	parking_brake = not parking_brake


func toggle_transmission_mode() -> void:
	## V: manual <-> automatic. Manual mode is what makes the clutch matter.
	transmission.automatic = not transmission.automatic
	GAME_STATE.flash("TRANSMISSION %s" % ("AUTO" if transmission.automatic else "MANUAL"))


func request_coupler_unlock() -> void:
	if not coupled:
		GAME_STATE.flash("ALREADY DETACHED")
		return
	if not coupling.can_unlock(speed(), parking_brake):
		GAME_STATE.flash(coupling.last_reject_reason)
		return
	coupled = false
	_set_joint_limits_active(false)
	GAME_STATE.set_coupling_state(GAME_STATE.CouplingState.DETACHED)
	coupling_unlocked.emit()
	print("COUPLING: UNLOCKED")


func request_landing_toggle() -> void:
	if not coupling.toggle_landing(coupled, speed()):
		GAME_STATE.flash(coupling.last_reject_reason)
		return
	coupling.step_landing(DT)


func try_auto_coupling() -> void:
	if coupled:
		return
	var kingpin_global: Vector3 = trailer.global_transform * PHYSICS_CONSTANTS.KINGPIN_TRAILER_LOCAL
	var fifth_global: Vector3 = tractor.global_transform * PHYSICS_CONSTANTS.FIFTH_WHEEL_CENTER
	var dist: float = coupling.kingpin_distance_m(kingpin_global, fifth_global)
	if coupling.aligning(dist):
		if GAME_STATE.coupling_state == GAME_STATE.CouplingState.DETACHED:
			GAME_STATE.set_coupling_state(GAME_STATE.CouplingState.ALIGNING)
		## DEVIATION D38: section 11 gates auto-lock on the kingpin's RELATIVE velocity, not on
		## how fast the tractor happens to be going. Using the tractor's speed
		## re-locks a stopped tractor the instant after unlock, and would lock a
		## trailer rolling past it at speed (tests/unit/test_kingpin_geometry.gd).
		var rel_speed: float = (trailer.linear_velocity - tractor.linear_velocity).length()
		if coupling.can_auto_lock(dist, articulation_deg(), rel_speed):
			coupled = true
			## Rebuilt rather than re-enabled: the frames must be captured at the
			## pose the kingpin actually locked at.
			rebuild_joint()
			GAME_STATE.set_coupling_state(GAME_STATE.CouplingState.LOCKED)
			coupling_locked.emit()
			print("COUPLING: LOCKED (CONFIRMED)")
	elif (
		GAME_STATE.coupling_state == GAME_STATE.CouplingState.ALIGNING
		and dist > PHYSICS_CONSTANTS.ALIGNING_DISTANCE_M
	):
		GAME_STATE.set_coupling_state(GAME_STATE.CouplingState.DETACHED)


class _WheelNodeCache:
	## One resolved wheel node, cached per body so the tree is walked at most
	## once per body per controller lifetime (D47, copies CameraRig._PivotCache).
	## Returns null once the body's Model is removed; otherwise re-resolves only
	## when the cached reference fails is_instance_valid (body replaced, model
	## swapped out).
	var body: Node = null
	var node: Node3D = null

	func resolve_for(body: Node, node_name: String) -> Node3D:
		# Re-check the Model parent is present first (D47, the CameraRig pattern):
		# a wheel node is a descendant of the body's Model, and is_instance_valid
		# has a one-frame lag after queue_free, so a freed Model's wheels can
		# briefly report valid and get passed to a typed call. get_node_or_null is
		# an immediate tree check (no lag) and the Model is a direct child, so this
		# is cheap and reliable.
		if body == null or body.get_node_or_null("Model") == null:
			self.node = null
			return null
		var fresh: bool = (
			self.body == body
			and is_instance_valid(self.body)
			and (self.node == null or is_instance_valid(self.node))
		)
		if fresh:
			return self.node
		self.node = ModelPivots.find_pivot(body, node_name)
		self.body = body
		return self.node
