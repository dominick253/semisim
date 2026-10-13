class_name CameraRig
extends Node3D
## The four Phase 1 camera modes and the Tab cycle (section 10):
## Chase -> Cab -> Trailer -> Free, plus the two cab mirror SubViewport cameras
## that are only active in Cab mode (CPU budget).
##
## No RNG anywhere (section 15 determinism rule). All geometry comes from
## PHYSICS_CONSTANTS. The chase and trailer arms are critically smoothed with
## the pinned damping time so camera motion never aliases with the 120 Hz tick.

enum Mode { CHASE, CAB, TRAILER, FREE }

const MODE_ORDER: Array[int] = [Mode.CHASE, Mode.CAB, Mode.TRAILER, Mode.FREE]

var mode: int = Mode.CHASE
var cab_look_yaw_deg: float = 0.0
var cab_look_pitch_deg: float = 0.0
var free_orbit_yaw_rad: float = 0.0
var free_orbit_elev_rad: float = 0.30

var chase_camera: Camera3D
var cab_camera: Camera3D
var trailer_camera: Camera3D
var free_camera: Camera3D
var mirror_cameras_left: Camera3D
var mirror_cameras_right: Camera3D
var mirror_quad_left: MeshInstance3D
var mirror_quad_right: MeshInstance3D
var mirror_viewport_left: SubViewport
var mirror_viewport_right: SubViewport

var _controller: Node3D = null
var _chase_position: Vector3 = Vector3.ZERO
var _trailer_position: Vector3 = Vector3.ZERO
var _shake_remaining_s: float = 0.0
var _cab_eye_cache := _PivotCache.new()
var _trailer_ref_cache := _PivotCache.new()


func bind(controller: Node3D) -> void:
	_controller = controller


func connect_control_layer(layer: ControlLayer) -> void:
	## Wire the pinned camera actions: camera_cycle (Tab / RB) cycles the mode,
	## gamepad_camera (right stick) jumps to Free orbit.
	layer.camera_cycle_requested.connect(cycle)
	layer.free_camera_requested.connect(_on_free_camera_requested)


func _on_free_camera_requested() -> void:
	set_mode(Mode.FREE)


func _ready() -> void:
	chase_camera = _make_camera("ChaseCamera")
	cab_camera = _make_camera("CabCamera")
	trailer_camera = _make_camera("TrailerCamera")
	free_camera = _make_camera("FreeCamera")
	_build_mirrors()
	_apply_mode()
	if _controller != null and not _controller.jackknife_occurred.is_connected(_on_jackknife):
		_controller.jackknife_occurred.connect(_on_jackknife)


func _physics_process(dt: float) -> void:
	if _controller == null:
		return
	_update_chase(dt)
	_update_trailer(dt)
	_update_cab()
	_update_free()
	_update_mirrors()
	if _shake_remaining_s > 0.0:
		_shake_remaining_s = maxf(0.0, _shake_remaining_s - dt)
		var amp: float = (
			PHYSICS_CONSTANTS.CAMERA_SHAKE_AMPLITUDE_M
			* _shake_remaining_s
			/ PHYSICS_CONSTANTS.CAMERA_SHAKE_SECONDS
		)
		# Deterministic shake: a fixed-phase sine, not noise, so runs stay
		# reproducible (section 15).
		var phase: float = float(_controller.sim_ticks) * 0.55
		var shake: Vector3 = Vector3(sin(phase) * amp, sin(phase * 1.7) * amp, 0.0)
		_apply_shake(shake)
	_apply_mode()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


func cycle() -> void:
	var index: int = MODE_ORDER.find(mode)
	mode = MODE_ORDER[(index + 1) % MODE_ORDER.size()]
	_apply_mode()


func set_mode(new_mode: int) -> void:
	mode = new_mode
	_apply_mode()


func mode_name() -> String:
	match mode:
		Mode.CHASE:
			return "CHASE"
		Mode.CAB:
			return "CAB"
		Mode.TRAILER:
			return "TRAILER"
		_:
			return "FREE"


