extends Node3D
## S3 braking scenario, pinned to acceptance A9 (phase1 prompt section 15 and
## section 19): "S3 braking: 80 km/h, full service brake plus retarder stage 5,
## stop distance 24..34 m. A9: S3 passes: stop distance 24..34 m from 80 km/h."
##
## The physics is already pinned and unit-tested by
## tests/unit/test_braking_distance.gd (AS4k, D56). This scenario reproduces the
## same measurement as a standalone, checksummed, in-process run in the house
## style of tests/sim/scenario_s1_alley.gd:
##   * the target is the LOADED combination (D20: apply_cargo(CARGO_MASS_MAX_KG)
##     then place_at_rest, so the static axle shares carry the full 29,000 kg);
##   * the transmission is held in gear 4 -- the top of the pinned
##     "gears 1-4" retarder window (RETARDER_MAX_GEAR = 4) -- so that
##     "full service brake plus retarder" is ACTUALLY applied. In automatic mode
##     the gearbox holds gear 5 at 80 km/h, and the spec's own gate turns the
##     retarder OFF in gear 5 (D56); the naive auto reading is measured in the
##     same process and reported honestly next to the pinned number.
##   * the tractor and trailer linear_velocity are seeded along the tractor
##     heading at 22.2222 m/s (80 km/h); a driven-up equivalent is infeasible
##     (a retarder gear cannot launch the loaded rig from rest, the auto upshift
##     lands in gear 5, and a hard downshift at 80 km/h over-revved the rigid
##     driveline into the permanent 1900 rpm shutdown -- D57).
##   * then throttle 0, brake_pedal 1, retarder_stage 5, and a fixed checksummed
##     per-step input script (FNV-1a over the records, no RNG) driven through the
##     controller's existing scripted_input Callable, integrated tick by tick
##     until speed <= 0.05 m/s.
##
## What it reports, from every sampled tick (both variants, same process):
##   * measured stop distance (tick-by-tick tractor position accumulation), the
##     ticks and simulated seconds to speed <= 0.05 m/s;
##   * the gear and retarder stage actually applied at the moment braking starts,
##     and whether the retarder was live (the D56 trap, reported not hidden);
##   * peak deceleration in m/s^2 and in g;
##   * peak wheel slip ratio during the stop;
##   * whether any wheel locked (drive-wheel spin near zero while the vehicle is
##     still moving), and the longest sustained-lock run;
##   * out_of_bounds() (the AS4l2 helper) at the end.
##
## RESULT = PASS gates on the PINNED scenario: stop distance inside 24..34 m,
## the rig at rest at the end, no sustained wheel lock, in bounds. The naive
## auto variant is reported for honesty but does not gate (it is the D56
## service-brake-only number, ~40 m, and is expected to miss the window).

const _HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

## Pinned physics step (Hz). project.godot sets 120.
const PHYSICS_HZ: float = 120.0
## 80 km/h, the S3 run speed (same seed the unit test uses).
const V0_M_S: float = 22.2222
## Stop threshold: the rig is "stopped" when its speed drops to this (m/s).
## Same value the unit test integrates against.
const STOP_SPEED_M_S: float = 0.05
## Rest settle after (re)seating the loaded combination (2 s at 120 Hz).
const SETTLE_TICKS: int = 240
## Tick budget for one stop run (10 s at 120 Hz). The measured stop is ~3.2 s
## (~386 ticks), so the budget is ~2.6x the measured run and only bounds a
## runaway (which the report would then flag as stopped_within_budget=false).
const STOP_TICKS: int = 10 * int(PHYSICS_HZ)
## A drive wheel counts as "spun near zero" when its surface speed is below
## this fraction of the vehicle's forward speed (the brief's "spin near zero").
const LOCK_SURF_FRACTION: float = 0.1
## A lock is "sustained" (a PASS failure) only when it persists this many
## consecutive ticks while the vehicle is still moving: a real lock, not the
## one-tick ABS pulse the mu-slip curve produces.
const SUSTAINED_LOCK_TICKS: int = 12  # 0.1 s
## A lock is only meaningful while the vehicle is still moving above this.
const LOCK_MIN_SPEED_M_S: float = 1.0
## The A9 window (section 15): the stop must land inside 24..34 m.
const A9_MIN_M: float = 24.0
const A9_MAX_M: float = 34.0

