extends Node
class_name AbyssPerkSystem

# Abyss perks are META (bought with Memories), and persist across runs.

var echoed_descent_level: int = 0
@export var echoed_descent_max: int = 10
@export var echoed_descent_base_cost: float = 25.0
@export var echoed_descent_cost_growth: float = 1.85
@export var start_depth_per_level: int = 1

var abyssal_focus_level: int = 0
@export var abyssal_focus_max: int = 10
@export var abyssal_focus_base_cost: float = 30.0
@export var abyssal_focus_cost_growth: float = 1.85
@export var control_mult_step: float = 0.10

var dark_insight_level: int = 0
@export var dark_insight_max: int = 10
@export var dark_insight_base_cost: float = 35.0
@export var dark_insight_cost_growth: float = 1.85
@export var thoughts_mult_step: float = 0.10

var abyss_veil_level: int = 0
@export var abyss_veil_max: int = 10
@export var abyss_veil_base_cost: float = 40.0
@export var abyss_veil_cost_growth: float = 1.90
@export var abyss_veil_step: float = 0.05
@export var abyss_veil_starts_at_depth: int = 5

func get_start_depth_bonus() -> int:
	return echoed_descent_level * start_depth_per_level

func get_control_mult() -> float:
	return 1.0 + float(abyssal_focus_level) * control_mult_step

func get_thoughts_mult() -> float:
	return 1.0 + float(dark_insight_level) * thoughts_mult_step

func get_instability_reduction_mult(depth: int) -> float:
	if abyss_veil_level <= 0:
		return 1.0
	if depth < abyss_veil_starts_at_depth:
		return 1.0
	var reduction: float = float(abyss_veil_level) * abyss_veil_step
	return maxf(0.10, 1.0 - reduction)

func get_echoed_descent_cost() -> float:
	return echoed_descent_base_cost * pow(echoed_descent_cost_growth, float(echoed_descent_level))

func get_abyssal_focus_cost() -> float:
	return abyssal_focus_base_cost * pow(abyssal_focus_cost_growth, float(abyssal_focus_level))

func get_dark_insight_cost() -> float:
	return dark_insight_base_cost * pow(dark_insight_cost_growth, float(dark_insight_level))

func get_abyss_veil_cost() -> float:
	return abyss_veil_base_cost * pow(abyss_veil_cost_growth, float(abyss_veil_level))

func try_buy_echoed_descent(memories: float) -> Dictionary:
	if echoed_descent_level >= echoed_descent_max:
		return {"bought": false, "cost": get_echoed_descent_cost(), "reason": "max"}
	var cost: float = get_echoed_descent_cost()
	if memories < cost:
		return {"bought": false, "cost": cost, "reason": "funds"}
	echoed_descent_level += 1
	return {"bought": true, "cost": cost, "reason": ""}

func try_buy_abyssal_focus(memories: float) -> Dictionary:
	if abyssal_focus_level >= abyssal_focus_max:
		return {"bought": false, "cost": get_abyssal_focus_cost(), "reason": "max"}
	var cost: float = get_abyssal_focus_cost()
	if memories < cost:
		return {"bought": false, "cost": cost, "reason": "funds"}
	abyssal_focus_level += 1
	return {"bought": true, "cost": cost, "reason": ""}

func try_buy_dark_insight(memories: float) -> Dictionary:
	if dark_insight_level >= dark_insight_max:
		return {"bought": false, "cost": get_dark_insight_cost(), "reason": "max"}
	var cost: float = get_dark_insight_cost()
	if memories < cost:
		return {"bought": false, "cost": cost, "reason": "funds"}
	dark_insight_level += 1
	return {"bought": true, "cost": cost, "reason": ""}

func try_buy_abyss_veil(memories: float) -> Dictionary:
	if abyss_veil_level >= abyss_veil_max:
		return {"bought": false, "cost": get_abyss_veil_cost(), "reason": "max"}
	var cost: float = get_abyss_veil_cost()
	if memories < cost:
		return {"bought": false, "cost": cost, "reason": "funds"}
	abyss_veil_level += 1
	return {"bought": true, "cost": cost, "reason": ""}
