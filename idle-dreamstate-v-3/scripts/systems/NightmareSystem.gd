class_name NightmareSystem
extends Node

var unlocked: bool = false

# TUNING
var unlock_max_instability_threshold: float = 95.0

var thoughts_mult: float = 1.5
var instability_mult: float = 1.25
var control_mult: float = 0.9  # slight nerf for tension

func check_unlock(max_instability: float) -> void:
	if (not unlocked) and (max_instability >= unlock_max_instability_threshold):
		unlocked = true
		print("NIGHTMARE UNLOCKED")

func get_thoughts_mult() -> float:
	return thoughts_mult if unlocked else 1.0

func get_instability_mult() -> float:
	return instability_mult if unlocked else 1.0

func get_control_mult() -> float:
	return control_mult if unlocked else 1.0
