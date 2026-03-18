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
@export var run_cost_growth: float = 2.2 # V27 Buff: 3.2 -> 2.2

@export var thoughts_base_cost: float = 2500.0 # V27 Smooth: 1200 -> 2500
@export var stability_base_cost: float = 3000.0 # V27 Smooth: 1500 -> 3000
@export var deep_dives_base_cost: float = 7500.0 # V27 Smooth: 5000 -> 7500
@export var mental_buffer_base_cost: float = 12000.0 # Was 750,000

@export var overclock_mastery_base_cost: float = 25000.0 # Was 1,250,000
@export var overclock_safety_base_cost: float = 40000.0 # Was 1,500,000

# Effects
# Thoughts upgrade: +12% thoughts mult per level
@export var thoughts_step: float = 0.12

# Stability upgrade: -5% instability gain per level (multiplicative) (Reduced from 7%)
@export var stability_step: float = 0.05

# Deep Dives: adds extra scaling PER DEPTH (Reduced from 3%)
@export var deep_dives_thoughts_per_depth: float = 0.02   # +2% per depth per level
@export var deep_dives_instab_per_depth: float = 0.02

# Mental Buffer: Thoughts bonus on every Dive (Reduced from 50)
@export var mental_buffer_per_depth: float = 25.0

# Overclock Mastery (Reduced bonuses)
@export var overclock_mastery_thoughts_step: float = 0.05  # Was 10%
@export var overclock_mastery_duration_step: float = 0.10  # Was 15%
@export var overclock_mastery_cost_step: float = 0.15     # Was 12% (Increased cost penalty)

# Overclock Safety (Reduced efficiency)
@export var overclock_safety_instab_step: float = 0.05     # Was 8%
@export var overclock_safety_thoughts_step: float = 0.05   # Was 3% (Increased penalty)


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