## 64-bit FNV-1a, same fold as golden_run.gd (see D58).
const _FNV_OFFSET: int = -3750763034362895579
const _FNV_PRIME: int = 0x100000001b3
const _DECIM: int = 1000000

# ---------------------------------------------------------------------------
# Scripted input (same shape as golden_run.gd / scenario_s1_alley.gd)
# ---------------------------------------------------------------------------


## The fixed braking script: one identical record per tick (throttle 0, steer
## 0, brake 1, retarder 5), no RNG. Constant input, so the checksum is stable.
static func _build_script() -> Array:
	var s: Array = []
	for _i in STOP_TICKS:
		s.append({"throttle": 0.0, "steer": 0.0, "brake": 1.0, "retarder": 5})
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
	## sim_ticks at which the first record (index 0) should be applied; set so
	## the script starts at record 0 on the first physics frame after arming.
	var start_tick: int = 0

	func apply() -> void:
		# The controller calls scripted_input.call() with no arguments (it
		# increments sim_ticks first), so the drive indexes the record itself.
		var c: Node = controller
		var t: int = c.sim_ticks - 1 - start_tick
		if t < 0 or t >= records.size():
			return
		var r: Dictionary = records[t]
		c.throttle = float(r["throttle"])
		c.steer_input_axis = float(r["steer"])
		c.brake_pedal = float(r["brake"])
		c.retarder_stage = int(r["retarder"])


# ---------------------------------------------------------------------------
# One stop run (a variant: "pinned" manual gear 4, or "auto" naive)
# ---------------------------------------------------------------------------


