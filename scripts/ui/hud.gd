class_name Hud
extends CanvasLayer
## HUD and debug overlay (section 12). Built by script so every gauge range and
## warning threshold traces back to PHYSICS_CONSTANTS.
##
## Widget names are pinned by tests/unit/test_hud.gd: Root/<Widget> for the HUD
## and Debug/<Line> for the overlay. Godot 4.7 ships Open Sans SemiBold as its
## built-in UI font, so the spec font needs no vendored file.

const WIDGET_NAMES: Array[String] = [
	"Speed",
	"Tach",
	"Gear",
	"Air",
	"Retarder",
	"ParkingBrake",
	"Articulation",
	"Load",
	"Strikes",
	"Timer",
	"Objective",
	"Flash",
]

# Wheel debug line names, in the order CombinationController._build_wheels
# appends them (steer L/R, drive L/R, bogie front pair, bogie rear pair).
const WHEEL_LINE_NAMES: Array[String] = [
	"SlipSteerL",
	"SlipSteerR",
	"SlipDriveL",
	"SlipDriveR",
	"SlipBogieFL",
	"SlipBogieFR",
	"SlipBogieRL",
	"SlipBogieRR",
]

const DEBUG_SUMMARY_NAMES: Array[String] = [
	"Articulation",
	"ArticulationRate",
	"FifthWheelLoad",
	"CombinationMass",
	"ComOffset",
	"PhysicsStepMs",
	"Fps",
]

const BAR_NAMES: Array[String] = [
	"SpeedBar",
	"TachBar",
	"AirBar",
	"ArticulationBar",
]

var objective_text: String = "FREE DRIVE: NO CHALLENGE ACTIVE"

var _root: Control
var _debug_root: Control
var _labels: Dictionary = {}
var _debug_labels: Dictionary = {}
var _bars: Dictionary = {}
var _bar_fill: Dictionary = {}
var _controller: Node3D = null
var _flash_remaining_s: float = 0.0


func _ready() -> void:
	_build_hud()
	_build_debug_overlay()
	# Flash expiry is driven by refresh(dt), not a Timer, so
	# headless runs stay deterministic (DEVIATIONS D29).
	GAME_STATE.hud_flash.connect(_on_flash)
	_set_label("Objective", objective_text)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


func bind(controller: Node3D) -> void:
	_controller = controller


func set_objective(text: String) -> void:
	objective_text = text
	_set_label("Objective", text)


func refresh(dt: float) -> void:
	# Flash expiry first: the reason label must clear even before a vehicle is
	# bound (a menu or a coupling screen has no controller yet).
	if _flash_remaining_s > 0.0:
		_flash_remaining_s -= dt
		if _flash_remaining_s <= 0.0:
			_clear_flash()
	if _controller == null:
		return
	var controller: Node3D = _controller
	var speed_kmh: float = controller.speed_kmh()
	var rpm: float = controller.engine_rpm
	var air_psi: float = controller.air.pressure_psi
	var artic_deg: float = controller.articulation_deg()

	_set_label("Speed", "%d km/h" % int(round(speed_kmh)))
	_set_label("Tach", "%d rpm" % int(round(rpm)))
	_set_label("Gear", gear_label(controller.transmission))
	_set_label("Air", "%d psi" % int(round(air_psi)))
	var max_stage: int = PHYSICS_CONSTANTS.RETARDER_STAGES_KN.size() - 1
	_set_label("Retarder", "Stage %d/%d" % [controller.retarder_stage, max_stage])
	_set_label("ParkingBrake", "PARK ON" if controller.parking_brake else "PARK OFF")
	_set_label("Articulation", "%d deg" % int(round(artic_deg)))
	_set_label("Load", "%d kg" % int(round(controller.cargo_kg)))
	_set_label("Strikes", "%d/%d" % [GAME_STATE.strikes, PHYSICS_CONSTANTS.STRIKE_LIMIT])
	_set_label("Timer", _timer_text())

	_set_bar_fraction("SpeedBar", speed_fraction(speed_kmh))
	_set_bar_fraction("TachBar", tach_fraction(rpm))
	_set_bar_fraction("AirBar", air_fraction(air_psi))
	_set_bar_fraction("ArticulationBar", articulation_fraction(artic_deg))
	_set_bar_color("TachBar", tach_color(rpm))
	_set_bar_color("AirBar", air_color(air_psi))
	_set_bar_color("ArticulationBar", articulation_color(artic_deg))
	_set_label_color("Air", air_color(air_psi))
	_set_label_color("Articulation", articulation_color(artic_deg))
	_set_label_color("Tach", tach_color(rpm))
	if controller.air.spring_brake_engaged:
		_set_label_color("ParkingBrake", PHYSICS_CONSTANTS.HUD_COLOR_DANGER)

	if _debug_root.visible:
		_refresh_debug()


func label_text(widget: String) -> String:
	var label: Label = _labels.get(widget) as Label
	if label == null:
		return ""
	return label.text


func set_debug_visible(visible_now: bool) -> void:
	_debug_root.visible = visible_now


func debug_visible() -> bool:
	return _debug_root.visible


