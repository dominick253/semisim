extends Node3D
## S1 alley-reverse scenario (A9: phase2-plan line 41; world-spec minimum street
## width, section 4 `alley` class). No scenario scripts existed before this one;
## `ls tests/sim/` held only harnesses, probes and shots.
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
## start the combination at the alley mouth, reverse it down the 8.0 m alley from
## the z=+45 end toward z=-15, and measure
##   1. minimum clearance per wall from the OUTERMOST body-box points (swept width,
##      not the origin)
##   2. whether any wall contact happened during the backup pass (collision-notify:
##      body_entered on the "wall" group)
##   3. peak articulation and peak reverse speed
##   4. whether the trailer ends inside the alley (box corners in x and z)
##   5. the fitted alley width the measured sweep clears, and whether the pinned
##      8.0 m alley fits
##   6. out_of_bounds() at the end (the AS4l2 helper)
##
## AS4o (D59) re-point: the drivetrain reverse-direction fix (gear R sign-flips
## the drive-wheel torque in combination_controller.gd) makes this a REAL
## completed backup. Measured (b95f299 + fix): delta_z -11.818 m over 900 ticks,
## peak reverse speed 3.3885 m/s, swept width 2.5935 m, min clearance west
## 2.7043 m / east 2.7022 m, wall contacts 0, trailer ends inside the alley
## (z 19.43..35.58 within the -15..+45 alley), out_of_bounds false.

const _HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

## Pinned physics step (Hz). project.godot sets 120.
const PHYSICS_HZ: float = 120.0
## Length of the scripted reverse attempt (ticks). 900 ticks = 7.5 s.
const MANEUVER_TICKS: int = 900
## Throttle held during the reverse attempt (0..1). Moderate: the high reverse
## ratio (8.315) already makes it a creep.
const REVERSE_THROTTLE: float = 0.3
## A completed back-down is a backward (toward -15) displacement of the drive
## axle of at least this much. The real backup covers ~11.8 m in the budget.
const REVERSE_TARGET_M: float = 1.0
## Handling margin per side used for the fitted-width read, matching the
## world-spec section 2 clearance term (half body 1.30 + plate drift 0.44 +
## 0.50 handling margin). Stated in the report.
const FIT_MARGIN_M: float = 0.50

## Alley wall inner faces (drivable side), straight from the pinned constants.
const WEST_FACE_X: float = PHYSICS_CONSTANTS.ALLEY_INNER_X_WEST  # -40.0
const EAST_FACE_X: float = PHYSICS_CONSTANTS.ALLEY_INNER_X_EAST  # -32.0
const ALLEY_MIN_Z: float = PHYSICS_CONSTANTS.ALLEY_MIN_Z  # -15.0
const ALLEY_MAX_Z: float = PHYSICS_CONSTANTS.ALLEY_MAX_Z  # +45.0

## Start placement: at the alley mouth, centreline x, facing +Z (heading 180) so
## the trailer leads into the alley (rear toward -15) -- the orientation a real
## alley backup needs. Drive axle 1 m inside the gate.
const START_X: float = -36.0
const START_Z: float = 44.0
const START_HEADING_DEG: float = 180.0

## 64-bit FNV-1a, same fold as golden_run.gd (see D58).
const _FNV_OFFSET: int = -3750763034362895579
const _FNV_PRIME: int = 0x100000001b3
const _DECIM: int = 1000000

var _h: Node
var _controller: Node
var _wall_contacts: int = 0
## Wall contacts count only during the 900-tick backup pass. The reverse steer
## sign diagnostic that follows it is a separate measurement and must not be
## able to touch a wall to sink the backup's contact count.
var _measuring_contacts: bool = true

# ---------------------------------------------------------------------------
# Scripted input (same shape as golden_run.gd)
# ---------------------------------------------------------------------------


## Fixed per-step drive: throttle REVERSE_THROTTLE, steer 0.0 (a straight alley
## pass -- the `alley` class is straight-running-only per world-spec section 4),
## no brake, no retarder. No RNG.
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
	## Place the combination through the shared harness at the alley mouth. The
	## controller carries the world transform; place_at_rest() settles y and
	## rebuilds the kingpin joint at the (rotated) fifth wheel, so the heading is
	## respected without forking a rig builder.
	var c: Node = _controller
	c.global_position = Vector3(START_X, 0.0, START_Z)
	c.rotation = Vector3(0.0, deg_to_rad(START_HEADING_DEG), 0.0)
	c.place_at_rest()


func _track_wall_contacts() -> void:
	_controller.tractor.body_entered.connect(_on_body_entered)
	_controller.trailer.body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _measuring_contacts and body != null and body.is_in_group("wall"):
		_wall_contacts += 1


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


