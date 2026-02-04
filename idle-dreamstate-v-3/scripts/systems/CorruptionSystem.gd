class_name CorruptionSystem
extends Node

var active: bool = false

# tuning
var start_threshold: float = 90.0

var thoughts_bonus_mult: float = 2.0
var instability_penalty_mult: float = 1.5

var event_chance_per_second: float = 0.5

func update(delta: float, instability: float) -> Dictionary:
	active = instability >= start_threshold

	var effects := {
		"thoughts_mult": 1.0,
		"instability_mult": 1.0,
		"extra_instability": 0.0
	}

	if not active:
		return effects

	# corruption bonuses/penalties
	effects.thoughts_mult = thoughts_bonus_mult
	effects.instability_mult = instability_penalty_mult

	# random corruption events
	if randf() < event_chance_per_second * delta:
		var roll := randi() % 3
		match roll:
			0:
				# sudden instability spike
				effects.extra_instability = 5.0
				print("CORRUPTION: instability surge")
			1:
				# temporary thought boost (handled via multiplier)
				effects.thoughts_mult *= 1.5
				print("CORRUPTION: power rush")
			2:
				# control drain (handled in GameManager)
				effects["drain_control"] = 5.0
				print("CORRUPTION: control leak")

	return effects
