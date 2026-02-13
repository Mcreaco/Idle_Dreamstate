# DepthMetaSystem.gd
extends Node
class_name DepthMetaSystem

const MAX_DEPTH: int = 15

# Permanent currencies earned on wake/fail per depth
var currency: Array[float] = []

# Legacy/core:
var instab_reduce_level: Array[int] = []
var unlock_next_bought: Array[int] = []

# Per-depth upgrade levels stored by id
# upgrades[depth] = { "id": level_int, ... }
var upgrades: Array[Dictionary] = []

var bank_memories: float = 0.0
var bank_thoughts: float = 0.0


func _init() -> void:
	_init_arrays()

func _ready() -> void:
	_init_arrays()

func ensure_ready() -> void:
	_init_arrays()

func _init_arrays() -> void:
	if currency.size() != MAX_DEPTH + 1:
		currency.resize(MAX_DEPTH + 1)
	if instab_reduce_level.size() != MAX_DEPTH + 1:
		instab_reduce_level.resize(MAX_DEPTH + 1)
	if unlock_next_bought.size() != MAX_DEPTH + 1:
		unlock_next_bought.resize(MAX_DEPTH + 1)
	if upgrades.size() != MAX_DEPTH + 1:
		upgrades.resize(MAX_DEPTH + 1)

	for d in range(1, MAX_DEPTH + 1):
		if upgrades[d] == null or typeof(upgrades[d]) != TYPE_DICTIONARY:
			upgrades[d] = {}
			
func reset_run_upgrades() -> void:
	ensure_ready()

	for d in range(1, MAX_DEPTH + 1):
		upgrades[d].clear()
		instab_reduce_level[d] = 0
		unlock_next_bought[d] = 0

# ---------------------------------------------------
# COST HELPERS (recipes)
# ---------------------------------------------------
func _cost_1(d: int) -> Dictionary:
	return { d: 1.0 }

func _cost_2(d: int) -> Dictionary:
	var gate := clampi(d + 3, 1, MAX_DEPTH)
	return { d: 1.0, gate: 0.35 }

func _cost_3(d: int) -> Dictionary:
	var mid := clampi(d + 3, 1, MAX_DEPTH)
	var late := clampi(d + 7, 1, MAX_DEPTH)
	return { d: 1.0, mid: 0.35, late: 0.20 }

func _cost_4(d: int) -> Dictionary:
	var mid := clampi(d + 3, 1, MAX_DEPTH)
	var late := clampi(d + 7, 1, MAX_DEPTH)
	return { d: 1.0, mid: 0.40, late: 0.25, MAX_DEPTH: 0.15 }

func _pick_costs(d: int, tier: int) -> Dictionary:
	match tier:
		1: return _cost_1(d)
		2: return _cost_2(d)
		3: return _cost_3(d)
		4: return _cost_4(d)
	return _cost_1(d)

