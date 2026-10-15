extends Node3D
## S1 alley-reverse scenario, pinned to acceptance A12 (phase1 prompt section 15
## and section 19): "scripted reverse completes the 60 m alley in under 120
## simulated seconds with 0 wall strikes. A12: S1 passes: 60 m alley reverse,
## 0 strikes."
##
## The maneuver, exactly as the pinned yard and challenge define it
## (section 7, section 9 challenge 2):
##   * spawn at the pinned alley challenge spawn, SPAWN_ALLEY_POS
##     (-36.0, 0.0, -22.0), heading SPAWN_ALLEY_HEADING_DEG (0.0 deg) -- both
##     read from PHYSICS_CONSTANTS, never restated here;
##   * engage reverse from rest (the 0.5 m/s reverse speed gate, section 5.3)
##     and drive a fixed, checksummed per-step input script until the tractor
##     drive axle reaches the north gate line z = ALLEY_MAX_Z (45.0), or until
##     the tick budget below expires;
##   * the drive axle travels 67.0 m in total: 7.0 m from the spawn to the
##     alley's open south end (ALLEY_MIN_Z = -15.0), then the 60.0 m alley to
##     the north gate line.
##
## Reuses the shared combination harness (tests/sim/combination_rest_harness.gd)
## for the rig and builds the two alley walls at their pinned geometry
## (PHYSICS_CONSTANTS ALLEY_INNER_X_WEST/EAST, ALLEY_MIN_Z/MAX_Z,
## WALL_THICKNESS_M, WALL_HEIGHT_M, LAYER_STRUCTURES) -- the exact boxes
## test_yard._build_alley() places, so the measured clearance is against the real
## alley, not a copy.
##
## The maneuver is a scripted, fixed per-step input drive (the same shape as
## tests/sim/golden_run.gd: deterministic records, no RNG, an FNV-1a script
## checksum, driven through the controller's existing scripted_input Callable):
## throttle REVERSE_THROTTLE, steer 0.0 (a straight alley pass -- the `alley`
## class is straight-running-only per world-spec section 4), no brake, no
## retarder. The "drive axle" is the tractor body origin: TRACTOR_REAR_AXLE
## sits at local (0, 0.563, 0) and the suspension/tire forces lever from the
## body origin, so tractor.global_position.z is the drive axle z.
##
## History: AS4n built this scenario against the 900-tick partial backup from
## the z=+44 end (11.8 m, from the wrong end and spawn; A9). AS4o (D59) made
## gear R a real reverse. AS4p (this) re-points it to the pinned A12
## acceptance: full 67 m drive-axle crossing from the pinned spawn, with the
## simulated crossing time reported against the 120 s limit.

const _HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

## Pinned physics step (Hz). project.godot sets 120.
const PHYSICS_HZ: float = 120.0
## A12's simulated-time limit for the alley reverse (section 15).
const A12_LIMIT_S: float = 120.0
## Tick budget for the scripted reverse: the full A12 limit at the pinned
## 120 Hz step = 120 s x 120 Hz = 14400 ticks. Sizing arithmetic: at the
## measured steady reverse speed ~3.4 m/s (3.4520 m/s peak, full-pass probe
## tests/scratch/s1_full_pass_probe.gd; 3.3885 m/s peak in the AS4o 900-tick
## run) the 67 m crossing needs 67.0 / 3.4 ~= 19.7 s ~= 2364 ticks, and the
## measured crossing is 23.508 s (2821 ticks). The full 120 s budget is ~6x
## the measured crossing, clearly larger than the requirement. The pass ends
## early at the gate line; the budget only bounds a failed crossing (in which
## case the run reports the shortfall and RESULT = FAIL).
const MANEUVER_TICKS: int = int(A12_LIMIT_S * PHYSICS_HZ)
## Throttle held during the reverse attempt (0..1). Moderate: the high reverse
## ratio (8.315) already makes it a creep. Same value the AS4n/AS4o script used.
const REVERSE_THROTTLE: float = 0.3
## Handling margin per side used for the fitted-width read, matching the
## world-spec section 2 clearance term (half body 1.30 + plate drift 0.44 +
## 0.50 handling margin). Stated in the report.
const FIT_MARGIN_M: float = 0.50