func label_rect(widget: String) -> Rect2:
	## Global rect of a HUD widget, used by the layout test to prove that no two
	## readouts collide.
	var label: Label = _labels.get(widget) as Label
	if label == null:
		return Rect2()
	return label.get_global_rect()


func panel_rect() -> Rect2:
	var panel: ColorRect = _root.get_node("Panel") as ColorRect
	return panel.get_global_rect()


func debug_lines() -> Array[String]:
	## The per-wheel slip lines, in pinned order.
	var out: Array[String] = []
	for name_v in WHEEL_LINE_NAMES:
		var label: Label = _debug_labels.get(name_v) as Label
		out.append(label.text if label != null else "")
	return out


# ---------------------------------------------------------------------------
# Pure gauge math (asserted by tests)
# ---------------------------------------------------------------------------


static func speed_fraction(speed_kmh: float) -> float:
	return clampf(speed_kmh / PHYSICS_CONSTANTS.HUD_SPEED_MAX_KMH, 0.0, 1.0)


static func tach_fraction(rpm: float) -> float:
	return clampf(rpm / PHYSICS_CONSTANTS.HUD_TACH_MAX_RPM, 0.0, 1.0)


static func air_fraction(psi: float) -> float:
	return clampf(psi / PHYSICS_CONSTANTS.HUD_AIR_MAX_PSI, 0.0, 1.0)


static func air_color(psi: float) -> Color:
	## Yellow at 60 psi (AIR_WARN_PSI), red at 40 psi (AIR_SPRING_BRAKE_PSI).
	if psi <= PHYSICS_CONSTANTS.AIR_SPRING_BRAKE_PSI:
		return PHYSICS_CONSTANTS.HUD_COLOR_DANGER
	if psi <= PHYSICS_CONSTANTS.AIR_WARN_PSI:
		return PHYSICS_CONSTANTS.HUD_COLOR_WARN
	return PHYSICS_CONSTANTS.HUD_COLOR_OK


static func articulation_fraction(artic_deg: float) -> float:
	## -75..+75 mapped onto 0..1 so the hard limit sits at both ends of the bar.
	var half: float = PHYSICS_CONSTANTS.HUD_ARTICULATION_MAX_DEG
	return clampf((artic_deg + half) / (2.0 * half), 0.0, 1.0)


static func articulation_color(artic_deg: float) -> Color:
	var magnitude: float = absf(artic_deg)
	if magnitude >= PHYSICS_CONSTANTS.HUD_ARTICULATION_DANGER_DEG:
		return PHYSICS_CONSTANTS.HUD_COLOR_DANGER
	if magnitude >= PHYSICS_CONSTANTS.HUD_ARTICULATION_WARN_DEG:
		return PHYSICS_CONSTANTS.HUD_COLOR_WARN
	return PHYSICS_CONSTANTS.HUD_COLOR_OK


static func gear_label(transmission: Transmission) -> String:
	## R, N, or range/gear (H3 for third high, L8 for eighth low).
	if transmission.gear == -1:
		return "R"
	if transmission.gear == 0:
		return "N"
	var prefix: String = "H"
	if transmission.range == PHYSICS_CONSTANTS.GEAR_RANGE_LOW:
		prefix = "L"
	return "%s%d" % [prefix, transmission.gear]


static func tach_color(rpm: float) -> Color:
	if rpm >= PHYSICS_CONSTANTS.HUD_TACH_REDLINE_RPM:
		return PHYSICS_CONSTANTS.HUD_COLOR_DANGER
	return PHYSICS_CONSTANTS.HUD_COLOR_OK


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------


func _build_hud() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# Backing panel so light HUD text stays readable over sky and concrete.
	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.position = Vector2(12.0, 12.0)
	panel.size = Vector2(588.0, 34.0 * WIDGET_NAMES.size() + 20.0)
	panel.color = Color(0.06, 0.07, 0.08, 0.72)
	_root.add_child(panel)
	var x: float = 24.0
	var y: float = 24.0
	for name_v in WIDGET_NAMES:
		var label := _make_label(name_v, Vector2(x, y))
		if name_v == "Flash":
			# Flash keeps its own row at the bottom of the panel so it can never
			# overlap a gauge readout.
			label.add_theme_color_override("font_color", PHYSICS_CONSTANTS.HUD_COLOR_WARN)
		y += 34.0
	for name_v in BAR_NAMES:
		_make_bar(name_v)


func _build_debug_overlay() -> void:
	_debug_root = Control.new()
	_debug_root.name = "Debug"
	_debug_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_debug_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_debug_root.visible = false
	add_child(_debug_root)
	var panel := ColorRect.new()
	panel.name = "Panel"
	panel.position = Vector2(608.0, 12.0)
	panel.size = Vector2(
		660.0, 24.0 * (WHEEL_LINE_NAMES.size() + DEBUG_SUMMARY_NAMES.size()) + 12.0
	)
	panel.color = Color(0.06, 0.07, 0.08, 0.72)
	_debug_root.add_child(panel)
	var y: float = 24.0
	for name_v in WHEEL_LINE_NAMES + DEBUG_SUMMARY_NAMES:
		var label := _make_label(name_v, Vector2(620.0, y), _debug_root)
		y += 24.0


