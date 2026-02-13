extends Node

@export var max_depth: int = 15
@export var base_memories_per_sec: float = 2.0
@export var base_crystals_per_sec: float = 1.0

# top panel base rates (tune later)
@export var thoughts_per_sec: float = 0.0
@export var control_per_sec: float = 0.0
@export var instability_per_sec: float = 0.0

@export var base_progress_per_sec: float = 0.000833  # 1/1200 = 0.000833 (20 min base)
@export var depth_length_growth: float = 1.25        # Gentler curve
@export var length_curve_power: float = 1.05         # Softer power curve

@export var dev_unlock_all_depths: bool = true
@export var dev_start_depth: int = 1

var _thoughts_per_sec_cached: float = 0.0
var _control_per_sec_cached: float = 0.0

var active_depth: int = 1
var max_unlocked_depth: int = 1

var run: Array[Dictionary] = []

# depth_index -> { upgrade_id: level } that are now frozen
var frozen_upgrades: Dictionary = {}
# depth_index -> { upgrade_id: level } current depth-local upgrades
var local_upgrades: Dictionary = {}

# Top HUD values (if you’re using this controller to drive a HUD)
var thoughts: float = 0.0
var control: float = 0.0
var instability: float = 0.0

var _panel: Node = null
var _hud: Node = null

var _depth_defs: Dictionary = {}              # depth -> definition dict
var _depth_runtime: Dictionary = {}           # depth -> runtime state (timers, flags)
var _last_depth: int = -1

signal active_depth_changed(new_depth: int)

func set_active_depth(d: int) -> void:
	active_depth = clampi(d, 1, max_depth)
	active_depth_changed.emit(active_depth)
	_sync_all_to_panel()

func _ready() -> void:
	_init_run()
	_build_depth_defs()

	# DEV: unlock/jump for testing
	#if dev_unlock_all_depths:
		#max_unlocked_depth = max_depth
	#if dev_start_depth > 1:
		#active_depth = clampi(dev_start_depth, 1, max_depth)

	_last_depth = active_depth
	_on_depth_changed(active_depth)

	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	
func dev_set_depth(d: int) -> void:
	active_depth = clampi(d, 1, max_depth)
	max_unlocked_depth = max(max_unlocked_depth, active_depth)
	_last_depth = active_depth
	_on_depth_changed(active_depth)
	_sync_all_to_panel()


func bind_panel(panel: Node) -> void:
	_panel = panel
	_sync_all_to_panel()


func bind_hud(hud: Node) -> void:
	_hud = hud
	_sync_hud()


func _process(delta: float) -> void:
	# Detect depth change FIRST (so timers reset before any ticking)
	if active_depth != _last_depth:
		_last_depth = active_depth
		_on_depth_changed(active_depth)

	# Apply gameplay ticks
	_tick_active_depth(delta) # sets instability_per_sec via rules + events
	_tick_top(delta)          # actually increments instability using instability_per_sec

	# Forced wake check AFTER instability has been updated this frame
	var def: Dictionary = get_depth_def(active_depth)
	var rules: Dictionary = def.get("rules", {})
	if bool(rules.get("forced_wake_at_100", false)) and instability >= 100.0:
		wake_cashout(1.0, true)
		return

	_sync_hud()



func _tick_active_depth(delta: float) -> void:
	if _panel == null:
		return

	var d: int = active_depth
	if d < 1 or d > run.size():
		return

	var data: Dictionary = run[d - 1]

	# Apply per-depth rules (sets instability_per_sec, returns muls)
	var applied := _apply_depth_rules(d)
	var depth_prog_mul := float(applied.get("progress_mul", 1.0))
	var depth_mem_mul := float(applied.get("mem_mul", 1.0))
	var depth_cry_mul := float(applied.get("cry_mul", 1.0))
	var rules: Dictionary = applied.get("rules", {})

	# Depth events (can spike instability etc.)
	_tick_depth_events(d, delta, rules)

	# multipliers from upgrades (unchanged)
	var speed_mul: float = 1.0 + 0.25 * _get_local_level(d, "progress_speed") + _frozen_effect(d, "progress_speed", 0.15)
	var mem_mul: float   = 1.0 + 0.15 * _get_local_level(d, "memories_gain")  + _frozen_effect(d, "memories_gain",  0.15)
	var cry_mul: float   = 1.0 + 0.12 * _get_local_level(d, "crystals_gain")  + _frozen_effect(d, "crystals_gain",  0.12)

	# LENGTH / DIFFICULTY
	var length: float = get_depth_length(d)
	var per_sec: float = (base_progress_per_sec * speed_mul * depth_prog_mul) / maxf(length, 0.0001)

	var p: float = float(data.get("progress", 0.0))
	p = minf(1.0, p + per_sec * delta)
	data["progress"] = p

	data["memories"] = float(data.get("memories", 0.0)) + base_memories_per_sec * mem_mul * depth_mem_mul * delta
	data["crystals"] = float(data.get("crystals", 0.0)) + base_crystals_per_sec * cry_mul * depth_cry_mul * delta

	run[d - 1] = data

	_panel.set_row_data(d, data)
	_panel.set_active_depth(active_depth)