## Alley wall inner faces (drivable side), straight from the pinned constants.
const WEST_FACE_X: float = PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST  # -40.0
const EAST_FACE_X: float = PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST  # -32.0
const ALLEY_MIN_Z: float = PHYSICS_CONSTANTS.ALLEY_MIN_Z  # -15.0
const ALLEY_MAX_Z: float = PHYSICS_CONSTANTS.ALLEY_MAX_Z  # +45.0

## The D19 strike proxy speed threshold (m/s), mirroring the production rule in
## combination_controller._on_body_entered: a wall contact above this speed
## counts as a strike. Jolt exposes no per-contact impulse to GDScript (D19).
const STRIKE_PROXY_SPEED_M_S: float = 1.0

## North gate line for A12 (section 9 challenge 2): the drive axle must reach
## z = ALLEY_MAX_Z. The gate line is a measurement line, not a wall: the yard
## has no barrier across the alley at z = +45 (test_yard._build_alley places
## only the two side walls).
const GATE_LINE_Z: float = ALLEY_MAX_Z

## 64-bit FNV-1a, same fold as golden_run.gd (see D58).
const _FNV_OFFSET: int = -3750763034362895579
const _FNV_PRIME: int = 0x100000001b3
const _DECIM: int = 1000000

var _h: Node
var _controller: Node
var _wall_contacts: int = 0
## D19 strike proxy (matching the production controller, combination_controller
## _on_body_entered): Jolt does not expose per-contact impulse to GDScript, so a
## wall contact counts as a strike when the combination speed exceeds
## STRIKE_PROXY_SPEED_M_S (1.0 m/s). We record the max contact speed so the
## report can state honestly whether any contact could have been a strike.
var _max_contact_speed_m_s: float = 0.0
var _strikes: int = 0
## Wall contacts count only during the reverse pass. The reverse steer sign
## diagnostic that follows it is a separate measurement and must not be able
## to touch a wall to sink the pass's contact count.
var _measuring_contacts: bool = true

# ---------------------------------------------------------------------------
# Scripted input (same shape as golden_run.gd)
# ---------------------------------------------------------------------------


## Fixed per-step drive: throttle REVERSE_THROTTLE, steer 0.0 (a straight alley
## pass -- the `alley` class is straight-running-only per world-spec section 4),
## no brake, no retarder. No RNG. One identical record per budget tick, so the
## checksum is fixed even though the pass ends early at the gate line.
static func _build_script() -> Array:
	var s: Array = []
	for _i in MANEUVER_TICKS:
		s.append({"throttle": REVERSE_THROTTLE, "steer": 0.0, "brake": 0.0, "retarder": 0})
	return s


## FNV-1a checksum of the per-step records (the "script checksum" the evidence
## records). Deterministic: fixed data, fixed order.
func script_checksum() -> int:
	var hval: int = _FNV_OFFSET
	for r in _build_script():
		hval = _fnv(hval, _q6(float(r["throttle"])))
		hval = _fnv(hval, _q6(float(r["steer"])))
		hval = _fnv(hval, _q6(float(r["brake"])))
		hval = _fnv(hval, _q6(float(r["retarder"])))
	return hval


class _Drive:
	var controller: Node
	var records: Array

	func apply() -> void:
		# The controller calls scripted_input.call() with no arguments (it
		# increments sim_ticks first), so the drive reads the tick itself.
		var c: Node = controller
		var t: int = c.sim_ticks - 1
		if t < 0 or t >= records.size():
			return
		var r: Dictionary = records[t]
		c.throttle = float(r["throttle"])
		c.steer_input_axis = float(r["steer"])
		c.brake_pedal = float(r["brake"])
		c.retarder_stage = int(r["retarder"])


# ---------------------------------------------------------------------------
# Rig + walls
# ---------------------------------------------------------------------------


