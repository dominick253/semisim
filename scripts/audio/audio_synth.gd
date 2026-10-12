class_name AudioSynth
extends RefCounted
## Procedural audio synthesis math (section 13). Static and pure: every pinned
## number is reachable from a test, and headless CI has no output device, so the
## audio subsystem has to be provable from its math alone.
##
## No RNG (section 15). Noise comes from a fixed integer hash so a given frame
## always produces the same samples.

const NOISE_SEED_INTAKE: int = 12345
const NOISE_SEED_SQUEAL: int = 67890
const NOISE_SEED_HISS: int = 24680

const HISS_NOISE_FLOOR_HZ: float = 1200.0
const ENGINE_DETUNE: float = 1.06
const INTAKE_LEVEL: float = 0.35


static func engine_frequency_hz(rpm: float) -> float:
	## Section 13: 2 saw oscillators at 0.5 * rpm / 60 Hz.
	return PHYSICS_CONSTANTS.ENGINE_FREQ_RPM_FACTOR * rpm / 60.0


static func engine_amplitude(rpm: float, load: float) -> float:
	## Amplitude scaled by load and rpm, bounded 0..1.
	if rpm <= 0.0:
		return 0.0
	var rpm_frac: float = clampf(rpm / PHYSICS_CONSTANTS.ENGINE_REDLINE_RPM, 0.0, 1.0)
	var load_frac: float = clampf(load, 0.0, 1.0)
	var base: float = 0.15 + 0.55 * rpm_frac
	var load_term: float = 0.35 * load_frac * rpm_frac
	return clampf(base + load_term, 0.0, 1.0)


static func saw(phase: float) -> float:
	## Ramp from -1 at the start of the period to +1 at the end, wrapping.
	var p: float = fmod(phase, 1.0)
	if p < 0.0:
		p += 1.0
	return -1.0 + 2.0 * p


static func square(phase: float) -> float:
	## +/-1 square wave for the jackknife beep.
	var p: float = fmod(phase, 1.0)
	if p < 0.0:
		p += 1.0
	return 1.0 if p < 0.5 else -1.0


static func lowpass_gain(freq_hz: float, corner_hz: float) -> float:
	## Two-pole magnitude: 1 / sqrt(1 + (f/fc)^4). -3 dB exactly at the corner.
	if corner_hz <= 0.0:
		return 0.0
	var ratio: float = freq_hz / corner_hz
	return 1.0 / sqrt(1.0 + pow(ratio, 4.0))


static func highpass_gain(freq_hz: float, corner_hz: float) -> float:
	## Two-pole magnitude: 1 / sqrt(1 + (fc/f)^4). DC is fully removed.
	if freq_hz <= 0.0:
		return 0.0
	if corner_hz <= 0.0:
		return 1.0
	var ratio: float = corner_hz / freq_hz
	return 1.0 / sqrt(1.0 + pow(ratio, 4.0))


static func bandpass_gain(freq_hz: float, center_hz: float) -> float:
	## Band shaping as a lowpass and a highpass around the center.
	return lowpass_gain(freq_hz, center_hz * 2.0) * highpass_gain(freq_hz, center_hz * 0.5)


static func squeal_gate(lateral_slip_ratio: float) -> bool:
	## Section 13: squeal when any wheel lateral slip ratio exceeds 0.12.
	return absf(lateral_slip_ratio) >= PHYSICS_CONSTANTS.SQUEAL_SLIP_THRESHOLD


static func squeal_amplitude(lateral_slip_ratio: float, slip_energy: float) -> float:
	## Section 13: amplitude min(1, 8 * max_slip_energy), gated by the slip ratio.
	if not squeal_gate(lateral_slip_ratio):
		return 0.0
	return clampf(PHYSICS_CONSTANTS.SQUEAL_AMPLITUDE_GAIN * absf(slip_energy), 0.0, 1.0)


static func hiss_envelope(elapsed_s: float) -> float:
	## Section 13: 0.8 s burst. Linear decay from 1 to 0 across the burst, and
	## exactly 0 outside it so a burst cannot leak past its window.
	if elapsed_s < 0.0 or elapsed_s > PHYSICS_CONSTANTS.HISS_DURATION_S:
		return 0.0
	return 1.0 - elapsed_s / PHYSICS_CONSTANTS.HISS_DURATION_S


static func jackknife_beep_gate(articulation_deg: float) -> bool:
	## Section 13: beep when articulation exceeds +/- 45 deg.
	return absf(articulation_deg) >= PHYSICS_CONSTANTS.JACKKNIFE_BEEP_ARTICULATION_DEG