func _make_label(name_v: String, at: Vector2, parent: Control = null) -> Label:
	var target: Control = parent if parent != null else _root
	var label := Label.new()
	label.name = name_v
	label.position = at
	label.add_theme_font_size_override("font_size", PHYSICS_CONSTANTS.HUD_FONT_SIZE)
	label.add_theme_color_override("font_color", PHYSICS_CONSTANTS.HUD_COLOR_OK)
	label.text = ""
	target.add_child(label)
	if parent == null:
		_labels[name_v] = label
	else:
		_debug_labels[name_v] = label
	return label


func _make_bar(name_v: String) -> void:
	var track := ColorRect.new()
	track.name = name_v
	track.position = Vector2(250.0, 24.0 + _bars.size() * 34.0 + 2.0)
	track.size = Vector2(180.0, 12.0)
	track.color = Color(0.16, 0.17, 0.18)
	_root.add_child(track)
	var fill := ColorRect.new()
	fill.name = "Fill"
	fill.position = Vector2.ZERO
	fill.size = Vector2(0.0, 12.0)
	fill.color = PHYSICS_CONSTANTS.HUD_COLOR_OK
	track.add_child(fill)
	_bars[name_v] = track
	_bar_fill[name_v] = fill


# ---------------------------------------------------------------------------
# Internals
# ---------------------------------------------------------------------------


func _refresh_debug() -> void:
	if _controller == null:
		return
	var controller: Node3D = _controller
	var wheels: Array = controller.wheels
	for i in WHEEL_LINE_NAMES.size():
		var label: Label = _debug_labels.get(WHEEL_LINE_NAMES[i]) as Label
		if label == null:
			continue
		if i >= wheels.size():
			label.text = "%s: n/a" % WHEEL_LINE_NAMES[i]
			continue
		var w: WheelRig = wheels[i] as WheelRig
		label.text = (
			"%s: slip %.3f  angle %.1f deg  N %d"
			% [WHEEL_LINE_NAMES[i], w.slip_ratio, rad_to_deg(w.slip_angle_rad), int(w.normal_n)]
		)
	_set_debug_text("Articulation", "%.2f deg" % controller.articulation_deg())
	_set_debug_text("ArticulationRate", "%.2f deg/s" % controller.articulation_rate_deg_s())
	_set_debug_text(
		"FifthWheelLoad",
		"%.0f kg" % (controller.fifth_wheel_load_n / PHYSICS_CONSTANTS.GRAVITY_M_S2)
	)
	_set_debug_text("CombinationMass", "%.0f kg" % LoadMath.combined_mass(controller.cargo_kg))
	_set_debug_text("ComOffset", _com_offset_text())
	_set_debug_text("PhysicsStepMs", "%.2f ms" % controller.physics_step_ms)
	_set_debug_text("Fps", "%d" % int(Engine.get_frames_per_second()))


func _com_offset_text() -> String:
	## Center of mass offsets from each body origin, which is where the
	## suspension and tire forces are levered from (DEVIATIONS D21).
	var t_com: Vector3 = PHYSICS_CONSTANTS.TRACTOR_COM
	var s_com: Vector3 = LoadMath.trailer_com_loaded(_controller.cargo_kg)
	return (
		"tractor (%.2f, %.2f, %.2f) trailer (%.2f, %.2f, %.2f)"
		% [t_com.x, t_com.y, t_com.z, s_com.x, s_com.y, s_com.z]
	)


func _set_debug_text(name_v: String, text: String) -> void:
	var label: Label = _debug_labels.get(name_v) as Label
	if label != null:
		label.text = text


func _timer_text() -> String:
	if GAME_STATE.challenge_state == GAME_STATE.ChallengeState.IDLE:
		return "--:--"
	return (
		"%02d:%02d"
		% [int(GAME_STATE.challenge_elapsed_s) / 60, int(GAME_STATE.challenge_elapsed_s) % 60]
	)


func _on_flash(message: String) -> void:
	_set_label("Flash", message)
	_flash_remaining_s = PHYSICS_CONSTANTS.HUD_FLASH_SECONDS


func _clear_flash() -> void:
	_set_label("Flash", "")


func _set_label(name_v: String, text: String) -> void:
	var label: Label = _labels.get(name_v) as Label
	if label != null:
		label.text = text


func _set_label_color(name_v: String, color: Color) -> void:
	var label: Label = _labels.get(name_v) as Label
	if label != null:
		label.add_theme_color_override("font_color", color)


func _set_bar_fraction(name_v: String, fraction: float) -> void:
	var fill: ColorRect = _bar_fill.get(name_v) as ColorRect
	if fill == null:
		return
	var track: ColorRect = _bars.get(name_v) as ColorRect
	fill.size = Vector2(track.size.x * fraction, track.size.y)


func _set_bar_color(name_v: String, color: Color) -> void:
	var fill: ColorRect = _bar_fill.get(name_v) as ColorRect
	if fill != null:
		fill.color = color
