extends Node
class_name UpgradeManager

# =========================
# RUN UPGRADES (reset on Wake/Fail)
# =========================

# Existing run upgrades
var thoughts_level: int = 0
var stability_level: int = 0

# Depth-based run upgrades
var deep_dives_level: int = 0
var mental_buffer_level: int = 0

# NEW: Overclock-based run upgrades
var overclock_mastery_level: int = 0
var overclock_safety_level: int = 0

# Tuning
@export var run_cost_growth: float = 1.6

@export var thoughts_base_cost: float = 10.0
@export var stability_base_cost: float = 12.0
@export var deep_dives_base_cost: float = 25.0
@export var mental_buffer_base_cost: float = 30.0

@export var overclock_mastery_base_cost: float = 40.0
@export var overclock_safety_base_cost: float = 45.0

# Effects
# Thoughts upgrade: +15% thoughts mult per level
@export var thoughts_step: float = 0.15

# Stability upgrade: -7% instability gain per level (multiplicative)
@export var stability_step: float = 0.07

# Deep Dives: adds extra scaling PER DEPTH
@export var deep_dives_thoughts_per_depth: float = 0.03   # +3% per depth per level
@export var deep_dives_instab_per_depth: float = 0.02     # +2% per depth per level

# Mental Buffer: control bonus on every Dive
# control_bonus = depth * mental_buffer_level * mental_buffer_per_depth
@export var mental_buffer_per_depth: float = 0.5

# Overclock Mastery (power + duration, costs more control)
@export var overclock_mastery_thoughts_step: float = 0.10  # +10% overclock thoughts mult per level
@export var overclock_mastery_duration_step: float = 0.15  # +15% duration per level
@export var overclock_mastery_cost_step: float = 0.12      # +12% control cost per level

# Overclock Safety (reduces overclock instability penalty, but slightly reduces overclock thoughts)
@export var overclock_safety_instab_step: float = 0.08     # -8% overclock instability mult per level (multiplicative)
@export var overclock_safety_thoughts_step: float = 0.03   # -3% overclock thoughts mult per level (multiplicative)


# =========================
# Multipliers used by GameManager
# =========================

func get_thoughts_mult() -> float:
	return 1.0 + (thoughts_level * 0.08)

func get_instability_mult() -> float:
	return maxf(0.1, 1.0 - (stability_level * 0.05))

func get_deep_dives_thoughts_bonus_per_depth() -> float:
	return deep_dives_level * 0.03

func get_deep_dives_instab_bonus_per_depth() -> float:
	return float(deep_dives_level) * deep_dives_instab_per_depth

func get_mental_buffer_per_depth() -> float:
	return float(mental_buffer_level) * mental_buffer_per_depth

# Overclock upgrade helpers
func get_overclock_thoughts_mult_bonus() -> float:
	# additive bonus for mastery
	return float(overclock_mastery_level) * overclock_mastery_thoughts_step

func get_overclock_duration_mult() -> float:
	return 1.0 + float(overclock_mastery_level) * overclock_mastery_duration_step

func get_overclock_cost_mult() -> float:
	return 1.0 + float(overclock_mastery_level) * overclock_mastery_cost_step

func get_overclock_instability_mult() -> float:
	# safety reduces instability mult multiplicatively
	return pow(1.0 - overclock_safety_instab_step, float(overclock_safety_level))

func get_overclock_thoughts_mult_penalty() -> float:
	# safety slightly reduces overclock thoughts mult multiplicatively
	return pow(1.0 - overclock_safety_thoughts_step, float(overclock_safety_level))


# =========================
# Costs
# =========================

func get_thoughts_upgrade_cost() -> float:
	return thoughts_base_cost * pow(run_cost_growth, thoughts_level)

func get_stability_upgrade_cost() -> float:
	return stability_base_cost * pow(run_cost_growth, stability_level)

func get_deep_dives_upgrade_cost() -> float:
	return deep_dives_base_cost * pow(run_cost_growth, deep_dives_level)

func get_mental_buffer_upgrade_cost() -> float:
	return mental_buffer_base_cost * pow(run_cost_growth, mental_buffer_level)

func get_overclock_mastery_upgrade_cost() -> float:
	return overclock_mastery_base_cost * pow(run_cost_growth, overclock_mastery_level)

func get_overclock_safety_upgrade_cost() -> float:
	return overclock_safety_base_cost * pow(run_cost_growth, overclock_safety_level)


# =========================
# Buying
# =========================

func try_buy_thoughts_upgrade(thoughts: float) -> Dictionary:
	var cost := get_thoughts_upgrade_cost()
	if thoughts < cost:
		return {"bought": false, "cost": cost}
	thoughts_level += 1
	return {"bought": true, "cost": cost}

func try_buy_stability_upgrade(thoughts: float) -> Dictionary:
	var cost := get_stability_upgrade_cost()
	if thoughts < cost:
		return {"bought": false, "cost": cost}
	stability_level += 1
	return {"bought": true, "cost": cost}

func try_buy_deep_dives_upgrade(thoughts: float) -> Dictionary:
	var cost := get_deep_dives_upgrade_cost()
	if thoughts < cost:
		return {"bought": false, "cost": cost}
	deep_dives_level += 1
	return {"bought": true, "cost": cost}

func try_buy_mental_buffer_upgrade(thoughts: float) -> Dictionary:
	var cost := get_mental_buffer_upgrade_cost()
	if thoughts < cost:
		return {"bought": false, "cost": cost}
	mental_buffer_level += 1
	return {"bought": true, "cost": cost}

func try_buy_overclock_mastery_upgrade(thoughts: float) -> Dictionary:
	var cost := get_overclock_mastery_upgrade_cost()
	if thoughts < cost:
		return {"bought": false, "cost": cost}
	overclock_mastery_level += 1
	return {"bought": true, "cost": cost}

func try_buy_overclock_safety_upgrade(thoughts: float) -> Dictionary:
	var cost := get_overclock_safety_upgrade_cost()
	if thoughts < cost:
		return {"bought": false, "cost": cost}
	overclock_safety_level += 1
	return {"bought": true, "cost": cost}
