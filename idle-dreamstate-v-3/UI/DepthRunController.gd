extends Node

@export var max_depth: int = 15
@export var base_memories_per_sec: float = 2.0
@export var base_crystals_per_sec: float = 1.0

# top panel base rates (tune later)
@export var thoughts_per_sec: float = 0.0
@export var control_per_sec: float = 0.0
@export var instability_per_sec: float = 0.0

@export var base_progress_per_sec: float = 1 # 1/1200 = 0.000833 (20 min base)
@export var depth_length_growth: float = 1.25        # Gentler curve
@export var length_curve_power: float = 1.05         # Softer power curve

@export var dev_unlock_all_depths: bool = true
@export var dev_start_depth: int = 1

var choice_modal: ChoiceModal = null
var _current_event_timer: float = 0.0
var _active_event: Dictionary = {}

var _thoughts_per_sec_cached: float = 0.0
var _control_per_sec_cached: float = 0.0

var active_depth: int = 1
var max_unlocked_depth: int = 1
var _run_internal: Array[Dictionary] = []

var run: Array[Dictionary]:
	get:
		return _run_internal
	set(value):
		_run_internal = value
	
func _get_run() -> Array[Dictionary]:
	return _run_internal

func _set_run(value: Array[Dictionary]) -> void:
	_run_internal = value


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

var _last_debug_print_time: float = 0.0
var _last_progress_value: float = -1.0

signal active_depth_changed(new_depth: int)

func set_active_depth(d: int) -> void:
	active_depth = clampi(d, 1, max_depth)
	active_depth_changed.emit(active_depth)
	_sync_all_to_panel()  # <-- This is fine, but does it reset anything?

func _ready() -> void:
	_init_run()
	_build_depth_defs()
	
	# Look for existing modal or create one
	choice_modal = get_tree().current_scene.find_child("ChoiceModal", true, false) as ChoiceModal
	if choice_modal == null:
		choice_modal = ChoiceModal.new()
		choice_modal.name = "ChoiceModal"
		get_tree().current_scene.add_child(choice_modal)

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
	# Remove depth change tracking if not needed, or keep it but don't block
	if active_depth != _last_depth:
		_last_depth = active_depth
		_on_depth_changed(active_depth)

	# CRITICAL FIX: Let depth 1 tick like all others (removed "if active_depth != 1" check)
	_tick_active_depth(delta)
	
	_tick_top(delta)
	
	# Check for death/fail when instability hits the cap (only depth 2+)
	if active_depth >= 2:  # Only check instability death for depth 2 and beyond
		var game_mgr = get_node_or_null("/root/GameManager")
		var actual_cap := 1000.0
		if game_mgr != null and game_mgr.depth_meta_system != null:
			actual_cap = game_mgr.depth_meta_system.get_instability_cap(active_depth)
		
		if instability >= actual_cap:
			wake_cashout(1.0, true)
			return

	_sync_hud()


func _tick_active_depth(delta: float) -> void:
	var d: int = active_depth
	var current_time := Time.get_ticks_msec() / 1000.0
	
	# Rate-limited debug (once per second)
	var should_print := (current_time - _last_debug_print_time) >= 1.0
	
	if d < 1 or d > _run_internal.size():
		return
		
	var data: Dictionary = _run_internal[d - 1]
	var current_progress: float = float(data.get("progress", 0.0))
	
	# DETECT RESET: If progress suddenly dropped to 0 from a higher value
	if current_progress == 0.0 and _last_progress_value > 0.1:
		if should_print:
			push_warning("DEPTH DATA RESET DETECTED! Progress was %.2f, now 0.0. Stack trace:" % _last_progress_value)
			# This will print what called this function
			print_stack()
			_last_debug_print_time = current_time
	
	_last_progress_value = current_progress
	
	# ... rest of your calculation code ...
	
	# Only print normal updates once per second
	if d == 1 and should_print:
		print("Depth 1 Tick: stored_progress=%.2f, new_progress=%.2f" % [current_progress, data.get("progress", 0.0)])
		_last_debug_print_time = current_time
	
	if _panel == null:
		return

	# Apply per-depth rules (sets instability_per_sec, returns muls)
	var applied := _apply_depth_rules(d)
	var depth_prog_mul := float(applied.get("progress_mul", 1.0))
	var depth_mem_mul := float(applied.get("mem_mul", 1.0))
	var depth_cry_mul := float(applied.get("cry_mul", 1.0))
	var _rules: Dictionary = applied.get("rules", {})

	# Multipliers from upgrades (RUN UPGRADES)
	var speed_lvl := _get_local_level(d, "progress_speed")
	var mem_lvl := _get_local_level(d, "memories_gain")
	var cry_lvl := _get_local_level(d, "crystals_gain")
	
	var speed_mul: float = 1.0 + 0.25 * speed_lvl + _frozen_effect(d, "progress_speed", 0.15)
	var mem_mul: float   = 1.0 + 0.15 * mem_lvl + _frozen_effect(d, "memories_gain", 0.15)
	var cry_mul: float   = 1.0 + 0.12 * cry_lvl + _frozen_effect(d, "crystals_gain", 0.12)
	
	# Apply specific depth upgrade bonuses
	# Depth 2: Controlled Fall (+10% progress per level)
	if d == 2:
		var controlled_fall_level := _get_local_level(d, "controlled_fall")
		if controlled_fall_level > 0:
			var fall_def: Dictionary = get_depth_def(d).get("upgrades", {}).get("controlled_fall", {})
			var fall_effect: float = fall_def.get("effect_per_level", 0.10)
			speed_mul += (fall_effect * controlled_fall_level)
	
	# Depth 2: Ruby Focus (+12% rubies per level)
	if d == 2:
		var ruby_level := _get_local_level(d, "ruby_focus")
		if ruby_level > 0:
			var ruby_def: Dictionary = get_depth_def(d).get("upgrades", {}).get("ruby_focus", {})
			var ruby_effect: float = ruby_def.get("effect_per_level", 0.12)
			cry_mul += (ruby_effect * ruby_level)

	# LENGTH / DIFFICULTY
	var length: float = get_depth_length(d)
	var per_sec: float = (base_progress_per_sec * speed_mul * depth_prog_mul) / maxf(length, 0.0001)

	# CRITICAL FIX: Use actual cap instead of hardcoded 1.0
	var cap: float = get_depth_progress_cap(d)
	var p: float = float(data.get("progress", 0.0))
	p = minf(cap, p + per_sec * delta)  # Use the actual cap (1000, 2500, etc.)
	data["progress"] = p

	# Update memories and crystals
	data["memories"] = float(data.get("memories", 0.0)) + base_memories_per_sec * mem_mul * depth_mem_mul * delta
	data["crystals"] = float(data.get("crystals", 0.0)) + base_crystals_per_sec * cry_mul * depth_cry_mul * delta

	_run_internal[d - 1] = data
	
	_panel.set_row_data(d, data)
	
	# Update panel
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