## Build a loaded combination at rest, configure the variant's transmission,
## seed 80 km/h, drive the fixed brake+retarder script, and return the measured
## result dict. Public so the unit test drives it; frees the harness on return.
func _measure_one(variant: String) -> Dictionary:
	var h: Node = load(_HARNESS_SCENE).instantiate()
	h.position = Vector3.ZERO
	add_child(h)
	await get_tree().process_frame  # harness _ready builds the rig + place_at_rest
	var c: Node = h.controller

	# The target is the loaded combination (D20). Re-seat at the loaded rest
	# heights so the static axle shares carry the full load, then settle.
	c.apply_cargo(PHYSICS_CONSTANTS.CARGO_MASS_MAX_KG)
	c.place_at_rest()
	await h.settle(SETTLE_TICKS)

	# Variant configuration. Pinned: manual, held in gear 4 (top of the
	# RETARDER_MAX_GEAR window) so the retarder is live. Naive auto: automatic
	# mode in the gear it holds when cruising at 80 km/h, which is gear 5 -- one
	# above RETARDER_MAX_GEAR, so the spec's own gate turns the retarder off and
	# the run is service-brake-only (D56). The D56 default-cargo number is 40.50 m;
	# at this scenario's full load the same gear-5 auto run measures ~51 m.
	if variant == "pinned":
		c.transmission.automatic = false
		c.transmission.gear = 4
	else:
		c.transmission.automatic = true
		c.transmission.gear = 5

	# Seed 80 km/h along the tractor heading on both bodies.
	var heading: Vector3 = -c.tractor.global_basis.z
	c.tractor.linear_velocity = heading * V0_M_S
	c.trailer.linear_velocity = heading * V0_M_S

	# Arm the fixed brake+retarder script; the first record applies on the next
	# physics frame (start_tick is read just before the loop, between frames).
	var drive: _Drive = _Drive.new()
	drive.controller = c
	drive.records = _build_script()
	drive.start_tick = c.sim_ticks
	c.scripted_input = drive.apply

	# Measure.
	var drive_radius: float = PHYSICS_CONSTANTS.TIRE_DRIVE["rolling_radius_m"]
	var start: Vector3 = c.tractor.global_position
	var dist: float = 0.0
	var ticks: int = 0
	var prev_vfwd: float = heading.dot(c.tractor.linear_velocity)
	var peak_decel_m_s2: float = 0.0
	var peak_slip: float = 0.0
	var abs_engaged: bool = false
	var min_surf_to_vfwd: float = 0.0
	var have_surf: bool = false
	var lock_run: int = 0
	var max_consecutive_lock: int = 0
	var gear_at_brake: int = 0
	var retarder_live_at_brake: bool = false
	var retarder_live_ever: bool = false
	var stop_tick: int = -1
	var oob: bool = false

	for _step in STOP_TICKS:
		await get_tree().physics_frame
		var vfwd: float = heading.dot(c.tractor.linear_velocity)
		# Deceleration (positive when slowing).
		var a: float = (prev_vfwd - vfwd) / (1.0 / PHYSICS_HZ)
		if a > peak_decel_m_s2:
			peak_decel_m_s2 = a
		prev_vfwd = vfwd
		# Distance accumulation (tick by tick, same as the unit test).
		dist += c.tractor.global_position.distance_to(start)
		start = c.tractor.global_position
		ticks += 1
		# Gear + retarder state, captured at the moment braking starts (first
		# sampled tick) -- the D56 trap, reported not hidden.
		if ticks == 1:
			gear_at_brake = c.transmission.gear
			retarder_live_at_brake = c.transmission.retarder_allowed(5, vfwd)
		retarder_live_ever = retarder_live_ever or c.transmission.retarder_allowed(5, vfwd)
		# Peak wheel slip across all eight wheels this tick.
		for w in c.wheels:
			if absf(w.slip_ratio) > peak_slip:
				peak_slip = absf(w.slip_ratio)
			if w.abs_engaged:
				abs_engaged = true
		# Wheel lock: the drive axle surface speed near zero while the vehicle
		# is still moving (the brief's definition of a lock).
		if absf(vfwd) > LOCK_MIN_SPEED_M_S:
			var surf: float = c.wheel_omega_rad_s * drive_radius
			var ratio: float = surf / vfwd
			if not have_surf or ratio < min_surf_to_vfwd:
				min_surf_to_vfwd = ratio
				have_surf = true
			if absf(surf) < LOCK_SURF_FRACTION * absf(vfwd):
				lock_run += 1
				if lock_run > max_consecutive_lock:
					max_consecutive_lock = lock_run
			else:
				lock_run = 0
		else:
			lock_run = 0
		if h.out_of_bounds():
			oob = true
		# Stop condition.
		if c.speed() <= STOP_SPEED_M_S:
			stop_tick = ticks
			break

	var final_speed: float = c.speed()
	var cargo_kg: float = c.cargo_kg
	var stopped_within_budget: bool = stop_tick >= 0
	var at_rest: bool = final_speed <= STOP_SPEED_M_S
	var wheel_locked_sustained: bool = max_consecutive_lock > SUSTAINED_LOCK_TICKS
	c.scripted_input = Callable()
	h.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	return {
		"variant": variant,
		"cargo_kg": cargo_kg,
		"v0_m_s": V0_M_S,
		"stop_distance_m": dist,
		"stop_ticks": ticks,
		"stop_seconds": ticks / PHYSICS_HZ,
		"stopped_within_budget": stopped_within_budget,
		"final_speed_m_s": final_speed,
		"at_rest": at_rest,
		"gear_at_brake": gear_at_brake,
		"retarder_stage": 5,
		"retarder_live_at_brake": retarder_live_at_brake,
		"retarder_live_ever": retarder_live_ever,
		"peak_decel_m_s2": peak_decel_m_s2,
		"peak_decel_g": peak_decel_m_s2 / PHYSICS_CONSTANTS.GRAVITY_M_S2,
		"peak_slip_ratio": peak_slip,
		"abs_engaged": abs_engaged,
		"min_surf_to_vfwd_ratio": min_surf_to_vfwd,
		"max_consecutive_lock_ticks": max_consecutive_lock,
		"sustained_lock_ticks": SUSTAINED_LOCK_TICKS,
		"wheel_locked_sustained": wheel_locked_sustained,
		"out_of_bounds": oob,
	}