func _tick_top(delta: float) -> void:
	# These should be REAL rates, not cached getters.
	var tps: float = thoughts_per_sec
	var cps: float = control_per_sec

	thoughts += tps * delta
	control += cps * delta

	_thoughts_per_sec_cached = tps
	_control_per_sec_cached = cps

	instability = clampf(instability + instability_per_sec * delta, 0.0, 100.0)


func _sync_hud() -> void:
	if _hud != null and _hud.has_method("set_values"):
		# Use cached values (they represent what we applied this frame)
		_hud.call("set_values", thoughts, _thoughts_per_sec_cached, control, _control_per_sec_cached, instability)


func can_dive() -> bool:
	# Can dive if:
	# 1. Not at max depth
	# 2. Next depth is unlocked via meta progression
	if active_depth < 1 or active_depth >= max_depth:
		return false
	
	# Check meta unlock
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null and meta.has_method("is_depth_unlocked"):
		return meta.call("is_depth_unlocked", active_depth + 1)
	
	# Fallback
	return active_depth < max_unlocked_depth


func dive() -> void:
	if not can_dive():
		return

	var d := active_depth
	var local: Dictionary = local_upgrades.get(d, {}) as Dictionary
	frozen_upgrades[d] = local.duplicate(true)

	active_depth += 1
	active_depth = clampi(active_depth, 1, max_depth)
	
	# NEW: Update max unlocked and notify panel
	max_unlocked_depth = maxi(max_unlocked_depth, active_depth)
	_sync_all_to_panel()

	if not local_upgrades.has(active_depth):
		local_upgrades[active_depth] = {}

	_sync_all_to_panel()


func dive_next_depth() -> void:
	# For button-based “dive” (if you still call it elsewhere)
	var next_d := clampi(active_depth + 1, 1, max_depth)
	active_depth = next_d

	if _panel != null:
		_panel.set_active_depth(active_depth)
		_panel.set_row_data(active_depth, run[active_depth - 1])


func add_local_upgrade(depth_index: int, upgrade_id: String, amount: int = 1) -> void:
	if depth_index != active_depth:
		return
	if not local_upgrades.has(depth_index):
		local_upgrades[depth_index] = {}
	var dct: Dictionary = local_upgrades[depth_index]
	dct[upgrade_id] = int(dct.get(upgrade_id, 0)) + amount
	local_upgrades[depth_index] = dct
	if _panel != null:
		_panel.request_refresh_details(depth_index)


# --------------------
# Helpers
# --------------------
func _init_run() -> void:
	run.clear()
	for i in range(max_depth):
		run.append({"depth": i + 1, "progress": 0.0, "memories": 0.0, "crystals": 0.0})

	local_upgrades.clear()
	frozen_upgrades.clear()
	local_upgrades[1] = {}

	active_depth = 1
	max_unlocked_depth = 1


func _sync_all_to_panel() -> void:
	if _panel == null:
		return
	_panel.set_max_unlocked_depth(max_unlocked_depth)
	_panel.set_active_depth(active_depth)
	for d in range(1, max_depth + 1):
		_panel.set_row_data(d, run[d - 1])
		_panel.set_row_frozen_upgrades(d, frozen_upgrades.get(d, {}))
	_panel.set_active_local_upgrades(active_depth, local_upgrades.get(active_depth, {}))


func _get_local_level(depth_index: int, upgrade_id: String) -> int:
	var dct: Dictionary = local_upgrades.get(depth_index, {}) as Dictionary
	return int(dct.get(upgrade_id, 0))