func get_depth_progress_cap(depth: int) -> float:
	return 1000.0 * pow(2.5, float(depth - 1))

func _sync_hud() -> void:
	if _hud != null and _hud.has_method("set_values"):
		# Use cached values (they represent what we applied this frame)
		_hud.call("set_values", thoughts, _thoughts_per_sec_cached, control, _control_per_sec_cached, instability)


func can_dive() -> bool:
	
	# Can't dive past max depth
	if active_depth < 1 or active_depth >= max_depth:
		return false
	
	# Check if next depth is unlocked in meta progression
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	var meta_unlocked := false
	if meta != null and meta.has_method("is_depth_unlocked"):
		meta_unlocked = meta.call("is_depth_unlocked", active_depth + 1)
	else:
		meta_unlocked = active_depth < max_unlocked_depth
	
	if not meta_unlocked:
		return false
	
	# Check depth-specific META upgrade requirements (permanent, not run upgrades)
	var def: Dictionary = get_depth_def(active_depth)
	var rules: Dictionary = def.get("rules", {})
	var dive_req = rules.get("dive_unlock_requirement", null)
	
	if dive_req != null:
		var req_upgrade: String = dive_req.get("upgrade", "")
		var req_level: int = dive_req.get("level", 0)
		
		if req_upgrade != "":
			var current_level: int = 0
			# CHECK META UPGRADE (permanent), not local run upgrade
			if meta != null and meta.has_method("get_level"):
				current_level = meta.call("get_level", active_depth, req_upgrade)
			
			if current_level < req_level:
				return false
	
	return true

func get_perk_index(perk_id: String) -> int:
	var perk_map := {
		"memory_engine": 0,
		"calm_mind": 1,
		"focused_will": 2,
		"starting_insight": 3,
		"stability_buffer": 4,
		"offline_echo": 5,
		"recursive_memory": 6,
		"lucid_dreaming": 7,
		"deep_sleeper": 8,
		"night_owl": 9,
		"dream_catcher": 10,
		"subconscious_miner": 11,
		"void_walker": 12,
		"rapid_eye": 13,
		"sleep_paralysis": 14,
		"oneiromancy": 15
	}
	return perk_map.get(perk_id, -1)
	
func get_run_upgrade_info(depth_index: int, upgrade_id: String) -> Dictionary:
	var def: Dictionary = get_depth_def(depth_index)
	var upgrades: Dictionary = def.get("upgrades", {})
	var upg: Dictionary = upgrades.get(upgrade_id, {})
	
	return {
		"name": upg.get("name", upgrade_id.capitalize()),
		"description": upg.get("description", ""),
		"max_level": upg.get("max_level", 1),
		"effect_per_level": upg.get("effect_per_level", 0.0),
		"current_level": _get_local_level(depth_index, upgrade_id)
	}
	
func dive() -> bool:
	if not can_dive():
		return false

	var d := active_depth
	var local: Dictionary = local_upgrades.get(d, {}) as Dictionary
	frozen_upgrades[d] = local.duplicate(true)

	active_depth += 1
	active_depth = clampi(active_depth, 1, max_depth)
	max_unlocked_depth = maxi(max_unlocked_depth, active_depth)

	if not local_upgrades.has(active_depth):
		local_upgrades[active_depth] = {}

	# Only sync if panel exists
	if _panel != null:
		_sync_all_to_panel()
	
	return true  # Return success


func dive_next_depth() -> void:
	# For button-based “dive” (if you still call it elsewhere)
	var next_d := clampi(active_depth + 1, 1, max_depth)
	active_depth = next_d

	if _panel != null:
		_panel.set_active_depth(active_depth)
		_panel.set_row_data(active_depth, _run_internal[active_depth - 1])


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
	_run_internal.clear()  # Was: run.clear()
	for i in range(max_depth):
		_run_internal.append({"depth": i + 1, "progress": 0.0, "memories": 0.0, "crystals": 0.0})  # Was: run.append(...)

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
	
	# CRITICAL: Include depth 1 (remove the d == 1 skip)
	for d in range(1, max_depth + 1):
		_panel.set_row_data(d, _run_internal[d - 1])
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