static func beep_gate_at(time_s: float, rate_hz: float) -> float:
	## 1 Hz blink: on for the first half of each period, off for the second.
	if rate_hz <= 0.0:
		return 0.0
	var period: float = 1.0 / rate_hz
	var phase: float = fmod(time_s, period)
	if phase < 0.0:
		phase += period
	return 1.0 if phase < period * 0.5 else 0.0


static func hash_noise(index: int, seed: int) -> float:
	## Deterministic noise in -1..1. Section 15 forbids RNG in reproducible
	## paths, so this is an integer hash of the sample index and a fixed seed.
	var h: int = (index + 1) * 374761393
	h = (h ^ seed) * 668265263
	h = h ^ (h >> 13)
	h = h & 0x7FFFFFFF
	return (float(h) / float(0x7FFFFFFF)) * 2.0 - 1.0


static func mix_window(frame: Dictionary, start_index: int, count: int) -> PackedFloat32Array:
	## Convenience wrapper used by the evidence pass: one window of samples.
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i in count:
		out[i] = mix_sample(frame, start_index + i)
	return out


static func mix_sample(frame: Dictionary, sample_index: int) -> float:
	## Mixes every section 13 source for one sample and clamps the result to
	## -1..1, which is what AudioStreamGenerator requires.
	##
	## frame keys: rpm, load, throttle, lateral_slip, slip_energy,
	## hiss_elapsed, articulation_deg, jackknife.
	var rate: float = float(PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ)
	var t: float = float(sample_index) / rate
	var out: float = 0.0

	var rpm: float = float(frame.get("rpm", 0.0))
	var load: float = float(frame.get("load", 0.0))
	var engine_amp: float = engine_amplitude(rpm, load)
	if engine_amp > 0.0:
		var freq: float = engine_frequency_hz(rpm)
		## Two saw oscillators, detuned a semitone apart for body, shaped by the
		## 900 Hz lowpass.
		var phase_a: float = freq * t
		var phase_b: float = freq * ENGINE_DETUNE * t
		var tone: float = (saw(phase_a) + saw(phase_b)) * 0.5
		out += tone * engine_amp * lowpass_gain(freq, PHYSICS_CONSTANTS.ENGINE_LOWPASS_HZ)
		## White-noise intake bandpassed at 300 Hz, amplitude scaled by load and
		## rpm.
		var intake: float = hash_noise(sample_index, NOISE_SEED_INTAKE)
		var intake_amp: float = engine_amp * INTAKE_LEVEL * float(frame.get("throttle", 0.0))
		out += (
			intake
			* intake_amp
			* bandpass_gain(
				PHYSICS_CONSTANTS.INTAKE_BANDPASS_HZ, PHYSICS_CONSTANTS.INTAKE_BANDPASS_HZ
			)
		)

	var slip: float = float(frame.get("lateral_slip", 0.0))
	var squeal_amp: float = squeal_amplitude(slip, float(frame.get("slip_energy", 0.0)))
	if squeal_amp > 0.0:
		out += (
			hash_noise(sample_index, NOISE_SEED_SQUEAL)
			* squeal_amp
			* bandpass_gain(
				PHYSICS_CONSTANTS.SQUEAL_BANDPASS_HZ, PHYSICS_CONSTANTS.SQUEAL_BANDPASS_HZ
			)
		)

	var hiss: float = hiss_envelope(float(frame.get("hiss_elapsed", -1.0)))
	if hiss > 0.0:
		## Highpassed noise burst: the low end is removed so it reads as a hiss.
		out += (
			hash_noise(sample_index, NOISE_SEED_HISS)
			* hiss
			* highpass_gain(HISS_NOISE_FLOOR_HZ, PHYSICS_CONSTANTS.INTAKE_BANDPASS_HZ)
		)

	if (
		bool(frame.get("jackknife", false))
		or jackknife_beep_gate(float(frame.get("articulation_deg", 0.0)))
	):
		var blink: float = beep_gate_at(t, PHYSICS_CONSTANTS.JACKKNIFE_BEEP_RATE_HZ)
		if blink > 0.0:
			out += (
				square(PHYSICS_CONSTANTS.JACKKNIFE_BEEP_HZ * t)
				* blink
				* PHYSICS_CONSTANTS.AUDIO_MASTER_GAIN
			)

	return clampf(out * PHYSICS_CONSTANTS.AUDIO_MASTER_GAIN, -1.0, 1.0)