func _frozen_multiplier_for_depth(depth_index: int) -> float:
	return clampf(0.40 + float(depth_index - 1) * 0.05, 0.40, 0.75)


func _frozen_effect(current_depth: int, upgrade_id: String, per_level: float) -> float:
	var total := 0.0
	for depth_key in frozen_upgrades.keys():
		var source_depth := int(depth_key)
		if source_depth >= current_depth:
			continue
		var dct: Dictionary = frozen_upgrades[depth_key] as Dictionary
		var lvl := int(dct.get(upgrade_id, 0))
		if lvl > 0:
			total += float(lvl) * per_level * _frozen_multiplier_for_depth(source_depth)
	return total


func get_thoughts_per_sec() -> float:
	return _thoughts_per_sec_cached


func get_control_per_sec() -> float:
	return _control_per_sec_cached


func get_instability_per_sec() -> float:
	return float(instability_per_sec)


func get_depth_length(depth_index: int) -> float:
	var d: float = float(max(depth_index, 1))
	return pow(depth_length_growth, pow(d - 1.0, length_curve_power))


func wake_cashout(ad_multiplier: float, forced: bool) -> void:
	var thoughts_mult: float = 1.0
	var memories_mult: float = 1.0
	var crystals_mult: float = 1.0
	if forced:
		thoughts_mult = 0.70
		memories_mult = 0.55
		crystals_mult = 0.40

	# Sum everything up to active depth (for UI / totals)
	var totals := _sum_run_totals(active_depth)
	var bank_thoughts: float = float(thoughts) * thoughts_mult * ad_multiplier
	var bank_memories: float = float(totals["memories"]) * memories_mult * ad_multiplier
	
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null:
		if meta.has_method("add_thoughts"):
			meta.call("add_thoughts", bank_thoughts)
		if meta.has_method("add_memories"):
			meta.call("add_memories", bank_memories)

	# Bank crystals PER DEPTH into the correct currency bucket
	var max_d := clampi(active_depth, 1, max_depth)
	for depth_i in range(1, max_d + 1):
		var data: Dictionary = run[depth_i - 1]
		var raw_cry := float(data.get("crystals", 0.0))
		var bank_cry := raw_cry * crystals_mult * ad_multiplier
		if bank_cry > 0.0:
			_apply_bank(depth_i, 0.0, 0.0, bank_cry)

	# NOTE: right now your meta banking only supports crystals (add_currency / currency array/dict).
	# Keep thoughts/memories in controller for now, or add meta methods later.
	# (If you later add meta.add_memories/add_thoughts, we’ll wire these two in properly.)
	# _apply_bank(active_depth, bank_thoughts, bank_memories, 0.0)

	# Reset ALL run bars + run-only currencies
	_reset_all_depth_progress()
	thoughts = 0.0
	control = 0.0
	instability = 0.0
	# Return to Depth 1 after waking
	active_depth = 1
	max_unlocked_depth = 1
	_last_depth = active_depth
	_on_depth_changed(active_depth)
	
	_sync_all_to_panel()
	_sync_hud()


func reset_active_depth_progress_only() -> void:
	_reset_depth_progress()
	if _panel != null:
		_panel.set_row_data(active_depth, run[active_depth - 1])
		_panel.set_active_depth(active_depth)



func _reset_depth_progress() -> void:
	var idx := active_depth - 1
	if idx < 0 or idx >= run.size():
		return
	var data: Dictionary = run[idx]
	data["progress"] = 0.0
	data["memories"] = 0.0
	data["crystals"] = 0.0
	run[idx] = data


func _calc_memories_gain() -> float:
	var idx := active_depth - 1
	if idx < 0 or idx >= run.size():
		return 0.0
	var data: Dictionary = run[idx]
	return float(data.get("memories", 0.0))

func _calc_crystals_gain() -> float:
	var idx := active_depth - 1
	if idx < 0 or idx >= run.size():
		return 0.0
	var data: Dictionary = run[idx]
	return float(data.get("crystals", 0.0))


