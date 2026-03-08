extends Node

@export var max_depth: int = 15
@export var base_memories_per_sec: float = 2.0
@export var base_crystals_per_sec: float = 1.0

# top panel base rates (tune later)
@export var thoughts_per_sec: float = 0.0
@export var dreamcloud_per_sec: float = 0.0
@export var instability_per_sec: float = 0.0

@export var base_progress_per_sec: float = 1 # 1/1200 = 0.000833 (20 min base)
@export var depth_length_growth: float = 1.25        # Gentler curve
@export var length_curve_power: float = 1.05         # Softer power curve

@export var dev_unlock_all_depths: bool = true
@export var dev_start_depth: int = 1

var choice_modal: ChoiceModal = null
#var _current_event_timer: float = 0.0
var _active_event: Dictionary = {}
var auto_dive_enabled: bool = false  # Player toggles this via checkbox
var _thoughts_per_sec_cached: float = 0.0
var _dreamcloud_per_sec_cached: float = 0.0

var active_depth: int = 1
var max_unlocked_depth: int = 1
var _run_internal: Array[Dictionary] = []
signal auto_dive_triggered(depth_index: int)  # CRITICAL: For panel closure
var _rift_event_active: bool = false
var _temp_buffs: Dictionary = {}  # Tracks temporary multipliers like "risky choice memory boost"

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
var dreamcloud: float = 0.0
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
	
	# CRITICAL: Connect the signal if not already connected
	if not choice_modal.choice_made.is_connected(_on_rift_choice_resolved):
		choice_modal.choice_made.connect(_on_rift_choice_resolved)

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
	# Check for death/fail when instability hits the cap (only depth 2+)
	if active_depth >= 2:
		var game_mgr = get_node_or_null("/root/GameManager")
		var actual_cap := 1000.0
		if game_mgr != null and game_mgr.depth_meta_system != null:
			actual_cap = game_mgr.depth_meta_system.get_instability_cap(active_depth)
		
		if instability >= actual_cap:
			wake_cashout(1.0, true)
			return
	
# Call this for the active depth (make sure this is OUTSIDE any if blocks that might skip it)
	if active_depth >= 4:
		var def = get_depth_def(active_depth)
		var rules = def.get("rules", {})
		if rules.get("event_enabled", false):
			_tick_depth_events(active_depth, delta, rules)
			
	# CRITICAL FIX: Auto-Dive Check (moved outside depth 2+ block, runs for all depths)
	_check_auto_dive()

	var shop = get_node_or_null("/root/Main/MainUI/Root/MetaPanel/Window/RootVBox/PetaPages/AbyssPage")
	if shop and shop.has_method("is_item_active"):
		if shop.is_item_active("auto_dive"):
			# Calculate progress percentage
			var progress_percent: float = 0.0
			if active_depth >= 1 and active_depth <= _run_internal.size():
				var data: Dictionary = _run_internal[active_depth - 1]
				var current: float = float(data.get("progress", 0.0))
				var cap: float = get_depth_progress_cap(active_depth)
				progress_percent = (current / cap) * 100.0 if cap > 0 else 0.0
				
					# Check auto-dive using GameManager (consolidated check)
				var gm_check = get_node_or_null("/root/Main/GameManager")
				if gm_check.has_auto_dive_enabled() and progress_percent >= 99.9 and can_dive():
					print("Auto-diving from depth ", active_depth)
					
					# CRITICAL FIX: Close ALL depth bars
					var panel = get_tree().current_scene.find_child("DepthBarsPanel", true, false)
					if panel:
						if panel.has_method("close_all_expanded"):
							panel.call("close_all_expanded")
						elif panel.has_method("set_expanded_depth"):
							panel.call("set_expanded_depth", -1)
					
					# Also notify any open rows to close
					for row in get_tree().current_scene.find_children("DepthBarRow*", "PanelContainer", true):
						if row.has_method("set_details_open"):
							row.call("set_details_open", false)
					
					dive()


func _check_auto_dive() -> void:
	# Get GameManager reference
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm == null or not gm.has_method("has_auto_dive_enabled"):
		return
	
	# Check if player owns and has enabled auto-dive
	if not gm.has_auto_dive_enabled():
		return
	
	# Verify we have valid run data
	if active_depth < 1 or active_depth > _run_internal.size():
		return
	
	var data: Dictionary = _run_internal[active_depth - 1]
	var current_progress: float = float(data.get("progress", 0.0))
	var cap: float = get_depth_progress_cap(active_depth)
	
	if cap <= 0:
		return
	
	# CRITICAL FIX: Use 99.9% threshold to avoid floating point precision issues
	var progress_percent: float = (current_progress / cap) * 100.0
	if progress_percent < 99.9:
		return
	
	# Check if we can actually dive
	if not can_dive():
		return
	
	# CRITICAL FIX: Add small cooldown to prevent multiple rapid dives
	if not has_meta("last_auto_dive_time"):
		set_meta("last_auto_dive_time", 0.0)
	
	var last_dive: float = float(get_meta("last_auto_dive_time"))
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - last_dive < 2.0:  # 2 second cooldown
		return
	
	# Execute dive
	print("Auto-diving from depth ", active_depth, " (progress: ", progress_percent, "%)")
	set_meta("last_auto_dive_time", now)
	
	# CRITICAL FIX: Emit signal for panel closure BEFORE diving
	auto_dive_triggered.emit(active_depth)
	
	dive()
	