func current_cameras() -> Array[Camera3D]:
	## Exactly one main camera is current at any time; mirrors are separate.
	var out: Array[Camera3D] = []
	match mode:
		Mode.CHASE:
			out.append(chase_camera)
		Mode.CAB:
			out.append(cab_camera)
		Mode.TRAILER:
			out.append(trailer_camera)
		_:
			out.append(free_camera)
	return out


func mirror_cameras() -> Array[Camera3D]:
	return [mirror_cameras_left, mirror_cameras_right]


func mirror_viewports() -> Array[SubViewport]:
	return [mirror_viewport_left, mirror_viewport_right]


func tractor_ref_global() -> Vector3:
	## Camera anchor for the tractor. Until the GLB lands this is the pinned
	## tractor reference point on the body (DEVIATIONS D32).
	if _controller == null:
		return Vector3.ZERO
	var body: RigidBody3D = _controller.tractor as RigidBody3D
	return body.global_transform * PHYSICS_CONSTANTS.TRACTOR_REF_LOCAL


func trailer_ref_global() -> Vector3:
	## Camera anchor for the trailer. Reads the GLB `trailer_ref` empty (AS2)
	## when a model is parented under the trailer body, and falls back to the
	## pinned TRAILER_REF_LOCAL (DEVIATIONS D31) until then.
	if _controller == null:
		return Vector3.ZERO
	var body: RigidBody3D = _controller.trailer as RigidBody3D
	if body == null:
		return Vector3.ZERO
	var pivot: Node3D = _trailer_ref_cache.resolve_for(body, "trailer_ref")
	if pivot != null:
		return pivot.global_position
	return body.global_transform * PHYSICS_CONSTANTS.TRAILER_REF_LOCAL


func cab_eye_global() -> Vector3:
	## Camera anchor for the cab eye. Reads the GLB `cab_eye` empty (AS1) when
	## a model is parented under the tractor body, and falls back to the
	## pinned CAB_EYE_LOCAL (DEVIATIONS D31) until then.
	if _controller == null:
		return Vector3.ZERO
	var body: RigidBody3D = _controller.tractor as RigidBody3D
	if body == null:
		return Vector3.ZERO
	var pivot: Node3D = _cab_eye_cache.resolve_for(body, "cab_eye")
	if pivot != null:
		return pivot.global_position
	return body.global_transform * PHYSICS_CONSTANTS.CAB_EYE_LOCAL


func add_cab_look(delta_yaw_deg: float, delta_pitch_deg: float) -> void:
	## Mouse look, clamped to the pinned limits (section 10).
	cab_look_yaw_deg = clampf(
		cab_look_yaw_deg + delta_yaw_deg,
		-PHYSICS_CONSTANTS.CAB_LOOK_YAW_LIMIT_DEG,
		PHYSICS_CONSTANTS.CAB_LOOK_YAW_LIMIT_DEG
	)
	cab_look_pitch_deg = clampf(
		cab_look_pitch_deg + delta_pitch_deg,
		PHYSICS_CONSTANTS.CAB_LOOK_PITCH_MIN_DEG,
		PHYSICS_CONSTANTS.CAB_LOOK_PITCH_MAX_DEG
	)


func orbit_from_stick(yaw_axis: float, elev_axis: float, dt: float) -> void:
	## Right-stick orbit for Free mode. Deadzone is the pinned gamepad deadzone.
	if (
		absf(yaw_axis) < PHYSICS_CONSTANTS.GAMEPAD_DEADZONE
		and absf(elev_axis) < PHYSICS_CONSTANTS.GAMEPAD_DEADZONE
	):
		return
	add_free_orbit(
		yaw_axis * PHYSICS_CONSTANTS.FREE_ORBIT_RATE_RAD_S * dt,
		-elev_axis * PHYSICS_CONSTANTS.FREE_ORBIT_RATE_RAD_S * dt
	)


func add_free_orbit(delta_yaw_rad: float, delta_elev_rad: float) -> void:
	free_orbit_yaw_rad += delta_yaw_rad
	free_orbit_elev_rad = clampf(free_orbit_elev_rad + delta_elev_rad, -0.6, 1.2)