func _apply_bank(depth_index: int, _bank_thoughts: float, _bank_memories: float, bank_crystals: float) -> void:
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta == null:
		push_warning("DepthRunController: DepthMetaSystem not found.")
		return

	# If your meta supports add_currency(depth, amount)
	if meta.has_method("add_currency"):
		meta.call("add_currency", depth_index, bank_crystals)
		return

	var currency_variant: Variant = meta.get("currency")
	if currency_variant is Dictionary:
		var c: Dictionary = currency_variant
		c[depth_index] = float(c.get(depth_index, 0.0)) + float(bank_crystals)
		meta.set("currency", c)
		return

	if currency_variant is Array:
		var a: Array = currency_variant
		if depth_index >= 0 and depth_index < a.size():
			a[depth_index] = float(a[depth_index]) + float(bank_crystals)
			meta.set("currency", a)
		return

	push_warning("DepthRunController: DepthMetaSystem.currency is not Dictionary/Array.")


func preview_wake(ad_multiplier: float, forced: bool) -> Dictionary:
	var thoughts_mult := 1.0
	var memories_mult := 1.0
	var crystals_mult := 1.0
	if forced:
		thoughts_mult = 0.70
		memories_mult = 0.55
		crystals_mult = 0.40

	# Count everything up to the current active depth
	var totals := _sum_run_totals(active_depth)

	var mem := float(totals["memories"]) * memories_mult * ad_multiplier
	var crystals_by_name: Dictionary = (totals["crystals_by_name"] as Dictionary).duplicate(true)

	# Apply multipliers to each named currency
	for k in crystals_by_name.keys():
		crystals_by_name[k] = float(crystals_by_name[k]) * crystals_mult * ad_multiplier

	return {
		"depth": active_depth,
		"forced": forced,
		"thoughts": float(thoughts) * thoughts_mult * ad_multiplier,
		"memories": mem,
		"crystals_by_name": crystals_by_name
	}