## Run the S1 alley-reverse maneuver and return the measured result dict.
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

	# Reverse speed gate: the rig is at rest (settled on the brake). Engage R and
	# record the pre-shift speed and whether the gate accepted it on the first
	# attempt.
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
	var z_trace: Array = []
	var x_trace: Array = []
	var oob: bool = false
	var final_min_x: float = 0.0
	var final_max_x: float = 0.0

	for step in MANEUVER_TICKS:
		await get_tree().physics_frame
		var c: Node = _controller
		var tz: float = c.tractor.global_position.z
		# Forward component along the heading; reverse = -forward (toward -Z here).
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
		if step % 90 == 0 or step == MANEUVER_TICKS - 1:
			z_trace.append("%d:%.3f" % [step, tz])
			x_trace.append("%d:[%.3f,%.3f]" % [step, minx, maxx])
		if _h.out_of_bounds():
			oob = true

	# End-of-pass trailer extent (the "trailer ends inside the alley" check).
	var c_end: Node = _controller
	var final_drive_z: float = c_end.tractor.global_position.z
	var delta_z: float = final_drive_z - start_drive_z
	# A back-down toward -15 is a negative delta_z: the real backup.
	var reverse_completed: bool = delta_z < -REVERSE_TARGET_M
	var vz: Array = _box_z_extent(c_end.trailer, PHYSICS_CONSTANTS.TRAILER_BOX_CENTER, trailer_half)
	var trailer_min_z: float = vz[0] as float
	var trailer_max_z: float = vz[1] as float
	var trailer_in_alley: bool = (
		trailer_min_z >= ALLEY_MIN_Z
		and trailer_max_z <= ALLEY_MAX_Z
		and final_min_x >= WEST_FACE_X
		and final_max_x <= EAST_FACE_X
	)

	# Fitted width from the measured sweep.
	var swept_width: float = max_x_all - min_x_all
	var min_width_zero_margin: float = swept_width
	var min_width_with_margin: float = swept_width + 2.0 * FIT_MARGIN_M
	var fits_8m: bool = min_x_all >= WEST_FACE_X and max_x_all <= EAST_FACE_X
	var fits_8m_with_margin: bool = (
		(min_x_all >= WEST_FACE_X + FIT_MARGIN_M) and (max_x_all <= EAST_FACE_X - FIT_MARGIN_M)
	)

	# Reverse steer sign diagnostic: a short steer +0.5 hold in gear R records the
	# trailer's articulation sign (the "trailer steers the other way in reverse"
	# trap). Done after the main pass so it does not perturb the sweep, and outside
	# the wall-contact window.
	_measuring_contacts = false
	var steer_sign_artic: float = await _reverse_steer_sign()

	var result: Dictionary = {
		"script_checksum": script_checksum(),
		"steps": MANEUVER_TICKS,
		"physics_hz": Engine.get_physics_ticks_per_second(),
		"pre_shift_speed_m_s": pre_speed,
		"reverse_engaged": reverse_engaged,
		"reverse_reject": reverse_reject,
		"reverse_completed": reverse_completed,
		"reverse_target_m": REVERSE_TARGET_M,
		"start_drive_z": start_drive_z,
		"final_drive_z": final_drive_z,
		"delta_z_m": delta_z,
		"peak_forward_speed_m_s": peak_forward_speed,
		"peak_reverse_speed_m_s": peak_reverse_speed,
		"peak_artic_rad": peak_artic_rad,
		"peak_artic_deg": rad_to_deg(peak_artic_rad),
		"peak_artic_at_step": peak_artic_at,
		"steer_sign_artic_deg": steer_sign_artic,
		"trailer_min_z_m": trailer_min_z,
		"trailer_max_z_m": trailer_max_z,
		"trailer_in_alley": trailer_in_alley,
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
		"out_of_bounds": oob,
		"z_trace": z_trace,
		"x_trace": x_trace,
	}
	# PASS: a real completed backup -- the reverse engaged from rest, the rig
	# backed down past the 1.0 m target, the trailer ended inside the alley, no
	# wall contact, strictly positive clearance on both walls, in bounds.
	result["pass"] = (
		reverse_engaged
		and reverse_completed
		and trailer_in_alley
		and _wall_contacts == 0
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
	print("S1 ALLEY-REVERSE  steps=%d  hz=%.0f  wall=%dms" % [r["steps"], r["physics_hz"], wall_ms])
	print("  script_checksum = %d (%d records)" % [r["script_checksum"], r["steps"]])
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
			"  reverse result: completed=%s (delta_z=%+.3f m over %d ticks, target back-down <= %.1f m)"
			% [str(r["reverse_completed"]), r["delta_z_m"], r["steps"], -r["reverse_target_m"]]
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
			"  trailer end-of-pass z extent = %.3f .. %.3f m (alley %.0f .. %.0f), inside alley = %s"
			% [
				r["trailer_min_z_m"],
				r["trailer_max_z_m"],
				ALLEY_MIN_Z,
				ALLEY_MAX_Z,
				str(r["trailer_in_alley"])
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
	print('  wall contact (body_entered on "wall", backup pass only): %d' % r["wall_contacts"])
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
