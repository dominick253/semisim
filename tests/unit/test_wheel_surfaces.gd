extends GutTest
## AS4e: surface-dependent tire friction.
##
## WheelRig.mu() used to return tire["mu_dry"] unconditionally, so the mu_wet
## and mu_ice columns in PHYSICS_CONSTANTS were dead data and the friction
## ellipse never saturated (21,314 N demand against a 65,654 N adhesion limit
## on the dry yard, abs_engaged false, docs/evidence/phase1/wheel_roll.txt).
##
## The channel: the suspension ray hit carries the collider, and the
## controller stores the hit collider RID per wheel, reading the collider's
## "surface" meta only when the RID changes. No meta means "dry", so the
## default yard (no meta anywhere) keeps byte-identical behaviour.
##
## These tests prove:
##   1. mu() reads the right column for each surface name (exact pinned values).
##   2. The surface comes from what the suspension ray actually hits
##      (contact-based, not a global switch), and returns to dry when the
##      tagged ground is replaced by an untagged one.
##   3. On ice the drive tyre saturates, spins up past v over radius and
##      engages ABS.
##   4. On dry the same launch never engages ABS and stays on the no-slip
##      line, so the AS4d behaviour is untouched.
##   5. An unknown surface name falls back to mu_dry without crashing.

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const SETTLE_TICKS: int = 240
const LAUNCH_TICKS: int = 360
const MU_DRIVE_DRY: float = 1.15  # PHYSICS_CONSTANTS.TIRE_DRIVE["mu_dry"]
const MU_DRIVE_WET: float = 0.72  # PHYSICS_CONSTANTS.TIRE_DRIVE["mu_wet"]
const MU_DRIVE_ICE: float = 0.25  # PHYSICS_CONSTANTS.TIRE_DRIVE["mu_ice"]

var _harness: Node


func _drive_wheel(c: Node) -> WheelRig:
	for w in c.wheels:
		if w.role == "drive":
			return w
	return null


func _swap_ground(surface: String) -> void:
	## Replace the harness ground with a new StaticBody3D (same 300 x 300 m
	## box, top at y = 0, so the vehicle never has to fall onto it). The meta
	## goes on the StaticBody3D because intersect_ray's `collider` key is the
	## collision object, not the shape. The new body is added and let register
	## BEFORE the old one is freed: a free-then-add gap drops the vehicle onto
	## the new ground hard enough to ring the suspension to 191 kN per drive
	## wheel (measured during the RED run of this file).
	var old: Node = _harness.get_node_or_null("Ground")
	var body := StaticBody3D.new()
	body.name = "GroundSwap"
	body.collision_layer = PHYSICS_CONSTANTS.LAYER_GROUND
	body.collision_mask = PHYSICS_CONSTANTS.LAYER_VEHICLE_MASK
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300.0, 2.0, 300.0)
	shape.shape = box
	shape.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(shape)
	if surface != "":
		body.set_meta("surface", surface)
	_harness.add_child(body)
	await _harness.settle(3)
	if old != null:
		old.queue_free()
	await _harness.settle(3)


func _make_harness() -> Node:
	var h: Node = load(HARNESS_SCENE).instantiate()
	add_child(h)
	await h.settle(SETTLE_TICKS)
	return h


func _free_harness() -> void:
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame


func _launch(c: Node, ticks: int) -> Dictionary:
	## Full-throttle launch from rest for `ticks` physics ticks, sampling the
	## drive wheel every tick. Returns the measured peaks; max_demand_over_
	## adhesion is the worst single-tick demand / (mu * normal_n) ratio.
	c.throttle = 1.0
	var max_demand: float = 0.0
	var max_adhesion: float = 0.0
	var max_demand_over_adhesion: float = 0.0
	var max_omega_over_noslip: float = 0.0
	var max_slip: float = 0.0
	var abs_seen: bool = false
	var v: float = 0.0
	for _i in ticks:
		await get_tree().physics_frame
		var w: WheelRig = _drive_wheel(c)
		if w == null or not w.grounded:
			continue
		v = c.tractor.linear_velocity.dot(-c.tractor.global_basis.z)
		var radius: float = w.rolling_radius()
		var adhesion: float = w.mu() * w.normal_n
		var motion: float = 1.0 if v > PHYSICS_CONSTANTS.BRAKE_HOLD_SPEED_M_S else 0.0
		var demand: float = (
			(
				c._drive_wheel_torque() * 0.5
				- float(c._brake_wheel_torques().get("drive", 0.0)) * motion
			)
			/ radius
		)
		max_demand = maxf(max_demand, demand)
		max_adhesion = maxf(max_adhesion, adhesion)
		if adhesion > 1.0:
			max_demand_over_adhesion = maxf(max_demand_over_adhesion, demand / adhesion)
		max_slip = maxf(max_slip, absf(w.slip_ratio))
		if w.abs_engaged:
			abs_seen = true
		if absf(v) > 0.3:
			max_omega_over_noslip = maxf(
				max_omega_over_noslip, c.wheel_omega_rad_s / (absf(v) / radius)
			)
	return {
		"max_demand": max_demand,
		"max_adhesion": max_adhesion,
		"max_demand_over_adhesion": max_demand_over_adhesion,
		"max_omega_over_noslip": max_omega_over_noslip,
		"max_slip": max_slip,
		"abs_seen": abs_seen,
		"v_final": v,
	}


# --- 1. Table wiring -------------------------------------------------------