# ---------------------------------------------------
# DEFINITIONS (Depth 1..15)
# Each entry can include:
#  - id, name, desc, max, kind
#  - costs: { depthIndex: multiplier } (multi-currency)
# ---------------------------------------------------
func get_depth_upgrade_defs(depth_i: int) -> Array:
	var d := clampi(depth_i, 1, MAX_DEPTH)

	var core_stab := {
		"id":"stab",
		"name":"Stabilise Instability",
		"desc":"Reduces Instability gain globally.",
		"max":10,
		"kind":"stab",
		"costs": _pick_costs(d, 1)
	}

	var core_unlock := {
		"id":"unlock",
		"name":"Unlock Next Depth",
		"desc":"Unlocks the next Depth tab (requires Stabilise maxed).",
		"max":1,
		"kind":"unlock",
		"costs": { d: 1.0 }  # Only current depth currency, not multi-currency
	}

	# Core trio (global)
	var t_gain := {
		"id":"t_gain",
		"name":"Thoughts Weaving",
		"desc":"+5% Thoughts gain per level (global).",
		"max":10,
		"kind":"thoughts_mult",
		"costs": _pick_costs(d, 1)
	}
	var c_gain := {
		"id":"c_gain",
		"name":"Control Tempering",
		"desc":"+4% Control gain per level (global).",
		"max":10,
		"kind":"control_mult",
		"costs": _pick_costs(d, 1)
	}
	var idle_soft := {
		"id":"idle_soft",
		"name":"Idle Instability Dampener",
		"desc":"-5% Idle Instability per level (global).",
		"max":10,
		"kind":"idle_instab_down",
		"costs": _pick_costs(d, 2)
	}

	# Two extra “bigger” upgrades (global)
	# wake_yield: increases crystal gain on Wake/Fail (meta snowball)
	# dive_eff: reduces dive cooldown (or you can repurpose to dive reward)
	var wake_yield := {
		"id":"wake_yield",
		"name":"Crystalline Echo",
		"desc":"+6% crystal gain on Wake/Fail per level (global).",
		"max":10,
		"kind":"wake_yield",
		"costs": _pick_costs(d, (2 if d <= 5 else 3))
	}
	var dive_start := {
		"id":"dive_start",
		"name":"Depth Start",
		"desc":"Start at +5% depth progress per level when diving (max 100%).",
		"max":20,  # 20 levels x 5% = 100%
		"kind":"dive_start",
		"costs": _pick_costs(d, (2 if d <= 8 else 3))
	}

	# Give each depth different names/descriptions (same kinds)
	match d:
		1:
			t_gain.name = "Thoughts Flow"
			c_gain.name = "Control Habit"
			idle_soft.name = "Idle Instability Dampener"
			wake_yield.name = "Amethyst Echo"
			dive_start.name = "Shallow Start"
		2:
			t_gain.name = "Thoughts Compression"
			c_gain.name = "Control Retention"
			idle_soft.name = "Spike Dampener"
			wake_yield.name = "Ruby Resonance"
			dive_start.name = "Quick Descent"
		3:
			t_gain.name = "Pressure-Born Insight"
			c_gain.name = "Steady Grip"
			idle_soft.name = "Quiet the Tremors"
			wake_yield.name = "Emerald Afterglow"
			dive_start.name = "Pressure Entry"
		4:
			t_gain.name = "Cognitive Pressure"
			c_gain.name = "Willpower Reinforcement"
			idle_soft.name = "Stability Lining"
			wake_yield.name = "Sapphire Reflection"
			dive_start.name = "Murk Entry"
		5:
			t_gain.name = "Rift Spark"
			c_gain.name = "Anchor Mind"
			idle_soft.name = "Fray Suppression"
			wake_yield.name = "Diamond Shardfall"
			dive_start.name = "Rift Entry"
		6:
			t_gain.name = "Hollow Patterning"
			c_gain.name = "Calibrated Nerves"
			idle_soft.name = "Hush the Static"
			wake_yield.name = "Topaz Refrain"
			dive_start.name = "Hollow Entry"
		7:
			t_gain.name = "Dread Clarity"
			c_gain.name = "Fear Harness"
			idle_soft.name = "Panic Diffuser"
			wake_yield.name = "Garnet Pulse"
			dive_start.name = "Dread Entry"
		8:
			t_gain.name = "Chasm Thinking"
			c_gain.name = "Grip of Stone"
			idle_soft.name = "Edge Stabiliser"
			wake_yield.name = "Opal Gleam"
			dive_start.name = "Chasm Entry"
		9:
			t_gain.name = "Silence Insight"
			c_gain.name = "Muted Focus"
			idle_soft.name = "Noise Canceller"
			wake_yield.name = "Aquamarine Drift"
			dive_start.name = "Silent Entry"
		10:
			t_gain.name = "Veiled Intuition"
			c_gain.name = "Control Under Fog"
			idle_soft.name = "Veil Buffer"
			wake_yield.name = "Onyx Return"
			dive_start.name = "Veil Entry"
		11:
			t_gain.name = "Ruin Synthesis"
			c_gain.name = "Rebuild Will"
			idle_soft.name = "Crack Sealant"
			wake_yield.name = "Jade Renewal"
			dive_start.name = "Ruin Entry"
		12:
			t_gain.name = "Eclipse Cognition"
			c_gain.name = "Shadow Control"
			idle_soft.name = "Dark Calm"
			wake_yield.name = "Moonstone Halo"
			dive_start.name = "Eclipse Entry"
		13:
			t_gain.name = "Voidline Pattern"
			c_gain.name = "Threaded Will"
			idle_soft.name = "Void Insulation"
			wake_yield.name = "Obsidian Tribute"
			dive_start.name = "Void Entry"
		14:
			t_gain.name = "Blackwater Insight"
			c_gain.name = "Iron Nerve"
			idle_soft.name = "Pressure Relief"
			wake_yield.name = "Citrine Surge"
			dive_start.name = "Blackwater Entry"
		15:
			t_gain.name = "Abyssal Thought"
			c_gain.name = "Abyssal Control"
			idle_soft.name = "Abyss Stillness"
			wake_yield.name = "Quartz Apotheosis"
			dive_start.name = "Abyssal Entry"

	return [
		core_stab,
		t_gain,
		c_gain,
		idle_soft,
		wake_yield,
		dive_start,
		core_unlock,
	]

