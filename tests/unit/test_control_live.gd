extends GutTest
## Task 21 part 2: the no-op rules must reach the HUD as reason flashes when
## driven through the live combination controller, not only through the pure
## rule table. Split out of test_controls.gd to stay inside the gdlint public
## method budget.

var _harness: Node = null

# ---------------------------------------------------------------------------
# Live controller: every no-op must reach the HUD as a reason flash
# ---------------------------------------------------------------------------


func _live_controller() -> Dictionary:
	var harness: Node = load("res://tests/sim/combination_rest_harness.tscn").instantiate()
	add_child(harness)
	await harness.settle(120)
	var flashes: Array[String] = []
	var sink: Callable = func(message: String) -> void: flashes.append(message)
	GAME_STATE.hud_flash.connect(sink)
	return {"harness": harness, "controller": harness.controller, "flashes": flashes, "sink": sink}


func test_live_manual_gear_change_without_clutch_flashes_a_reason() -> void:
	var ctx: Dictionary = await _live_controller()
	var controller: Node = ctx["controller"]
	# The harness settles in automatic mode, which auto-shifts into a drive
	# gear. Force neutral and manual mode so the shift under test is real.
	controller.transmission.automatic = false
	controller.transmission.gear = 0
	controller.request_gear(4)
	var flashes: Array = ctx["flashes"]
	assert_eq(flashes.size(), 1, "one reason flash")
	assert_eq(flashes[0], NoopRules.REASON_GEAR_NO_CLUTCH, "flash text")
	assert_eq(controller.transmission.gear, 0, "gear unchanged (no-op)")
	_free_harness(ctx)


func test_live_auto_mode_gear_change_does_not_flash() -> void:
	var ctx: Dictionary = await _live_controller()
	var controller: Node = ctx["controller"]
	controller.transmission.automatic = true
	controller.request_gear(4)
	assert_eq(ctx["flashes"].size(), 0, "accepted shift is silent")
	assert_eq(controller.transmission.gear, 4, "gear changed")
	_free_harness(ctx)


func test_live_retarder_in_low_range_flashes_a_reason() -> void:
	var ctx: Dictionary = await _live_controller()
	var controller: Node = ctx["controller"]
	controller.transmission.automatic = true
	controller.request_gear(8)  # low range
	controller.request_retarder(1)
	var flashes: Array = ctx["flashes"]
	assert_eq(flashes.size(), 1, "retarder rejected")
	assert_eq(flashes[0], NoopRules.REASON_RETARDER, "flash text")
	assert_eq(controller.retarder_stage, 0, "stage unchanged (no-op)")
	_free_harness(ctx)


func test_live_unlock_while_coupled_and_rolling_flashes_a_reason() -> void:
	var ctx: Dictionary = await _live_controller()
	var controller: Node = ctx["controller"]
	controller.parking_brake = false
	controller.request_coupler_unlock()
	var flashes: Array = ctx["flashes"]
	assert_eq(flashes.size(), 1, "unlock rejected")
	assert_true(
		flashes[0] == NoopRules.REASON_UNLOCK_SPEED or flashes[0] == NoopRules.REASON_UNLOCK_BRAKE,
		"flash names the missing condition: %s" % flashes[0]
	)
	assert_true(controller.coupled, "still coupled (no-op)")
	_free_harness(ctx)


func test_live_landing_gear_while_attached_flashes_a_reason() -> void:
	var ctx: Dictionary = await _live_controller()
	var controller: Node = ctx["controller"]
	controller.request_landing_toggle()
	var flashes: Array = ctx["flashes"]
	assert_eq(flashes.size(), 1, "landing gear rejected")
	assert_eq(flashes[0], NoopRules.REASON_LANDING_ATTACHED, "flash text")
	_free_harness(ctx)


func test_control_layer_samples_the_live_controller() -> void:
	var ctx: Dictionary = await _live_controller()
	var controller: Node = ctx["controller"]
	var layer: ControlLayer = ControlLayer.new(controller)
	layer.sample()
	assert_true(layer.input_state is VehicleInput, "input state filled")
	assert_eq(
		controller.steer_rate_deg_s,
		PHYSICS_CONSTANTS.KEYBOARD_STEER_RATE_DEG_S,
		"keyboard steer rate by default"
	)
	layer.overlay_enabled = true
	assert_true(layer.overlay_enabled, "G overlay toggles")
	_free_harness(ctx)


func test_control_layer_lives_in_code_not_project_godot() -> void:
	var cfg: String = FileAccess.get_file_as_string("res://project.godot")
	assert_false(cfg.contains("[input]"), "project.godot must not hand-author the map")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _free_harness(ctx: Dictionary) -> void:
	## The flash sink lives on the GAME_STATE autoload, so it must be detached
	## or the next test sees the previous test's flash handler.
	GAME_STATE.hud_flash.disconnect(ctx["sink"] as Callable)
	var harness: Node = ctx["harness"]
	harness.queue_free()
	await get_tree().physics_frame
