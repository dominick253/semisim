extends GutTest
## Task 24 part 5: the AudioStreamGenerator wiring and its link to the live
## combination. Runs headless with no output device, which is valid because the
## generator only needs the stream, not a sink.

const AudioDirector := preload("res://scripts/audio/audio_director.gd")

const HARNESS_SCENE: String = "res://tests/sim/combination_rest_harness.tscn"

var _harness: Node = null
var _director: Node = null


func before_each() -> void:
	_harness = load(HARNESS_SCENE).instantiate()
	add_child(_harness)
	_director = AudioDirector.new()
	_director.name = "AudioDirector"
	_director.bind(_harness.controller)
	add_child(_director)


func after_each() -> void:
	_director.queue_free()
	if is_instance_valid(_harness):
		_harness.queue_free()
		await get_tree().physics_frame
		await get_tree().physics_frame


func test_generator_is_an_audio_stream_generator_at_48khz() -> void:
	var gen: AudioStreamGenerator = _director.generator
	assert_true(gen is AudioStreamGenerator, "AudioStreamGenerator")
	assert_eq(int(gen.mix_rate), PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ, "48 kHz")
	assert_eq(
		int(gen.mix_rate_mode),
		int(AudioStreamGenerator.MIX_RATE_CUSTOM),
		"mix_rate_mode custom so 48 kHz is honored"
	)
	assert_gt(gen.buffer_length, 0.0, "buffer length set")


func test_zero_audio_files_are_loaded() -> void:
	## Section 13: procedural only, zero audio files.
	var src: String = FileAccess.get_file_as_string("res://scripts/audio/audio_director.gd")
	assert_false(src.contains(".wav"), "no wav")
	assert_false(src.contains(".ogg"), "no ogg")
	assert_false(src.contains("AudioStreamMP3"), "no mp3")
	var synth: String = FileAccess.get_file_as_string("res://scripts/audio/audio_synth.gd")
	assert_false(synth.contains("randf"), "no randf in the synth")
	assert_false(synth.contains("RandomNumberGenerator"), "no RNG object in the synth")


func test_director_reads_the_live_combination_state() -> void:
	## rpm is speed-linked (section 4), so the combination has to actually roll
	## before the tone leaves idle. Automatic mode holds first gear off the line.
	await _harness.settle(120)
	_harness.controller.transmission.automatic = true
	_harness.controller.throttle = 1.0
	for _i in 600:
		await get_tree().physics_frame
	var frame: Dictionary = _director.current_frame()
	assert_gt(float(frame["rpm"]), PHYSICS_CONSTANTS.ENGINE_IDLE_RPM, "rpm rises once rolling")
	assert_almost_eq(
		float(frame["rpm"]),
		float(_harness.controller.engine_rpm),
		1e-6,
		"frame rpm mirrors the controller"
	)
	assert_almost_eq(float(frame["throttle"]), 1.0, 1e-6, "throttle mirrored")
	assert_true(frame.has("lateral_slip"), "frame key lateral_slip")
	assert_true(frame.has("slip_energy"), "frame key slip_energy")
	assert_true(frame.has("articulation_deg"), "frame key articulation_deg")
	assert_true(frame.has("hiss_elapsed"), "frame key hiss_elapsed")


func test_spring_brake_event_arms_the_hiss_burst() -> void:
	await _harness.settle(60)
	_director.hiss_elapsed = -1.0
	_harness.controller.air.pressure_psi = 30.0
	await get_tree().physics_frame
	_director._sync_air_events()
	assert_true(_director.hiss_elapsed >= 0.0, "spring brake engagement starts a burst")
	assert_true(_director.hiss_active, "hiss armed")


func test_audio_releases_are_ignored_while_pressure_is_healthy() -> void:
	await _harness.settle(60)
	_director.hiss_elapsed = -1.0
	_director.hiss_active = false
	_director._sync_air_events()
	assert_false(_director.hiss_active, "no hiss without an air event")
