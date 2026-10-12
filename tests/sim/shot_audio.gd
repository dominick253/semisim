extends Node3D
## Audio evidence pass (section 13). Drives the combination into a slide with a
## spring-brake event, then synthesizes the mix and measures the actual signal:
## peak, RMS, clipped sample count, zero-crossing rate and a determinism hash.
## Also writes a waveform PNG so the tone can be inspected, not only asserted.

const OUT_DIR: String = "res://docs/evidence/phase1"
const AUDIO_SYNTH := preload("res://scripts/audio/audio_synth.gd")
const WINDOW_SAMPLES: int = 48000  # 1 second at 48 kHz

var _director: Node
var _controller: Node3D


func _ready() -> void:
	var yard: Node3D = load("res://scenes/world/test_yard.tscn").instantiate()
	add_child(yard)
	_controller = load("res://scripts/vehicles/combination_controller.gd").new()
	_controller.name = "Combination"
	_controller.add_child(load("res://scenes/vehicles/tractor.tscn").instantiate())
	_controller.add_child(load("res://scenes/vehicles/trailer.tscn").instantiate())
	add_child(_controller)
	_controller.place_at_rest()
	_director = load("res://scripts/audio/audio_director.gd").new()
	_director.name = "AudioDirector"
	_director.bind(_controller)
	add_child(_director)
	await _run()


func _run() -> void:
	## Roll, then slide: hard steer at speed pushes lateral slip past 0.12 so the
	## squeal gate opens, and dropping the air below the spring-brake threshold
	## arms the 0.8 s hiss burst.
	_controller.transmission.automatic = true
	for i in 800:
		await get_tree().physics_frame
		_controller.throttle = 1.0
	var squeal_frame: Dictionary = _director.current_frame()
	var rolling_frame: Dictionary = squeal_frame
	var peak_slip: float = 0.0
	var peak_speed_kmh: float = 0.0
	var peak_speed_kmh_rolling: float = 0.0
	for i in 400:
		await get_tree().physics_frame
		_controller.throttle = 1.0
		_controller.steer_input_axis = 1.0
		if i > 200:
			_controller.brake_pedal = 1.0
		var speed_kmh: float = _controller.speed() * 3.6
		## Two frames are captured on purpose. The biggest lateral slip in this
		## maneuver lands in the low-speed transient where the squeal gate opens,
		## and the fastest frame is a rolling frame with no squeal. Reporting both
		## keeps the evidence honest about which source is audible in which window.
		if _controller.max_lateral_slip > peak_slip:
			peak_slip = _controller.max_lateral_slip
			peak_speed_kmh = speed_kmh
			squeal_frame = _director.current_frame()
		if speed_kmh > peak_speed_kmh_rolling:
			peak_speed_kmh_rolling = speed_kmh
			rolling_frame = _director.current_frame()
	print(
		(
			"AUDIO squeal_frame speed=%.2f rpm=%.1f lateral_slip=%.3f slip_energy=%.3f gate=%s"
			% [
				peak_speed_kmh,
				float(squeal_frame["rpm"]),
				float(squeal_frame["lateral_slip"]),
				float(squeal_frame["slip_energy"]),
				str(squeal_frame["lateral_slip"] >= PHYSICS_CONSTANTS.SQUEAL_SLIP_THRESHOLD),
			]
		)
	)
	print(
		(
			"AUDIO rolling_frame speed=%.2f rpm=%.1f lateral_slip=%.3f slip_energy=%.3f"
			% [
				peak_speed_kmh_rolling,
				float(rolling_frame["rpm"]),
				float(rolling_frame["lateral_slip"]),
				float(rolling_frame["slip_energy"]),
			]
		)
	)
	_controller.air.pressure_psi = 30.0
	await get_tree().physics_frame
	_director._sync_air_events()
	var frame: Dictionary = _director.current_frame()
	print(
		(
			"AUDIO air lateral_slip=%.3f slip_energy=%.3f hiss_elapsed=%.3f artic=%.1f"
			% [
				float(frame["lateral_slip"]),
				float(frame["slip_energy"]),
				float(frame["hiss_elapsed"]),
				float(frame["articulation_deg"]),
			]
		)
	)
	_report(AUDIO_SYNTH.mix_window(squeal_frame, 0, WINDOW_SAMPLES), "squeal_window")
	_report(AUDIO_SYNTH.mix_window(rolling_frame, 0, WINDOW_SAMPLES), "rolling_window")
	_report(AUDIO_SYNTH.mix_window(frame, 0, WINDOW_SAMPLES), "air_window")
	# Determinism: the same frame and window must hash identically.
	var hash_a: int = _hash_of(AUDIO_SYNTH.mix_window(squeal_frame, 0, WINDOW_SAMPLES))
	var hash_b: int = _hash_of(AUDIO_SYNTH.mix_window(squeal_frame, 0, WINDOW_SAMPLES))
	print(
		"AUDIO determinism hash_a=%d hash_b=%d equal=%s" % [hash_a, hash_b, str(hash_a == hash_b)]
	)
	var squeal_samples: PackedFloat32Array = AUDIO_SYNTH.mix_window(squeal_frame, 0, WINDOW_SAMPLES)
	_write_waveform(squeal_samples)
	# The same windows as 16 bit PCM so the evidence can be listened to, not only
	# measured. These are evidence artifacts, not game assets: the game itself
	# ships no audio files (section 13).
	_write_wav(squeal_samples, "audio_squeal_window.wav")
	_write_wav(AUDIO_SYNTH.mix_window(rolling_frame, 0, WINDOW_SAMPLES), "audio_rolling_window.wav")
	_write_wav(AUDIO_SYNTH.mix_window(frame, 0, WINDOW_SAMPLES), "audio_air_window.wav")
	print("AUDIO SHOTS DONE")
	get_tree().quit()