# ---------------------------------------------------
# LEVEL GET/SET
# ---------------------------------------------------
func get_level(depth_i: int, id: String) -> int:
	var d := clampi(depth_i, 1, MAX_DEPTH)
	if id == "stab":
		return clampi(instab_reduce_level[d], 0, 10)
	if id == "unlock":
		return clampi(unlock_next_bought[d], 0, 1)
	if not upgrades[d].has(id):
		return 0
	return int(upgrades[d][id])

func set_level(depth_i: int, id: String, lvl: int) -> void:
	var d := clampi(depth_i, 1, MAX_DEPTH)
	if id == "stab":
		instab_reduce_level[d] = clampi(lvl, 0, 10)
		return
	if id == "unlock":
		unlock_next_bought[d] = clampi(lvl, 0, 1)
		return
	upgrades[d][id] = lvl

# ---------------------------------------------------
# EFFECTS (GLOBAL, Option B)
# ---------------------------------------------------
func get_global_instability_mult() -> float:
	var total_lvl := 0
	for d in range(1, MAX_DEPTH + 1):
		total_lvl += clampi(instab_reduce_level[d], 0, 10)
	# each level = -2% globally
	return maxf(0.0, 1.0 - 0.02 * float(total_lvl))

func get_global_thoughts_mult() -> float:
	var total_lvl := 0
	for d in range(1, MAX_DEPTH + 1):
		total_lvl += clampi(get_level(d, "t_gain"), 0, 10)
	return 1.0 + 0.05 * float(total_lvl)

func get_global_control_mult() -> float:
	var total_lvl := 0
	for d in range(1, MAX_DEPTH + 1):
		total_lvl += clampi(get_level(d, "c_gain"), 0, 10)
	return 1.0 + 0.04 * float(total_lvl)

func get_global_idle_instability_mult() -> float:
	var total_lvl := 0
	for d in range(1, MAX_DEPTH + 1):
		total_lvl += clampi(get_level(d, "idle_soft"), 0, 10)
	return maxf(0.05, 1.0 - 0.05 * float(total_lvl))

# NEW: crystal gain multiplier on Wake/Fail (hook in GameManager award_depth_currency)
func get_global_wake_currency_mult() -> float:
	var total_lvl := 0
	for d in range(1, MAX_DEPTH + 1):
		total_lvl += clampi(get_level(d, "wake_yield"), 0, 10)
	# +0% .. +60% (tune)
	return 1.0 + 0.06 * float(total_lvl)

# NEW: dive cooldown multiplier (hook in GameManager _get_effective_dive_cooldown)
func get_global_dive_cooldown_mult() -> float:
	var total_lvl := 0
	for d in range(1, MAX_DEPTH + 1):
		total_lvl += clampi(get_level(d, "dive_eff"), 0, 10)
	# -0% .. -30% (tune), clamp so it never hits 0
	return maxf(0.25, 1.0 - 0.03 * float(total_lvl))
	
func get_dive_start_progress(depth_i: int) -> float:
	var lvl := get_level(depth_i, "dive_start")
	# Each level = 5%, max 20 levels = 100%
	return clampf(float(lvl) * 0.05, 0.0, 1.0)

func is_instab_fully_reduced(depth_i: int) -> bool:
	var d := clampi(depth_i, 1, MAX_DEPTH)
	var max_lvl := 3 if d == 1 else 10
	return instab_reduce_level[d] >= max_lvl

func can_show_unlock_upgrade(depth_i: int) -> bool:
	return is_instab_fully_reduced(depth_i)

func is_next_unlocked(depth_i: int) -> bool:
	var d := clampi(depth_i, 1, MAX_DEPTH)
	return unlock_next_bought[d] > 0

# ---------------------------------------------------
# COSTS
# ---------------------------------------------------
func cost_for(depth_i: int, def: Dictionary) -> float:
	var d := clampi(depth_i, 1, MAX_DEPTH)
	var kind := String(def.get("kind", ""))
	var id := String(def.get("id", ""))

	var lvl := get_level(d, id)
	
	# Much cheaper base for Depth 1
	var base := 10.0 if d == 1 else (50.0 + float(d - 1) * 35.0)

	match kind:
		"stab":
			# Gentler curve for Depth 1
			var growth := 1.25 if d == 1 else 1.45
			return base * pow(growth, float(lvl))
		"unlock":
			return 250.0 + float(d - 1) * 150.0
		"thoughts_mult":
			return (base * 1.2) * pow(1.55, float(lvl))
		"control_mult":
			return (base * 1.15) * pow(1.52, float(lvl))
		"idle_instab_down":
			return (base * 1.35) * pow(1.60, float(lvl))
		"wake_yield":
			return (base * 1.75) * pow(1.70, float(lvl))
		"dive_start":  # Changed from dive_eff
			return (base * 1.45) * pow(1.55, float(lvl))  # Slightly higher growth
		_:
			return base * pow(1.50, float(lvl))