func _tick_active_depth(delta: float) -> void:
	if has_meta("progress_paused") and get_meta("progress_paused"):
		return
		
	var d: int = active_depth
	if d < 1 or d > _run_internal.size():
		return
	
	# Track time in depth
	_ensure_depth_runtime(d)
	var rt: Dictionary = _depth_runtime[d]
	rt["time_in_depth"] = rt.get("time_in_depth", 0.0) + delta
	_depth_runtime[d] = rt
	
	# Get depth rules
	var applied := _apply_depth_rules(d)
	
	# CRITICAL: Update class variables for TopBarPanel to read
	instability_per_sec = applied.get("instability_per_sec", 0.0)
	var depth_prog_mul := float(applied.get("progress_mul", 1.0))
	var depth_mem_mul := float(applied.get("mem_mul", 1.0))
	var depth_cry_mul := float(applied.get("cry_mul", 1.0))
	var inst_cap: float = applied.get("instability_cap", 1000.0)
	var rules: Dictionary = applied.get("rules", {})
	
	# CRITICAL FIX: Apply instability increase
	if d >= 2 and rules.get("instability_enabled", false):
		var inst_per_sec: float = applied.get("instability_per_sec", 0.0)
		
		# THIS LINE WAS MISSING - actually add to instability
		instability += (inst_per_sec * delta)
		
		# Check for death
		if instability >= inst_cap:
			instability = inst_cap
			wake_cashout(1.0, true)  # Force wake
			return
			
	var current_time := Time.get_ticks_msec() / 1000.0
	
	# Rate-limited debug (once per second)
	var should_print := (current_time - _last_debug_print_time) >= 1.0
	
	if d < 1 or d > _run_internal.size():
		return
		
	var data: Dictionary = _run_internal[d - 1]
	var current_progress: float = float(data.get("progress", 0.0))
	
	_last_progress_value = current_progress
	
	# Only print normal updates once per second
	if d == 1 and should_print:
		_last_debug_print_time = current_time
	
	if _panel == null:
		return

	# Apply per-depth rules (sets instability_per_sec, returns muls)
	var _rules: Dictionary = applied.get("rules", {})

	# DREAM CURRENT SYSTEM: Fetch global progress rate from GameManager
	var gm = get_node_or_null("/root/Main/GameManager")
	var dream_current: float = 1.0
	if gm and "dream_current" in gm:
		dream_current = gm.dream_current

	# Apply Echo Navigation (Depth 4 progress speed upgrade)
	if d == 4:
		var echo_lvl := _get_local_level(d, "echo_navigation")
		if echo_lvl > 0:
			var echo_def: Dictionary = get_depth_def(d).get("upgrades", {}).get("echo_navigation", {})
			var echo_effect: float = echo_def.get("effect_per_level", 0.12)
			dream_current *= (1.0 + (echo_effect * echo_lvl))  # +12% per level

	# LENGTH / DIFFICULTY - USE DREAM CURRENT
	var length: float = get_depth_length(d)
	var per_sec: float = (base_progress_per_sec * dream_current * depth_prog_mul) / maxf(length, 0.0001)
	
	# Multipliers for Memories/Crystals (progress uses dream_current instead)
	var mem_lvl := _get_local_level(d, "memories_gain")
	var cry_lvl := _get_local_level(d, "crystals_gain")

	# Get the specific crystal focus for this depth (e.g., "ruby_focus", "emerald_focus", "sapphire_focus")
	var crystal_focus_id := ""
	match d:
		2: crystal_focus_id = "ruby_focus"
		3: crystal_focus_id = "emerald_focus"
		4: crystal_focus_id = "sapphire_focus"
		5: crystal_focus_id = "diamond_focus"  # if you have this

	var crystal_focus_lvl := _get_local_level(d, crystal_focus_id)

	var mem_mul: float = 1.0 + (0.15 * mem_lvl) + _frozen_effect(d, "memories_gain", 0.15)
	var cry_mul: float = 1.0 + (0.12 * cry_lvl) + _frozen_effect(d, "crystals_gain", 0.12)

	# Add crystal focus bonus
	if crystal_focus_lvl > 0 and crystal_focus_id != "":
		var focus_def: Dictionary = get_depth_def(d).get("upgrades", {}).get(crystal_focus_id, {})
		var focus_effect: float = focus_def.get("effect_per_level", 0.15)  # Default 15%
		cry_mul += (focus_effect * crystal_focus_lvl)

	# Then apply to crystal generation:
	data["crystals"] = float(data.get("crystals", 0.0)) + base_crystals_per_sec * cry_mul * depth_cry_mul * delta
	
	var game_mgr := get_node_or_null("/root/GameManager")
	var abyss_mult: float = 1.0
	if game_mgr != null and game_mgr.has_method("get_abyss_multiplier"):
		abyss_mult = game_mgr.get_abyss_multiplier()

	mem_mul *= abyss_mult
	cry_mul *= abyss_mult
	# Apply specific depth upgrade bonuses
	
	# Depth 2: Ruby Focus (+12% rubies per level)
	if d == 2:
		var ruby_level := _get_local_level(d, "ruby_focus")
		if ruby_level > 0:
			var ruby_def: Dictionary = get_depth_def(d).get("upgrades", {}).get("ruby_focus", {})
			var ruby_effect: float = ruby_def.get("effect_per_level", 0.12)
			cry_mul += (ruby_effect * ruby_level)

	# CRITICAL FIX: Use actual cap instead of hardcoded 1.0
	var cap: float = get_depth_progress_cap(d)
	var p: float = float(data.get("progress", 0.0))
	p = minf(cap, p + per_sec * delta)  # Use the actual cap (1000, 2500, etc.)
	data["progress"] = p

	# Update memories and crystals
	data["memories"] = float(data.get("memories", 0.0)) + base_memories_per_sec * mem_mul * depth_mem_mul * delta
	data["crystals"] = float(data.get("crystals", 0.0)) + base_crystals_per_sec * cry_mul * depth_cry_mul * delta
	
	_run_internal[d - 1] = data
	
	# Make sure to pass the calculated instability rate to the HUD
	thoughts_per_sec = _calculate_thoughts_per_sec(d)
	dreamcloud_per_sec = _calculate_dreamcloud_per_sec(d)
	instability_per_sec = applied.get("instability_per_sec", 0.0)
	
	# Update panel
	_panel.set_row_data(d, data)
	_panel.set_active_depth(active_depth)

func _calculate_thoughts_per_sec(d: int) -> float:
	var base: float = 1.0
	var multipliers: float = 1.0
	
	# Depth scaling (exponential growth for big numbers)
	multipliers *= pow(1.5, d - 1)
	
	# Apply frozen upgrade bonuses
	for depth_key in frozen_upgrades.keys():
		var source_depth: int = int(depth_key)
		if source_depth >= d:
			continue
		var dct: Dictionary = frozen_upgrades[depth_key]
		# Velocity/Progress speed from frozen depths
		var frozen_speed_lvl: int = int(dct.get("progress_speed", 0))
		if frozen_speed_lvl > 0:
			multipliers += (frozen_speed_lvl * 0.2)
	
	# Apply current depth local upgrades
	var local: Dictionary = local_upgrades.get(d, {})
	var speed_lvl: int = int(local.get("progress_speed", 0))
	if speed_lvl > 0:
		multipliers += (speed_lvl * 0.25)  # +25% per level in current depth
	
	# Meta multipliers from GameManager
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm:
		if gm.has_method("get_thoughts_mult"):
			multipliers *= gm.get_thoughts_mult()
		if gm.has_method("get_abyss_multiplier"):
			multipliers *= gm.get_abyss_multiplier()
	
	return base * multipliers

func _calculate_dreamcloud_per_sec(_d: int) -> float:
	# Minimal passive generation - Dreamcloud is now primarily from clicks/combat
	var base: float = 0.05  # Very small passive gain
	return base * (1.0 + (_d * 0.02))  # Slight scaling with depth

func get_dreamcloud_per_sec() -> float:
	return _calculate_dreamcloud_per_sec(active_depth)
	
func add_local_upgrade(depth_index: int, upgrade_id: String, amount: int = 1) -> void:
	if depth_index != active_depth:
		return
	if not local_upgrades.has(depth_index):
		local_upgrades[depth_index] = {}
	var dct: Dictionary = local_upgrades[depth_index]
	dct[upgrade_id] = int(dct.get(upgrade_id, 0)) + amount
	local_upgrades[depth_index] = dct
	
	# DREAM CURRENT HOOKS - Add effects here
	var game_mgr = get_node_or_null("/root/Main/GameManager")
	if game_mgr and game_mgr.has_method("buy_dream_current_upgrade"):
		
		# Standard progress_speed adds +0.2
		if upgrade_id == "progress_speed":
			game_mgr.buy_dream_current_upgrade(0.2 * amount)
		
		# Depth 2: dreamcloudled Fall adds +0.1 per level
		elif upgrade_id == "dreamcloudled_fall":
			var current_dc = game_mgr.dream_current
			var bonus = 0.1 * amount
			game_mgr.dream_current = current_dc * (1.0 + bonus)  # Multiplicative: 1.0 -> 1.1 -> 1.21 etc
		
		# Add other depth-specific upgrades here as needed
		# elif upgrade_id == "ruby_focus":
		# 	pass  # Ruby focus affects crystals, not speed
	
	if _panel != null:
		_panel.request_refresh_details(depth_index)
		
func can_transcend() -> bool:
	if active_depth != 15:
		return false
	var progress: float = float(_run_internal[14].get("progress", 0.0))
	var cap: float = get_depth_progress_cap(15)
	return progress >= cap * 0.999

func perform_transcendence() -> Dictionary:
	if not can_transcend():
		return {"success": false}
	
	_init_run()
	active_depth = 1
	_last_depth = 1
	local_upgrades.clear()
	local_upgrades[1] = {}
	_sync_all_to_panel()
	
	return {"success": true, "new_depth": 1}
	