func test_mu_reads_the_pinned_surface_values() -> void:
	var w := WheelRig.new()
	w.tire = PHYSICS_CONSTANTS.TIRE_DRIVE
	assert_eq(w.surface, "dry", "default surface must be dry")
	assert_eq(
		w.mu(), MU_DRIVE_DRY, "default surface mu() = %f, want mu_dry %f" % [w.mu(), MU_DRIVE_DRY]
	)
	w.surface = "ice"
	assert_eq(
		w.mu(), MU_DRIVE_ICE, "ice mu() = %f, want the pinned mu_ice %f" % [w.mu(), MU_DRIVE_ICE]
	)
	w.surface = "wet"
	assert_eq(
		w.mu(), MU_DRIVE_WET, "wet mu() = %f, want the pinned mu_wet %f" % [w.mu(), MU_DRIVE_WET]
	)


# --- 2. Contact wiring -----------------------------------------------------


func test_ice_ground_sets_the_wheel_surface() -> void:
	_harness = await _make_harness()
	# The default ground carries no meta: everything must read dry.
	for w in _harness.controller.wheels:
		assert_eq(w.surface, "dry", "wheel %s surface before swap" % w.role)
	await _swap_ground("ice")
	await _harness.settle(180)
	var grounded: int = 0
	for w in _harness.controller.wheels:
		if w.grounded:
			grounded += 1
			assert_eq(
				w.surface,
				"ice",
				(
					"grounded wheel %s (side %d) surface = %s after grounding on ice"
					% [w.role, w.side, w.surface]
				)
			)
	assert_eq(grounded, 8, "all eight wheels must be grounded on the ice ground")
	var drive: WheelRig = _drive_wheel(_harness.controller)
	assert_eq(
		drive.mu(),
		MU_DRIVE_ICE,
		"drive wheel mu() = %f after grounding on ice, want %f" % [drive.mu(), MU_DRIVE_ICE]
	)
	# Replace the tagged ground with an untagged one: the channel must return
	# to dry. This is the proof the surface is contact-based, not sticky.
	await _swap_ground("")
	await _harness.settle(180)
	for w in _harness.controller.wheels:
		assert_eq(
			w.surface,
			"dry",
			"wheel %s surface = %s after the ice ground was removed" % [w.role, w.surface]
		)
	await _free_harness()


# --- 3. Saturation becomes reachable on ice ---------------------------------


func test_ice_launch_saturates_the_drive_tyre_and_engages_abs() -> void:
	_harness = await _make_harness()
	await _swap_ground("ice")
	await _harness.settle(180)
	var m: Dictionary = await _launch(_harness.controller, LAUNCH_TICKS)
	var noslip_at_end: float = m.v_final / _drive_wheel(_harness.controller).rolling_radius()
	assert_gt(m.v_final, 1.0, "launch did not actually move: v_final %.3f m/s" % m.v_final)
	assert_gt(
		m.max_demand_over_adhesion,
		1.0,
		(
			(
				"ice: drive demand never exceeded mu()*normal on a sampled tick: peak ratio %.3f "
				+ "(peak demand %.0f N, peak adhesion %.0f N)"
			)
			% [m.max_demand_over_adhesion, m.max_demand, m.max_adhesion]
		)
	)
	assert_gt(
		m.max_omega_over_noslip,
		1.10,
		(
			"ice: omega never exceeded v/r by 10 percent: peak ratio %.3f (omega %.2f rad/s vs v/r %.2f)"
			% [m.max_omega_over_noslip, m.max_omega_over_noslip * noslip_at_end, noslip_at_end]
		)
	)
	assert_true(
		m.abs_seen,
		(
			(
				"ice: abs_engaged never became true on the drive wheel (peak slip %.3f, "
				+ "peak demand %.0f N vs peak adhesion %.0f N)"
			)
			% [m.max_slip, m.max_demand, m.max_adhesion]
		)
	)
	await _free_harness()


# --- 4. Dry regression ------------------------------------------------------


func test_dry_launch_keeps_abs_off_and_stays_on_the_noslip_line() -> void:
	_harness = await _make_harness()
	var m: Dictionary = await _launch(_harness.controller, LAUNCH_TICKS)
	var drive: WheelRig = _drive_wheel(_harness.controller)
	assert_gt(m.v_final, 1.0, "launch did not actually move: v_final %.3f m/s" % m.v_final)
	assert_false(
		m.abs_seen,
		(
			(
				"dry: abs_engaged became true on the drive wheel (peak demand %.0f N vs peak adhesion %.0f N, "
				+ "peak slip %.3f)"
			)
			% [m.max_demand, m.max_adhesion, m.max_slip]
		)
	)
	assert_false(drive.abs_engaged, "dry: drive wheel abs_engaged still true at end of run")
	assert_lt(
		m.max_slip, 0.05, "dry: slip ratio left the no-slip line, max |slip| %.4f" % m.max_slip
	)
	await _free_harness()


# --- 5. Unknown name safety --------------------------------------------------


func test_unknown_surface_falls_back_to_dry() -> void:
	var w := WheelRig.new()
	w.tire = PHYSICS_CONSTANTS.TIRE_DRIVE
	w.surface = "moon"
	assert_eq(
		w.mu(),
		MU_DRIVE_DRY,
		(
			"unknown surface 'moon' must fall back to mu_dry: mu() = %f, want %f"
			% [w.mu(), MU_DRIVE_DRY]
		)
	)