# ---------------------------------------------------
# BUYING (multi-currency)
# ---------------------------------------------------
func try_buy(depth_i: int, id: String) -> Dictionary:
	ensure_ready()
	var d := clampi(depth_i, 1, MAX_DEPTH)

	var defs := get_depth_upgrade_defs(d)
	var def: Dictionary = {}
	for item in defs:
		if String(item.get("id","")) == id:
			def = item
			break
	if def.is_empty():
		return {"bought": false, "reason": "no_def"}

	var max_lvl := int(def.get("max", 1))
	var lvl := get_level(d, id)
	if lvl >= max_lvl:
		return {"bought": false, "reason": "max"}

	# Gate unlock
	if id == "unlock":
		if d >= MAX_DEPTH:
			return {"bought": false, "reason": "no_next"}
		if not can_show_unlock_upgrade(d):
			return {"bought": false, "reason": "locked"}

	var base := cost_for(d, def)
	var costs: Dictionary = def.get("costs", { d: 1.0 })

	# Check funds
	for k in costs.keys():
		var idx := int(k)
		var need := base * float(costs[k])
		if currency[idx] < need:
			return {"bought": false, "reason": "funds", "need": need, "currency": idx}

	# Subtract all currencies
	for k in costs.keys():
		var idx := int(k)
		currency[idx] -= base * float(costs[k])

	set_level(d, id, lvl + 1)
	return {"bought": true, "reason": "", "cost": base}

# ---------------------------------------------------
# Names
# ---------------------------------------------------
static func get_depth_currency_name(d: int) -> String:
	match d:
		1:  return "Amethyst"
		2:  return "Ruby"
		3:  return "Emerald"
		4:  return "Sapphire"
		5:  return "Diamond"
		6:  return "Topaz"
		7:  return "Garnet"
		8:  return "Opal"
		9:  return "Aquamarine"
		10: return "Onyx"
		11: return "Jade"
		12: return "Moonstone"
		13: return "Obsidian"
		14: return "Citrine"
		15: return "Quartz"
		_:  return "Crystal"

static func get_depth_name(d: int) -> String:
	match d:
		1:  return "Depth 1 — Shallows"
		2:  return "Depth 2 — Descent"
		3:  return "Depth 3 — Pressure"
		4:  return "Depth 4 — Murk"
		5:  return "Depth 5 — Rift"
		6:  return "Depth 6 — Hollow"
		7:  return "Depth 7 — Dread"
		8:  return "Depth 8 — Chasm"
		9:  return "Depth 9 — Silence"
		10: return "Depth 10 — Veil"
		11: return "Depth 11 — Ruin"
		12: return "Depth 12 — Eclipse"
		13: return "Depth 13 — Voidline"
		14: return "Depth 14 — Blackwater"
		15: return "Depth 15 — Abyss"
		_:  return "Depth %d" % d

func _get_depth_name(d: int) -> String:
	# Prefer asking the scene instance (this is the correct way)
	var meta := get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null:
		if meta.has_method("get_depth_name"):
			return str(meta.call("get_depth_name", d))
		if meta.has_method("get_depth_currency_name"):
			return str(meta.call("get_depth_currency_name", d))
		if meta.has_method("get_depth_name_static"):
			return str(meta.call("get_depth_name_static", d)) # only if you made one

	# Safe fallback
	return "Depth %d" % d

func add_memories(amount: float) -> void:
	bank_memories += maxf(0.0, amount)

func add_thoughts(amount: float) -> void:
	bank_thoughts += maxf(0.0, amount)

func get_memories() -> float:
	return bank_memories

func get_thoughts() -> float:
	return bank_thoughts

func is_next_depth_unlocked(current_depth: int) -> bool:
	var next_depth := current_depth + 1
	if next_depth > MAX_DEPTH:
		return false
	return is_depth_unlocked(next_depth)

func is_depth_unlocked(depth: int) -> bool:
	var d := clampi(depth, 1, MAX_DEPTH)
	if d == 1:
		return true  # Depth 1 always unlocked
	# Check if previous depth has unlock bought
	return unlock_next_bought[d - 1] > 0
