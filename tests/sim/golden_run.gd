extends Node3D
## A14 golden determinism harness (phase2-plan line 42 / section 6).
##
## Builds the tractor+trailer combination through the shared
## combination_rest_harness (not a forked rig builder), drives a fixed
## GOLDEN_STEPS=600 scripted input at the pinned 120 Hz step, and checks
## reproducibility. It hashes transforms only: 64-bit FNV-1a over the position
## plus basis of the tractor, the trailer, and the eight wheel nodes, sampled
## every step, quantized to 6-decimal ASCII. No velocities, forces, or audio.
##
## WHY THE GATE IS ENVELOPE-BASED, NOT BYTE-IDENTITY
## Godot 4.7's built-in Jolt is NOT bit-deterministic: the godot-jolt README
## states it "is not able to make [determinism] guarantees ... this should not
## be relied upon if determinism is a hard requirement," and there is no
## user-facing determinism/single-thread toggle. Measured here (two sequential
## single-truck runs, this build), two identical runs of the golden drive agree
## to a transform ENVELOPE of ~32-47 mm (max over all bodies and steps) and
## ~0.0015 rad of articulation, not byte-identity. (Restoring RigidBody3D state
## through the float64 API is also not bit-exact: Jolt is float32 internally.)
## So the gate bounds the run-to-run transform ENVELOPE (max pairwise deviation
## between the two runs) rather than asserting byte-identical hashes. The two
## printed hashes differ by the envelope; they are a gross-regression sentinel,
## not a byte-identity contract. See DEVIATIONS (Jolt non-determinism row) for
## the measured envelope and the separately-measured cross-process result.
##
## DESIGN NOTE: the two runs are SEQUENTIAL SINGLE-TRUCK runs in one process
## (build A, run, free; build B, run, free), NOT K trucks in one space. K trucks
## in one Jolt space perturb each other's threaded solver reduction (their body
## list order changes the dynamics), which would conflate solver interaction
## with the noise floor. A single truck per run isolates the Jolt noise.

const GOLDEN_STEPS: int = 600
## Pinned physics step (Hz). project.godot sets 120; the run reports it.
const PHYSICS_HZ: float = 120.0
## In-process envelope bound (m). The measured Jolt noise floor is 32-47 mm
## (bimodal, max over all bodies and steps); the bound is ~4x the worst
## observed, so it is safely above run-to-run and cross-machine noise yet far
## below any real reproducibility regression (a jackknife/flip/gear error moves
## a body by centimeters to meters). Cross-process variation is measured and
## recorded separately (never gated) because it is larger and machine dependent.
const ENVELOPE_BOUND_M: float = 0.2
## In-process articulation-angle bound (rad). Measured divergence <= 0.0015 rad
## (0.085 deg); bound ~13x that.
const ARTIC_BOUND_RAD: float = 0.02

const _HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"
const _PIVOTS: String = "res://scripts/vehicles/model_pivots.gd"
## Wheel node names, in a fixed order (tractor then trailer axles) so the hash
## input order is stable. Resolved through the shared ModelPivots helper.
const _WHEEL_NAMES: Array[String] = [
	"WheelSteerL",
	"WheelSteerR",
	"WheelDriveL",
	"WheelDriveR",
	"TrailerWheelFL",
	"TrailerWheelFR",
	"TrailerWheelRL",
	"TrailerWheelRR",
]

## 64-bit FNV-1a. GDScript int overflow wraps two's-complement (mod 2^64), so
## this is a faithful 64-bit fold; the offset basis is written as its signed
## representative because 0xcbf29ce484222325 exceeds the signed 64-bit range.
const _FNV_OFFSET: int = -3750763034362895579
const _FNV_PRIME: int = 0x100000001b3
const _DECIM: int = 1000000


