extends GutTest
## Task 24 part 2: audio behaviour. Amplitude scaling, the squeal gate, the
## hiss burst envelope, the jackknife beep gate and the sample bounds that keep
## AudioStreamGenerator from clipping or stalling.

const AudioSynth := preload("res://scripts/audio/audio_synth.gd")

const TICK_HZ: float = float(PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ)

# ---------------------------------------------------------------------------
# Engine tone
# ---------------------------------------------------------------------------


func test_engine_amplitude_scales_with_load_and_rpm() -> void:
	var idle: float = AudioSynth.engine_amplitude(700.0, 0.0)
	var loaded: float = AudioSynth.engine_amplitude(1500.0, 1.0)
	assert_gt(loaded, idle, "load and rpm raise amplitude")
	assert_true(idle >= 0.0 and idle <= 1.0, "idle amplitude in 0..1")
	assert_true(loaded >= 0.0 and loaded <= 1.0, "loaded amplitude in 0..1")
	assert_eq(AudioSynth.engine_amplitude(0.0, 0.0), 0.0, "no rpm means silence")


func test_saw_wave_is_the_pinned_shape() -> void:
	## A saw ramps from -1 at the start of the period to +1 at the end, then
	## wraps. Phase is a normalized position in 0..1.
	assert_almost_eq(AudioSynth.saw(0.0), -1.0, 1e-9, "start of period")
	assert_almost_eq(AudioSynth.saw(0.5), 0.0, 1e-9, "mid period")
	assert_almost_eq(AudioSynth.saw(0.75), 0.5, 1e-9, "linear ramp")
	assert_almost_eq(AudioSynth.saw(1.25), AudioSynth.saw(0.25), 1e-9, "wraps past 1")
	assert_almost_eq(AudioSynth.saw(-0.25), AudioSynth.saw(0.75), 1e-9, "wraps below 0")


func test_lowpass_attenuates_above_its_corner() -> void:
	## One-pole lowpass: the DC step passes, a 6 kHz tone is attenuated.
	var passed: float = AudioSynth.lowpass_gain(0.0, PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ)
	var stopped: float = AudioSynth.lowpass_gain(6000.0, PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ)
	assert_almost_eq(passed, 1.0, 1e-9, "DC passes")
	assert_lt(stopped, 0.2, "6 kHz is attenuated by the 900 Hz lowpass")
	assert_lt(
		AudioSynth.lowpass_gain(
			PHYSICS_CONSTANTS.SQUEAL_BANDPASS_HZ, PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ
		),
		0.5,
		"the squeal band sits outside the engine lowpass"
	)
	assert_almost_eq(
		AudioSynth.lowpass_gain(
			PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ, PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ
		),
		1.0 / sqrt(2.0),
		0.02,
		"-3 dB at the corner"
	)