static func steering_wheel_angle_rad(steer_angle_rad: float) -> float:
	## Visual steering wheel rotation: full lock is 2.5 turns from center
	## (section 5.7), so the wheel angle scales with the steer angle ratio.
	var ratio: float = steer_angle_rad / deg_to_rad(PHYSICS_CONSTANTS.STEER_MAX_ANGLE_DEG)
	return ratio * PHYSICS_CONSTANTS.STEERING_WHEEL_TURNS * TAU


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------


func _update_chase(dt: float) -> void:
	var ref: Vector3 = tractor_ref_global()
	var rear: Vector3 = _rear_direction(_controller.tractor as RigidBody3D)
	var desired: Vector3 = (
		ref
		+ rear * PHYSICS_CONSTANTS.CHASE_ARM_LENGTH_M
		+ Vector3(0.0, PHYSICS_CONSTANTS.CHASE_HEIGHT_M, 0.0)
	)
	if _chase_position == Vector3.ZERO:
		_chase_position = desired
	else:
		# Critically damped spring arm with the pinned 0.25 s time constant.
		var factor: float = 1.0 - exp(-dt / PHYSICS_CONSTANTS.CHASE_DAMPING_S)
		_chase_position += (desired - _chase_position) * factor
	chase_camera.global_position = _chase_position
	chase_camera.look_at(ref + Vector3(0.0, 1.0, 0.0), Vector3.UP)


func _update_trailer(dt: float) -> void:
	var ref: Vector3 = trailer_ref_global()
	var rear: Vector3 = _rear_direction(_controller.trailer as RigidBody3D)
	var desired: Vector3 = (
		ref
		+ rear * PHYSICS_CONSTANTS.TRAILER_ARM_LENGTH_M
		+ Vector3(0.0, PHYSICS_CONSTANTS.CHASE_HEIGHT_M, 0.0)
	)
	if _trailer_position == Vector3.ZERO:
		_trailer_position = desired
	else:
		var factor: float = 1.0 - exp(-dt / PHYSICS_CONSTANTS.CHASE_DAMPING_S)
		_trailer_position += (desired - _trailer_position) * factor
	trailer_camera.global_position = _trailer_position
	trailer_camera.look_at(ref + Vector3(0.0, 1.5, 0.0), Vector3.UP)


func _update_cab() -> void:
	var body: RigidBody3D = _controller.tractor as RigidBody3D
	cab_camera.global_position = cab_eye_global()
	var yaw: float = body.global_transform.basis.get_euler().y + deg_to_rad(cab_look_yaw_deg)
	var pitch: float = deg_to_rad(cab_look_pitch_deg)
	cab_camera.global_rotation = Vector3(pitch, yaw, 0.0)


func _update_free() -> void:
	var ref: Vector3 = tractor_ref_global()
	var radius: float = PHYSICS_CONSTANTS.FREE_ORBIT_RADIUS_M
	var offset: Vector3 = (
		Vector3(
			cos(free_orbit_elev_rad) * cos(free_orbit_yaw_rad),
			sin(free_orbit_elev_rad),
			cos(free_orbit_elev_rad) * sin(free_orbit_yaw_rad)
		)
		* radius
	)
	free_camera.global_position = ref + offset
	free_camera.look_at(ref, Vector3.UP)


func _apply_mode() -> void:
	chase_camera.current = mode == Mode.CHASE
	cab_camera.current = mode == Mode.CAB
	trailer_camera.current = mode == Mode.TRAILER
	free_camera.current = mode == Mode.FREE
	var mirrors_on: bool = mode == Mode.CAB
	mirror_cameras_left.current = mirrors_on
	mirror_cameras_right.current = mirrors_on
	mirror_quad_left.visible = mirrors_on
	mirror_quad_right.visible = mirrors_on


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _make_camera(cam_name: String) -> Camera3D:
	var cam := Camera3D.new()
	cam.name = cam_name
	cam.fov = PHYSICS_CONSTANTS.CAMERA_FOV_DEG
	cam.near = PHYSICS_CONSTANTS.CAMERA_NEAR_M
	cam.far = PHYSICS_CONSTANTS.CAMERA_FAR_M
	add_child(cam)
	return cam


