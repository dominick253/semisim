class_name ControlLayer
## Samples the pinned section 11 control map and drives the combination
## controller. One sample per physics tick keeps runs deterministic, and
## momentary actions (gear, range, retarder, parking brake, unlock, landing
## gear, transmission mode) are consumed once per press so a held key cannot
## spam a request.
##
## The no-op rules themselves live in NoopRules and are enforced by the
## transmission and coupling controller, which emit the HUD reason flash.

var input_state: VehicleInput = VehicleInput.new()
var overlay_enabled: bool = false
var debug_overlay_enabled: bool = false
var paused: bool = false
var last_device: String = "keyboard"

var _controller: Node3D
var _held_gear_action: String = ""


func _init(controller: Node3D) -> void:
	_controller = controller


func sample() -> void:
	## Called once per physics tick before the controller steps.
	var steer_kb: float = (
		Input.get_action_strength("steer_left") - Input.get_action_strength("steer_right")
	)
	var steer_pad: float = _axis("gamepad_steer")
	if absf(steer_pad) > PHYSICS_CONSTANTS.GAMEPAD_DEADZONE:
		steer_kb = steer_pad
		last_device = "gamepad"
	elif absf(steer_kb) > 0.0:
		last_device = "keyboard"
	else:
		last_device = "keyboard"
	var rate: float = PHYSICS_CONSTANTS.KEYBOARD_STEER_RATE_DEG_S
	if last_device == "gamepad":
		rate = PHYSICS_CONSTANTS.GAMEPAD_STEER_RATE_DEG_S
	_controller.steer_rate_deg_s = rate

	input_state.throttle = maxf(Input.get_action_strength("throttle"), _axis("gamepad_throttle"))
	input_state.brake = maxf(Input.get_action_strength("brake"), _axis("gamepad_brake"))
	input_state.clutch = maxf(Input.get_action_strength("clutch"), _axis("gamepad_clutch"))
	input_state.steer_axis = clampf(steer_kb, -1.0, 1.0)
	_controller.throttle = input_state.throttle
	_controller.brake_pedal = input_state.brake
	_controller.clutch_pedal = input_state.clutch
	_controller.steer_input_axis = input_state.steer_axis
	_apply_momentary()


func _apply_momentary() -> void:
	var gear_action: String = _pressed_gear_action()
	if gear_action != "":
		if gear_action != _held_gear_action:
			_held_gear_action = gear_action
			_controller.request_gear(InputMapSetup.gear_for_key_index(_gear_index(gear_action)))
	else:
		_held_gear_action = ""
	if Input.is_action_just_pressed("reverse"):
		_controller.request_gear(-1)
	if Input.is_action_just_pressed("neutral"):
		_controller.request_gear(0)
	if Input.is_action_just_pressed("gamepad_gear_up"):
		_controller.request_gear(_controller.transmission.gear + 1)
	if Input.is_action_just_pressed("gamepad_gear_down"):
		_controller.request_gear(maxi(_controller.transmission.gear - 1, -1))
	if (
		Input.is_action_just_pressed("range_toggle")
		or Input.is_action_just_pressed("gamepad_range")
	):
		_controller.request_range_toggle()
	if Input.is_action_just_pressed("transmission_mode"):
		_controller.toggle_transmission_mode()
	if (
		Input.is_action_just_pressed("retarder_up")
		or Input.is_action_just_pressed("gamepad_retarder_right")
	):
		_controller.request_retarder(1)
	if (
		Input.is_action_just_pressed("retarder_down")
		or Input.is_action_just_pressed("gamepad_retarder_left")
	):
		_controller.request_retarder(-1)
	if (
		Input.is_action_just_pressed("parking_brake")
		or Input.is_action_just_pressed("gamepad_parking_brake")
	):
		_controller.toggle_parking_brake()
	if Input.is_action_just_pressed("coupler_unlock"):
		_controller.request_coupler_unlock()
	if (
		Input.is_action_just_pressed("landing_gear")
		or Input.is_action_just_pressed("gamepad_landing_up")
		or Input.is_action_just_pressed("gamepad_landing_down")
	):
		_controller.request_landing_toggle()
	if Input.is_action_just_pressed("trailer_path_overlay"):
		overlay_enabled = not overlay_enabled
	if Input.is_action_just_pressed("debug_overlay"):
		debug_overlay_enabled = not debug_overlay_enabled


func _pressed_gear_action() -> String:
	for i in 10:
		var action: String = InputMapSetup.gear_action_name(i)
		if Input.is_action_pressed(action):
			return action
	return ""


func _gear_index(action: String) -> int:
	## Inverse of InputMapSetup.gear_action_name.
	for i in 10:
		if InputMapSetup.gear_action_name(i) == action:
			return i
	return 9


func _axis(action: String) -> float:
	var value: float = Input.get_action_strength(action)
	if absf(value) < PHYSICS_CONSTANTS.GAMEPAD_DEADZONE:
		return 0.0
	return clampf(value, 0.0, 1.0)