## Run the S3 braking acceptance (A9): the pinned scenario and the naive
## automatic variant, both in this process. Awaitable. Public so the unit test
## drives it.
func run(_root: Node) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var pinned: Dictionary = await _measure_one("pinned")
	var auto: Dictionary = await _measure_one("auto")
	var result: Dictionary = {
		"script_checksum": script_checksum(),
		"physics_hz": Engine.get_physics_ticks_per_second(),
		"stop_ticks_budget": STOP_TICKS,
		"a9_min_m": A9_MIN_M,
		"a9_max_m": A9_MAX_M,
		"pinned": pinned,
		"auto": auto,
		"elapsed_ms": 0,
	}
	# A9: the PINNED scenario (loaded, gear 4, full brake + retarder live) must
	# stop inside 24..34 m, end at rest, with no sustained wheel lock and in
	# bounds. The auto variant is reported but does not gate (it is the D56
	# service-brake-only number, expected to miss the window).
	result["pass"] = (
		pinned["stop_distance_m"] >= A9_MIN_M
		and pinned["stop_distance_m"] <= A9_MAX_M
		and pinned["at_rest"]
		and not pinned["wheel_locked_sustained"]
		and not pinned["out_of_bounds"]
	)
	result["elapsed_ms"] = Time.get_ticks_msec() - t0
	return result


# ---------------------------------------------------------------------------
# Standalone entry point (scenario_s3_braking.tscn as the main scene)
# ---------------------------------------------------------------------------


func _ready() -> void:
	if get_tree().current_scene != self:
		return  # loaded as a library (GUT or another scene); do nothing
	var wall: int = Time.get_ticks_msec()
	var r: Dictionary = await run(self)
	_report(r, Time.get_ticks_msec() - wall)
	get_tree().quit()


func _report(r: Dictionary, wall_ms: int) -> void:
	var p: Dictionary = r["pinned"]
	var a: Dictionary = r["auto"]
	print(
		(
			"S3 BRKING (A9)  hz=%.0f  wall=%dms  a9_window=%.0f..%.0f m"
			% [r["physics_hz"], wall_ms, r["a9_min_m"], r["a9_max_m"]]
		)
	)
	print(
		(
			"  script_checksum = %d (%d budget records)"
			% [r["script_checksum"], r["stop_ticks_budget"]]
		)
	)
	print(
		(
			"  cargo=%.0f kg  v0=%.4f m/s  stop_ticks_budget=%d"
			% [p["cargo_kg"], p["v0_m_s"], r["stop_ticks_budget"]]
		)
	)
	print(
		(
			"  [pinned, manual gear 4]  stop = %.2f m in %d ticks = %.3f s (within budget=%s)"
			% [
				p["stop_distance_m"],
				p["stop_ticks"],
				p["stop_seconds"],
				str(p["stopped_within_budget"])
			]
		)
	)
	print(
		(
			"     gear at brake=%d  retarder stage=%d  retarder live at brake=%s (live ever=%s)  [D56 trap]"
			% [
				p["gear_at_brake"],
				p["retarder_stage"],
				str(p["retarder_live_at_brake"]),
				str(p["retarder_live_ever"]),
			]
		)
	)
	print(
		(
			"     peak decel = %.3f m/s^2 (%.3f g)   peak wheel slip = %.4f   ABS engaged=%s"
			% [p["peak_decel_m_s2"], p["peak_decel_g"], p["peak_slip_ratio"], str(p["abs_engaged"])]
		)
	)
	print(
		(
			"     spin/vehicle min ratio = %.4f  lock run=%d (sustained>=%d) sustained lock=%s"
			% [
				p["min_surf_to_vfwd_ratio"],
				p["max_consecutive_lock_ticks"],
				p["sustained_lock_ticks"],
				str(p["wheel_locked_sustained"]),
			]
		)
	)
	print(
		(
			"     at rest at end=%s (final speed %.4f m/s)   out_of_bounds=%s"
			% [str(p["at_rest"]), p["final_speed_m_s"], str(p["out_of_bounds"])]
		)
	)
	print(
		(
			"  [auto, naive D56]       stop = %.2f m in %d ticks = %.3f s  (within budget=%s)"
			% [
				a["stop_distance_m"],
				a["stop_ticks"],
				a["stop_seconds"],
				str(a["stopped_within_budget"])
			]
		)
	)
	print(
		(
			"     gear at brake=%d  retarder live at brake=%s  [gear 5 gates the retarder off, D56]"
			% [a["gear_at_brake"], str(a["retarder_live_at_brake"])]
		)
	)
	print("  RESULT = %s" % ("PASS" if r["pass"] else "FAIL"))


func _fnv(h: int, s: String) -> int:
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = h * _FNV_PRIME
	return h


func _q6(x: float) -> String:
	return str(int(round(x * _DECIM)))
