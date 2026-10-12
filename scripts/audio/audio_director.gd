class_name AudioDirector
extends Node
## Procedural audio driver (section 13). One AudioStreamGenerator at 48 kHz fed
## by AudioSynth, plus the air-brake event tracking that arms the 0.8 s hiss
## burst. No audio files and no RNG: the whole signal is synthesized per tick,
## which keeps headless runs reproducible.

var generator: AudioStreamGenerator
var synth := preload("res://scripts/audio/audio_synth.gd")
var player: AudioStreamPlayer

var hiss_elapsed: float = -1.0
var hiss_active: bool = false
var sample_index: int = 0
var audio_enabled: bool = true

var _playback: AudioStreamGeneratorPlayback = null
var _controller: Node3D = null
var _spring_was_engaged: bool = false
var _service_was_applied: bool = false


func bind(controller: Node3D) -> void:
	_controller = controller


func _ready() -> void:
	generator = AudioStreamGenerator.new()
	## mix_rate is only honored when the mode is CUSTOM; the default follows the
	## engine mix target (44100 here), which would break the pinned 48 kHz.
	generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	generator.mix_rate = PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ
	## Godot 4 names this buffer_length, not buffer_duration.
	generator.buffer_length = PHYSICS_CONSTANTS.AUDIO_BUFFER_SECONDS
	player = AudioStreamPlayer.new()
	player.stream = generator
	## Master gain is applied inside the mix, so the player must not attenuate a
	## second time.
	player.volume_db = 0.0
	## AudioStreamGenerator is a Resource, not a Node: it is held by the
	## player as its stream rather than added to the tree.
	add_child(player)
	if audio_enabled:
		player.play()
		_playback = player.get_stream_playback()
	if _controller != null:
		if _controller.air.spring_brake_engaged:
			_spring_was_engaged = true


func _exit_tree() -> void:
	## Release the playback handle and clear the generator buffer so the stream
	## does not outlive the scene (an AudioStreamGenerator left referenced shows
	## up as a leaked ObjectDB instance at exit).
	if player != null and player.playing:
		player.stop()
	## AudioStreamGeneratorPlayback has no clear(); dropping the handle is the
	## release, and the generator stream itself is a Resource held by the player.
	_playback = null


func _physics_process(dt: float) -> void:
	if _controller == null:
		return
	_sync_air_events()
	if hiss_active:
		hiss_elapsed += dt
		if hiss_elapsed > PHYSICS_CONSTANTS.HISS_DURATION_S:
			hiss_active = false
			hiss_elapsed = -1.0
	_emit_frames()


func current_frame() -> Dictionary:
	## The synthesis inputs read from the live combination. Keys match
	## AudioSynth.mix_sample.
	var artic_deg: float = _controller.articulation_deg()
	return {
		"rpm": float(_controller.engine_rpm),
		"load": float(_controller.throttle),
		"throttle": float(_controller.throttle),
		"lateral_slip": float(_controller.max_lateral_slip),
		"slip_energy": float(_controller.max_slip_energy),
		"hiss_elapsed": hiss_elapsed if hiss_active else -1.0,
		"articulation_deg": artic_deg,
		"jackknife": bool(_controller.jackknifed),
	}


func trigger_hiss() -> void:
	## Section 13: the hiss fires on release and spring-brake events.
	hiss_active = true
	hiss_elapsed = 0.0


func _sync_air_events() -> void:
	var engaged: bool = _controller.air.spring_brake_engaged
	var applied: bool = _controller.brake_pedal > 0.0
	if engaged and not _spring_was_engaged:
		trigger_hiss()
	if _spring_was_engaged and not engaged:
		## Spring brake release is the other hiss event in section 13.
		trigger_hiss()
	if applied and not _service_was_applied:
		trigger_hiss()
	_spring_was_engaged = engaged
	_service_was_applied = applied


func _emit_frames() -> void:
	## Feed the generator in fixed-size frames so the buffer never starves and
	## never overruns, which is what makes the tone stall-free at 120 Hz ticks.
	if not audio_enabled:
		return
	var frame: Dictionary = current_frame()
	var samples_per_tick: int = int(
		round(PHYSICS_CONSTANTS.AUDIO_SAMPLE_RATE_HZ / PHYSICS_CONSTANTS.PHYSICS_TICKS_PER_SECOND)
	)
	## AudioStreamGeneratorPlayback.push_buffer takes stereo frames: x is the
	## left channel and y the right. Phase is identical, so mono is x == y.
	var packed: PackedVector2Array = PackedVector2Array()
	packed.resize(samples_per_tick)
	for i in samples_per_tick:
		var sample: float = synth.mix_sample(frame, sample_index)
		packed[i] = Vector2(sample, sample)
		sample_index += 1
	## Push through the player playback handle: AudioStreamGenerator itself has no
	## push method.
	if _playback != null and _playback.get_frames_available() >= samples_per_tick:
		_playback.push_buffer(packed)
