extends GutTest
## Task 24 part 1: the pinned audio synthesis math (section 13).
##
## The synthesis is static and pure so every pinned number can be asserted
## without an audio device. Headless CI has no output device, so the audio
## subsystem has to be provable from its math.

const AudioSynth := preload("res://scripts/audio/audio_synth.gd")

# ---------------------------------------------------------------------------
# Pinned numbers
# ---------------------------------------------------------------------------


func test_generator_is_48khz() -> void:
	assert_eq(PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ, 48000, "sample rate")


func test_engine_is_two_saw_oscillators_at_half_rpm_over_60() -> void:
	assert_eq(PHYSICS_CONSTANTS.ENGINE_OSC_COUNT, 2, "two oscillators")
	## 0.5 * rpm / 60 Hz. At 1800 rpm that is 15 Hz per oscillator.
	assert_almost_eq(AudioSynth.engine_frequency_hz(1800.0), 15.0, 1e-9, "1800 rpm")
	assert_almost_eq(AudioSynth.engine_frequency_hz(700.0), 350.0 / 60.0, 1e-9, "idle")
	assert_almost_eq(AudioSynth.engine_frequency_hz(0.0), 0.0, 1e-9, "stopped")


func test_filter_corners_are_pinned() -> void:
	assert_eq(PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ, 900.0, "engine lowpass")
	assert_eq(PHYSICS_CONSTANTS.INTAKE_BANDPASS_HZ, 300.0, "intake band")
	assert_eq(PHYSICS_CONSTANTS.SQUEAL_BANDPASS_HZ, 2500.0, "squeal band")


func test_squeal_threshold_and_gain_are_pinned() -> void:
	assert_eq(PHYSICS_CONSTANTS.SQUEAL_SLIP_THRESHOLD, 0.12, "lateral slip threshold")
	assert_eq(PHYSICS_CONSTANTS.SQUEAL_AMPLITUDE_GAIN, 8.0, "amplitude gain")


func test_hiss_is_a_0p8s_burst() -> void:
	assert_eq(PHYSICS_CONSTANTS.HISS_DURATION_S, 0.8, "hiss duration")


func test_jackknife_beep_is_880hz_square_at_1hz() -> void:
	assert_eq(PHYSICS_CONSTANTS.JACKKNIFE_BEEP_HZ, 880.0, "beep tone")
	assert_eq(PHYSICS_CONSTANTS.JACKKNIFE_BEEP_RATE_HZ, 1.0, "beep rate")
	assert_eq(PHYSICS_CONSTANTS.JACKKNIFE_BEEP_ARTICULATION_DEG, 45.0, "beep gate")
