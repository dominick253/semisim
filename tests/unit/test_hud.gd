extends GutTest
## Task 22: HUD (section 12) and debug overlay.
##
## The HUD is built by script from PHYSICS_CONSTANTS so every gauge range and
## warning threshold is traceable. Asserts:
##   - every pinned HUD widget exists,
##   - gauge values clamp at both ends of their pinned ranges,
##   - the air gauge goes yellow at 60 psi and red at 40 psi,
##   - the articulation gauge goes yellow at +/- 45 deg and red at +/- 60 deg,
##   - the gear indicator reads R, N, or range/gear,
##   - the debug overlay reports one slip line per wheel plus the pinned summary
##     fields,
##   - a GAME_STATE flash lands on the HUD reason label.

const Hud := preload("res://scripts/ui/hud.gd")
const NoopRules := preload("res://scripts/input/noop_rules.gd")

const REQUIRED_NODES: Array[String] = [
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
const REQUIRED_DEBUG_LINES: Array[String] = [
	"SlipSteerL",
	"SlipSteerR",
	"SlipDriveL",
	"SlipDriveR",
	"SlipBogieFL",
	"SlipBogieFR",
	"SlipBogieRL",
	"SlipBogieRR",
	"Articulation",
	"ArticulationRate",
	"FifthWheelLoad",
	"CombinationMass",
	"ComOffset",
	"PhysicsStepMs",
	"Fps",
]

var _hud: Hud


func before_each() -> void:
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	add_child(_hud)


func _matches(text: String, pattern: String) -> bool:
	var re: RegEx = RegEx.create_from_string(pattern)
	return re.search(text) != null


func after_each() -> void:
	_hud.queue_free()
	await get_tree().process_frame


# ---------------------------------------------------------------------------
# Widget inventory
# ---------------------------------------------------------------------------


func test_every_pinned_hud_widget_exists() -> void:
	for name_v in REQUIRED_NODES:
		var node: Node = _hud.get_node_or_null("Root/" + name_v)
		assert_true(node is Label, "missing HUD label: %s" % name_v)


func test_hud_font_is_open_sans_semibold_16() -> void:
	## Godot 4.7 ships Open Sans SemiBold as its built-in UI font, so the spec's
	## font requirement needs no vendored file (see docs/ATTRIBUTION.md).
	var label: Label = _hud.get_node("Root/Speed") as Label
	var font: FontFile = label.get_theme_font("font") as FontFile
	assert_true(font is FontFile, "HUD font must be a font file")
	assert_eq(font.get_font_name(), PHYSICS_CONSTANTS.HUD_FONT_NAME, "font name")
	assert_eq(font.get_font_style_name(), PHYSICS_CONSTANTS.HUD_FONT_STYLE, "font style")
	assert_eq(font.get_font_weight(), PHYSICS_CONSTANTS.HUD_FONT_WEIGHT, "weight 600")
	assert_eq(label.get_theme_font_size("font"), PHYSICS_CONSTANTS.HUD_FONT_SIZE, "16 px")


func test_hud_is_ascii_only() -> void:
	## Style rule: no em dash or non-ASCII in UI text.
	var harness: Node = _make_controller()
	await harness.settle(60)
	_hud.bind(harness.controller)
	_hud.refresh(1.0 / 60.0)
	for name_v in REQUIRED_NODES:
		var label: Label = _hud.get_node("Root/" + name_v) as Label
		var text: String = label.text
		for i in text.length():
			assert_lt(text.unicode_at(i), 128, "%s contains non-ASCII: %s" % [name_v, text])
	harness.queue_free()


# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------


func test_hud_widgets_do_not_overlap_each_other() -> void:
	var harness: Node = _make_controller()
	await harness.settle(60)
	_hud.bind(harness.controller)
	_hud.refresh(1.0 / 60.0)
	await get_tree().process_frame
	var rects: Dictionary = {}
	for name_v in REQUIRED_NODES:
		rects[name_v] = _hud.label_rect(name_v)
	for i in REQUIRED_NODES.size():
		for j in range(i + 1, REQUIRED_NODES.size()):
			var a: Rect2 = rects[REQUIRED_NODES[i]] as Rect2
			var b: Rect2 = rects[REQUIRED_NODES[j]] as Rect2
			assert_false(
				a.intersects(b),
				"%s overlaps %s: %s vs %s" % [REQUIRED_NODES[i], REQUIRED_NODES[j], a, b]
			)
	harness.queue_free()
	await get_tree().physics_frame


func test_hud_readouts_fit_inside_the_backing_panel() -> void:
	var harness: Node = _make_controller()
	await harness.settle(60)
	_hud.bind(harness.controller)
	_hud.refresh(1.0 / 60.0)
	GAME_STATE.flash(NoopRules.REASON_RETARDER)
	await get_tree().process_frame
	var panel: Rect2 = _hud.panel_rect()
	for name_v in REQUIRED_NODES:
		var r: Rect2 = _hud.label_rect(name_v)
		assert_true(panel.encloses(r), "%s spills outside the panel: %s in %s" % [name_v, r, panel])
	harness.queue_free()
	await get_tree().physics_frame


# ---------------------------------------------------------------------------
# Gauge ranges and warning thresholds
# ---------------------------------------------------------------------------


func test_speed_gauge_range_is_0_to_160_kmh() -> void:
	assert_eq(PHYSICS_CONSTANTS.HUD_SPEED_MAX_KMH, 160.0, "pinned range")
	assert_almost_eq(Hud.speed_fraction(-20.0), 0.0, 1e-9, "clamped low")
	assert_almost_eq(Hud.speed_fraction(400.0), 1.0, 1e-9, "clamped high")
	assert_almost_eq(Hud.speed_fraction(80.0), 0.5, 1e-9, "half scale")


func test_tach_range_is_0_to_1800_with_redline_at_1750() -> void:
	assert_eq(PHYSICS_CONSTANTS.HUD_TACH_MAX_RPM, 1800.0, "pinned tach range")
	assert_eq(PHYSICS_CONSTANTS.HUD_TACH_REDLINE_RPM, 1750.0, "pinned redline")
	assert_almost_eq(Hud.tach_fraction(-100.0), 0.0, 1e-9, "clamped low")
	assert_almost_eq(Hud.tach_fraction(3000.0), 1.0, 1e-9, "clamped high")
	assert_almost_eq(Hud.tach_fraction(900.0), 0.5, 1e-9, "half scale")


func test_air_gauge_range_is_0_to_120_psi() -> void:
	assert_eq(PHYSICS_CONSTANTS.HUD_AIR_MAX_PSI, 120.0, "pinned air gauge range")
	assert_almost_eq(Hud.air_fraction(-5.0), 0.0, 1e-9, "clamped low")
	assert_almost_eq(Hud.air_fraction(200.0), 1.0, 1e-9, "clamped high")


func test_air_gauge_color_thresholds() -> void:
	var green: Color = PHYSICS_CONSTANTS.HUD_COLOR_OK
	var yellow: Color = PHYSICS_CONSTANTS.HUD_COLOR_WARN
	var red: Color = PHYSICS_CONSTANTS.HUD_COLOR_DANGER
	assert_eq(Hud.air_color(61.0), green, "61 psi is nominal")
	assert_eq(Hud.air_color(60.0), yellow, "yellow at 60 psi")
	assert_eq(Hud.air_color(41.0), yellow, "still yellow above 40")
	assert_eq(Hud.air_color(40.0), red, "red at 40 psi")
	assert_eq(Hud.air_color(0.0), red, "red at 0 psi")


func test_articulation_gauge_range_is_minus_75_to_plus_75() -> void:
	assert_almost_eq(Hud.articulation_fraction(-90.0), 0.0, 1e-9, "clamped low")
	assert_almost_eq(Hud.articulation_fraction(90.0), 1.0, 1e-9, "clamped high")
	assert_almost_eq(Hud.articulation_fraction(0.0), 0.5, 1e-9, "center is half scale")
	assert_almost_eq(Hud.articulation_fraction(75.0), 1.0, 1e-9, "hard limit at full scale")


func test_articulation_gauge_color_thresholds() -> void:
	var green: Color = PHYSICS_CONSTANTS.HUD_COLOR_OK
	var yellow: Color = PHYSICS_CONSTANTS.HUD_COLOR_WARN
	var red: Color = PHYSICS_CONSTANTS.HUD_COLOR_DANGER
	assert_eq(Hud.articulation_color(44.0), green, "44 deg is fine")
	assert_eq(Hud.articulation_color(-44.0), green, "-44 deg is fine")
	assert_eq(Hud.articulation_color(45.0), yellow, "yellow at +45")
	assert_eq(Hud.articulation_color(-45.0), yellow, "yellow at -45")
	assert_eq(Hud.articulation_color(60.0), red, "red at +60")
	assert_eq(Hud.articulation_color(-60.0), red, "red at -60")
	assert_eq(Hud.articulation_color(80.0), red, "red beyond the gauge")


# ---------------------------------------------------------------------------
# Gear indicator
# ---------------------------------------------------------------------------


func test_gear_indicator_reads_r_n_or_range_gear() -> void:
	var t := Transmission.new()
	t.gear = -1
	assert_eq(Hud.gear_label(t), "R", "reverse")
	t.gear = 0
	assert_eq(Hud.gear_label(t), "N", "neutral")
	t.gear = 3
	t.range = PHYSICS_CONSTANTS.GEAR_RANGE_HIGH
	assert_eq(Hud.gear_label(t), "H3", "third high")
	t.gear = 8
	t.range = PHYSICS_CONSTANTS.GEAR_RANGE_LOW
	assert_eq(Hud.gear_label(t), "L8", "eighth low")


# ---------------------------------------------------------------------------
# Live refresh against the real controller
# ---------------------------------------------------------------------------


func _make_controller() -> Node:
	var harness: Node = load("res://tests/sim/combination_rest_harness.tscn").instantiate()
	add_child(harness)
	return harness


func test_refresh_writes_every_widget_from_the_controller() -> void:
	var harness: Node = _make_controller()
	await harness.settle(120)
	var controller: Node = harness.controller
	_hud.bind(controller)
	_hud.refresh(1.0 / 60.0)
	assert_true(
		_matches(_hud.label_text("Speed"), r"^\d+(\.\d)? km/h$"),
		"speed text: %s" % _hud.label_text("Speed")
	)
	assert_true(
		_matches(_hud.label_text("Tach"), r"^\d+ rpm$"), "tach text: %s" % _hud.label_text("Tach")
	)
	assert_true(
		(
			_hud.label_text("Gear")
			in ["R", "N", "H1", "H2", "H3", "H4", "H5", "L6", "L7", "L8", "L9", "L10"]
		),
		"gear text: %s" % _hud.label_text("Gear")
	)
	assert_true(
		_matches(_hud.label_text("Air"), r"^\d+ psi$"), "air text: %s" % _hud.label_text("Air")
	)
	assert_true(
		_matches(_hud.label_text("Retarder"), r"^Stage \d/\d$"),
		"retarder text: %s" % _hud.label_text("Retarder")
	)
	assert_true(
		_matches(_hud.label_text("Articulation"), r"^-?\d+ deg$"),
		"articulation text: %s" % _hud.label_text("Articulation")
	)
	assert_true(
		_matches(_hud.label_text("Load"), r"^\d+ kg$"), "load text: %s" % _hud.label_text("Load")
	)
	assert_eq(_hud.label_text("Strikes"), "0/3", "strikes text")
	assert_true(
		_hud.label_text("ParkingBrake") in ["PARK OFF", "PARK ON"],
		"parking lamp: %s" % _hud.label_text("ParkingBrake")
	)
	assert_true(_hud.label_text("Objective").length() > 0, "objective line")
	harness.queue_free()
	await get_tree().physics_frame


func test_flash_reaches_the_hud_reason_label() -> void:
	GAME_STATE.flash("SHIFT NEEDS CLUTCH OR AUTO MODE")
	await get_tree().process_frame
	assert_eq(_hud.label_text("Flash"), "SHIFT NEEDS CLUTCH OR AUTO MODE", "flash text")


func test_flash_clears_after_the_pinned_duration() -> void:
	## Flash expiry runs on simulated ticks, not wall clock, so it is
	## deterministic in headless runs.
	GAME_STATE.flash("UNLOCK NEEDS PARKING BRAKE")
	await get_tree().process_frame
	assert_eq(_hud.label_text("Flash"), "UNLOCK NEEDS PARKING BRAKE", "flash shown")
	var ticks: int = int(
		PHYSICS_CONSTANTS.HUD_FLASH_SECONDS * PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND
	)
	for _i in ticks + 2:
		_hud.refresh(1.0 / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
	assert_eq(_hud.label_text("Flash"), "", "flash cleared")


# ---------------------------------------------------------------------------
# Debug overlay
# ---------------------------------------------------------------------------


func test_debug_overlay_has_one_slip_line_per_wheel_and_the_pinned_fields() -> void:
	var harness: Node = _make_controller()
	await harness.settle(60)
	var controller: Node = harness.controller
	_hud.bind(controller)
	_hud.set_debug_visible(true)
	_hud.refresh(1.0 / 60.0)
	for name_v in REQUIRED_DEBUG_LINES:
		var node: Node = _hud.get_node_or_null("Debug/" + name_v)
		assert_true(node is Label, "missing debug line: %s" % name_v)
	assert_eq(_hud.debug_lines().size(), controller.wheels.size(), "one slip line per wheel")
	harness.queue_free()
	await get_tree().physics_frame


func test_debug_overlay_hides_and_shows() -> void:
	_hud.set_debug_visible(true)
	assert_true(_hud.debug_visible(), "shown")
	_hud.set_debug_visible(false)
	assert_false(_hud.debug_visible(), "hidden")


func test_debug_overlay_is_hidden_by_default() -> void:
	assert_false(_hud.debug_visible(), "F3 toggles, it does not start visible")