func wake_cashout(ad_multiplier: float, forced: bool) -> Dictionary:
	push_warning("wake_cashout() called - resetting run data")
	print_stack()
	var thoughts_mult: float = 1.0
	var memories_mult: float = 1.0
	var crystals_mult: float = 1.0
	if forced:
		thoughts_mult = 0.70
		memories_mult = 0.55
		crystals_mult = 0.40

	var totals := _sum_run_totals(active_depth)
	var bank_thoughts: float = float(thoughts) * thoughts_mult * ad_multiplier
	var bank_memories: float = float(totals["memories"]) * memories_mult * ad_multiplier
	
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null:
		if meta.has_method("add_thoughts"):
			meta.call("add_thoughts", bank_thoughts)
		if meta.has_method("add_memories"):
			meta.call("add_memories", bank_memories)

	var max_d := clampi(active_depth, 1, max_depth)
	for depth_i in range(1, max_d + 1):
		var data: Dictionary = _run_internal[depth_i - 1]  # Was: run[depth_i - 1]
		var raw_cry := float(data.get("crystals", 0.0))
		var bank_cry := raw_cry * crystals_mult * ad_multiplier
		if bank_cry > 0.0:
			_apply_bank(depth_i, 0.0, 0.0, bank_cry)

	_reset_all_depth_progress()
	thoughts = 0.0
	control = 0.0
	instability = 0.0
	active_depth = 1
	max_unlocked_depth = 1
	_last_depth = active_depth
	_on_depth_changed(active_depth)
	
	_sync_all_to_panel()
	_sync_hud()
	
	# THIS IS THE FIX - return the dictionary
	return {
		"thoughts": bank_thoughts,
		"memories": bank_memories,
		"crystals_by_name": totals["crystals_by_name"]
	}


func reset_active_depth_progress_only() -> void:
	_reset_depth_progress()
	if _panel != null:
		_panel.set_row_data(active_depth, _run_internal[active_depth - 1])
		_panel.set_active_depth(active_depth)

func _reset_depth_progress() -> void:
	var idx := active_depth - 1
	if idx < 0 or idx >= _run_internal.size():
		return
	var _data: Dictionary = _run_internal[idx]
	_data["progress"] = 0.0
	_data["memories"] = 0.0
	_data["crystals"] = 0.0
	_run_internal[idx] = _data


func _reset_all_depth_progress() -> void:
	for i in range(_run_internal.size()):  # Was: run.size()
		var data: Dictionary = _run_internal[i]  # Was: run[i]
		data["progress"] = 0.0
		data["memories"] = 0.0
		data["crystals"] = 0.0
		_run_internal[i] = data  # Was: run[i] = data


func _calc_memories_gain() -> float:
	var idx := active_depth - 1
	if idx < 0 or idx >= _run_internal.size():  # Was: run.size()
		return 0.0
	var data: Dictionary = _run_internal[idx]
	return float(data.get("memories", 0.0))