func _tick_top(delta: float) -> void:
	# Only thoughts should generate passively
	var tps: float = thoughts_per_sec
	thoughts += tps * delta
	
	# CRITICAL: Set dreamcloud to 0 - only Combat Focus clicks generate it
	_dreamcloud_per_sec_cached = 0.0
	_thoughts_per_sec_cached = tps

func get_depth_progress_cap(depth: int) -> float:
	# NEW: Exponential scaling for 250-300 hour target
	return 1000.0 * pow(2.8, float(depth - 1))

func _sync_hud() -> void:
	if _hud != null and _hud.has_method("set_values"):
		# Use cached values (they represent what we applied this frame)
		_hud.call("set_values", thoughts, _thoughts_per_sec_cached, dreamcloud, _dreamcloud_per_sec_cached, instability)


func can_dive() -> bool:
	# Can't dive past max depth
	if active_depth < 1 or active_depth >= max_depth:
		return false
	
	# CRITICAL FIX: For depth 1, allow dive at 100% progress regardless of other requirements
	if active_depth == 1:
		var current_progress: float = float(_run_internal[0].get("progress", 0.0))
		var cap: float = get_depth_progress_cap(1)
		if current_progress >= cap * 0.999:  # 99.9% complete
			return true
	
	# Check if next depth is unlocked in meta progression
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	var meta_unlocked := false
	if meta != null and meta.has_method("is_depth_unlocked"):
		meta_unlocked = meta.call("is_depth_unlocked", active_depth + 1)
	else:
		meta_unlocked = active_depth < max_unlocked_depth
	
	if not meta_unlocked:
		return false
	
	# Check depth-specific META upgrade requirements
	var def: Dictionary = get_depth_def(active_depth)
	var rules: Dictionary = def.get("rules", {})
	var dive_req = rules.get("dive_unlock_requirement", null)
	
	if dive_req != null:
		var req_upgrade: String = dive_req.get("upgrade", "")
		var req_level: int = dive_req.get("level", 0)
		
		if req_upgrade != "":
			var current_level: int = 0
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
	# At Depth 15, trigger transcendence instead
	if active_depth == 15:
		if can_transcend():
			var game_mgr := get_node_or_null("/root/GameManager")
			if game_mgr != null and game_mgr.has_method("prompt_transcendence"):
				game_mgr.prompt_transcendence()
		return false
	
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

func get_instability_cap(depth: int) -> float:
	# Scale with progress cap (120% of progress required)
	return get_depth_progress_cap(depth) * 1.2

func get_depth_length(depth_index: int) -> float:
	var d: float = float(max(depth_index, 1))
	return pow(depth_length_growth, pow(d - 1.0, length_curve_power))


func wake_cashout(ad_multiplier: float, forced: bool) -> Dictionary:
	print("WAKE_CASHOUT called - forced:", forced, " depth:", active_depth)
	
	var thoughts_mult: float = 1.0
	var memories_mult: float = 1.0
	var crystals_mult: float = 1.0
	
	if forced:
		thoughts_mult = 0.70
		memories_mult = 0.55
		crystals_mult = 0.40
	
	# Calculate gains
	var totals := _sum_run_totals(active_depth)
	var bank_thoughts: float = float(thoughts) * thoughts_mult * ad_multiplier
	var bank_memories: float = float(totals["memories"]) * memories_mult * ad_multiplier
	
	# Bank the currencies
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm:
		if "memories" in gm: gm.memories += bank_memories
		# Add crystals to meta
		var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
		if meta and meta.has_method("add_currency"):
			for depth_i in range(1, active_depth + 1):
				var data: Dictionary = _run_internal[depth_i - 1]
				var raw_cry := float(data.get("crystals", 0.0))
				var bank_cry := raw_cry * crystals_mult * ad_multiplier
				if bank_cry > 0.0:
					meta.call("add_currency", depth_i, bank_cry)
	
	# CRITICAL: FULL RESET
	_reset_run_data()
	
	return {
		"thoughts": bank_thoughts,
		"memories": bank_memories,
		"forced": forced
	}

func _reset_run_data() -> void:
	print("RESETTING RUN DATA")
	
	# Reset all progress
	for i in range(_run_internal.size()):
		var data: Dictionary = _run_internal[i]
		data["progress"] = 0.0
		data["memories"] = 0.0
		data["crystals"] = 0.0
		_run_internal[i] = data
	
	# CRITICAL: Clear local upgrades (this was missing!)
	local_upgrades.clear()
	local_upgrades[1] = {}  # Start fresh at depth 1
	
	# Clear frozen upgrades
	frozen_upgrades.clear()
	
	# Reset currencies
	thoughts = 0.0
	dreamcloud = 0.0
	instability = 0.0
	
	# Reset depth
	active_depth = 1
	max_unlocked_depth = 1
	_last_depth = active_depth
	
	# Sync
	_sync_all_to_panel()
	_sync_hud()
	
	print("Reset complete: active_depth=", active_depth, " local_upgrades=", local_upgrades)

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