func _put_tag(bytes: PackedByteArray, offset: int, tag: String) -> int:
	for i in tag.length():
		bytes[offset + i] = tag.unicode_at(i)
	return offset + tag.length()


func _put_u32(bytes: PackedByteArray, offset: int, value: int) -> int:
	bytes.encode_u32(offset, value)
	return offset + 4


func _put_u16(bytes: PackedByteArray, offset: int, value: int) -> int:
	bytes.encode_u16(offset, value)
	return offset + 2


func _write_wav(samples: PackedFloat32Array, file_name: String) -> void:
	## Hand written RIFF header: 16 bit PCM, mono, the pinned mix rate.
	var rate: int = PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ
	var data_size: int = samples.size() * 2
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(44 + data_size)
	var o: int = 0
	o = _put_tag(bytes, o, "RIFF")
	o = _put_u32(bytes, o, 36 + data_size)
	o = _put_tag(bytes, o, "WAVE")
	o = _put_tag(bytes, o, "fmt ")
	o = _put_u32(bytes, o, 16)
	o = _put_u16(bytes, o, 1)
	o = _put_u16(bytes, o, 1)
	o = _put_u32(bytes, o, rate)
	o = _put_u32(bytes, o, rate * 2)
	o = _put_u16(bytes, o, 2)
	o = _put_u16(bytes, o, 16)
	o = _put_tag(bytes, o, "data")
	o = _put_u32(bytes, o, data_size)
	for sample in samples:
		bytes.encode_s16(o, int(clampf(sample, -1.0, 1.0) * 32767.0))
		o += 2
	var file: FileAccess = FileAccess.open(OUT_DIR + "/" + file_name, FileAccess.WRITE)
	if file == null:
		print("AUDIO wav ", file_name, " open_error=", FileAccess.get_open_error())
		return
	file.store_buffer(bytes)
	file.close()
	print("AUDIO wav ", file_name, " bytes=", bytes.size())


func _report(samples: PackedFloat32Array, label: String) -> int:
	var peak: float = 0.0
	var sum_sq: float = 0.0
	var clipped: int = 0
	var crossings: int = 0
	var last_sign: float = 0.0
	for s in samples:
		var a: float = absf(s)
		if a > peak:
			peak = a
		sum_sq += s * s
		if a >= 1.0:
			clipped += 1
		var sign: float = signf(s)
		if sign != 0.0 and last_sign != 0.0 and sign != last_sign:
			crossings += 1
		if sign != 0.0:
			last_sign = sign
	var rms: float = sqrt(sum_sq / float(samples.size()))
	## Zero-crossing rate is a crude but honest frequency proxy: a live mix lands
	## in the hundreds to thousands, a silent window is 0.
	print(
		(
			"AUDIO %s peak=%.4f rms=%.4f clipped=%d crossings=%d"
			% [label, peak, rms, clipped, crossings]
		)
	)
	return _hash_of(samples)


func _hash_of(samples: PackedFloat32Array) -> int:
	## FNV-1a over the quantized samples. The same frame must hash identically.
	var h: int = 0x811C9DC5
	for s in samples:
		var q: int = int(round(s * 100000.0))
		h = (h ^ q) * 0x01000193
		h = h & 0x7FFFFFFF
	return h


func _write_waveform(samples: PackedFloat32Array) -> void:
	## One column per sample bin drawn around the center line. This is the signal
	## itself, not a screenshot of the game.
	var width: int = 1200
	var height: int = 420
	var img := Image.create(width, height, false, Image.FORMAT_RGB8)
	img.fill(Color(0.07, 0.08, 0.10))
	var per_bin: int = maxi(1, samples.size() / width)
	for x in width:
		var peak: float = 0.0
		for k in per_bin:
			var idx: int = x * per_bin + k
			if idx < samples.size():
				peak = maxf(peak, absf(samples[idx]))
		var half: int = int(round(peak * float(height) * 0.48))
		for y in range(height / 2 - half, height / 2 + half + 1):
			if y >= 0 and y < height:
				img.set_pixel(x, y, Color(0.35, 0.85, 0.65))
	var dir := DirAccess.open("res://")
	dir.make_dir("docs/evidence")
	dir.make_dir(OUT_DIR.replace("res://", ""))
	print("AUDIO waveform err=", img.save_png(OUT_DIR + "/audio_waveform.png"))
