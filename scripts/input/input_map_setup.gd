class_name InputMapSetup
## Installs the complete section 11 control map. Called from _enter_tree of the
## boot scene and from tests, so the map is identical no matter how the game is
## launched. install() is idempotent: it erases each pinned action first, so a
## re-install never duplicates bindings.

## Keyboard gear keys 1..0 in physical order: 1..5 are the high range, 6..0 the
## low range (section 11). Index 0..9 maps to gear 1..10.
const GEAR_KEY_ORDER: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

const KEYBOARD_ACTIONS: Dictionary = {
	"throttle": KEY_W,
	"brake": KEY_S,
	"clutch": KEY_SHIFT,
	"reverse": KEY_R,
	"neutral": KEY_N,
	"range_toggle": KEY_E,
	"retarder_up": KEY_Z,
	"retarder_down": KEY_X,
	"parking_brake": KEY_SPACE,
	"coupler_unlock": KEY_U,
	"landing_gear": KEY_L,
	"camera_cycle": KEY_TAB,
	"trailer_path_overlay": KEY_G,
	"transmission_mode": KEY_V,
	"debug_overlay": KEY_F3,
	"context_help": KEY_F1,
	"pause_menu": KEY_ESCAPE,
}

const STEER_LEFT_KEYS: Array[int] = [KEY_A, KEY_LEFT]
const STEER_RIGHT_KEYS: Array[int] = [KEY_D, KEY_RIGHT]

# Gamepad (section 11): LT throttle, RT brake, LSx steer, LB clutch, A gear up,
# B gear down, X range, Y parking brake, Dpad left/right retarder, Dpad
# up/down landing gear, RS camera, RB camera cycle, Start pause.
const GAMEPAD_BUTTON_ACTIONS: Dictionary = {
	"gamepad_clutch": JoyButton.JOY_BUTTON_LEFT_SHOULDER,
	"gamepad_gear_up": JoyButton.JOY_BUTTON_A,
	"gamepad_gear_down": JoyButton.JOY_BUTTON_B,
	"gamepad_range": JoyButton.JOY_BUTTON_X,
	"gamepad_parking_brake": JoyButton.JOY_BUTTON_Y,
	"gamepad_retarder_left": JoyButton.JOY_BUTTON_DPAD_LEFT,
	"gamepad_retarder_right": JoyButton.JOY_BUTTON_DPAD_RIGHT,
	"gamepad_landing_up": JoyButton.JOY_BUTTON_DPAD_UP,
	"gamepad_landing_down": JoyButton.JOY_BUTTON_DPAD_DOWN,
	"gamepad_camera": JoyButton.JOY_BUTTON_RIGHT_STICK,
	"gamepad_camera_cycle": JoyButton.JOY_BUTTON_RIGHT_SHOULDER,
	"gamepad_pause": JoyButton.JOY_BUTTON_START,
}

const GAMEPAD_AXIS_ACTIONS: Dictionary = {
	"gamepad_throttle": [JoyAxis.JOY_AXIS_TRIGGER_LEFT, 1.0],
	"gamepad_brake": [JoyAxis.JOY_AXIS_TRIGGER_RIGHT, 1.0],
}

const STEER_AXIS: Array = [JoyAxis.JOY_AXIS_LEFT_X]


static func install() -> void:
	for action in KEYBOARD_ACTIONS:
		_ensure_action(action)
		_add_key(action, int(KEYBOARD_ACTIONS[action]))
	for action in ["steer_left", "steer_right"]:
		_ensure_action(action)
	for key in STEER_LEFT_KEYS:
		_add_key("steer_left", key)
	for key in STEER_RIGHT_KEYS:
		_add_key("steer_right", key)
	for i in 10:
		var action: String = gear_action_name(i)
		_ensure_action(action)
		_add_key(action, _gear_keycode(i))
	for action in GAMEPAD_BUTTON_ACTIONS:
		_ensure_action(action)
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(GAMEPAD_BUTTON_ACTIONS[action])
		InputMap.action_add_event(action, ev)
	for action in GAMEPAD_AXIS_ACTIONS:
		_ensure_action(action)
		var spec: Array = GAMEPAD_AXIS_ACTIONS[action] as Array
		_add_axis(action, int(spec[0]), float(spec[1]))
	_ensure_action("gamepad_steer")
	_add_axis("gamepad_steer", JoyAxis.JOY_AXIS_LEFT_X, -1.0)
	_add_axis("gamepad_steer", JoyAxis.JOY_AXIS_LEFT_X, 1.0)


static func gear_action_name(key_index: int) -> String:
	## key_index 0..9 is the physical key row order 1,2,3,4,5,6,7,8,9,0.
	return "gear_%d" % (10 if key_index == 9 else key_index + 1)


static func gear_for_key_index(key_index: int) -> int:
	## The transmission gear number a gear key selects.
	return GEAR_KEY_ORDER[key_index]


static func _gear_keycode(key_index: int) -> int:
	match key_index:
		0:
			return KEY_1
		1:
			return KEY_2
		2:
			return KEY_3
		3:
			return KEY_4
		4:
			return KEY_5
		5:
			return KEY_6
		6:
			return KEY_7
		7:
			return KEY_8
		8:
			return KEY_9
		_:
			return KEY_0


static func _ensure_action(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action)


static func _add_key(action: String, physical: int) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = physical
	InputMap.action_add_event(action, ev)


static func _add_axis(action: String, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
