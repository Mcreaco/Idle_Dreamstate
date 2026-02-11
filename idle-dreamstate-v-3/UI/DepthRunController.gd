extends Node

@export var max_depth: int = 15
@export var base_memories_per_sec: float = 2.0
@export var base_crystals_per_sec: float = 1.0

# top panel base rates (tune later)
@export var thoughts_per_sec: float = 0.0
@export var control_per_sec: float = 0.0
@export var instability_per_sec: float = 0.0

@export var base_progress_per_sec: float = 0.015   # was too fast
@export var depth_length_growth: float = 1.35      # >1 means deeper = longer bar
@export var length_curve_power: float = 1.10       # >1 makes mid-depths ramp harder

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
	if dev_unlock_all_depths:
		max_unlocked_depth = max_depth
	if dev_start_depth > 1:
		active_depth = clampi(dev_start_depth, 1, max_depth)

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
	var speed_mul: float = 1.0 + 0.10 * _get_local_level(d, "progress_speed") + _frozen_effect(d, "progress_speed", 0.10)
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
	if active_depth < 1 or active_depth > run.size():
		return false
	return float(run[active_depth - 1].get("progress", 0.0)) >= 1.0 and active_depth < max_unlocked_depth


func dive() -> void:
	if not can_dive():
		return

	var d := active_depth
	var local: Dictionary = local_upgrades.get(d, {}) as Dictionary
	frozen_upgrades[d] = local.duplicate(true)

	active_depth += 1
	active_depth = clampi(active_depth, 1, max_depth)

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

	# Depth 1 — baseline
	_depth_defs[1] = {
		"new_title": "Baseline",
		"desc": "Core loop only. Learn the flow.",
		"ui_unlocks": [],
		"rules": {
			"instability_enabled": false,
			"instability_per_sec": 0.0,
			"progress_mul": 1.0,
			"mem_mul": 1.0,
			"cry_mul": 1.0,
		},
		"events": []
	}

	# Depth 2 — Instability introduced
	_depth_defs[2] = {
		"new_title": "Instability",
		"desc": "Instability rises over time. Hit 100% and you’re forced to Wake (reduced payout).",
		"ui_unlocks": ["instability_bar"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 3.0, # tune
			"progress_mul": 1.0,
			"mem_mul": 1.0,
			"cry_mul": 1.0,
			"forced_wake_at_100": true,
		},
		"events": []
	}

	# Depth 3 — Pressure threshold (progress slows if instability high)
	_depth_defs[3] = {
		"new_title": "Pressure",
		"desc": "High instability slows progress. Push too hard and you stall.",
		"ui_unlocks": ["instability_bar", "pressure_hint"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 3.5,
			"progress_mul": 1.0,
			"mem_mul": 1.05,
			"cry_mul": 1.02,
			"pressure_threshold": 60.0,      # above this, progress slows
			"pressure_slow_mul": 0.60,       # 60% speed when pressured
		},
		"events": []
	}

	# Depth 4 — Murk (reward uncertainty)
	_depth_defs[4] = {
		"new_title": "Murk",
		"desc": "Rewards are uncertain until you Wake. You only see ranges.",
		"ui_unlocks": ["reward_ranges"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 4.0,
			"progress_mul": 1.0,
			"mem_mul": 1.10,
			"cry_mul": 1.05,
			"mirk_ranges": true, # (spelling not important; consistent key)
		},
		"events": []
	}

	# Depth 5 — Rift (choice event)
	_depth_defs[5] = {
		"new_title": "Rift",
		"desc": "You get a recurring choice: safe/steady vs volatile/reward.",
		"ui_unlocks": ["choice_events"],
		"rules": {
			"instability_enabled": true,
			"instability_per_sec": 4.5,
			"progress_mul": 1.0,
			"mem_mul": 1.15,
			"cry_mul": 1.10,
			"choice_every_sec": 18.0, # fires choice event
		},
		"events": ["rift_choice"]
	}

	# Fill the rest later; you can stub them:
	for d in range(6, max_depth + 1):
		if not _depth_defs.has(d):
			_depth_defs[d] = {
				"new_title": "TBD",
				"desc": "Coming soon.",
				"ui_unlocks": [],
				"rules": {
					"instability_enabled": true,
					"instability_per_sec": 5.0 + float(d - 5) * 0.5,
					"progress_mul": 1.0,
					"mem_mul": 1.0 + float(d) * 0.02,
					"cry_mul": 1.0 + float(d) * 0.015,
				},
				"events": []
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