func _build_depth_defs() -> void:
	_depth_defs.clear()
	
	# ============================================
	# DEPTH 1 — SHALLOWS (Tutorial, no instability)
	# ============================================
	_depth_defs[1] = {
		"new_title": "Shallows",
		"desc": "Calm waters. Learn the flow of thoughts and memories.",
		"ui_unlocks": ["progress_bar", "memories_display", "crystals_display", "run_upgrades_panel"],
		"rules": {
			"instability_enabled": false,
			"instability_per_sec": 0.0,
			"progress_mul": 1.0,
			"mem_mul": 1.0,
			"cry_mul": 1.0,
			"forced_wake_at_100": false,
			"event_enabled": false,
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 50.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,  # +25% speed
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 40.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,  # +30% memories
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 60.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,  # +25% crystals
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 2 — INSTABILITY (First risk)
	# ============================================
	_depth_defs[2] = {
		"new_title": "Instability",
		"desc": "The water stirs. Instability rises over time. Manage it or be forced to Wake.",
		"ui_unlocks": ["instability_bar", "wake_button"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.4,
			"progress_mul": 1.0,
			"mem_mul": 1.05,
			"cry_mul": 1.02,
			"forced_wake_at_100": true,
			"event_enabled": false,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}  # Max stabilize to unlock dive
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 75.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 60.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 90.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {  # MANDATORY: Must max to unlock dive
				"max_level": 10,
				"base_cost": 30.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,  # -8% instability gain
				"cost_currency": "thoughts",
				"description": "Reduce instability gain. MAX THIS TO UNLOCK DIVE."
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 100.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,  # +15% control generation
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 3 — PRESSURE (Slowdown mechanic)
	# ============================================
	_depth_defs[3] = {
		"new_title": "Pressure",
		"desc": "The deep presses in. High instability slows your progress.",
		"ui_unlocks": ["pressure_indicator"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.6,
			"progress_mul": 1.0,
			"mem_mul": 1.10,
			"cry_mul": 1.05,
			"forced_wake_at_100": true,
			"event_enabled": false,
			"pressure_threshold": 60.0,  # Above 60% instability, slowdown applies
			"pressure_slow_mul": 0.60,   # 60% speed when pressured
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 100.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 80.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 120.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 50.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 150.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"pressure_resist": {  # Counter Depth 3 mechanic
				"max_level": 3,
				"base_cost": 200.0,
				"cost_growth": 2.5,
				"effect_per_level": -0.20,  # -20% slowdown effect
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 4 — MURK (Hidden rewards)
	# ============================================
	_depth_defs[4] = {
		"new_title": "Murk",
		"desc": "Visibility drops. Rewards are uncertain until you Wake.",
		"ui_unlocks": ["reward_ranges_hidden"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.9,
			"progress_mul": 1.0,
			"mem_mul": 1.15,
			"cry_mul": 1.08,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 45.0,  # Flicker every 45s
			"murk_hidden_rewards": true,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 150.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 120.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 180.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 80.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"clairvoyance": {  # See through murk
				"max_level": 3,
				"base_cost": 300.0,
				"cost_growth": 3.0,
				"effect_per_level": 0.25,  # +25% visibility per level, max 75%
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "flicker",
				"trigger": "timer",
				"cooldown": 45.0,
				"choices": [
					{
						"id": "wait",
						"text": "Wait it out",
						"effect": {"type": "pause_progress", "duration": 10.0}
					},
					{
						"id": "overclock_through",
						"text": "Overclock through",
						"effect": {"type": "cost_control", "amount": 20.0, "instability_bonus": 0.15, "bypass_pause": true}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 5 — RIFT (Choice events)
	# ============================================
	_depth_defs[5] = {
		"new_title": "Rift",
		"desc": "Reality fractures. Choose your path: steady or risky.",
		"ui_unlocks": ["choice_modal"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 1.3,
			"progress_mul": 1.0,
			"mem_mul": 1.20,
			"cry_mul": 1.12,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,  # Choice every 30s
			"choice_paused": true,  # Progress pauses during choice
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 200.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 160.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 240.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 120.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"rift_mastery": {  # Better choices
				"max_level": 3,
				"base_cost": 400.0,
				"cost_growth": 2.5,
				"effect_per_level": 0.20,  # +20% better outcomes
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "the_choice",
				"trigger": "timer",
				"cooldown": 30.0,
				"pause_progress": true,
				"choices": [
					{
						"id": "steady",
						"text": "Steady path",
						"effect": {"progress_bonus": 0.10, "instability_bonus": 0.05}
					},
					{
						"id": "risk",
						"text": "Risky leap",
						"effect": {"progress_bonus": 0.25, "instability_bonus": 0.20, "mem_mul": 1.50, "duration": 10.0}
					}
				],
				"upgrade_bonus": "rift_mastery"  # Applies to both choices
			}
		]
	}
	
	# ============================================
	# DEPTH 6 — HOLLOW (Frozen depth bonus)
	# ============================================
	_depth_defs[6] = {
		"new_title": "Hollow",
		"desc": "Emptiness echoes. Your past depths strengthen you.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 1.8,
			"progress_mul": 1.0,
			"mem_mul": 1.25,
			"cry_mul": 1.15,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 40.0,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 300.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 240.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			# NO crystals_gain in Depth 6
			"stabilize": {
				"max_level": 10,
				"base_cost": 200.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 500.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"echo": {  # Frozen depth bonus
				"max_level": 5,
				"base_cost": 600.0,
				"cost_growth": 2.2,
				"effect_per_level": 0.10,  # +10% frozen depth 5 bonuses
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "echo_event",
				"trigger": "timer",
				"cooldown": 40.0,
				"choices": [
					{
						"id": "embrace",
						"text": "Embrace the echo",
						"effect": {"frozen_bonus_mul": 1.5, "duration": 15.0, "instability_bonus": 0.10}
					},
					{
						"id": "reject",
						"text": "Reject the past",
						"effect": {"progress_bonus": 0.05}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 7 — DREAD (Fake threats)
	# ============================================
	_depth_defs[7] = {
		"new_title": "Dread",
		"desc": "Fear manifests. Not all dangers are real.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 2.4,
			"progress_mul": 1.0,
			"mem_mul": 1.30,
			"cry_mul": 1.18,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 35.0,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 450.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 360.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {  # Returns in Depth 7
				"max_level": 3,
				"base_cost": 540.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 320.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"dread_resist": {  # See fake threats
				"max_level": 3,
				"base_cost": 800.0,
				"cost_growth": 2.5,
				"effect_per_level": -0.15,  # -15% fake threat penalty
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "paranoia",
				"trigger": "timer",
				"cooldown": 35.0,
				"fake_instability_spike": true,
				"choices": [
					{
						"id": "panic",
						"text": "Panic overclock",
						"effect": {"cost_control": 30.0, "instability_bonus": 0.10, "was_fake": true}
					},
					{
						"id": "wait",
						"text": "Wait and see",
						"effect": {"progress_bonus": 0.05, "reveal_fake": true}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 8 — CHASM (Progress per frozen depth)
	# ============================================
	_depth_defs[8] = {
		"new_title": "Chasm",
		"desc": "A vast drop. Your journey strengthens your step.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 3.1,
			"progress_mul": 1.0,
			"mem_mul": 1.35,
			"cry_mul": 1.20,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 600.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 480.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 720.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 480.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 1000.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"chasm_flow": {  # +10% speed per frozen depth
				"max_level": 5,
				"base_cost": 1200.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "narrow_ledge",
				"trigger": "timer",
				"cooldown": 30.0,
				"effect_on_trigger": {"pause_progress": true, "instability_mul": 2.0, "duration": 10.0},
				"choices": [
					{
						"id": "push",
						"text": "Push through",
						"effect": {"resume_progress": true, "keep_instability_mul": true}
					},
					{
						"id": "find_path",
						"text": "Find safe path",
						"effect": {"cost_thoughts": 50.0, "normal_instability": true, "progress_bonus_after": 0.15}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 9 — SILENCE (Blind play)
	# ============================================
	_depth_defs[9] = {
		"new_title": "Silence",
		"desc": "Sound dies. You must feel your way forward.",
		"ui_unlocks": ["hidden_numbers"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 4.0,
			"progress_mul": 1.0,
			"mem_mul": 1.40,
			"cry_mul": 1.22,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 25.0,
			"hide_all_numbers": true,  # Blind mode
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 900.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			# NO memories_gain in Depth 9
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 1080.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 720.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 1500.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"silent_step": {  # Flat instability reduction
				"max_level": 3,
				"base_cost": 2000.0,
				"cost_growth": 3.0,
				"effect_per_level": -0.10,  # -0.1 base instability/sec per level
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "the_hush",
				"trigger": "timer",
				"cooldown": 25.0,
				"effect_on_trigger": {"hide_ui_duration": 8.0},
				"choices": [
					{
						"id": "listen",
						"text": "Listen carefully",
						"effect": {"instability_mul": -0.20, "pause_progress": true}
					},
					{
						"id": "guess",
						"text": "Push forward blind",
						"effect": {"continue_blind": true, "risk_overclock": true}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 10 — VEIL (Random outcomes)
	# ============================================
	_depth_defs[10] = {
		"new_title": "Veil",
		"desc": "Truth and lie intertwine. Choose wisely, or don't.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 5.0,
			"progress_mul": 1.0,
			"mem_mul": 1.45,
			"cry_mul": 1.25,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			# NO progress_speed in Depth 10
			"memories_gain": {
				"max_level": 5,
				"base_cost": 960.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 1440.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 960.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 2000.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"veil_pierce": {  # See true outcomes
				"max_level": 1,
				"base_cost": 5000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,  # Reveal random choices
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "truth_false",
				"trigger": "timer",
				"cooldown": 30.0,
				"random_outcome": true,
				"choices": [
					{
						"id": "button_a",
						"text": "???",
						"outcomes": [
							{"chance": 0.5, "progress_bonus": 0.20, "instability_bonus": -0.10},
							{"chance": 0.5, "progress_bonus": -0.10, "instability_bonus": 0.20}
						]
					},
					{
						"id": "button_b",
						"text": "???",
						"outcomes": [
							{"chance": 0.5, "progress_bonus": 0.20, "instability_bonus": -0.10},
							{"chance": 0.5, "progress_bonus": -0.10, "instability_bonus": 0.20}
						]
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 11 — RUIN (Lose frozen bonuses)
	# ============================================
	_depth_defs[11] = {
		"new_title": "Ruin",
		"desc": "What was built crumbles. The past is not forever.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 6.2,
			"progress_mul": 1.0,
			"mem_mul": 1.50,
			"cry_mul": 1.28,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 25.0,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 1500.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 1200.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			# NO crystals_gain in Depth 11
			"stabilize": {
				"max_level": 10,
				"base_cost": 1280.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 2500.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"ruin_harvest": {  # Gain from failure
				"max_level": 3,
				"base_cost": 3000.0,
				"cost_growth": 2.5,
				"effect_per_level": 0.50,  # +50% crystals from failed runs
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "collapse",
				"trigger": "timer",
				"cooldown": 25.0,
				"effect_on_trigger": {"lose_frozen_depth": -2},  # Lose depth n-2 bonuses
				"choices": [
					{
						"id": "let_go",
						"text": "Let it crumble",
						"effect": {"confirm_loss": true, "instability_bonus": -0.10}
					},
					{
						"id": "reinforce",
						"text": "Reinforce structure",
						"effect": {"cost_crystals": 100.0, "keep_bonuses": true, "instability_bonus": 0.15}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 12 — ECLIPSE (Mirror danger)
	# ============================================
	_depth_defs[12] = {
		"new_title": "Eclipse",
		"desc": "Your shadow acts. Every move echoes dangerously.",
		"ui_unlocks": ["shadow_clone"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 7.6,
			"progress_mul": 1.0,
			"mem_mul": 1.55,
			"cry_mul": 1.30,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 20.0,
			"shadow_clone_enabled": true,
			"shadow_delay": 5.0,  # 5 second delay
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 2250.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 1800.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 2700.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 1920.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"eclipse_shield": {  # Cap at 110%
				"max_level": 1,
				"base_cost": 8000.0,
				"cost_growth": 1.0,
				"effect_per_level": 10.0,  # +10% cap (110% max)
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "shadow_self",
				"trigger": "timer",
				"cooldown": 20.0,
				"effect_on_trigger": {"shadow_active": true, "duration": 15.0},
				"warning": "Your shadow mirrors your actions with 5s delay!"
			}
		]
	}
	
	# ============================================
	# DEPTH 13 — VOIDLINE (Passive drain)
	# ============================================
	_depth_defs[13] = {
		"new_title": "Voidline",
		"desc": "The edge of existence. The void hungers constantly.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 9.2,
			"progress_mul": 1.0,
			"mem_mul": 1.60,
			"cry_mul": 1.35,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_type": "passive",  # Constant effect
			"void_drain_chance": 0.01,  # 1% per second
			"void_drain_amount": 0.05,  # 5% progress
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 3375.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 2700.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 4050.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 2880.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 5000.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"void_tap": {  # Convert drain to thoughts
				"max_level": 5,
				"base_cost": 6000.0,
				"cost_growth": 2.0,
				"effect_per_level": 1.0,  # 1:1 conversion of lost progress to thoughts
				"cost_currency": "thoughts"
			}
		},
		"events": []  # Passive effect, no triggered events
	}
	
	# ============================================
	# DEPTH 14 — BLACKWATER (Crystal carryover)
	# ============================================
	_depth_defs[14] = {
		"new_title": "Blackwater",
		"desc": "Dark tides rise. What you gain here stains the next.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 11.0,
			"progress_mul": 1.0,
			"mem_mul": 1.65,
			"cry_mul": 1.38,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 20.0,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 5000.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			# NO memories_gain in Depth 14
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 6000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 10,
				"base_cost": 4320.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 7500.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"blackwater_cache": {  # Carry crystals to next run
				"max_level": 3,
				"base_cost": 10000.0,
				"cost_growth": 3.0,
				"effect_per_level": 0.25,  # +25% carryover per level
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "tide",
				"trigger": "timer",
				"cooldown": 20.0,
				"effect_on_trigger": {"instability_mul": 1.5, "duration": 15.0},
				"choices": [
					{
						"id": "swim",
						"text": "Swim through",
						"effect": {"continue": true, "keep_mul": true}
					},
					{
						"id": "anchor",
						"text": "Drop anchor",
						"effect": {"cost_control": 75.0, "normal_instability": true, "progress_mul": 0.75}
					}
				]
			}
		]
	}
	
	# ============================================
	# DEPTH 15 — ABYSS (Final test, all events)
	# ============================================
	_depth_defs[15] = {
		"new_title": "Abyss",
		"desc": "The final threshold. All trials converge here.",
		"ui_unlocks": ["abyss_challenge"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 13.0,
			"progress_mul": 1.0,
			"mem_mul": 1.70,
			"cry_mul": 1.45,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 15.0,
			"abyss_extra_instability": 2.0,  # +2/sec unavoidable
			"random_event_pool": ["echo", "paranoia", "narrow_ledge", "the_hush", "truth_false", "collapse", "shadow_self", "tide"],
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 5}  # Capped at 5 in Abyss
		},
		"upgrades": {
			"progress_speed": {
				"max_level": 5,
				"base_cost": 7500.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"max_level": 5,
				"base_cost": 6000.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"max_level": 3,
				"base_cost": 9000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"stabilize": {
				"max_level": 5,  # CAPPED at 5
				"base_cost": 6480.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"control_buffer": {
				"max_level": 3,
				"base_cost": 10000.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"abyssal_form": {  # Boosts all previous unique upgrades
				"max_level": 5,
				"base_cost": 15000.0,
				"cost_growth": 2.5,
				"effect_per_level": 0.10,  # +10% to echo, dread_resist, etc.
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "final_test",
				"trigger": "timer",
				"cooldown": 15.0,
				"random_from_pool": true,
				"note": "Randomly picks from all previous depth events"
			}
		]
	}
func get_depth_def(depth_index: int) -> Dictionary:
	return _depth_defs.get(depth_index, {})

func _ensure_depth_runtime(depth_index: int) -> void:
	if _depth_runtime.has(depth_index):
		return
	_depth_runtime[depth_index] = {
		"time_in_depth": 0.0,
		"next_choice_t": 0.0,
		"flags": {}
	}

func _apply_depth_rules(d: int) -> Dictionary:
	var def: Dictionary = get_depth_def(d)
	var rules: Dictionary = def.get("rules", {})

	# Defaults
	var inst_enabled := bool(rules.get("instability_enabled", false))
	var inst_ps := float(rules.get("instability_per_sec", 0.0))
	var prog_mul := float(rules.get("progress_mul", 1.0))
	var mem_mul := float(rules.get("mem_mul", 1.0))
	var cry_mul := float(rules.get("cry_mul", 1.0))

	# Pressure (Depth 3 example): slow progress if instability high
	if rules.has("pressure_threshold") and float(instability) >= float(rules.get("pressure_threshold")):
		prog_mul *= float(rules.get("pressure_slow_mul", 0.6))

	# Apply top rates
	instability_per_sec = inst_ps if inst_enabled else 0.0

	return {
		"progress_mul": prog_mul,
		"mem_mul": mem_mul,
		"cry_mul": cry_mul,
		"rules": rules,
		"def": def
	}

func _tick_depth_events(d: int, delta: float, rules: Dictionary) -> void:
	_ensure_depth_runtime(d)
	var rt: Dictionary = _depth_runtime[d]
	rt["time_in_depth"] = float(rt.get("time_in_depth", 0.0)) + delta

	# Example: Depth 5 choice event timer
	if rules.has("choice_every_sec"):
		var every := float(rules.get("choice_every_sec", 0.0))
		if every > 0.0:
			var next_t := float(rt.get("next_choice_t", 0.0))
			if next_t <= 0.0:
				rt["next_choice_t"] = every
			else:
				rt["next_choice_t"] = next_t - delta
				if float(rt["next_choice_t"]) <= 0.0:
					rt["next_choice_t"] = every
					_fire_depth_event(d, "rift_choice")

	_depth_runtime[d] = rt

func _fire_depth_event(depth_index: int, event_id: String) -> void:
	if event_id == "rift_choice":
		var spike := 4.0 + float(depth_index) * 0.5
		instability = clampf(instability + spike, 0.0, 100.0)


func _on_depth_changed(new_depth: int) -> void:
	_ensure_depth_runtime(new_depth)
	_depth_runtime[new_depth]["time_in_depth"] = 0.0
	_depth_runtime[new_depth]["next_choice_t"] = 0.0

func _get_depth_currency_name(depth_index: int) -> String:
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null and meta.has_method("get_depth_currency_name"):
		return str(meta.call("get_depth_currency_name", depth_index))
	return "Cry"

func _sum_run_totals(up_to_depth: int) -> Dictionary:
	# Sums memories/crystals across depths 1..up_to_depth
	var max_d := clampi(up_to_depth, 1, max_depth)

	var total_mem := 0.0
	var total_cry := 0.0
	var crystals_by_name: Dictionary = {} # name -> amount

	for d in range(1, max_d + 1):
		var data: Dictionary = run[d - 1]
		var mem := float(data.get("memories", 0.0))
		var cry := float(data.get("crystals", 0.0))

		total_mem += mem
		total_cry += cry

		var nm := _get_depth_currency_name(d)
		crystals_by_name[nm] = float(crystals_by_name.get(nm, 0.0)) + cry

	return {
		"memories": total_mem,
		"crystals_total": total_cry,
		"crystals_by_name": crystals_by_name,
		"depth_counted": max_d
	}

func _reset_all_depth_progress() -> void:
	for i in range(run.size()):
		var data: Dictionary = run[i]
		data["progress"] = 0.0
		data["memories"] = 0.0
		data["crystals"] = 0.0
		run[i] = data
