extends Node
class_name PerkSystem

# Permanent perk levels (saved)
var perk1_level: int = 0
var perk2_level: int = 0
var perk3_level: int = 0

# Caps
@export var perk1_max: int = 25
@export var perk2_max: int = 25
@export var perk3_max: int = 25

# Cost curve
@export var perk1_base_cost: int = 10
@export var perk2_base_cost: int = 25
@export var perk3_base_cost: int = 50
@export var cost_growth: float = 1.6

# Effects
# perk1: Thoughts multiplier +10% per level
# perk2: Instability multiplier 0.95 per level (reduces instability gain)
# perk3: Control multiplier +10% per level
@export var perk1_step: float = 0.10
@export var perk2_step: float = 0.05
@export var perk3_step: float = 0.10


func get_thoughts_mult() -> float:
	return 1.0 + float(perk1_level) * perk1_step

func get_instability_mult() -> float:
	# lower is better; at level 1 => 0.95, level 2 => 0.9025 ...
	return pow(1.0 - perk2_step, float(perk2_level))

func get_control_mult() -> float:
	return 1.0 + float(perk3_level) * perk3_step


func get_perk_level(perk_id: int) -> int:
	match perk_id:
		1: return perk1_level
		2: return perk2_level
		3: return perk3_level
	return 0

func get_perk_max(perk_id: int) -> int:
	match perk_id:
		1: return perk1_max
		2: return perk2_max
		3: return perk3_max
	return 0

func is_maxed(perk_id: int) -> bool:
	return get_perk_level(perk_id) >= get_perk_max(perk_id)

func get_cost(perk_id: int) -> int:
	var lvl := get_perk_level(perk_id)
	var base := _base_cost(perk_id)
	var costf := float(base) * pow(cost_growth, float(lvl))
	return max(1, int(round(costf)))

func _base_cost(perk_id: int) -> int:
	match perk_id:
		1: return perk1_base_cost
		2: return perk2_base_cost
		3: return perk3_base_cost
	return 999999


func try_buy(perk_id: int, memories: float) -> Dictionary:
	var result := {
		"bought": false,
		"cost": 0,
		"perk_id": perk_id
	}

	if is_maxed(perk_id):
		return result

	var cost := get_cost(perk_id)
	result.cost = cost

	if memories < float(cost):
		return result

	# Apply
	match perk_id:
		1: perk1_level += 1
		2: perk2_level += 1
		3: perk3_level += 1
		_: return result

	result.bought = true
	return result


func get_perk_name(perk_id: int) -> String:
	match perk_id:
		1: return "Deep Focus"
		2: return "Steady Hands"
		3: return "Iron Will"
	return "Unknown"

func get_perk_desc(perk_id: int) -> String:
	match perk_id:
		1: return "+10% Thoughts per level"
		2: return "-5% Instability gain per level"
		3: return "+10% Control per level"
	return ""