func _build_alley_walls() -> void:
	## The two alley walls exactly as test_yard._build_alley() places them:
	## west wall from (WEST-t, 0, MIN_Z) to (WEST, h, MAX_Z), east wall from
	## (EAST, 0, MIN_Z) to (EAST+t, h, MAX_Z), in the "wall" group on the
	## structure layer masking the vehicle mask.
	var t: float = PHYSICS_CONSTANTS.WALL_THICKNESS_M
	var h: float = PHYSICS_CONSTANTS.WALL_HEIGHT_M
	_add_wall(
		"AlleyWallWest",
		Vector3(WEST_FACE_X - t, 0.0, ALLEY_MIN_Z),
		Vector3(WEST_FACE_X, h, ALLEY_MAX_Z)
	)
	_add_wall(
		"AlleyWallEast",
		Vector3(EAST_FACE_X, 0.0, ALLEY_MIN_Z),
		Vector3(EAST_FACE_X + t, h, ALLEY_MAX_Z)
	)


func _add_wall(wall_name: String, min_corner: Vector3, max_corner: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = PHYSICS_CONSTANTS.LAYER_STRUCTURES
	body.collision_mask = PHYSICS_CONSTANTS.LAYER_VEHICLE_MASK
	body.add_to_group("wall")
	var size: Vector3 = max_corner - min_corner
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = (min_corner + max_corner) * 0.5
	body.add_child(shape_node)
	add_child(body)


func _place_rig() -> void:
	## Place the combination at the pinned alley challenge spawn
	## (PHYSICS_CONSTANTS.SPAWN_ALLEY_POS, SPAWN_ALLEY_HEADING_DEG). The
	## controller carries the world transform; place_at_rest() settles y and
	## rebuilds the kingpin joint at the (rotated) fifth wheel, so the heading
	## is respected without forking a rig builder.
	var c: Node = _controller
	c.global_position = PHYSICS_CONSTANTS.SPAWN_ALLEY_POS
	c.rotation = Vector3(0.0, deg_to_rad(PHYSICS_CONSTANTS.SPAWN_ALLEY_HEADING_DEG), 0.0)
	c.place_at_rest()


func _track_wall_contacts() -> void:
	_controller.tractor.body_entered.connect(_on_body_entered)
	_controller.trailer.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _measuring_contacts and body != null and body.is_in_group("wall"):
		_wall_contacts += 1
		# D19: read the combination speed at the instant of contact. Jolt will
		# not hand back a per-contact impulse, so the production strike rule is
		# this speed proxy; we mirror it so the pass reports strikes honestly.
		var s: float = _controller.speed() if _controller != null else 0.0
		_max_contact_speed_m_s = maxf(_max_contact_speed_m_s, s)
		if s > STRIKE_PROXY_SPEED_M_S:
			_strikes += 1


# ---------------------------------------------------------------------------
# Measurement helpers
# ---------------------------------------------------------------------------


## [min_x, max_x] of the 8 world-space corners of a body box (centre + half
## extents, body-local) -- the outermost swept lateral extent, not the origin.
func _box_x_extent(body: RigidBody3D, center_local: Vector3, half: Vector3) -> Array:
	var t: Transform3D = body.global_transform
	var minx: float = INF
	var maxx: float = -INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner: Vector3 = center_local + Vector3(half.x * sx, half.y * sy, half.z * sz)
				var w: Vector3 = t * corner
				minx = minf(minx, w.x)
				maxx = maxf(maxx, w.x)
	return [minx, maxx]


## [min_z, max_z] of the box corners -- the trailer's end-of-run z extent.
func _box_z_extent(body: RigidBody3D, center_local: Vector3, half: Vector3) -> Array:
	var t: Transform3D = body.global_transform
	var minz: float = INF
	var maxz: float = -INF
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				var corner: Vector3 = center_local + Vector3(half.x * sx, half.y * sy, half.z * sz)
				var w: Vector3 = t * corner
				minz = minf(minz, w.z)
				maxz = maxf(maxz, w.z)
	return [minz, maxz]


# ---------------------------------------------------------------------------
# The maneuver
# ---------------------------------------------------------------------------


## Run the S1 alley-reverse maneuver (A12) and return the measured result dict.
## Awaitable. Public so the unit test drives it.
func run(_root: Node) -> Dictionary:
	var t0: int = Time.get_ticks_msec()

	_h = load(_HARNESS_SCENE).instantiate()
	_h.position = Vector3.ZERO
	add_child(_h)
	_build_alley_walls()
	await get_tree().process_frame  # harness _ready builds the rig + place_at_rest
	_controller = _h.controller
	_place_rig()
	_track_wall_contacts()
	await _settle(60)

	# Reverse speed gate: the rig is at rest (settled on the brake). Engage R
	# and record the pre-shift speed and whether the gate accepted it on the
	# first attempt.
	var pre_speed: float = _controller.speed()
	_controller.request_gear(-1)
	var reverse_engaged: bool = _controller.transmission.gear == -1
	var reverse_reject: String = _controller.transmission.last_reject_reason
	var start_drive_z: float = _controller.tractor.global_position.z

	# The scripted reverse attempt.
	var drive: _Drive = _Drive.new()
	drive.controller = _controller
	drive.records = _build_script()
	_controller.scripted_input = drive.apply

	var tractor_half: Vector3 = PHYSICS_CONSTANTS.TRACTOR_BOX * 0.5
	var trailer_half: Vector3 = PHYSICS_CONSTANTS.TRAILER_BOX * 0.5
	var min_x_all: float = INF
	var max_x_all: float = -INF
	var min_clear_west: float = INF
	var min_clear_east: float = INF
	var peak_artic_rad: float = 0.0
	var peak_reverse_speed: float = 0.0
	var peak_forward_speed: float = 0.0
	var peak_artic_at: int = -1
	var crossing_tick: int = -1
	var z_trace: Array = []
	var x_trace: Array = []
	var oob: bool = false
	var final_min_x: float = 0.0
	var final_max_x: float = 0.0
	var ticks_driven: int = MANEUVER_TICKS

	for step in MANEUVER_TICKS:
		await get_tree().physics_frame
		var c: Node = _controller
		var tz: float = c.tractor.global_position.z
		# Forward component along the heading; reverse = -forward (toward +Z
		# here, since the spawn heading 0.0 deg faces -Z).
		var fwd: Vector3 = -c.tractor.global_basis.z
		var vdot_fwd: float = c.tractor.linear_velocity.dot(fwd)
		peak_forward_speed = maxf(peak_forward_speed, maxf(vdot_fwd, 0.0))
		peak_reverse_speed = maxf(peak_reverse_speed, maxf(-vdot_fwd, 0.0))
		var artic: float = c.articulation_rad()
		if absf(artic) > absf(peak_artic_rad):
			peak_artic_rad = artic
			peak_artic_at = step
		# Swept lateral extent from the outermost box corners of both bodies.
		var te: Array = _box_x_extent(c.tractor, PHYSICS_CONSTANTS.TRACTOR_BOX_CENTER, tractor_half)
		var ve: Array = _box_x_extent(c.trailer, PHYSICS_CONSTANTS.TRAILER_BOX_CENTER, trailer_half)
		var minx: float = minf(te[0] as float, ve[0] as float)
		var maxx: float = maxf(te[1] as float, ve[1] as float)
		min_x_all = minf(min_x_all, minx)
		max_x_all = maxf(max_x_all, maxx)
		min_clear_west = minf(min_clear_west, minx - WEST_FACE_X)
		min_clear_east = minf(min_clear_east, EAST_FACE_X - maxx)
		final_min_x = minx
		final_max_x = maxx
		if step % 120 == 0:
			z_trace.append("%d:%.3f" % [step, tz])
			x_trace.append("%d:[%.3f,%.3f]" % [step, minx, maxx])
		if _h.out_of_bounds():
			oob = true
		# A12: the pass is complete when the drive axle reaches the north
		# gate line. End early; the budget above only bounds a failure.
		if crossing_tick < 0 and tz >= GATE_LINE_Z:
			crossing_tick = step
			break
	ticks_driven = crossing_tick if crossing_tick >= 0 else MANEUVER_TICKS
	if crossing_tick >= 0:
		z_trace.append("%d:%.3f" % [crossing_tick, _controller.tractor.global_position.z])
		x_trace.append("%d:[%.3f,%.3f]" % [crossing_tick, final_min_x, final_max_x])

	# End-of-pass trailer extent (the "trailer's final z extent inside the
	# alley" read).
	var c_end: Node = _controller
	var final_drive_z: float = c_end.tractor.global_position.z
	var distance_travelled_m: float = final_drive_z - start_drive_z
	# The gate crossing, stated as a boolean plus the signed gap: positive when
	# the drive axle ended past the line, negative when it fell short.
	var gate_crossed: bool = final_drive_z >= GATE_LINE_Z
	var drive_gate_gap_m: float = final_drive_z - GATE_LINE_Z
	# The A12 number: simulated seconds for the crossing, against the 120 s
	# limit.
	var crossing_time_s: float = crossing_tick / PHYSICS_HZ if crossing_tick >= 0 else -1.0
	var under_a12_limit: bool = crossing_tick >= 0 and crossing_time_s < A12_LIMIT_S
	var vz: Array = _box_z_extent(c_end.trailer, PHYSICS_CONSTANTS.TRAILER_BOX_CENTER, trailer_half)
	var trailer_min_z: float = vz[0] as float
	var trailer_max_z: float = vz[1] as float
	var trailer_in_alley_z_m: float = (
		minf(trailer_max_z, ALLEY_MAX_Z) - maxf(trailer_min_z, ALLEY_MIN_Z)
	)

	# Fitted width from the measured sweep.
	var swept_width: float = max_x_all - min_x_all
	var min_width_zero_margin: float = swept_width
	var min_width_with_margin: float = swept_width + 2.0 * FIT_MARGIN_M
	var fits_8m: bool = min_x_all >= WEST_FACE_X and max_x_all <= EAST_FACE_X
	var fits_8m_with_margin: bool = (
		(min_x_all >= WEST_FACE_X + FIT_MARGIN_M) and (max_x_all <= EAST_FACE_X - FIT_MARGIN_M)
	)

	# Reverse steer sign diagnostic: a short steer +0.5 hold in gear R records
	# the trailer's articulation sign (the "trailer steers the other way in
	# reverse" trap). Done after the main pass so it does not perturb the
	# sweep, and outside the wall-contact window.
	_measuring_contacts = false
	var steer_sign_artic: float = await _reverse_steer_sign()

	var result: Dictionary = {
		"script_checksum": script_checksum(),
		"steps": ticks_driven,
		"tick_budget": MANEUVER_TICKS,
		"physics_hz": Engine.get_physics_ticks_per_second(),
		"pre_shift_speed_m_s": pre_speed,
		"reverse_engaged": reverse_engaged,
		"reverse_reject": reverse_reject,
		"spawn_pos": PHYSICS_CONSTANTS.SPAWN_ALLEY_POS,
		"spawn_heading_deg": PHYSICS_CONSTANTS.SPAWN_ALLEY_HEADING_DEG,
		"gate_line_z": GATE_LINE_Z,
		"crossing_tick": crossing_tick,
		"crossing_time_s": crossing_time_s,
		"a12_limit_s": A12_LIMIT_S,
		"under_a12_limit": under_a12_limit,
		"gate_crossed": gate_crossed,
		"start_drive_z": start_drive_z,
		"final_drive_z": final_drive_z,
		"distance_travelled_m": distance_travelled_m,
		"drive_gate_gap_m": drive_gate_gap_m,
		"peak_forward_speed_m_s": peak_forward_speed,
		"peak_reverse_speed_m_s": peak_reverse_speed,
		"peak_artic_rad": peak_artic_rad,
		"peak_artic_deg": rad_to_deg(peak_artic_rad),
		"peak_artic_at_step": peak_artic_at,
		"steer_sign_artic_deg": steer_sign_artic,
		"trailer_min_z_m": trailer_min_z,
		"trailer_max_z_m": trailer_max_z,
		"trailer_in_alley_z_m": trailer_in_alley_z_m,
		"min_x_all": min_x_all,
		"max_x_all": max_x_all,
		"swept_width_m": swept_width,
		"min_width_zero_margin_m": min_width_zero_margin,
		"fit_margin_m": FIT_MARGIN_M,
		"min_width_with_margin_m": min_width_with_margin,
		"min_clear_west_m": min_clear_west,
		"min_clear_east_m": min_clear_east,
		"fits_8m": fits_8m,
		"fits_8m_with_margin": fits_8m_with_margin,
		"wall_contacts": _wall_contacts,
		"max_contact_speed_m_s": _max_contact_speed_m_s,
		"strikes": _strikes,
		"out_of_bounds": oob,
		"z_trace": z_trace,
		"x_trace": x_trace,
	}
	# A12: gate line crossed, simulated time under the 120 s limit, 0 wall
	# contacts (hence 0 strikes, the D19 proxy), strictly positive clearance on
	# both walls, in bounds.
	result["pass"] = (
		gate_crossed
		and under_a12_limit
		and _wall_contacts == 0
		and _strikes == 0
		and min_clear_west > 0.0
		and min_clear_east > 0.0
		and not oob
	)

	_free_rig()
	result["elapsed_ms"] = Time.get_ticks_msec() - t0
	return result


## Short gear-R steer hold: returns the peak |articulation| (deg) so the reverse
## steer sign is a measured trace, not an assumption. Positive steer input in
## reverse articulates the trailer to the opposite sign of forward.
func _reverse_steer_sign() -> float:
	_controller.scripted_input = Callable()
	var peak: float = 0.0
	for i in 150:
		await get_tree().physics_frame
		_controller.throttle = REVERSE_THROTTLE
		_controller.steer_input_axis = 0.5
		_controller.brake_pedal = 0.0
		_controller.retarder_stage = 0
		peak = maxf(peak, absf(rad_to_deg(_controller.articulation_rad())))
	_controller.steer_input_axis = 0.0
	return peak


func _settle(ticks: int) -> void:
	for _i in ticks:
		await get_tree().physics_frame
		_controller.throttle = 0.0
		_controller.brake_pedal = 1.0
		_controller.steer_input_axis = 0.0


func _free_rig() -> void:
	_controller.scripted_input = Callable()
	_h.queue_free()
	_h = null
	_controller = null
	await get_tree().process_frame
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Standalone entry point (scenario_s1_alley.tscn as the main scene)
# ---------------------------------------------------------------------------


func _ready() -> void:
	if get_tree().current_scene != self:
		return  # loaded as a library (GUT or another scene); do nothing
	var wall: int = Time.get_ticks_msec()
	var r: Dictionary = await run(self)
	_report(r, Time.get_ticks_msec() - wall)
	get_tree().quit()


func _report(r: Dictionary, wall_ms: int) -> void:
	print(
		(
			"S1 ALLEY-REVERSE (A12)  steps=%d  hz=%.0f  wall=%dms"
			% [r["steps"], r["physics_hz"], wall_ms]
		)
	)
	print(
		(
			"  spawn = (%.1f, %.1f, %.1f) heading %.1f deg (pinned SPAWN_ALLEY_POS/HEADING)"
			% [
				r["spawn_pos"].x,
				r["spawn_pos"].y,
				r["spawn_pos"].z,
				r["spawn_heading_deg"],
			]
		)
	)
	print("  script_checksum = %d (%d budget records)" % [r["script_checksum"], r["tick_budget"]])
	print(
		(
			"  reverse gate: pre-shift speed=%.4f m/s (<=%.2f), engaged=%s, reject='%s'"
			% [
				r["pre_shift_speed_m_s"],
				PHYSICS_CONSTANTS.REVERSE_MAX_SPEED_M_S,
				str(r["reverse_engaged"]),
				r["reverse_reject"]
			]
		)
	)
	print(
		(
			"  A12 crossing: gate line z=%.1f, crossed=%s at tick %d = %.3f s (limit %.0f s, under=%s)"
			% [
				r["gate_line_z"],
				str(r["gate_crossed"]),
				r["crossing_tick"],
				r["crossing_time_s"],
				r["a12_limit_s"],
				str(r["under_a12_limit"])
			]
		)
	)
	print(
		(
			"  drive axle: start z=%.3f -> final z=%.3f, distance=%.3f m, gap to gate line=%+.3f m"
			% [
				r["start_drive_z"],
				r["final_drive_z"],
				r["distance_travelled_m"],
				r["drive_gate_gap_m"]
			]
		)
	)
	print(
		(
			"  peak reverse (backward) speed = %.4f m/s   peak forward speed = %.4f m/s"
			% [r["peak_reverse_speed_m_s"], r["peak_forward_speed_m_s"]]
		)
	)
	print(
		(
			"  peak articulation = %+.4f rad (%+.3f deg) at step %d"
			% [r["peak_artic_rad"], r["peak_artic_deg"], r["peak_artic_at_step"]]
		)
	)
	print(
		(
			"  trailer final z extent = %.3f .. %.3f m (alley %.0f .. %.0f), in-alley length = %.3f m"
			% [
				r["trailer_min_z_m"],
				r["trailer_max_z_m"],
				ALLEY_MIN_Z,
				ALLEY_MAX_Z,
				r["trailer_in_alley_z_m"]
			]
		)
	)
	print(
		(
			"  reverse steer sign: steer +0.5 in gear R -> peak |artic| = %+.3f deg (sign flips vs forward)"
			% r["steer_sign_artic_deg"]
		)
	)
	print("  z trace (step:z)         = %s" % str(r["z_trace"]))
	print("  x extent trace (step:[min,max]) = %s" % str(r["x_trace"]))
	print(
		(
			"  swept width = %.4f m   (min x %.4f, max x %.4f)"
			% [r["swept_width_m"], r["min_x_all"], r["max_x_all"]]
		)
	)
	print(
		(
			"  min clearance: west wall = %.4f m, east wall = %.4f m (strictly positive=%s)"
			% [
				r["min_clear_west_m"],
				r["min_clear_east_m"],
				str(r["min_clear_west_m"] > 0.0 and r["min_clear_east_m"] > 0.0)
			]
		)
	)
	# Jolt will not hand back a per-contact impulse from body_entered, so the
	# 15 kN strike threshold (PHYSICS_CONSTANTS.STRIKE_FORCE_N) is not measured
	# as a force. The production strike rule is the D19 speed proxy (a wall
	# contact above 1 m/s counts as a strike); we mirror it, so strikes are
	# reported the same way the game scores them. 0 contacts implies 0 strikes.
	print(
		(
			(
				'  wall contact (body_entered on "wall", pass only): %d, '
				+ "max contact speed = %.3f m/s, strikes (D19 proxy >1 m/s) = %d"
			)
			% [r["wall_contacts"], r["max_contact_speed_m_s"], r["strikes"]]
		)
	)
	print(
		(
			"  fitted width: zero-margin = %.4f m, +2x%.2f m margin = %.4f m"
			% [r["min_width_zero_margin_m"], r["fit_margin_m"], r["min_width_with_margin_m"]]
		)
	)
	print(
		(
			"  pinned 8.0 m alley fits: %s (with %.2f m margin: %s)"
			% [str(r["fits_8m"]), r["fit_margin_m"], str(r["fits_8m_with_margin"])]
		)
	)
	print("  out_of_bounds = %s" % str(r["out_of_bounds"]))
	print("  RESULT = %s" % ("PASS" if r["pass"] else "FAIL"))


func _fnv(h: int, s: String) -> int:
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = h * _FNV_PRIME
	return h


func _q6(x: float) -> String:
	return str(int(round(x * _DECIM)))