func get_upgrade_cost(depth: int, tier: int, level: int) -> float:
	# tier 0-5 (6 upgrades per depth)
	var base_exponent: float = pow(depth, 1.9)  # 1^1.9=1, 15^1.9=~105
	var base: float = 10.0 * pow(10.0, base_exponent / 2.5)  # Scaled to reach 1e300
	
	# Tier multiplier (0=cheap, 5=expensive)
	var tier_mult: float = 1.0 + (tier * 0.8)  # 1.0, 1.8, 2.6, 3.4, 4.2, 5.0
	
	var cost: float = base * tier_mult * pow(1.4, level)
	return cost
	
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
			"thought_stream": {  # Replaces Mental Strike
				"name": "Thought Stream",
				"description": "+0.5 idle Thoughts per second per level",
				"max_level": 10,
				"base_cost": 10.0,  # Starts at 10 as requested
				"cost_growth": 1.35,
				"effect_per_level": 0.5,
				"cost_currency": "thoughts"
			},
			"focus_training": {
				"name": "Lucid Training", 
				"description": "+15% progress speed per level",
				"max_level": 8,
				"base_cost": 25.0,
				"cost_growth": 1.4,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"velocity": {
				"name": "Velocity",
				"description": "+20% idle progress speed per level (stacks with Lucid)",
				"max_level": 5,
				"base_cost": 60.0,
				"cost_growth": 1.45,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"dream_recall": {
				"name": "Dream Recall",
				"description": "+15% Memory Gain per level",
				"max_level": 6,
				"base_cost": 150.0,
				"cost_growth": 1.55,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"mnemonic_anchor": {
				"name": "Mnemonic Anchor",
				"description": "+12% Amethyst Crystal Gain per level",
				"max_level": 4,
				"base_cost": 400.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"combat_reflexes": {  # Keep this one - it's the bridge to combat
				"name": "Combat Reflexes",
				"description": "+10% damage in Dream Combat per level",
				"max_level": 3,
				"base_cost": 800.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	
	## ============================================
# DEPTH 2 — DESCENT (Instability Gate)
# ============================================
	_depth_defs[2] = {
		"new_title": "Descent",
		"desc": "The first stirrings of chaos. Stabilize to survive.",
		"ui_unlocks": ["instability_bar", "wake_button"],
		"rules": {
			"instability_enabled": true,
			"instability_base_rate": 0.025,  # 2.5%/s - scary but manageable
			"progress_mul": 1.0,
			"mem_mul": 1.08,
			"cry_mul": 1.04,
			"forced_wake_at_100": true,
			"combat_available": true,
			"dive_unlock_requirement": {"upgrade": "stabilize", "level": 3}
		},
		"upgrades": {
			"stabilize": {
				"name": "Stabilize",
				"description": "-4% Instability gain per level (multiplicative)",
				"max_level": 8,  # More levels, cheaper
				"base_cost": 1000.0,  # 1k (was 2k)
				"cost_growth": 1.45,
				"effect_per_level": -0.04,
				"cost_currency": "thoughts"
			},
			"abyssal_current": {
				"name": "Abyssal Current",
				"description": "+0.08 Global Progress Speed per level",
				"max_level": 10,
				"base_cost": 2000.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"trauma_inoculation": {
				"name": "Trauma Inoculation",
				"description": "+10% Memory retention if forced Wake",
				"max_level": 5,
				"base_cost": 5000.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"combat_stance": {  # NEW
				"name": "Defensive Stance",
				"description": "-10% damage taken in combat per level",
				"max_level": 3,
				"base_cost": 8000.0,
				"cost_growth": 1.7,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"ruby_focus": {
				"name": "Ruby Focus",
				"description": "+15% Ruby Crystal gain per level",
				"max_level": 6,
				"base_cost": 15000.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"pressure_tolerance": {  # Replaces breath dreamcloud
				"name": "Pressure Tolerance",
				"description": "+3% Max Instability cap per level",
				"max_level": 5,
				"base_cost": 25000.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.03,
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
			"progress_mul": 1.0,
			"mem_mul": 1.12,  # Buffed from 1.10
			"cry_mul": 1.08,  # Buffed from 1.05
			"forced_wake_at_100": true,
			"event_enabled": false,
			"pressure_threshold": 60.0,  # Slowdown starts at 60% instability
			"pressure_slow_mul": 0.60,   # Base: 60% speed at high instability
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"pressure_hardening": {
				"name": "Pressure Hardening",
				"description": "Instability slows Progress 12% less per level",
				"max_level": 5,  # Max 60% reduction of penalty (0.6 + 0.6 = 1.2 capped at 1.0)
				"base_cost": 25000.0,  # 10x Depth 2 costs
				"cost_growth": 1.6,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"crush_resistance": {
				"name": "Crush Resistance",
				"description": "-6% Instability gain per level (multiplicative)",
				"max_level": 15,
				"base_cost": 40000.0,
				"cost_growth": 1.5,
				"effect_per_level": -0.06,  # Changed to multiplicative like Depth 2
				"cost_currency": "thoughts"
			},
			"emerald_focus": {
				"name": "Emerald Focus",
				"description": "+18% Emerald Crystal gain per level",
				"max_level": 50,
				"base_cost": 150000.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.18,
				"cost_currency": "thoughts"
			},
			"risky_compression": {
				"name": "Risky Compression",
				"description": "+20% Thoughts, +10% Instability (Trade-off)",
				"max_level": 3,
				"base_cost": 500000.0,
				"cost_growth": 2.0,
				"effect_per_level": 0.20,  # Multiplicative bonuses
				"cost_currency": "thoughts"
			},
			"safety_valves": {
				"name": "Safety Valves",
				"description": "Instability cap -8% per level (emergency buffer)",
				"max_level": 3,  # Cap 76% of normal (safety net)
				"base_cost": 800000.0,
				"cost_growth": 2.2,
				"effect_per_level": -0.08,  # Flat -8% cap reduction
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}
	# ============================================
	# DEPTH 4 — MURK (Hidden rewards - 5 upgrades)
	# ============================================
	_depth_defs[4] = {  # <-- WAS [5], CHANGE TO [4]
		"new_title": "Murk",
		"desc": "Shadows conceal truth. Adapt or be lost.",
		"ui_unlocks": ["hidden_rewards"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.15,
			"cry_mul": 1.10,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 45.0,
			"dive_unlock_requirement": {"upgrade": "stab", "level": 10}
		},
		"upgrades": {
			"dark_adaptation": {
				"name": "Dark Adaptation",
				"description": "Reveal 15% of hidden crystal rewards per level",
				"max_level": 7,  # 105% total, ensures you see all hidden rewards eventually
				"base_cost": 300000.0,  # 10x Depth 3 costs
				"cost_growth": 1.6,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"echo_navigation": {
				"name": "Echo Navigation",
				"description": "+12% progress speed per level",
				"max_level": 25,
				"base_cost": 600000.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"whisper_harvest": {
				"name": "Whisper Harvest",
				"description": "+8% thoughts when instability >60% per level",
				"max_level": 5,  # Max 40% bonus
				"base_cost": 1500000.0,
				"cost_growth": 1.8,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"sapphire_focus": {
				"name": "Sapphire Focus",
				"description": "+18% Sapphire crystals per level",
				"max_level": 50,
				"base_cost": 4000000.0,
				"cost_growth": 1.6,
				"effect_per_level": 0.18,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "flicker",
				"trigger": "timer",
				"cooldown": 45.0,
				"pause_progress": true,
				"choices": [
					{
						"id": "wait",
						"text": "Wait it out (Pause 10s)",
						"effect": {
							"pause_duration": 10,
							"instability_bonus": 0.0  # No change
						}
					},
					{
						"id": "overclock",
						"text": "Overclock through (-10% Thoughts, +15% Instability)",
						"effect": {
							"cost_thoughts_percent": 0.10,  # Costs 10% of current thoughts
							"instability_bonus": 0.15,
							"progress_bonus": 0.05
						}
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
				"max_level": 5,
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
				"description": "+0.15 Max dreamcloud per level",
				"max_level": 999,
				"base_cost": 120.0,
				"cost_growth": 1.5,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"rift_mining": {
				"name": "Rift Mining",
				"description": "Choices grant +8% Thoughts per level",
				"max_level": 50,
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
						"effect": {"progress_bonus": 0.15, "instability_bonus": 0.05}
					},
					{
						"id": "risk",
						"text": "Risky leap",
						"effect": {
							"progress_bonus": 0.40,      # Big jump
							"instability_bonus": 0.35,   # High risk
							"mem_mul": 2.0,              # Double memories
							"duration": 15.0,            # 15 seconds
							"cost_thoughts_percent": 0.25,         # Also costs dreamcloud
						}
					}
				],
				"upgrade_bonus": "rift_mastery"
			}
		]
	}
	
	# ============================================
# DEPTH 6 — HOLLOW (Frozen Depth Synergy)
# ============================================
	_depth_defs[6] = {
		"new_title": "Hollow",
		"desc": "Emptiness echoes. Your frozen past depths amplify present gains.",
		"ui_unlocks": ["frozen_depth_indicator"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.25,
			"cry_mul": 1.15,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 40.0,
			"dive_unlock_requirement": {"upgrade": "crystalline_memory", "level": 5}
		},
		"upgrades": {
			"crystalline_memory": {
				"name": "Crystalline Memory",
				"description": "Each completed depth below grants +5% Progress Speed",
				"max_level": 10,  # Max 50% bonus from 10 frozen depths
				"base_cost": 1.0e6,  # 1 Million thoughts
				"cost_growth": 2.0,  # Doubles each level: 1M, 2M, 4M... ~1B at max
				"effect_per_level": 0.05,
				"cost_currency": "thoughts"
			},
			"thermal_preservation": {
				"name": "Thermal Preservation",
				"description": "Reduce Instability acceleration from time pressure by 15%/level",
				"max_level": 5,  # Capped to prevent infinite stagnation
				"base_cost": 2.5e6,
				"cost_growth": 2.2,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"deep_cache": {
				"name": "Deep Cache",
				"description": "+25% Topaz Crystals per level",
				"max_level": 50,
				"base_cost": 5.0e6,
				"cost_growth": 1.6,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"hibernation_protocol": {
				"name": "Hibernation Protocol",
				"description": "Instability gain reduced by 20%/level when progress is paused",
				"max_level": 3,
				"base_cost": 1.0e7,
				"cost_growth": 3.0,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"echo_chamber": {
				"name": "Echo Chamber",
				"description": "Memories from this depth are worth +12% per level",
				"max_level": 25,
				"base_cost": 8.0e6,
				"cost_growth": 1.7,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "frozen_resonance",
				"trigger": "timer",
				"cooldown": 40.0,
				"pause_progress": true,
				"choices": [
					{
						"id": "embrace_cold",
						"text": "Embrace the Hollow (+30% progress, +25% Instability)",
						"effect": {"progress_mul": 1.3, "instability_mul": 1.25, "duration": 20.0}
					},
					{
						"id": "burn_memory",
						"text": "Burn a Memory (-50% Memories, reset Instability to 0)",
						"effect": {"memories_penalty": 0.5, "set_instability": 0.0}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 7 — DREAD (Paranoia/Fake Threats)
	# ============================================
	_depth_defs[7] = {
		"new_title": "Dread",
		"desc": "Fear manifests as phantom Instability spikes. Not all dangers are real.",
		"ui_unlocks": ["threat_indicator"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.32,
			"cry_mul": 1.18,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 35.0,
			"dive_unlock_requirement": {"upgrade": "reality_anchor", "level": 3}
		},
		"upgrades": {
			"reality_anchor": {
				"name": "Reality Anchor",
				"description": "20% chance to ignore fake Instability spikes per level",
				"max_level": 5,  # 100% at max
				"base_cost": 5.0e9,  # 5 Billion
				"cost_growth": 2.5,
				"effect_per_level": 0.20,
				"cost_currency": "thoughts"
			},
			"fear_feeding": {
				"name": "Fear Feeding",
				"description": "+40% Thoughts generation during fake threat events per level",
				"max_level": 10,
				"base_cost": 2.5e9,
				"cost_growth": 2.0,
				"effect_per_level": 0.40,
				"cost_currency": "thoughts"
			},
			"true_sight": {
				"name": "True Sight",
				"description": "Distinguish real from fake threats (reveals outcome before choosing)",
				"max_level": 1,
				"base_cost": 5.0e10,  # 50 Billion
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"garnet_focus": {
				"name": "Garnet Focus",
				"description": "+22% Garnet Crystal gain per level",
				"max_level": 50,
				"base_cost": 1.0e10,
				"cost_growth": 1.65,
				"effect_per_level": 0.22,
				"cost_currency": "thoughts"
			},
			"dread_immunity": {
				"name": "Dread Immunity",
				"description": "First real threat per run is automatically negated",
				"max_level": 1,
				"base_cost": 2.5e11,  # 250 Billion
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "phantom_spike",
				"trigger": "timer",
				"cooldown": 35.0,
				"is_fake": true,  # 70% chance this is fake, 30% real
				"choices": [
					{
						"id": "overreact",
						"text": "Emergency Stabilize (Costs 25% progress)",
						"effect": {"progress_penalty": 0.25, "instability_reduction": 0.3, "was_fake_bonus": 0.15}
					},
					{
						"id": "observe",
						"text": "Observe carefully",
						"effect": {"reveal_truth": true, "if_fake": {"progress_bonus": 0.1}, "if_real": {"instability_bonus": 0.2}}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 8 — CHASM (Speed vs Safety Tradeoffs)
	# ============================================
	_depth_defs[8] = {
		"new_title": "Chasm",
		"desc": "Gravity accelerates. The faster you fall, the harder you hit bottom.",
		"ui_unlocks": ["momentum_meter"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.40,
			"cry_mul": 1.22,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"dive_unlock_requirement": {"upgrade": "controlled_fall", "level": 5}
		},
		"upgrades": {
			"controlled_fall": {
				"name": "Controlled Fall",
				"description": "+8% Progress Speed, -3% Instability Gain per level",
				"max_level": 20,
				"base_cost": 1.0e14,  # 100 Trillion
				"cost_growth": 1.8,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"terminal_velocity": {
				"name": "Terminal Velocity",
				"description": "Instability cap +10% per level (allows exceeding 100%)",
				"max_level": 10,
				"base_cost": 5.0e14,
				"cost_growth": 2.5,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"impact_dampening": {
				"name": "Impact Dampening",
				"description": "When forced Wake occurs, retain +15% more Memories/level",
				"max_level": 5,
				"base_cost": 2.5e15,  # 2.5 Quadrillion
				"cost_growth": 3.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"opal_focus": {
				"name": "Opal Focus",
				"description": "+25% Opal Crystals per level",
				"max_level": 50,
				"base_cost": 1.0e15,
				"cost_growth": 1.7,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"weightless_moment": {
				"name": "Weightless Moment",
				"description": "Pause button also pauses Instability gain for 3s/level",
				"max_level": 5,
				"base_cost": 5.0e15,
				"cost_growth": 2.2,
				"effect_per_level": 3.0,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "narrow_ledge",
				"trigger": "timer",
				"cooldown": 30.0,
				"choices": [
					{
						"id": "leap",
						"text": "Leap (+40% speed for 10s, +20% Instability)",
						"effect": {"progress_mul": 1.4, "instability_mul": 1.2, "duration": 10.0}
					},
					{
						"id": "climb",
						"text": "Climb safely (+10% progress, -10% Instability)",
						"effect": {"progress_mul": 1.1, "instability_mul": 0.9, "duration": 15.0}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 9 — SILENCE (Information Denial)
	# ============================================
	_depth_defs[9] = {
		"new_title": "Silence",
		"desc": "No numbers. No certainty. Only instinct guides you now.",
		"ui_unlocks": ["blind_mode"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.48,
			"cry_mul": 1.28,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 25.0,
			"hide_all_numbers": true,
			"dive_unlock_requirement": {"upgrade": "inner_eye", "level": 2}
		},
		"upgrades": {
			"inner_eye": {
				"name": "Inner Eye",
				"description": "Restore UI element: Lv1=Thoughts, Lv2=Instability, Lv3=Progress, Lv4=All",
				"max_level": 4,
				"base_cost": 1.0e20,
				"cost_growth": 10.0,  # Expensive jumps: 1e20, 1e21, 1e22, 1e23
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"sixth_sense": {
				"name": "Sixth Sense",
				"description": "+15% all gains while UI is hidden per level",
				"max_level": 10,
				"base_cost": 5.0e19,
				"cost_growth": 1.9,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"silent_running": {
				"name": "Silent Running",
				"description": "-12% Instability gain while blind per level",
				"max_level": 5,
				"base_cost": 2.5e20,
				"cost_growth": 2.5,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"aquamarine_focus": {
				"name": "Aquamarine Focus",
				"description": "+28% Aquamarine Crystals per level",
				"max_level": 50,
				"base_cost": 1.0e21,
				"cost_growth": 1.75,
				"effect_per_level": 0.28,
				"cost_currency": "thoughts"
			},
			"void_trust": {
				"name": "Trust the Void",
				"description": "Permanently blind but +35% all gains (Irreversible)",
				"max_level": 1,
				"base_cost": 1.0e25,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}

	# ============================================
	# DEPTH 10 — VEIL (High RNG/Variance)
	# ============================================
	_depth_defs[10] = {
		"new_title": "Veil",
		"desc": "Probability fluctuates wildly. Certainty is purchased at a premium.",
		"ui_unlocks": ["probability_display"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.55,
			"cry_mul": 1.35,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 30.0,
			"dive_unlock_requirement": {"upgrade": "probability_anchor", "level": 5}
		},
		"upgrades": {
			"probability_anchor": {
				"name": "Probability Anchor",
				"description": "Reduce random variance by 12% per level",
				"max_level": 5,  # 60% reduction max
				"base_cost": 1.0e28,
				"cost_growth": 4.0,
				"effect_per_level": 0.12,
				"cost_currency": "thoughts"
			},
			"quantum_lock": {
				"name": "Quantum Lock",
				"description": "All random outcomes are at least neutral (no negatives)",
				"max_level": 1,
				"base_cost": 1.0e30,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"chaos_gaming": {
				"name": "Chaos Gaming",
				"description": "Random events trigger 25% more frequently, +20% rewards",
				"max_level": 5,
				"base_cost": 5.0e28,
				"cost_growth": 2.5,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			},
			"onyx_focus": {
				"name": "Onyx Focus",
				"description": "+30% Onyx Crystals per level",
				"max_level": 50,
				"base_cost": 2.5e29,
				"cost_growth": 1.8,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"certainty_protocol": {
				"name": "Certainty Protocol",
				"description": "Spend 1e50 Thoughts to guarantee next event is positive (Cooldown: 60s)",
				"max_level": 1,
				"base_cost": 1.0e50,  # Massive one-time cost
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "schrodinger_box",
				"trigger": "timer",
				"cooldown": 30.0,
				"choices": [
					{
						"id": "open",
						"text": "Open the box",
						"effect": {"random_range": {"progress": [-0.2, 0.5], "instability": [-0.3, 0.4]}}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 11 — RUIN (Permanent Loss Mechanics)
	# ============================================
	_depth_defs[11] = {
		"new_title": "Ruin",
		"desc": "Entropy claims all. Even your upgrades decay here.",
		"ui_unlocks": ["decay_warning"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.65,
			"cry_mul": 1.42,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 25.0,
			"dive_unlock_requirement": {"upgrade": "entropy_shield", "level": 1}
		},
		"upgrades": {
			"entropy_shield": {
				"name": "Entropy Shield",
				"description": "40% chance to resist upgrade decay per level",
				"max_level": 5,  # 200% effective = immunity
				"base_cost": 1.0e40,
				"cost_growth": 5.0,
				"effect_per_level": 0.40,
				"cost_currency": "thoughts"
			},
			"phoenix_protocol": {
				"name": "Phoenix Protocol",
				"description": "When upgrade decays, gain +50% burst progress",
				"max_level": 3,
				"base_cost": 5.0e41,
				"cost_growth": 3.0,
				"effect_per_level": 0.50,
				"cost_currency": "thoughts"
			},
			"scavenger_fortune": {
				"name": "Scavenger's Fortune",
				"description": "+35% Crystals gained from Ruin events per level",
				"max_level": 10,
				"base_cost": 2.5e41,
				"cost_growth": 2.0,
				"effect_per_level": 0.35,
				"cost_currency": "thoughts"
			},
			"jade_focus": {
				"name": "Jade Focus",
				"description": "+32% Jade Crystals per level",
				"max_level": 50,
				"base_cost": 1.0e42,
				"cost_growth": 1.85,
				"effect_per_level": 0.32,
				"cost_currency": "thoughts"
			},
			"ruin_diver": {
				"name": "Ruin Diver",
				"description": "Lose 50% less Memories on forced Wake per level",
				"max_level": 5,
				"base_cost": 5.0e42,
				"cost_growth": 4.0,
				"effect_per_level": 0.50,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "structural_collapse",
				"trigger": "timer",
				"cooldown": 25.0,
				"effect_on_trigger": {"random_upgrade_level_down": 1},
				"choices": [
					{
						"id": "accept",
						"text": "Accept the loss",
						"effect": {"instability_reduction": 0.15}
					},
					{
						"id": "resist",
						"text": "Resist (50% chance to save upgrade, +30% Instability)",
						"effect": {"resist_chance": 0.5, "instability_bonus": 0.3}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 12 — ECLIPSE (Shadow Clone - Combat Synergy)
	# ============================================
	_depth_defs[12] = {
		"new_title": "Eclipse",
		"desc": "Your shadow fights beside you. Combat efficiency peaks here.",
		"ui_unlocks": ["shadow_clone_ui"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.75,
			"cry_mul": 1.50,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 20.0,
			"dive_unlock_requirement": {"upgrade": "shadow_binding", "level": 5}
		},
		"upgrades": {
			"shadow_binding": {
				"name": "Shadow Binding",
				"description": "Shadow Clone deals +15% damage per level in Dream Combat",
				"max_level": 20,
				"base_cost": 1.0e55,
				"cost_growth": 2.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"twin_momentum": {
				"name": "Twin Momentum",
				"description": "Clone generates +3% of your Thoughts/sec per level",
				"max_level": 25,
				"base_cost": 5.0e55,
				"cost_growth": 1.9,
				"effect_per_level": 0.03,
				"cost_currency": "thoughts"
			},
			"umbral_shield": {
				"name": "Umbral Shield",
				"description": "Clone absorbs +10% of Instability gain per level",
				"max_level": 5,
				"base_cost": 2.5e56,
				"cost_growth": 3.0,
				"effect_per_level": 0.10,
				"cost_currency": "thoughts"
			},
			"moonstone_focus": {
				"name": "Moonstone Focus",
				"description": "+35% Moonstone Crystals per level",
				"max_level": 50,
				"base_cost": 1.0e57,
				"cost_growth": 1.9,
				"effect_per_level": 0.35,
				"cost_currency": "thoughts"
			},
			"eclipse_burst": {
				"name": "Eclipse Burst",
				"description": "Every 45s, gain instant 8% progress + Dreamcloud generation burst",
				"max_level": 5,
				"base_cost": 1.0e58,
				"cost_growth": 2.5,
				"effect_per_level": 0.02,  # +2% progress and +10% Dreamcloud gen per level
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "shadow_merge",
				"trigger": "timer",
				"cooldown": 20.0,
				"choices": [
					{
						"id": "merge",
						"text": "Merge with Shadow (Double all stats for 15s, then +50% Instability)",
						"effect": {"all_mul": 2.0, "duration": 15.0, "after_instability": 0.5}
					},
					{
						"id": "separate",
						"text": "Remain Separate (+20% Dreamcloud generation for combat)",
						"effect": {"dreamcloud_gen_mul": 1.2, "duration": 30.0}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 13 — VOIDLINE (Passive Drain)
	# ============================================
	_depth_defs[13] = {
		"new_title": "Voidline",
		"desc": "The event horizon. Progress itself is consumed.",
		"ui_unlocks": ["void_drain_meter"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.85,
			"cry_mul": 1.60,
			"forced_wake_at_100": true,
			"event_enabled": false,
			"void_drain_enabled": true,  # Special rule
			"dive_unlock_requirement": {"upgrade": "void_anchor", "level": 10}
		},
		"upgrades": {
			"void_anchor": {
				"name": "Void Anchor",
				"description": "-15% progress drain rate per level",
				"max_level": 10,
				"base_cost": 1.0e75,
				"cost_growth": 3.0,
				"effect_per_level": 0.15,
				"cost_currency": "thoughts"
			},
			"tether_recovery": {
				"name": "Tether Recovery",
				"description": "40% chance to recover drained progress per level",
				"max_level": 5,
				"base_cost": 5.0e76,
				"cost_growth": 2.5,
				"effect_per_level": 0.40,
				"cost_currency": "thoughts"
			},
			"obsidian_focus": {
				"name": "Obsidian Focus",
				"description": "+40% Obsidian Crystals per level",
				"max_level": 50,
				"base_cost": 2.5e77,
				"cost_growth": 2.0,
				"effect_per_level": 0.40,
				"cost_currency": "thoughts"
			},
			"embrace_void": {
				"name": "Embrace the Void",
				"description": "Drain is doubled, but all gains are +80%",
				"max_level": 1,
				"base_cost": 1.0e80,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"null_field": {
				"name": "Null Field",
				"description": "Immune to drain for first 60s of depth per level",
				"max_level": 5,
				"base_cost": 1.0e78,
				"cost_growth": 5.0,
				"effect_per_level": 60.0,
				"cost_currency": "thoughts"
			}
		},
		"events": []
	}

	# ============================================
	# DEPTH 14 — BLACKWATER (Meta/Carryover Focus)
	# ============================================
	_depth_defs[14] = {
		"new_title": "Blackwater",
		"desc": "Dark tides bind runs together. Prepare for transcendence.",
		"ui_unlocks": ["carryover_preview"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 1.95,
			"cry_mul": 1.75,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 20.0,
			"dive_unlock_requirement": {"upgrade": "abyssal_tribute", "level": 3}
		},
		"upgrades": {
			"abyssal_memory": {
				"name": "Abyssal Memory",
				"description": "Carry +8% of total Thoughts to next run per level",
				"max_level": 10,
				"base_cost": 1.0e120,
				"cost_growth": 10.0,
				"effect_per_level": 0.08,
				"cost_currency": "thoughts"
			},
			"crystal_resonance": {
				"name": "Crystal Resonance",
				"description": "Start next run with +100 of this depth's crystals per level",
				"max_level": 50,
				"base_cost": 1.0e125,
				"cost_growth": 1.5,
				"effect_per_level": 100.0,
				"cost_currency": "thoughts"
			},
			"tidal_stabilization": {
				"name": "Tidal Stabilization",
				"description": "Instability reduces by 0.05%/sec per level passively",
				"max_level": 5,
				"base_cost": 5.0e122,
				"cost_growth": 5.0,
				"effect_per_level": 0.05,
				"cost_currency": "thoughts"
			},
			"citrine_focus": {
				"name": "Citrine Focus",
				"description": "+45% Citrine Crystals per level",
				"max_level": 50,
				"base_cost": 2.5e124,
				"cost_growth": 2.1,
				"effect_per_level": 0.45,
				"cost_currency": "thoughts"
			},
			"permanent_record": {
				"name": "Permanent Record",
				"description": "Transcendence Points from this run +25% per level",
				"max_level": 10,
				"base_cost": 1.0e150,
				"cost_growth": 100.0,
				"effect_per_level": 0.25,
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "dark_tide",
				"trigger": "timer",
				"cooldown": 20.0,
				"choices": [
					{
						"id": "drown",
						"text": "Drown in Memories (Sacrifice 90% current Thoughts for +50% Instability cap)",
						"effect": {"thoughts_sacrifice": 0.9, "instability_cap_bonus": 0.5, "duration": 30.0}
					},
					{
						"id": "float",
						"text": "Float (+20% carryover to next run)",
						"effect": {"next_run_carryover_mul": 1.2}
					}
				]
			}
		]
	}

	# ============================================
	# DEPTH 15 — ABYSS (Final Challenge)
	# ============================================
	_depth_defs[15] = {
		"new_title": "Abyss",
		"desc": "The convergence. All previous mechanics manifest randomly.",
		"ui_unlocks": ["abyss_challenge", "transcendence_button"],
		"rules": {
			"instability_enabled": true,
			"progress_mul": 1.0,
			"mem_mul": 2.10,
			"cry_mul": 2.00,
			"forced_wake_at_100": true,
			"event_enabled": true,
			"event_timer": 15.0,
			"random_event_pool": ["phantom_spike", "schrodinger_box", "structural_collapse", "shadow_merge", "dark_tide"],
			"dive_unlock_requirement": {"upgrade": "cosmic_horror", "level": 1}
		},
		"upgrades": {
			"cosmic_horror": {
				"name": "Cosmic Horror",
				"description": "All previous depth upgrades active at 30% efficiency",
				"max_level": 1,
				"base_cost": 1.0e200,
				"cost_growth": 1.0,
				"effect_per_level": 0.30,
				"cost_currency": "thoughts"
			},
			"abyssal_sovereignty": {
				"name": "Abyssal Sovereignty",
				"description": "Immune to all negative event effects",
				"max_level": 1,
				"base_cost": 1.0e250,
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"quartz_focus": {
				"name": "Quartz Focus",
				"description": "+50% Quartz Crystals per level",
				"max_level": 100,
				"base_cost": 1.0e180,
				"cost_growth": 1.5,
				"effect_per_level": 0.50,
				"cost_currency": "thoughts"
			},
			"transcendence": {
				"name": "Transcendence",
				"description": "Unlock the Sleep mechanic (Second Prestige Layer)",
				"max_level": 1,
				"base_cost": 1.0e300,  # The ultimate goal
				"cost_growth": 1.0,
				"effect_per_level": 1.0,
				"cost_currency": "thoughts"
			},
			"infinite_depth": {
				"name": "Infinite Depth",
				"description": "Can continue past 100% Instability, but gains scale exponentially with danger",
				"max_level": 10,
				"base_cost": 1.0e220,
				"cost_growth": 100.0,
				"effect_per_level": 0.10,  # +10% gains per % over 100
				"cost_currency": "thoughts"
			}
		},
		"events": [
			{
				"id": "final_test",
				"trigger": "timer",
				"cooldown": 15.0,
				"random_from_pool": true,
				"intensity_mul": 1.5  # All events are 50% more severe
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
	
	# Default returns
	var inst_rate: float = 0.0
	var prog_mul: float = 1.0
	var mem_mul: float = float(rules.get("mem_mul", 1.0))
	var cry_mul: float = float(rules.get("cry_mul", 1.0))
	var inst_cap: float = get_instability_cap(d)
	
	# Calculate instability rate for depth 2+
	if d >= 2 and rules.get("instability_enabled", false):
	# FASTER: 3.5% at depth 2 (fills in ~28s), scales aggressively
		var base_rate: float = 0.035 * pow(1.45, d - 2)
		
		# Time pressure: +0.2% per second spent in depth
		_ensure_depth_runtime(d)
		var rt: Dictionary = _depth_runtime[d]
		var time_in_depth: float = rt.get("time_in_depth", 0.0)
		var time_pressure: float = 1.0 + (time_in_depth * 0.002)
		base_rate *= time_pressure
		
		# Apply Stabilize upgrades (Depth 2) - 5% multiplicative reduction per level
		var stab_level: int = _get_local_level(2, "stabilize") + _get_local_level(d, "stabilize")
		if stab_level > 0:
			base_rate *= pow(0.95, stab_level)
		
		# Apply Crush Resistance (Depth 3) - 6% multiplicative reduction per level
		if d >= 3:
			var crush_level: int = _get_local_level(3, "crush_resistance")
			if crush_level > 0:
				base_rate *= pow(0.94, crush_level)
		
		inst_rate = base_rate * 100.0  # Convert to percentage points
	
	# Pressure mechanic (Depth 3)
	if d == 3 and rules.has("pressure_threshold"):
		var pressure_threshold: float = rules.get("pressure_threshold", 60.0)
		var inst_percent: float = (instability / inst_cap) * 100.0 if inst_cap > 0 else 0.0
		
		if inst_percent >= pressure_threshold:
			var pressure_severity: float = (inst_percent - pressure_threshold) / (100.0 - pressure_threshold)
			pressure_severity = clampf(pressure_severity, 0.0, 1.0)
			var slow_mult: float = 0.4
			
			var hardening_level: int = _get_local_level(d, "pressure_hardening")
			if hardening_level > 0:
				var hardening_def: Dictionary = def.get("upgrades", {}).get("pressure_hardening", {})
				var hardening_effect: float = hardening_def.get("effect_per_level", 0.12)
				slow_mult = maxf(0.0, 0.4 - (hardening_effect * hardening_level))
			
			prog_mul *= (1.0 - (pressure_severity * slow_mult))
	
	return {
		"instability_per_sec": inst_rate,  # This is % per second (e.g., 0.5 means +0.5%/s)
		"progress_mul": prog_mul,
		"mem_mul": mem_mul,
		"cry_mul": cry_mul,
		"rules": rules,
		"instability_cap": inst_cap
	}
# Add helper to get upgrade level (if not already present)
func _get_meta_upgrade_level(depth: int, upgrade_id: String) -> int:
	var meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null and meta.has_method("get_level"):
		return meta.call("get_level", depth, upgrade_id)
	return 0

# Calculate event interval with Temporal Sense
func _get_event_interval() -> float:
	if active_depth != 5:
		return 30.0
	
	var temporal_lvl = _get_local_level(5, "temporal_sense")
	var base_interval = 30.0
	# 10% faster per level: 30 -> 27 -> 24 -> 21 -> 18
	return base_interval * (1.0 - (temporal_lvl * 0.10))

func _tick_depth_events(d: int, delta: float, rules: Dictionary) -> void:
	_ensure_depth_runtime(d)
	var rt: Dictionary = _depth_runtime[d]
	
	# FIX: Initialize event_timer if missing
	if not rt.has("event_timer"):
		rt["event_timer"] = 0.0
	
	# FIX: Get interval with Temporal Sense check for Depth 5
	var interval: float = rules.get("event_timer", 30.0)
	if d == 5:
		var temp_sense = _get_local_level(5, "temporal_sense")
		interval *= (1.0 - (temp_sense * 0.10))  # 10% faster per level
	
	rt["event_timer"] = float(rt["event_timer"]) + delta
	
	# DEBUG: Print timer progress
	if Engine.get_process_frames() % 60 == 0:
		print("Depth ", d, " event timer: ", rt["event_timer"], " / ", interval)
	
	if rt["event_timer"] >= interval:
		rt["event_timer"] = 0.0
		
		# Trigger specific events based on depth
		if d == 4:
			_trigger_flicker_event({})
			print("TRIGGERED: Flicker event at Depth 4")
		elif d == 5:
			_trigger_rift_choice({})
			print("TRIGGERED: Rift choice at Depth 5")
	
	_depth_runtime[d] = rt
	
func _trigger_depth_event(d: int) -> void:
	var def: Dictionary = get_depth_def(d)
	var events: Array = def.get("events", [])
	
	if events.size() == 0:
		return
	
	var event_data: Dictionary = events[0]  # Get first event for now
	
	# For Depth 4: Flicker event
	if d == 4:
		_trigger_flicker_event(event_data)
	# For Depth 5: Rift Choice event
	elif d == 5:
		_trigger_rift_choice(event_data)


func _on_rift_choice_resolved(_choice_id: String, effects: Dictionary) -> void:
	set_meta("progress_paused", false)
	_rift_event_active = false
	
	# Get instability cap
	var inst_cap: float = get_instability_cap(active_depth)
	
	if effects.has("instability_bonus"):
		var percent: float = float(effects["instability_bonus"])
		instability += (inst_cap * percent)
	
	if effects.has("progress_bonus"):
		var prog_cap: float = get_depth_progress_cap(active_depth)
		var current: float = _run_internal[active_depth - 1].get("progress", 0.0)
		_run_internal[active_depth - 1]["progress"] = minf(prog_cap, current + (prog_cap * float(effects["progress_bonus"])))
	
	# Handle costs if any (now in thoughts, not dreamcloud)
	if effects.has("cost_thoughts"):
		var cost: float = float(effects["cost_thoughts"])
		thoughts = max(0.0, thoughts - cost)
		
func get_temporary_memory_multiplier() -> float:
	var mult = 1.0
	for buff in _temp_buffs.values():
		if buff.type == "memory_mult":
			mult *= buff.value
	return mult  # <-- Return is here

func _trigger_flicker_event(_event_data: Dictionary = {}) -> void:
	set_meta("progress_paused", true)
	
	if choice_modal != null:
		# CRITICAL: Disconnect first to prevent error
		if choice_modal.choice_made.is_connected(_on_flicker_choice):
			choice_modal.choice_made.disconnect(_on_flicker_choice)
			print("Disconnected existing flicker connection")
		
		choice_modal.show_choice(
			"The Murk flickers...",
			[
				{"id": "wait", "text": "Wait it out (Pause 10s)"},
				{"id": "overclock", "text": "Overclock through (-20 dreamcloud, +15% Instability)"}
			]
		)
		
		# Connect fresh
		choice_modal.choice_made.connect(_on_flicker_choice)
		print("Connected flicker choice handler")

func _on_flicker_choice(choice_id: String, _effects: Dictionary) -> void:
	print("FLICKER CHOICE: ", choice_id)
	set_meta("progress_paused", false)
	
	if choice_modal and choice_modal.choice_made.is_connected(_on_flicker_choice):
		choice_modal.choice_made.disconnect(_on_flicker_choice)
	
	if choice_id == "overclock":
		# NEW: Cost 10% of current Thoughts (minimum 1000)
		var cost: float = max(1000.0, thoughts * 0.10)
		
		if thoughts >= cost:
			thoughts -= cost
			print("Overclock cost %.0f thoughts, remaining: %.0f" % [cost, thoughts])
			
			# Get actual cap for this depth
			var inst_cap: float = get_instability_cap(active_depth)
			
			# +15% instability (flat percentage)
			instability += (inst_cap * 0.15)
			
			# +5% instant progress
			var current_prog: float = _run_internal[active_depth - 1].get("progress", 0.0)
			var prog_cap: float = get_depth_progress_cap(active_depth)
			var new_prog: float = minf(prog_cap, current_prog + (prog_cap * 0.05))
			_run_internal[active_depth - 1]["progress"] = new_prog
			
			print("Overclock complete: +15% inst, +5% progress")
		else:
			print("Not enough thoughts for overclock!")
			# Optional: Show UI feedback
			
	elif choice_id == "wait":
		print("Wait choice - 10s pause")
		# Add a 10s timer that pauses progress here if you want
			
func _trigger_rift_choice(_event_data: Dictionary = {}) -> void:
	set_meta("progress_paused", true)
	var def = get_depth_def(5)
	var events = def.get("events", [])
	if events.size() == 0:
		return
	
	var evt = events[0]  # "the_choice" event
	_rift_event_active = true
	
	if choice_modal != null:
		var risk_assess_lvl = _get_local_level(5, "risk_assessment")
		choice_modal.show_event(evt, def, risk_assess_lvl > 0)
		if not choice_modal.choice_made.is_connected(_on_rift_choice_resolved):
			choice_modal.choice_made.connect(_on_rift_choice_resolved)

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
	"""Returns list of upgrade IDs for a specific depth (e.g., ["stabilize", "dreamcloudled_fall", ...])"""
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
func get_run_dreamcloud_mult() -> float:
	# If you have dreamcloud upgrades, add them here
	return 1.0

func get_run_instability_reduction() -> float:
	# If you have stability upgrades that reduce instability
	return 1.0