func _calc_crystals_gain() -> float:
	var idx := active_depth - 1
	if idx < 0 or idx >= _run_internal.size():  # Was: run.size()
		return 0.0
	var data: Dictionary = _run_internal[idx]
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
	# DEPTH 1 — SHALLOWS (Tutorial - 3 upgrades)
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
			"dive_unlock_requirement": {"upgrade": "manual_click", "level": 10}
		},
		"upgrades": {
			"progress_speed": {
				"name": "Velocity",
				"description": "+20% progress speed per level",
				"max_level": 999,
				"base_cost": 100.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"memories_gain": {
				"name": "Dream Recall",
				"description": "+12% Memory Gain per level",
				"max_level": 999999,
				"base_cost": 40.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"crystals_gain": {
				"name": "Mnemonic Anchor",
				"description": "+10% Crystal Gain per level",
				"max_level": 999999,
				"base_cost": 60.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 2 — DESCENT (Instability Gate - 5 upgrades)
	# ============================================
	_depth_defs[2] = {
		"new_title": "Descent",
		"desc": "The first stirrings of chaos. Instability rises. Stabilize to proceed deeper.",
		"ui_unlocks": ["instability_bar", "wake_button"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.12,
			"progress_mul": 1.0,
			"mem_mul": 1.05,
			"cry_mul": 1.02,
			"forced_wake_at_100": true,
			"event_enabled": false,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"stabilize": {
				"name": "Stabilize",
				"description": "Reduce instability gain by 0.05%/sec per level.",
				"max_level": 999999,
				"base_cost": 40.0,
				"cost_growth": 1.5,
				"effect_per_level": -0.05,
				"cost_currency": "thoughts"
			},
			"controlled_fall": {
				"name": "Controlled Fall",
				"description": "+10% Dive Progress Speed per level",
				"max_level": 999999,
				"base_cost": 25.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"trauma_inoculation": {
				"name": "Trauma Inoculation",
				"description": "+8% Memory retention if forced Wake",
				"max_level": 999999,
				"base_cost": 60.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"ruby_focus": {
				"name": "Ruby Focus",
				"description": "+12% Ruby Crystal gain this run",
				"max_level": 999999,
				"base_cost": 35.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"breath_control": {
				"name": "Breath Control",
				"description": "+0.1 Max Control capacity per level",
				"max_level": 999999,
				"base_cost": 20.0,
				"cost_growth": 1.4,
				"effect_per_level": 0.1,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 3 — PRESSURE (Slowdown mechanic - 5 upgrades)
	# ============================================
	_depth_defs[3] = {
		"new_title": "Pressure",
		"desc": "The deep presses in. High instability slows your progress.",
		"ui_unlocks": ["pressure_indicator"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.15,
			"progress_mul": 1.0,
			"mem_mul": 1.10,
			"cry_mul": 1.05,
			"forced_wake_at_100": true,
			"event_enabled": false,
			"pressure_threshold": 60.0,
			"pressure_slow_mul": 0.60,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"pressure_hardening": {
				"name": "Pressure Hardening",
				"description": "Instability reduces Progress Speed 10% less per level",
				"max_level": 999999,
				"base_cost": 100.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"crush_resistance": {
				"name": "Crush Resistance",
				"description": "-0.04% Instability/sec per level",
				"max_level": 999999,
				"base_cost": 80.0,
				"cost_growth": 1.5,
				"effect_per_level": -0.04,
				"cost_currency": "thoughts"
			},
			"risky_compression": {
				"name": "Risky Compression",
				"description": "+15% Thoughts, but +8% Instability gain",
				"max_level": 999999,
				"base_cost": 120.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"safety_valves": {
				"name": "Safety Valves",
				"description": "Instability cap reduced by 5% per level (95% max at Lv 1)",
				"max_level": 3,
				"base_cost": 150.0,
				"cost_growth": 2.0,
				"effect_per_level": -5.0,
				"cost_currency": "thoughts"
			},
			"emergency_ascent": {
				"name": "Emergency Ascent",
				"description": "Auto-Wake at 95% instead of 100%",
				"max_level": 1,
				"base_cost": 500.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 4 — MURK (Hidden rewards - 5 upgrades)
	# ============================================
	_depth_defs[4] = {
		"new_title": "Murk",
		"desc": "Visibility drops. Rewards are uncertain until you Wake.",
		"ui_unlocks": ["reward_ranges_hidden"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.18,
			"progress_mul": 1.0,
			"mem_mul": 1.15,
			"cry_mul": 1.08,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 45.0,
			"murk_hidden_rewards": true,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"dark_adaptation": {
				"name": "Dark Adaptation",
				"description": "Reveal 10% of hidden Crystal rewards per level",
				"max_level": 999999,
				"base_cost": 150.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"echo_navigation": {
				"name": "Echo Navigation",
				"description": "+10% Progress Speed per level",
				"max_level": 999999,
				"base_cost": 120.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"whisper_harvest": {
				"name": "Whisper Harvest",
				"description": "+6% Thoughts when Instability >60%",
				"max_level": 999999,
				"base_cost": 100.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.06,
				"cost_currency": "thoughts"
			},
			"murk_diving": {
				"name": "Murk Diving",
				"description": "+15% Emerald Crystals per level",
				"max_level": 999999,
				"base_cost": 180.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"instinctual_dive": {
				"name": "Instinctual Dive",
				"description": "+6% Progress when rewards are hidden",
				"max_level": 999999,
				"base_cost": 200.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.06,
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
	# DEPTH 5 — RIFT (Choice events - 5 upgrades)
	# ============================================
	_depth_defs[5] = {
		"new_title": "Rift",
		"desc": "Reality fractures. Choose your path: steady or risky.",
		"ui_unlocks": ["choice_modal"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.22,
			"progress_mul": 1.0,
			"mem_mul": 1.20,
			"cry_mul": 1.12,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"choice_paused": true,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"temporal_sense": {
				"name": "Temporal Sense",
				"description": "Choice events trigger 10% faster per level",
				"max_level": 999999,
				"base_cost": 200.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"risk_assessment": {
				"name": "Risk Assessment",
				"description": "See one outcome before choosing",
				"max_level": 1,
				"base_cost": 600.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"stable_footing": {
				"name": "Stable Footing",
				"description": "12% chance to avoid negative outcomes per level",
				"max_level": 4,
				"base_cost": 150.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"fractured_mirage": {
				"name": "Fractured Mirage",
				"description": "+0.15 Max Control per level",
				"max_level": 999999,
				"base_cost": 120.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"rift_mining": {
				"name": "Rift Mining",
				"description": "Choices grant +8% Thoughts per level",
				"max_level": 999999,
				"base_cost": 180.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.08,
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
				"upgrade_bonus": "rift_mastery"
			}
		]
	}
	
	# ============================================
	# DEPTH 6 — HOLLOW (Frozen depth bonus - 5 upgrades)
	# ============================================
	_depth_defs[6] = {
		"new_title": "Hollow",
		"desc": "Emptiness echoes. Your past depths strengthen you.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.28,
			"progress_mul": 1.0,
			"mem_mul": 1.25,
			"cry_mul": 1.15,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 40.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"crystalline_memory": {
				"name": "Crystalline Memory",
				"description": "Each prior depth cleared = +3% Progress Speed",
				"max_level": 999999,
				"base_cost": 300.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.03,
				"cost_currency": "thoughts"
			},
			"deep_freeze": {
				"name": "Deep Freeze",
				"description": "+10% Sapphire Crystals per level",
				"max_level": 999999,
				"base_cost": 240.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"thermal_vent": {
				"name": "Thermal Vent",
				"description": "-0.06% Instability/sec, -3% Thoughts",
				"max_level": 3,
				"base_cost": 400.0,
				"cost_growth": 2.0,
				"effect_per_level": -0.06,
				"cost_currency": "thoughts"
			},
			"hollow_echo": {
				"name": "Hollow Echo",
				"description": "+0.5% All gains per frozen depth per level",
				"max_level": 999999,
				"base_cost": 500.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.005,
				"cost_currency": "thoughts"
			},
			"ice_anchor": {
				"name": "Ice Anchor",
				"description": "Instability rises 8% slower per level",
				"max_level": 999999,
				"base_cost": 350.0,
				"cost_growth": 1.9,
				"effect_per_level": 0.08,
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
	# DEPTH 7 — DREAD (Fake threats - 5 upgrades)
	# ============================================
	_depth_defs[7] = {
		"new_title": "Dread",
		"desc": "Fear manifests. Not all dangers are real.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.28,
			"progress_mul": 1.0,
			"mem_mul": 1.30,
			"cry_mul": 1.18,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 35.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"reality_check": {
				"name": "Reality Check",
				"description": "15% chance to ignore fake threats per level",
				"max_level": 999999,
				"base_cost": 450.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"adrenaline_mining": {
				"name": "Adrenaline Mining",
				"description": "+20% Thoughts during fake threats per level",
				"max_level": 999999,
				"base_cost": 500.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"true_fear": {
				"name": "True Fear",
				"description": "Real threats deal 12% less Instability per level",
				"max_level": 4,
				"base_cost": 400.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"paranoia_shield": {
				"name": "Paranoia Shield",
				"description": "+0.2 Max Control per level",
				"max_level": 999999,
				"base_cost": 300.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.2,
				"cost_currency": "thoughts"
			},
			"dread_immunity": {
				"name": "Dread Immunity",
				"description": "First real threat per run is negated",
				"max_level": 1,
				"base_cost": 1200.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
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
	# DEPTH 8 — CHASM (Speed synergy - 5 upgrades)
	# ============================================
	_depth_defs[8] = {
		"new_title": "Chasm",
		"desc": "A vast drop. Your journey strengthens your step.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.28,
			"progress_mul": 1.0,
			"mem_mul": 1.35,
			"cry_mul": 1.20,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"momentum_cascade": {
				"name": "Momentum Cascade",
				"description": "+5% Progress per frozen depth per level",
				"max_level": 999999,
				"base_cost": 600.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.05,
				"cost_currency": "thoughts"
			},
			"gravity_slingshot": {
				"name": "Gravity Slingshot",
				"description": "Auto-progress +3%/sec, but +12% Instability",
				"max_level": 3,
				"base_cost": 800.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.03,
				"cost_currency": "thoughts"
			},
			"void_breathing": {
				"name": "Void Breathing",
				"description": "+12% Control Generation per level",
				"max_level": 999999,
				"base_cost": 480.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"diamond_focus": {
				"name": "Diamond Focus",
				"description": "+15% Diamond Crystals per level",
				"max_level": 999999,
				"base_cost": 720.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"weightless": {
				"name": "Weightless",
				"description": "Progress unaffected by Instability slowdowns",
				"max_level": 1,
				"base_cost": 2000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
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
	# DEPTH 9 — SILENCE (Blind mode - 5 upgrades)
	# ============================================
	_depth_defs[9] = {
		"new_title": "Silence",
		"desc": "Sound dies. You must feel your way forward.",
		"ui_unlocks": ["hidden_numbers"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.28,
			"progress_mul": 1.0,
			"mem_mul": 1.40,
			"cry_mul": 1.22,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 25.0,
			"hide_all_numbers": true,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"inner_eye": {
				"name": "Inner Eye",
				"description": "Unlock UI: Lv1=Thoughts, Lv2=Instability, Lv3=Progress, Lv4=Crystals",
				"max_level": 4,
				"base_cost": 900.0,
				"cost_growth": 2.5,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"blind_intuition": {
				"name": "Blind Intuition",
				"description": "+10% all gains while numbers hidden per level",
				"max_level": 999999,
				"base_cost": 700.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"silent_running": {
				"name": "Silent Running",
				"description": "-0.08% Instability/sec while blind per level",
				"max_level": 4,
				"base_cost": 850.0,
				"cost_growth": 1.9,
				"effect_per_level": -0.08,
				"cost_currency": "thoughts"
			},
			"aquamarine_focus": {
				"name": "Aquamarine Focus",
				"description": "+18% Aquamarine Crystals per level",
				"max_level": 999999,
				"base_cost": 1080.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.18,
				"cost_currency": "thoughts"
			},
			"trust_the_void": {
				"name": "Trust the Void",
				"description": "At max level, numbers stay hidden but +20% all gains permanently",
				"max_level": 1,
				"base_cost": 3000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
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
	# DEPTH 10 — VEIL (Random outcomes - 5 upgrades)
	# ============================================
	_depth_defs[10] = {
		"new_title": "Veil",
		"desc": "Truth and lie intertwine. Choose wisely, or don't.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.35,
			"progress_mul": 1.0,
			"mem_mul": 1.45,
			"cry_mul": 1.25,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"probability_anchor": {
				"name": "Probability Anchor",
				"description": "Reduce random variance by 8% per level",
				"max_level": 999999,
				"base_cost": 960.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"veil_piercing": {
				"name": "Veil Piercing",
				"description": "See exact outcomes before choosing",
				"max_level": 1,
				"base_cost": 5000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"chaos_tax": {
				"name": "Chaos Tax",
				"description": "+15% Thoughts, outcomes 25% more random",
				"max_level": 999999,
				"base_cost": 1200.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"order_from_chaos": {
				"name": "Order from Chaos",
				"description": "Every 3rd choice is guaranteed positive",
				"max_level": 1,
				"base_cost": 2500.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"astral_logic": {
				"name": "Astral Logic",
				"description": "+12% Topaz Crystals, choices slightly favor good outcomes",
				"max_level": 999999,
				"base_cost": 1440.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.12,
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
	# DEPTH 11 — RUIN (Loss risk - 5 upgrades)
	# ============================================
	_depth_defs[11] = {
		"new_title": "Ruin",
		"desc": "What was built crumbles. The past is not forever.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.35,
			"progress_mul": 1.0,
			"mem_mul": 1.50,
			"cry_mul": 1.28,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 25.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"reinforced_anchors": {
				"name": "Reinforced Anchors",
				"description": "25% chance to resist bonus loss per level",
				"max_level": 999999,
				"base_cost": 1500.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"scavengers_luck": {
				"name": "Scavenger's Luck",
				"description": "Gain +20% Crystals when bonuses are 'ruined' per level",
				"max_level": 999999,
				"base_cost": 1200.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"entropy_shield": {
				"name": "Entropy Shield",
				"description": "Immune to bonus loss, -0.05% Instability/sec",
				"max_level": 1,
				"base_cost": 4000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"ruin_diver": {
				"name": "Ruin Diver",
				"description": "+18% Garnet Crystals per level",
				"max_level": 999999,
				"base_cost": 1000.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.18,
				"cost_currency": "thoughts"
			},
			"phoenix_protocol": {
				"name": "Phoenix Protocol",
				"description": "If all bonuses lost, gain +80% Thoughts for 60s",
				"max_level": 1,
				"base_cost": 3500.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "collapse",
				"trigger": "timer",
				"cooldown": 25.0,
				"effect_on_trigger": {"lose_frozen_depth": -2},
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
	# DEPTH 12 — ECLIPSE (Mirror danger - 5 upgrades)
	# ============================================
	_depth_defs[12] = {
		"new_title": "Eclipse",
		"desc": "Your shadow acts. Every move echoes dangerously.",
		"ui_unlocks": ["shadow_clone"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.35,
			"progress_mul": 1.0,
			"mem_mul": 1.55,
			"cry_mul": 1.30,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 20.0,
			"shadow_clone_enabled": true,
			"shadow_delay": 5.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"shadow_sync": {
				"name": "Shadow Sync",
				"description": "Clone efficiency +10% per level",
				"max_level": 999999,
				"base_cost": 2250.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"dark_twin": {
				"name": "Dark Twin",
				"description": "Clone generates 8% of your Thoughts per level",
				"max_level": 999999,
				"base_cost": 1800.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"eclipse_phase": {
				"name": "Eclipse Phase",
				"description": "Clone absorbs 12% of Instability per level",
				"max_level": 4,
				"base_cost": 2000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"mirror_pool": {
				"name": "Mirror Pool",
				"description": "Clone also generates 4% of Crystals per level",
				"max_level": 999999,
				"base_cost": 2700.0,
				"cost_growth": 1.9,
				"effect_per_level": 0.04,
				"cost_currency": "thoughts"
			},
			"umbral_burst": {
				"name": "Umbral Burst",
				"description": "Every 60s, clone grants instant 6% Progress",
				"max_level": 1,
				"base_cost": 6000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
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
	# DEPTH 13 — VOIDLINE (Passive drain - 5 upgrades)
	# ============================================
	_depth_defs[13] = {
		"new_title": "Voidline",
		"desc": "The edge of existence. The void hungers constantly.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.45,
			"progress_mul": 1.0,
			"mem_mul": 1.60,
			"cry_mul": 1.35,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_type": "passive",
			"void_drain_chance": 0.01,
			"void_drain_amount": 0.05,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"void_anchor": {
				"name": "Void Anchor",
				"description": "Reduce drain chance by 0.1%/sec per level",
				"max_level": 999999,
				"base_cost": 3375.0,
				"cost_growth": 1.7,
				"effect_per_level": -0.001,
				"cost_currency": "thoughts"
			},
			"tether_line": {
				"name": "Tether Line",
				"description": "25% chance to recover drained progress per level",
				"max_level": 999999,
				"base_cost": 2700.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"embrace_the_void": {
				"name": "Embrace the Void",
				"description": "+60% all gains, drain chance becomes 4%",
				"max_level": 1,
				"base_cost": 8000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"onyx_focus": {
				"name": "Onyx Focus",
				"description": "+20% Onyx Crystals per level",
				"max_level": 999999,
				"base_cost": 4050.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"null_field": {
				"name": "Null Field",
				"description": "First 30s of each depth immune to drain",
				"max_level": 1,
				"base_cost": 5000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	# ============================================
	# DEPTH 14 — BLACKWATER (Crystal carryover - 5 upgrades)
	# ============================================
	_depth_defs[14] = {
		"new_title": "Blackwater",
		"desc": "Dark tides rise. What you gain here stains the next.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.45,
			"progress_mul": 1.0,
			"mem_mul": 1.65,
			"cry_mul": 1.38,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 20.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"crystal_memory": {
				"name": "Crystal Memory",
				"description": "Carry +6% of this depth's Crystals to next run per level",
				"max_level": 999999,
				"base_cost": 5000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.06,
				"cost_currency": "thoughts"
			},
			"resonance": {
				"name": "Resonance",
				"description": "All depths generate +3% Crystals this run per level",
				"max_level": 999999,
				"base_cost": 4000.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.03,
				"cost_currency": "thoughts"
			},
			"blackwater_breathing": {
				"name": "Blackwater Breathing",
				"description": "-0.1% Instability/sec per level",
				"max_level": 3,
				"base_cost": 7500.0,
				"cost_growth": 2.0,
				"effect_per_level": -0.1,
				"cost_currency": "thoughts"
			},
			"abyssal_tribute": {
				"name": "Abyssal Tribute",
				"description": "+20% Jade Crystals, but 5% sacrificed to the deep",
				"max_level": 3,
				"base_cost": 6000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"permanent_record": {
				"name": "Permanent Record",
				"description": "Wake grants +2% of total run Crystals as bonus",
				"max_level": 1,
				"base_cost": 10000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
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
	# DEPTH 15 — ABYSS (Final test - 5 upgrades)
	# ============================================
	_depth_defs[15] = {
		"new_title": "Abyss",
		"desc": "The final threshold. All trials converge here.",
		"ui_unlocks": ["abyss_challenge"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 0.45,
			"progress_mul": 1.0,
			"mem_mul": 1.70,
			"cry_mul": 1.45,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 15.0,
			"abyss_extra_instability": 2.0,
			"random_event_pool": ["echo", "paranoia", "narrow_ledge", "the_hush", "truth_false", "collapse", "shadow_self", "tide"],
			"dive_unlock_requirement": {"upgrade": "stab", "level": 5}
		},
		"upgrades": {
			"abyssal_will": {
				"name": "Abyssal Will",
				"description": "+1% resistance to all negative effects per level",
				"max_level": 999999,
				"base_cost": 7500.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.01,
				"cost_currency": "thoughts"
			},
			"depth_mastery": {
				"name": "Depth Mastery",
				"description": "+25% Thoughts, Memories, Crystals per level",
				"max_level": 999999,
				"base_cost": 6000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"final_anchor": {
				"name": "Final Anchor",
				"description": "-0.15% Instability/sec (costs 10x more)",
				"max_level": 999999,
				"base_cost": 6480.0,
				"cost_growth": 1.4,
				"effect_per_level": -0.15,
				"cost_currency": "thoughts"
			},
			"cosmic_horror": {
				"name": "Cosmic Horror",
				"description": "All previous depth upgrades active at 25% effect",
				"max_level": 1,
				"base_cost": 15000.0,
				"cost_growth": 1.0,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"transcendence": {
				"name": "Transcendence",
				"description": "Gain ability to 'Sleep' (second prestige layer)",
				"max_level": 1,
				"base_cost": 50000.0,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
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

	var inst_enabled := bool(rules.get("instability_enabled", false))
	
	var base_inst_ps: float = 0.0
	match d:
		2: base_inst_ps = 0.12
		3: base_inst_ps = 0.15
		4: base_inst_ps = 0.18
		5: base_inst_ps = 0.22
		6, 7, 8, 9: base_inst_ps = 0.28
		10, 11, 12: base_inst_ps = 0.35
		13, 14, 15: base_inst_ps = 0.45
		_: base_inst_ps = 0.0
	
	# APPLY STABILIZER UPGRADE (Depth 2)
	if d == 2:
		var stabilizer_level := _get_local_level(d, "stabilize")
		if stabilizer_level > 0:
			var def_data: Dictionary = def.get("upgrades", {}).get("stabilize", {})
			var effect_per_level: float = def_data.get("effect_per_level", -0.05)
			base_inst_ps += (effect_per_level * stabilizer_level)  # effect is negative
			base_inst_ps = maxf(0.01, base_inst_ps)  # Floor at 0.01 so it never goes negative
	
	# APPLY PRESSURE HARDENING (Depth 3) - reduces slowdown from pressure
	var prog_mul := float(rules.get("progress_mul", 1.0))
	if rules.has("pressure_threshold") and float(instability) >= float(rules.get("pressure_threshold")):
		var pressure_slow: float = float(rules.get("pressure_slow_mul", 0.6))
		# Pressure Hardening reduces the penalty
		var hardening_level := _get_local_level(d, "pressure_hardening")
		if hardening_level > 0:
			var hardening_def: Dictionary = def.get("upgrades", {}).get("pressure_hardening", {})
			var hardening_effect: float = hardening_def.get("effect_per_level", 0.10)
			# Restore progress speed: 0.6 + (0.1 * level), capped at 1.0
			pressure_slow = minf(1.0, pressure_slow + (hardening_effect * hardening_level))
		prog_mul *= pressure_slow

	var mem_mul := float(rules.get("mem_mul", 1.0))
	var cry_mul := float(rules.get("cry_mul", 1.0))
	
	# APPLY CRUSH RESISTANCE (Depth 3) - reduces instability gain
	if d == 3:
		var crush_level := _get_local_level(d, "crush_resistance")
		if crush_level > 0:
			var crush_def: Dictionary = def.get("upgrades", {}).get("crush_resistance", {})
			var crush_effect: float = crush_def.get("effect_per_level", -0.04)
			base_inst_ps += (crush_effect * crush_level)
			base_inst_ps = maxf(0.01, base_inst_ps)

	instability_per_sec = base_inst_ps if inst_enabled else 0.0
	
	return {
		"instability_per_sec": base_inst_ps,
		"progress_mul": prog_mul,
		"mem_mul": mem_mul,
		"cry_mul": cry_mul,
		"rules": rules
	}

func _tick_depth_events(d: int, delta: float, rules: Dictionary) -> void:
	_ensure_depth_runtime(d)
	var rt: Dictionary = _depth_runtime[d]
	rt["time_in_depth"] = float(rt.get("time_in_depth", 0.0)) + delta
	
	# Handle choice events
	if rules.get("event_enabled", false) and rules.has("event_timer"):
		var interval := float(rules.get("event_timer", 30.0))
		_current_event_timer += delta
		
		if _current_event_timer >= interval:
			_current_event_timer = 0.0
			
			# Pick event from depth's event pool
			var def: Dictionary = get_depth_def(d)
			var events: Array = def.get("events", [])
			
			if events.size() > 0:
				# For now, just fire first event (or random for Abyss)
				var evt: Dictionary = events[0]
				if evt.get("random_from_pool", false) and d == 15:
					# Abyss logic: pick random from previous depths
					evt = _get_random_abyss_event()
				
				_fire_depth_event(d, evt.get("id", ""))
	
	_depth_runtime[d] = rt

func _fire_depth_event(depth_index: int, event_id: String) -> void:
	var def: Dictionary = get_depth_def(depth_index)
	var events: Array = def.get("events", [])
	
	# Find matching event
	for evt in events:
		if evt.get("id") == event_id:
			_active_event = evt
			if choice_modal != null:
				choice_modal.show_event(evt, def)
			return
	
	# Fallback for undefined events (backward compat)
	if event_id == "rift_choice":
		var spike := 4.0 + float(depth_index) * 0.5
		instability = clampf(instability + spike, 0.0, 100.0)


func _on_depth_changed(new_depth: int) -> void:
	_ensure_depth_runtime(new_depth)
	_depth_runtime[new_depth]["time_in_depth"] = 0.0
	_depth_runtime[new_depth]["next_choice_t"] = 0.0
	# Does this reset progress? It shouldn't!

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
		var data: Dictionary = _run_internal[d - 1]
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
	
func get_run_upgrade_ids(depth_index: int) -> Array[String]:
	"""Returns list of upgrade IDs for a specific depth (e.g., ["stabilize", "controlled_fall", ...])"""
	var def: Dictionary = get_depth_def(depth_index)
	var upgrades: Dictionary = def.get("upgrades", {})
	var ids: Array[String] = []
	for key in upgrades.keys():
		ids.append(key)
	return ids

func get_run_upgrade_data(depth_index: int, upgrade_id: String) -> Dictionary:
	"""Returns full upgrade definition including name, cost, effects"""
	var def: Dictionary = get_depth_def(depth_index)
	var upgrades: Dictionary = def.get("upgrades", {})
	var upg: Dictionary = upgrades.get(upgrade_id, {})
	
	return {
		"id": upgrade_id,
		"name": upg.get("name", upgrade_id.capitalize().replace("_", " ")),
		"description": upg.get("description", ""),
		"max_level": upg.get("max_level", 1),
		"base_cost": upg.get("base_cost", 100.0),
		"cost_growth": upg.get("cost_growth", 1.5),
		"effect_per_level": upg.get("effect_per_level", 0.0),
		"cost_currency": upg.get("cost_currency", "thoughts")
	}

func _get_random_abyss_event() -> Dictionary:
	var pool := ["flicker", "the_choice", "echo_event", "paranoia", "narrow_ledge", "the_hush", "truth_false", "collapse", "shadow_self", "tide"]
	var random_id: String = pool[randi() % pool.size()]
	
	# Find the event def from previous depths
	for d in range(1, 15):
		var def: Dictionary = get_depth_def(d)
		for evt in def.get("events", []):
			if evt.get("id") == random_id:
				return evt
	return {}

func get_run_thoughts_mult() -> float:
	"""Calculate total thought generation multiplier from all purchased run upgrades"""
	var total_mult := 1.0
	
	# Sum up progress_speed upgrades from all depths (Lucid Training, etc.)
	for depth_idx in range(1, max_depth + 1):
		var local_upgs := local_upgrades.get(depth_idx, {}) as Dictionary
		var speed_lvl := int(local_upgs.get("progress_speed", 0))
		
		if speed_lvl > 0:
			# Get the effect per level from depth definition
			var def := get_depth_def(depth_idx)
			var upgrades := def.get("upgrades", {}) as Dictionary
			var progress_upg := upgrades.get("progress_speed", {}) as Dictionary
			var effect_per_level := float(progress_upg.get("effect_per_level", 0.25))
			
			total_mult += float(speed_lvl) * effect_per_level
	
	return total_mult

# In DepthRunController.gd
func get_run_control_mult() -> float:
	# If you have control upgrades, add them here
	return 1.0

func get_run_instability_reduction() -> float:
	# If you have stability upgrades that reduce instability
	return 1.0