func _build_mirrors() -> void:
	## Two 480 x 270 SubViewport cameras for the cab mirror quads (section 10).
	## Rendered only in Cab mode to stay inside the CPU budget.
	for side_i in [1, -1]:
		var side: int = int(side_i)
		var vp := SubViewport.new()
		vp.name = "MirrorViewport%s" % ("L" if side > 0 else "R")
		vp.size = Vector2i(
			PHYSICS_CONSTANTS.MIRROR_VIEWPORT_WIDTH, PHYSICS_CONSTANTS.MIRROR_VIEWPORT_HEIGHT
		)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var cam := Camera3D.new()
		cam.name = "MirrorCamera%s" % ("L" if side > 0 else "R")
		cam.fov = PHYSICS_CONSTANTS.MIRROR_FOV_DEG
		cam.near = PHYSICS_CONSTANTS.CAMERA_NEAR_M
		cam.far = PHYSICS_CONSTANTS.CAMERA_FAR_M
		vp.add_child(cam)
		var quad := MeshInstance3D.new()
		quad.name = "MirrorQuad%s" % ("L" if side > 0 else "R")
		var plane := PlaneMesh.new()
		plane.size = PHYSICS_CONSTANTS.MIRROR_QUAD_SIZE_M
		quad.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		## get_texture() returns a ViewportTexture already bound to the
		## SubViewport; a hand-built ViewportTexture errors until it is set.
		mat.albedo_texture = vp.get_texture()
		quad.material_override = mat
		quad.visible = false
		add_child(quad)
		if side > 0:
			mirror_viewport_left = vp
			mirror_cameras_left = cam
			mirror_quad_left = quad
		else:
			mirror_viewport_right = vp
			mirror_cameras_right = cam
			mirror_quad_right = quad


func mirror_quads() -> Array[MeshInstance3D]:
	return [mirror_quad_left, mirror_quad_right]


func _update_mirrors() -> void:
	if mode != Mode.CAB:
		return
	var body: RigidBody3D = _controller.tractor as RigidBody3D
	var side_dir: Vector3 = body.global_transform.basis.x
	var fwd: Vector3 = -body.global_transform.basis.z
	for pair in [[mirror_cameras_left, 1.0], [mirror_cameras_right, -1.0]]:
		var cam: Camera3D = pair[0] as Camera3D
		var side: float = float(pair[1])
		var anchor: Vector3 = body.global_transform * PHYSICS_CONSTANTS.MIRROR_ANCHOR_LOCAL
		var quad: MeshInstance3D = mirror_quad_left if side > 0 else mirror_quad_right
		quad.global_position = anchor + side_dir * side * PHYSICS_CONSTANTS.MIRROR_OFFSET_M
		quad.global_basis = body.global_transform.basis
		cam.global_position = anchor + side_dir * side * PHYSICS_CONSTANTS.MIRROR_OFFSET_M
		var target: Vector3 = (
			cam.global_position + fwd * 8.0 + side_dir * side * 2.5 + Vector3(0.0, -0.2, 0.0)
		)
		cam.look_at(target, Vector3.UP)


func _rear_direction(body: RigidBody3D) -> Vector3:
	## Godot forward is -Z, so "behind the vehicle" is +basis.z.
	return body.global_transform.basis.z


func _apply_shake(shake: Vector3) -> void:
	chase_camera.translate(shake)
	cab_camera.translate(shake)
	trailer_camera.translate(shake)


func _on_jackknife() -> void:
	_shake_remaining_s = PHYSICS_CONSTANTS.CAMERA_SHAKE_SECONDS


class _PivotCache:
	## One resolved GLB pivot, cached per body so the tree is walked at most
	## once per body per rig lifetime (D47). Re-resolves only when the cached
	## reference fails is_instance_valid: the body was freed and replaced, or
	## the pivot node was removed (model swapped out).
	var body: Node = null
	var pivot: Node3D = null

	func resolve_for(body: Node, pivot_name: String) -> Node3D:
		var fresh: bool = (
			self.body == body
			and is_instance_valid(self.body)
			and (self.pivot == null or is_instance_valid(self.pivot))
		)
		if fresh:
			return self.pivot
		self.pivot = ModelPivots.find_pivot(body, pivot_name)
		self.body = body
		return self.pivot
