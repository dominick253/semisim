extends GutTest
## Task 24 part 3: squeal gate, hiss envelope, jackknife beep gate, and the
## sample bounds that keep AudioStreamGenerator from clipping.

const AudioSynth := preload("res://scripts/audio/audio_synth.gd")

# ---------------------------------------------------------------------------
# Tire squeal
# ---------------------------------------------------------------------------


func test_squeal_is_silent_below_the_slip_threshold() -> void:
	assert_eq(AudioSynth.squeal_amplitude(0.119, 0.0), 0.0, "below 0.12 is silent")
	assert_eq(AudioSynth.squeal_amplitude(0.0, 40.0), 0.0, "no slip is silent")


func test_squeal_amplitude_is_min_1_8_times_slip_energy() -> void:
	## Section 13: amplitude min(1, 8 * max_slip_energy) once any wheel lateral
	## slip ratio exceeds 0.12.
	assert_almost_eq(AudioSynth.squeal_amplitude(0.15, 0.10), 0.8, 1e-9, "8 * 0.1")
	assert_almost_eq(AudioSynth.squeal_amplitude(0.2, 0.05), 0.4, 1e-9, "8 * 0.05")
	assert_almost_eq(AudioSynth.squeal_amplitude(0.9, 5.0), 1.0, 1e-9, "clamped at 1")


func test_squeal_gate_uses_the_pinned_threshold() -> void:
	assert_false(AudioSynth.squeal_gate(0.1199), "just under threshold")
	assert_true(AudioSynth.squeal_gate(0.12), "exactly at threshold engages")


# ---------------------------------------------------------------------------
# Air brake hiss
# ---------------------------------------------------------------------------


func test_hiss_envelope_spans_the_pinned_0p8_seconds() -> void:
	assert_almost_eq(AudioSynth.hiss_envelope(0.0), 1.0, 1e-9, "starts full")
	assert_almost_eq(AudioSynth.hiss_envelope(0.4), 0.5, 1e-9, "mid burst")
	assert_almost_eq(AudioSynth.hiss_envelope(0.8), 0.0, 1e-9, "ends at 0.8 s")
	assert_eq(AudioSynth.hiss_envelope(0.81), 0.0, "silent after the burst")
	assert_eq(AudioSynth.hiss_envelope(-0.01), 0.0, "silent before the burst")


func test_hiss_is_highpassed_not_lowpassed() -> void:
	## Section 13 says highpassed noise burst: low frequencies are removed.
	var low: float = AudioSynth.highpass_gain(100.0, PHYSICS_CONSTANTS.INTAKE_BANDPASS_HZ)
	var high: float = AudioSynth.highpass_gain(6000.0, PHYSICS_CONSTANTS.INTAKE_BANDPASS_HZ)
	assert_lt(low, 0.2, "100 Hz is removed by the highpass")
	assert_almost_eq(high, 1.0, 0.05, "6 kHz passes")
