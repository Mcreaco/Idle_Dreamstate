extends Node
class_name PermPerkSystem

# ---- levels ----
var memory_engine_level := 0
var calm_mind_level := 0
var focused_will_level := 0
var starting_insight_level := 0
var stability_buffer_level := 0
var offline_echo_level := 0

# ---- max ----
@export var max_level := 25

# ---- base costs ----
@export var base_cost := 50.0
@export var growth := 1.55

func _cost_for(level: int) -> float:
	return base_cost * pow(growth, float(level))

# ---- costs ----
func cost_memory_engine() -> float: return _cost_for(memory_engine_level)
func cost_calm_mind() -> float: return _cost_for(calm_mind_level)
func cost_focused_will() -> float: return _cost_for(focused_will_level)
func cost_starting_insight() -> float: return _cost_for(starting_insight_level)
func cost_stability_buffer() -> float: return _cost_for(stability_buffer_level)
func cost_offline_echo() -> float: return _cost_for(offline_echo_level)

# ---- buy helpers ----
func _try_buy(memories: float, level_ref: String) -> Dictionary:
	var lvl := int(get(level_ref))
	if lvl >= max_level:
		return {"bought": false, "cost": _cost_for(lvl), "reason": "max"}

	var cost := _cost_for(lvl)
	if memories < cost:
		return {"bought": false, "cost": cost, "reason": "funds"}

	set(level_ref, lvl + 1)
	return {"bought": true, "cost": cost, "reason": ""}

# ---- buy API ----
func try_buy_memory_engine(memories: float) -> Dictionary: return _try_buy(memories, "memory_engine_level")
func try_buy_calm_mind(memories: float) -> Dictionary: return _try_buy(memories, "calm_mind_level")
func try_buy_focused_will(memories: float) -> Dictionary: return _try_buy(memories, "focused_will_level")
func try_buy_starting_insight(memories: float) -> Dictionary: return _try_buy(memories, "starting_insight_level")
func try_buy_stability_buffer(memories: float) -> Dictionary: return _try_buy(memories, "stability_buffer_level")
func try_buy_offline_echo(memories: float) -> Dictionary: return _try_buy(memories, "offline_echo_level")

# ---- effects ----
func get_thoughts_mult() -> float:
	return 1.0 + float(memory_engine_level) * 0.05   # +5%/lvl

func get_instability_mult() -> float:
	return maxf(0.25, 1.0 - float(calm_mind_level) * 0.04) # -4%/lvl (floor)

func get_control_mult() -> float:
	return 1.0 + float(focused_will_level) * 0.06    # +6%/lvl

func get_starting_thoughts() -> float:
	return float(starting_insight_level) * 25.0

func get_starting_instability_reduction() -> float:
	return float(stability_buffer_level) * 2.0       # -2 per lvl (cap in GM)

func get_offline_mult() -> float:
	return 1.0 + float(offline_echo_level) * 0.08    # +8%/lvl
