extends GutTest
## Task 24 part 4: jackknife beep, sample bounds, determinism, and the
## AudioStreamGenerator wiring that does not need an output device.

const AudioSynth := preload("res://scripts/audio/audio_synth.gd")
const AudioDirector := preload("res://scripts/audio/audio_director.gd")

# ---------------------------------------------------------------------------
# Jackknife warning beep
# ---------------------------------------------------------------------------


func test_beep_is_a_square_at_880_hz_gated_at_45_deg() -> void:
	assert_true(AudioSynth.square(0.0) > 0.0, "square is high at phase 0")
	assert_true(AudioSynth.square(0.5) < 0.0, "square is low at half phase")
	assert_almost_eq(absf(AudioSynth.square(0.25)), 1.0, 1e-9, "square is +/-1")
	assert_true(AudioSynth.jackknife_beep_gate(45.0), "gate opens at exactly 45 deg")
	assert_true(AudioSynth.jackknife_beep_gate(-45.0), "gate opens at -45 deg")
	assert_false(AudioSynth.jackknife_beep_gate(44.999), "gate closed just under")
	assert_true(AudioSynth.jackknife_beep_gate(70.0), "gate open past the limit")


func test_beep_blinks_once_per_second() -> void:
	## 1 Hz gate: on for the first half of each second, off for the second half.
	assert_almost_eq(AudioSynth.beep_gate_at(0.25, 1.0), 1.0, 1e-9, "on at 0.25 s")
	assert_almost_eq(AudioSynth.beep_gate_at(0.75, 1.0), 0.0, 1e-9, "off at 0.75 s")
	assert_almost_eq(AudioSynth.beep_gate_at(1.25, 1.0), 1.0, 1e-9, "on again at 1.25 s")


# ---------------------------------------------------------------------------
# Noise and sample bounds
# ---------------------------------------------------------------------------


func test_deterministic_noise_is_in_range_and_repeatable() -> void:
	## Section 15 forbids RNG in reproducible paths, so the intake and squeal
	## noise come from a fixed phase hash rather than randf.
	var first: Array[float] = []
	var second: Array[float] = []
	for i in 64:
		first.append(AudioSynth.hash_noise(i, 12345))
		second.append(AudioSynth.hash_noise(i, 12345))
	for i in 64:
		assert_true(first[i] >= -1.0 and first[i] <= 1.0, "noise in -1..1")
		assert_eq(first[i], second[i], "same seed gives the same noise")
	var varied: float = AudioSynth.hash_noise(7, 99999)
	assert_true(varied != AudioSynth.hash_noise(7, 12345), "different seed differs")


func test_mixed_sample_stays_inside_minus_one_to_one() -> void:
	## AudioStreamGenerator clips and distorts outside -1..1, so the mix must be
	## clamped no matter how loud the sources are.
	var frame: Dictionary = {
		"rpm": 1800.0,
		"load": 1.0,
		"throttle": 1.0,
		"lateral_slip": 1.0,
		"slip_energy": 9.0,
		"hiss_elapsed": 0.0,
		"articulation_deg": 70.0,
		"jackknife": true,
	}
	for i in 512:
		var sample: float = AudioSynth.mix_sample(frame, i)
		assert_true(sample >= -1.0 and sample <= 1.0, "sample bounded at frame %d" % i)


func test_silence_when_every_source_is_off() -> void:
	var frame: Dictionary = {
		"rpm": 0.0,
		"load": 0.0,
		"throttle": 0.0,
		"lateral_slip": 0.0,
		"slip_energy": 0.0,
		"hiss_elapsed": -1.0,
		"articulation_deg": 0.0,
		"jackknife": false,
	}
	var total: float = 0.0
	for i in 256:
		total += absf(AudioSynth.mix_sample(frame, i))
	assert_almost_eq(total, 0.0, 1e-9, "no source means no signal")