## The fixed 600-step drive, as deterministic per-step input records (no RNG),
## built once and shared by every run. A change to it changes the hash and the
## script checksum.
static func _build_script() -> Array:
	var s: Array = []
	for i in 150:  # Phase 1: throttle ramp 0 -> 1, straight.
		s.append({"throttle": float(i) / 149.0, "steer": 0.0, "brake": 0.0, "retarder": 0})
	for _i in 150:  # Phase 2: throttle 0.6, right steer 0.4.
		s.append({"throttle": 0.6, "steer": 0.4, "brake": 0.0, "retarder": 0})
	for _i in 150:  # Phase 3: full service brake, no throttle.
		s.append({"throttle": 0.0, "steer": 0.0, "brake": 1.0, "retarder": 0})
	for _i in 150:  # Phase 4: engine/retarder down (no service brake), coast.
		s.append({"throttle": 0.0, "steer": 0.0, "brake": 0.0, "retarder": 4})
	return s


## 64-bit FNV-1a checksum of the per-step input records (the "script checksum"
## the evidence file records). Deterministic: fixed data, fixed order.
func script_checksum() -> int:
	var hval: int = _FNV_OFFSET
	for r in _build_script():
		hval = _fnv(hval, _q6(float(r["throttle"])))
		hval = _fnv(hval, _q6(float(r["steer"])))
		hval = _fnv(hval, _q6(float(r["brake"])))
		hval = _fnv(hval, str(int(r["retarder"])))
	return hval


## The drive applied to one controller: reads the per-step record for the
## current tick from the fixed script. Bound through the controller's existing
## scripted_input Callable (no change to combination_controller.gd).
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


func _bodies(c: Node, pivots: GDScript) -> Array:
	var out: Array = [c.tractor, c.trailer]
	for nm in _WHEEL_NAMES:
		var w: Node3D = pivots.find_pivot.call(c, nm)
		if w == null:
			push_error("golden_run: wheel pivot %s not found" % nm)
			w = c.tractor
		out.append(w)
	return out


## Build one canonical truck at rest, drive it through the fixed 600-step
## script, record its per-step trajectory and FNV-1a hash, then free it.
## Public so the cross-process probe can hash a single run per process.
## Returns {hash, traj (Array of 10 Vector3 per step), speed, artic, oob}.
func run_single() -> Dictionary:
	var pivots: GDScript = load(_PIVOTS)
	var h: Node = load(_HARNESS_SCENE).instantiate()
	h.position = Vector3.ZERO
	add_child(h)
	await get_tree().process_frame  # _ready builds + place_at_rest
	var c: Node = h.controller
	var drive: _Drive = _Drive.new()
	drive.controller = c
	drive.records = _build_script()
	c.scripted_input = drive.apply
	var bodies: Array = _bodies(c, pivots)
	var start_pos: Array = []
	var start_inv: Array = []
	for b in bodies:
		start_pos.append(b.global_position)
		start_inv.append(b.global_transform.affine_inverse())
	var hval: int = _FNV_OFFSET
	var traj: Array = []
	var oob: bool = false
	for _step in GOLDEN_STEPS:
		await get_tree().physics_frame
		var row: Array = []
		for n in bodies.size():
			var b: Node3D = bodies[n]
			row.append(b.global_position - start_pos[n])
			# Fold the quantized start-local position + basis into the hash.
			var rel: Transform3D = b.global_transform * start_inv[n]
			hval = _fnv(hval, _q6(rel.origin.x))
			hval = _fnv(hval, _q6(rel.origin.y))
			hval = _fnv(hval, _q6(rel.origin.z))
			hval = _basis_hash(hval, rel.basis)
		traj.append(row)
		if h.out_of_bounds():
			oob = true
	var result: Dictionary = {
		"hash": hval,
		"traj": traj,
		"speed": c.speed(),
		"artic": c.articulation_rad(),
		"oob": oob,
		"final_pos": c.tractor.global_position,
		"gear": c.transmission.gear,
	}
	h.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	return result


