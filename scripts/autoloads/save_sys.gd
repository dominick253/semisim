extends Node
## SAVE_SYS autoload: persists best challenge times and settings to
## user://cityhaul.cfg (section 9).

const SAVE_PATH: String = "user://cityhaul.cfg"

var best_times: Dictionary = {}


func _ready() -> void:
	load_save()


func load_save() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(SAVE_PATH)
	if err != OK:
		return
	best_times = cfg.get_value("challenges", "best_times", {})


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("challenges", "best_times", best_times)
	cfg.save(SAVE_PATH)


func record_best_time(challenge_id: String, time_s: float) -> bool:
	var current: float = best_times.get(challenge_id, 1.0e9)
	if time_s < current:
		best_times[challenge_id] = time_s
		save()
		return true
	return false
