extends Node
class_name DreamEncountercontroller

signal encounter_started(encounter: Dictionary)
signal encounter_completed(result: Dictionary)

var spawn_timer: float = 0.0
var min_spawn_time: float = 10.0
var max_spawn_time: float = 30.0
var next_spawn: float = 15.0

var current_encounter: Dictionary = {}

func update(delta: float, depth: int, instability: float) -> void:
	if current_encounter.size() > 0:
		return
	
	spawn_timer += delta
	
	var spawn_mult: float = 1.0 - (depth * 0.02)
	spawn_mult *= 1.0 + (instability / 200.0)
	
	if spawn_timer >= next_spawn * spawn_mult:
		_spawn_encounter(depth)
		spawn_timer = 0.0
		next_spawn = randf_range(min_spawn_time, max_spawn_time)

func _spawn_encounter(depth: int) -> void:
	var type: String = "combat" if randf() < 0.8 else "puzzle"
	
	if type == "combat":
		current_encounter = _generate_combat(depth)
	else:
		current_encounter = _generate_puzzle(depth)
	
	encounter_started.emit(current_encounter)

func _generate_combat(depth: int) -> Dictionary:
	var enemy_types: Array[String] = ["shadow", "manifestation", "echo", "wraith", "behemoth"]
	var type: String = enemy_types[min(int(float(depth) / 3.0), enemy_types.size() - 1)]
	
	var gm: Node = get_node("/root/Main/GameManager")
	var gs: float = gm.current_gear_score
	var recommended_gs: float = _get_recommended_gs(depth)
	
	var under_geared: bool = gs < recommended_gs
	var stat_mult: float = 1.5 if under_geared else 1.0
	
	return {
		"type": "combat",
		"depth": depth,
		"enemy": {
			"name": _generate_enemy_name(type, depth),
			"hp": 100.0 * pow(1.5, depth - 3) * stat_mult,
			"attack": 10.0 * pow(1.3, depth - 3) * stat_mult,
			"defense": 5.0 * pow(1.2, depth - 3),
			"type": type,
			"intents": _generate_intent_pattern(depth)
		},
		"under_geared_penalty": under_geared
	}

func _get_recommended_gs(depth: int) -> float:
	match depth:
		3: return 5000.0
		5: return 25000.0
		7: return 100000.0
		10: return 350000.0
		12: return 600000.0
		15: return 1200000.0
	return 1000000.0

func complete_current(result: Dictionary) -> void:
	encounter_completed.emit(result)
	current_encounter = {}

# MISSING HELPERS
func _generate_puzzle(depth: int) -> Dictionary:
	# TODO: Implement puzzle encounters
	return {"type": "puzzle", "depth": depth}

func _generate_enemy_name(type: String, depth: int) -> String:
	var prefixes: Array[String] = ["Twisted", "Eternal", "Shattered", "Ancient", "Dread"]
	var suffix: String = " of Depth %d" % depth
	return prefixes[randi() % prefixes.size()] + " " + type.capitalize() + suffix

func _generate_intent_pattern(_depth: int) -> Array:
	# TODO: Generate enemy attack patterns
	return ["strike", "crush"]