## Run the fixed drive twice (two sequential single-truck runs) and return the
## in-process reproducibility result. Awaitable.
func run(_root: Node) -> Dictionary:
	var t0: int = Time.get_ticks_msec()
	var a: Dictionary = await run_single()
	var b: Dictionary = await run_single()
	# Envelope = max pairwise world-frame deviation between the two runs'
	# trajectories (all 10 bodies, all steps).
	var ta: Array = a["traj"]
	var tb: Array = b["traj"]
	var env: float = 0.0
	var env_at: int = 0
	for s in ta.size():
		for n in ta[s].size():
			var d: float = ta[s][n].distance_to(tb[s][n])
			if d > env:
				env = d
				env_at = s
	var env_artic: float = absf(a["artic"] - b["artic"])
	var oob: bool = a["oob"] or b["oob"]
	var result: Dictionary = {
		"hashes": [a["hash"], b["hash"]],
		"envelope_m": env,
		"envelope_at_step": env_at,
		"envelope_artic_rad": env_artic,
		"envelope_bound_m": ENVELOPE_BOUND_M,
		"artic_bound_rad": ARTIC_BOUND_RAD,
		"out_of_bounds": oob,
		"physics_hz": Engine.get_physics_ticks_per_second(),
		"steps": GOLDEN_STEPS,
		"elapsed_ms": Time.get_ticks_msec() - t0,
		"final":
		[
			{"run": 0, "speed_m_s": a["speed"], "artic_rad": a["artic"], "oob": a["oob"]},
			{"run": 1, "speed_m_s": b["speed"], "artic_rad": b["artic"], "oob": b["oob"]},
		],
	}
	result["pass"] = env <= ENVELOPE_BOUND_M and env_artic <= ARTIC_BOUND_RAD and not oob
	return result


## --- Standalone entry point (golden_run.tscn as the main scene) -----------
func _ready() -> void:
	if get_tree().current_scene != self:
		return  # loaded as a library (GUT or another scene); do nothing
	var wall: int = Time.get_ticks_msec()
	var r: Dictionary = await run(self)
	_report(r, Time.get_ticks_msec() - wall)
	get_tree().quit()


func _report(r: Dictionary, wall_ms: int) -> void:
	print("GOLDEN A14  steps=%d  hz=%.0f  wall=%dms" % [r["steps"], r["physics_hz"], wall_ms])
	for i in r["hashes"].size():
		print("  hash[%d] = %d" % [i, r["hashes"][i]])
	print("  script_checksum = %d (%d records)" % [script_checksum(), GOLDEN_STEPS])
	print(
		(
			"  envelope (max pairwise, all bodies) = %.3f mm  [bound %.0f mm] (at step %d)"
			% [r["envelope_m"] * 1000.0, r["envelope_bound_m"] * 1000.0, r["envelope_at_step"]]
		)
	)
	print(
		(
			"  envelope (articulation)             = %.6f rad [bound %.4f rad]"
			% [r["envelope_artic_rad"], r["artic_bound_rad"]]
		)
	)
	print("  out_of_bounds = %s" % str(r["out_of_bounds"]))
	for f in r["final"]:
		print(
			(
				"  run%d speed=%.4f m/s artic=%.5f rad oob=%s"
				% [f["run"], f["speed_m_s"], f["artic_rad"], str(f["oob"])]
			)
		)
	print("  RESULT = %s" % ("PASS" if r["pass"] else "FAIL"))


func _basis_hash(h: int, bb: Basis) -> int:
	var cols: Array = [bb.x, bb.y, bb.z]
	for col in cols:
		var cv: Vector3 = col
		h = _fnv(h, _q6(cv.x))
		h = _fnv(h, _q6(cv.y))
		h = _fnv(h, _q6(cv.z))
	return h


func _fnv(h: int, s: String) -> int:
	for i in s.length():
		h = h ^ s.unicode_at(i)
		h = h * _FNV_PRIME
	return h


func _q6(x: float) -> String:
	return str(int(round(x * _DECIM)))
