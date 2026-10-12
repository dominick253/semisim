class_name VehicleInput
## Plain input state for the combination. The live game fills this from the
## input map; headless scenarios fill it from scripted schedules. All values
## are sampled once per physics tick, which keeps runs deterministic.

var throttle: float = 0.0  # 0..1
var brake: float = 0.0  # 0..1
var clutch: float = 0.0  # 0 released .. 1 fully pressed
var steer_axis: float = 0.0  # -1 right .. +1 left
var gear_request: int = -2  # -2 none, -1 R, 0 N, 1..10
var range_toggle: bool = false
var retarder_delta: int = 0  # +1 up, -1 down, 0 none
var parking_brake_toggle: bool = false
var coupler_unlock: bool = false
var landing_toggle: bool = false
var transmission_mode_toggle: bool = false


func clear_momentary() -> void:
	gear_request = -2
	range_toggle = false
	retarder_delta = 0
	parking_brake_toggle = false
	coupler_unlock = false
	landing_toggle = false
	transmission_mode_toggle = false
