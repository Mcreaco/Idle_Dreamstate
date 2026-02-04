extends Node

@export var max_offline_seconds: float = 3600.0 # cap at 1 hour

var gm: Node = null

func _ready() -> void:
	gm = get_parent()
	apply_offline_progress()

func apply_offline_progress() -> void:
	var data: Dictionary = SaveSystem.load_game()

	if not data.has("last_play_time"):
		data["last_play_time"] = Time.get_unix_time_from_system()
		SaveSystem.save_game(data)
		return

	var last_time: float = float(data["last_play_time"])
	var now: float = Time.get_unix_time_from_system()

	var offline_time: float = clamp(now - last_time, 0.0, max_offline_seconds)

	if offline_time <= 1.0:
		return

	# ----- APPLY IDLE GAINS -----
	var thoughts_gain := gm.idle_thoughts_rate * offline_time
	var control_gain := gm.idle_control_rate * offline_time
	var instability_gain := gm.idle_instability_rate * offline_time

	gm.thoughts += thoughts_gain
	gm.control += control_gain
	gm.instability += instability_gain

	print("Offline progress applied:", offline_time, "seconds")

func save_time() -> void:
	var data: Dictionary = SaveSystem.load_game()
	data["last_play_time"] = Time.get_unix_time_from_system()
	SaveSystem.save_game(data)
