extends Node
class_name PermPerkSystem

# ---- levels ----
# EXISTING (keep only these declarations, remove the duplicates!)
var memory_engine_level := 0
var calm_mind_level := 0
var focused_will_level := 0
var starting_insight_level := 0
var stability_buffer_level := 0
var offline_echo_level := 0

# NEW UPGRADES - Add these vars (FIXED: added 'var' keyword)
var recursive_memory_level: int = 0      # +Memories gain per level
var lucid_dreaming_level: int = 0        # +Overclock duration
var deep_sleeper_level: int = 0          # +Max depth bonus
var night_owl_level: int = 0             # +Idle thoughts at night (or always)
var dream_catcher_level: int = 0         # +Chance to not consume control on overclock
var subconscious_miner_level: int = 0    # +Auto thoughts generation even while offline
var void_walker_level: int = 0           # +Instability cap increase (can go over 100 without failing)
var rapid_eye_level: int = 0             # +Dive cooldown reduction
var sleep_paralysis_level: int = 0       # +Instability freezes temporarily on wake/fail
var oneiromancy_level: int = 0           # +See next depth preview/bonuses

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

# NEW COST FUNCTIONS
func cost_recursive_memory() -> float: return _cost_for(recursive_memory_level)
func cost_lucid_dreaming() -> float: return _cost_for(lucid_dreaming_level)
func cost_deep_sleeper() -> float: return _cost_for(deep_sleeper_level)
func cost_night_owl() -> float: return _cost_for(night_owl_level)
func cost_dream_catcher() -> float: return _cost_for(dream_catcher_level)
func cost_subconscious_miner() -> float: return _cost_for(subconscious_miner_level)
func cost_void_walker() -> float: return _cost_for(void_walker_level)
func cost_rapid_eye() -> float: return _cost_for(rapid_eye_level)
func cost_sleep_paralysis() -> float: return _cost_for(sleep_paralysis_level)
func cost_oneiromancy() -> float: return _cost_for(oneiromancy_level)

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

# NEW BUY API
func try_buy_recursive_memory(memories: float) -> Dictionary: return _try_buy(memories, "recursive_memory_level")
func try_buy_lucid_dreaming(memories: float) -> Dictionary: return _try_buy(memories, "lucid_dreaming_level")
func try_buy_deep_sleeper(memories: float) -> Dictionary: return _try_buy(memories, "deep_sleeper_level")
func try_buy_night_owl(memories: float) -> Dictionary: return _try_buy(memories, "night_owl_level")
func try_buy_dream_catcher(memories: float) -> Dictionary: return _try_buy(memories, "dream_catcher_level")
func try_buy_subconscious_miner(memories: float) -> Dictionary: return _try_buy(memories, "subconscious_miner_level")
func try_buy_void_walker(memories: float) -> Dictionary: return _try_buy(memories, "void_walker_level")
func try_buy_rapid_eye(memories: float) -> Dictionary: return _try_buy(memories, "rapid_eye_level")
func try_buy_sleep_paralysis(memories: float) -> Dictionary: return _try_buy(memories, "sleep_paralysis_level")
func try_buy_oneiromancy(memories: float) -> Dictionary: return _try_buy(memories, "oneiromancy_level")

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
	
# NEW GETTER METHODS
func get_recursive_memory_mult() -> float:
	return 1.0 + (float(recursive_memory_level) * 0.05)

func get_lucid_dreaming_duration_bonus() -> float:
	return float(lucid_dreaming_level) * 0.10

func get_deep_sleeper_depth_bonus() -> float:
	return float(deep_sleeper_level) * 0.02

func get_night_owl_mult() -> float:
	return 1.0 + (float(night_owl_level) * 0.08)

func get_dream_catcher_chance() -> float:
	return float(dream_catcher_level) * 0.03

func get_subconscious_miner_rate() -> float:
	return float(subconscious_miner_level) * 0.5

func get_void_walker_instability_cap() -> float:
	return float(void_walker_level) * 5.0

func get_rapid_eye_cooldown_reduction() -> float:
	return float(rapid_eye_level) * 0.03

func get_sleep_paralysis_seconds() -> float:
	return float(sleep_paralysis_level) * 1.0

func get_oneiromancy_preview_depths() -> int:
	return oneiromancy_level

func get_perm_upgrade_cost(upgrade_index: int, current_level: int) -> float:
	var base_costs := [
		10.0,   # Memory Engine
		15.0,   # Calm Mind
		20.0,   # Focused Will
		25.0,   # Starting Insight
		30.0,   # Stability Buffer
		50.0,   # Offline Echo
		100.0,  # Recursive Memory
		150.0,  # Lucid Dreaming
		250.0,  # Deep Sleeper
		400.0,  # Night Owl
		650.0,  # Dream Catcher
		1000.0, # Subconscious Miner
		1500.0, # Void Walker
		2500.0, # Rapid Eye
		4000.0, # Sleep Paralysis
		6500.0, # Oneiromancy
	]
	
	if upgrade_index >= base_costs.size():
		return 99999.0
	
	var base: float = base_costs[upgrade_index]
	return base * pow(1.4, float(current_level))

func get_cost_by_id(perk_id: String) -> float:
	var index := get_perk_index(perk_id)
	var level := get_level_by_id(perk_id)
	return get_perm_upgrade_cost(index, level)

func get_perk_index(perk_id: String) -> int:
	var ids := [
		"memory_engine", "calm_mind", "focused_will", "starting_insight", 
		"stability_buffer", "offline_echo", "recursive_memory", "lucid_dreaming",
		"deep_sleeper", "night_owl", "dream_catcher", "subconscious_miner",
		"void_walker", "rapid_eye", "sleep_paralysis", "oneiromancy"
	]
	return ids.find(perk_id)

func get_level_by_id(perk_id: String) -> int:
	match perk_id:
		"memory_engine": return memory_engine_level
		"calm_mind": return calm_mind_level
		"focused_will": return focused_will_level
		"starting_insight": return starting_insight_level
		"stability_buffer": return stability_buffer_level
		"offline_echo": return offline_echo_level
		"recursive_memory": return recursive_memory_level
		"lucid_dreaming": return lucid_dreaming_level
		"deep_sleeper": return deep_sleeper_level
		"night_owl": return night_owl_level
		"dream_catcher": return dream_catcher_level
		"subconscious_miner": return subconscious_miner_level
		"void_walker": return void_walker_level
		"rapid_eye": return rapid_eye_level
		"sleep_paralysis": return sleep_paralysis_level
		"oneiromancy": return oneiromancy_level
		_: return 0
