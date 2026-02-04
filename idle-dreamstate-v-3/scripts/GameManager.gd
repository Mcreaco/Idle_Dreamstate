extends Node
class_name GameManager

signal abyss_unlocked

# -------------------------
# SCENE / SYSTEM REFERENCES
# -------------------------
@onready var pillar_stack: Node = get_tree().current_scene.find_child("Segments", true, false)
@onready var risk_system: RiskSystem = $"../Systems/RiskSystem"
@onready var overclock_system: OverclockSystem = $"../Systems/OverclockSystem"
@onready var upgrade_manager: UpgradeManager = $"../Systems/UpgradeManager"
@onready var automation_system: AutomationSystem = $"../Systems/AutomationSystem"
@onready var corruption_system: CorruptionSystem = $"../Systems/CorruptionSystem"
@onready var nightmare_system: NightmareSystem = $"../Systems/NightmareSystem"
@onready var perk_system: PerkSystem = $"../Systems/PerkSystem"
@onready var abyss_perk_system: AbyssPerkSystem = $"../Systems/AbyssPerkSystem"
@onready var perm_perk_system: PermPerkSystem = $"../Systems/PermPerkSystem"
@onready var depth_meta_system: DepthMetaSystem = $"../Systems/DepthMetaSystem"
@onready var sound_system = $"../SoundSystem"
@onready var top_bar_panel: Node = $"../MainUI/Root/TopBarPanel"  # ensure this path matches your scene

# -------------------------
# DIVE COOLDOWN (perk2 reduction)
# -------------------------
@export var dive_cd_min: float = 3.0
@export var perk2_cd_reduction_per_level: float = 0.5

func _get_effective_dive_cooldown() -> float:
	var cd := dive_cooldown
	if perk_system != null:
		cd -= perk2_cd_reduction_per_level * float(perk_system.perk2_level)
	return maxf(dive_cd_min, cd)

# -------------------------
# UI NODES (MainUI)
# -------------------------
var thoughts_label: Label
var control_label: Label
var instability_label: Label
var instability_bar: Range

var overclock_button: Button
var dive_button: Button
var wake_button: Button
var meta_button: Button

var auto_dive_toggle: BaseButton
var auto_overclock_toggle: BaseButton

var meta_panel: MetaPanelController
var prestige_panel: PrestigePanel

# -------------------------
# RUN
# -------------------------
var thoughts: float = 0.0
var control: float = 0.0
var instability: float = 0.0
var time_in_run: float = 0.0
var total_thoughts_earned: float = 0.0
var max_instability: float = 0.0

# -------------------------
# DEPTH
# -------------------------
var depth: int = 0
var max_depth_reached: int = 1

# -------------------------
# ABYSS (meta unlock)
# -------------------------
var abyss_unlocked_flag: bool = false
var run_start_depth: int = 0
var abyss_target_depth: int = 15

# -------------------------
# META CURRENCY
# -------------------------
var memories: float = 0.0

# -------------------------
# RATES
# -------------------------
var idle_thoughts_rate: float = 2.5
var idle_control_rate: float = 1.0
var idle_instability_rate: float = 0.45

var dive_thoughts_gain: float = 18.0
var dive_control_gain: float = 6.0
var dive_instability_gain: float = 9.0

var wake_bonus_mult: float = 1.35
var fail_penalty_mult: float = 0.60

var depth_thoughts_step: float = 0.05
var depth_instab_step: float = 0.08

# -------------------------
# DIVE COOLDOWN
# -------------------------
var dive_cooldown: float = 10.0
var dive_cooldown_timer: float = 0.0

# -------------------------
# WAKE GUARD
# -------------------------
var wake_guard_seconds: float = 0.35
var wake_guard_timer: float = 0.0

# -------------------------
# OFFLINE PROGRESS
# -------------------------
const MAX_OFFLINE_SECONDS: float = 3600.0
var offline_seconds: float = 0.0

# -------------------------
# AUTOSAVE
# -------------------------
var autosave_timer: float = 0.0
var autosave_interval: float = 10.0

# -------------------------
# CRACK SYNC THROTTLE
# -------------------------
var _crack_sync_timer: float = 0.0

# -------------------------
# RATE SAMPLING FOR UI
# -------------------------
var _rate_sample_timer: float = 0.0
var _last_thoughts_sample: float = 0.0
var _last_control_sample: float = 0.0
var _thoughts_ps: float = 0.0
var _control_ps: float = 0.0

func _sync_cracks() -> void:
	if pillar_stack != null and pillar_stack.has_method("set_instability"):
		pillar_stack.call("set_instability", instability, 100.0)

# -------------------------
# READY
# -------------------------
func _ready() -> void:
	set_process_priority(1000)
	load_game()
	_apply_offline_progress()
	_bind_ui_mainui()

	# init samples
	_last_thoughts_sample = thoughts
	_last_control_sample = control

	_sync_meta_progress()

	_connect_pressed_once(overclock_button, Callable(self, "do_overclock"))
	_connect_pressed_once(dive_button, Callable(self, "do_dive"))
	_connect_pressed_once(wake_button, Callable(self, "_on_wake_pressed"))
	_connect_pressed_once(meta_button, Callable(self, "_on_meta_pressed"))

	if auto_dive_toggle != null:
		auto_dive_toggle.button_pressed = false
	if auto_overclock_toggle != null:
		auto_overclock_toggle.button_pressed = false

	automation_system.auto_dive = false
	automation_system.auto_overclock = false

	if auto_dive_toggle != null and not auto_dive_toggle.toggled.is_connected(Callable(self, "_on_auto_dive_toggled")):
		auto_dive_toggle.toggled.connect(Callable(self, "_on_auto_dive_toggled"))
	if auto_overclock_toggle != null and not auto_overclock_toggle.toggled.is_connected(Callable(self, "_on_auto_overclock_toggled")):
		auto_overclock_toggle.toggled.connect(Callable(self, "_on_auto_overclock_toggled"))

	if time_in_run <= 0.0:
		run_start_depth = depth

	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", depth)
	if pillar_stack != null and pillar_stack.has_method("reset_visuals"):
		pillar_stack.call("reset_visuals")

	_sync_cracks()
	_refresh_top_ui()
	_update_buttons_ui()
	_force_cooldown_texts()
	save_game()

# -------------------------
# PROCESS
# -------------------------
func _process(delta: float) -> void:
	autosave_timer += delta
	if autosave_timer >= autosave_interval:
		autosave_timer = 0.0
		save_game()

	if prestige_panel != null and prestige_panel.visible:
		_refresh_top_ui()
		_update_buttons_ui()
		_force_cooldown_texts()
		return

	dive_cooldown_timer = maxf(dive_cooldown_timer - delta, 0.0)
	wake_guard_timer = maxf(wake_guard_timer - delta, 0.0)
	time_in_run += delta

	overclock_system.update(delta)

	# Automation toggles
	if auto_dive_toggle != null:
		automation_system.auto_dive = auto_dive_toggle.button_pressed
	if auto_overclock_toggle != null:
		automation_system.auto_overclock = auto_overclock_toggle.button_pressed
	if automation_system.auto_overclock:
		_try_auto_overclock()

	var attempt: int = automation_system.update(delta)
	if attempt > 0:
		_press_button(dive_button)

	var _corruption = corruption_system.update(delta, instability)

	# -------------------------
	# Base multipliers
	# -------------------------
	var thoughts_mult: float = upgrade_manager.get_thoughts_mult() * perk_system.get_thoughts_mult() * nightmare_system.get_thoughts_mult()
	var instability_mult: float = upgrade_manager.get_instability_mult() * perk_system.get_instability_mult() * nightmare_system.get_instability_mult()
	var control_mult: float = perk_system.get_control_mult() * nightmare_system.get_control_mult()

	# Depth-meta GLOBAL (permanent across all depths)
	var depth_meta_thoughts_mult: float = 1.0
	var depth_meta_control_mult: float = 1.0
	var depth_meta_instab_mult: float = 1.0
	var depth_meta_idle_instab_mult: float = 1.0
	if depth_meta_system != null:
		depth_meta_thoughts_mult = depth_meta_system.get_global_thoughts_mult()
		depth_meta_control_mult = depth_meta_system.get_global_control_mult()
		depth_meta_instab_mult = depth_meta_system.get_global_instability_mult()
		depth_meta_idle_instab_mult = depth_meta_system.get_global_idle_instability_mult()

	thoughts_mult *= depth_meta_thoughts_mult
	control_mult *= depth_meta_control_mult

	# PERM perks
	if perm_perk_system != null:
		thoughts_mult *= perm_perk_system.get_thoughts_mult()
		instability_mult *= perm_perk_system.get_instability_mult()
		control_mult *= perm_perk_system.get_control_mult()

	# Abyss perk multipliers
	if abyss_perk_system != null:
		thoughts_mult *= abyss_perk_system.get_thoughts_mult()
		control_mult *= abyss_perk_system.get_control_mult()

	# -------------------------
	# Depth scaling (run scaling)
	# -------------------------
	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	var deep_risk_per_depth: float = upgrade_manager.get_deep_dives_instab_bonus_per_depth()
	var depth_thoughts_mult: float = 1.0 + (float(depth) * (depth_thoughts_step + deep_bonus_per_depth))
	var depth_instab_mult: float = 1.0 + (float(depth) * (depth_instab_step + deep_risk_per_depth))

	# Overclock
	if overclock_system.active:
		thoughts_mult *= overclock_system.thoughts_mult
		instability_mult *= overclock_system.instability_mult

	# Corruption modifiers
	thoughts_mult *= float(_corruption.thoughts_mult)
	instability_mult *= float(_corruption.instability_mult)

	# Abyss veil reduction
	var abyss_instab_mult: float = 1.0
	if abyss_perk_system != null:
		abyss_instab_mult = abyss_perk_system.get_instability_reduction_mult(depth)

	# -------------------------
	# Idle gains
	# -------------------------
	thoughts += idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * delta
	control += idle_control_rate * control_mult * delta

	var idle_risk_gain: float = (idle_instability_rate * instability_mult * depth_instab_mult * delta) + float(_corruption.extra_instability)
	instability = risk_system.add_risk(
		instability,
		idle_risk_gain * abyss_instab_mult * depth_meta_instab_mult * depth_meta_idle_instab_mult
	)

	# Crack sync throttled
	_crack_sync_timer += delta
	if _crack_sync_timer >= 0.1:
		_crack_sync_timer = 0.0
		_sync_cracks()

	# Tracking
	total_thoughts_earned = maxf(total_thoughts_earned, thoughts)
	max_instability = maxf(max_instability, instability)
	nightmare_system.check_unlock(max_instability)

	# Sample rates for UI (simple diff over time)
	_rate_sample_timer += delta
	if _rate_sample_timer >= 0.5:
		var inv_dt: float = 1.0 / _rate_sample_timer
		_thoughts_ps = (thoughts - _last_thoughts_sample) * inv_dt
		_control_ps = (control - _last_control_sample) * inv_dt
		_last_thoughts_sample = thoughts
		_last_control_sample = control
		_rate_sample_timer = 0.0

	_refresh_top_ui()
	_update_buttons_ui()
	_force_cooldown_texts()

	if instability >= 100.0:
		do_fail()

# -------------------------
# UI UPDATE
# -------------------------
func _refresh_top_ui() -> void:
	# Old fallback labels
	if thoughts_label != null:
		thoughts_label.text = "Thoughts: %s" % _fmt_num(thoughts)
	if control_label != null:
		control_label.text = "Control: %s" % _fmt_num(control)
	if instability_bar != null:
		instability_bar.min_value = 0.0
		instability_bar.max_value = 100.0
		instability_bar.value = clampf(instability, 0.0, 100.0)
	if instability_label != null:
		instability_label.text = "Instability"

	# Preferred: send to TopBarPanel if present
	if top_bar_panel != null and top_bar_panel.has_method("update_top_bar"):
		var inst_pct: float = clampf(instability, 0.0, 100.0)
		var overclock_time_left: float = 0.0
		if overclock_system != null and overclock_system.active:
			overclock_time_left = maxf(overclock_system.timer, 0.0)
		var ttf: float = get_seconds_until_fail()
		top_bar_panel.update_top_bar(
			thoughts,
			_thoughts_ps,
			control,
			_control_ps,
			inst_pct,
			overclock_system != null and overclock_system.active,
			overclock_time_left,
			ttf
		)

func _update_buttons_ui() -> void:
	if overclock_button != null:
		var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
		var effective_overclock_cost: float = overclock_system.base_control_cost * cost_mul
		overclock_button.disabled = overclock_system.active or (control < effective_overclock_cost)
	if dive_button != null:
		dive_button.disabled = (dive_cooldown_timer > 0.0)
	if wake_button != null:
		wake_button.disabled = (wake_guard_timer > 0.0)

func _force_cooldown_texts() -> void:
	if overclock_button != null:
		if overclock_system.active:
			var sec_left_o: int = int(ceil(maxf(overclock_system.timer, 0.0)))
			overclock_button.text = "Overclock (%ds)" % sec_left_o
		else:
			var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
			var effective_cost: float = overclock_system.base_control_cost * cost_mul
			overclock_button.text = "Overclock (-%d Control)" % int(round(effective_cost))
	if dive_button != null:
		if dive_cooldown_timer > 0.0:
			var sec_left_d: int = int(ceil(dive_cooldown_timer))
			dive_button.text = "Dive (%ds)" % sec_left_d
		else:
			dive_button.text = "Dive"
	if wake_button != null:
		wake_button.text = "Wake"

# -------------------------
# META PANEL
# -------------------------
func _on_meta_pressed() -> void:
	if meta_panel == null:
		meta_panel = _ui_find("MetaPanel") as MetaPanelController
	if meta_panel == null:
		push_warning("MetaPanelController not found on MetaPanel.")
		return
	_sync_meta_progress()
	meta_panel.toggle_open()

func _sync_meta_progress() -> void:
	max_depth_reached = maxi(max_depth_reached, maxi(1, depth))
	if meta_panel == null:
		meta_panel = _ui_find("MetaPanel") as MetaPanelController
	if meta_panel != null:
		meta_panel.set_progress(max_depth_reached, abyss_unlocked_flag)

func force_unlock_depth_tab(new_depth: int) -> void:
	max_depth_reached = maxi(max_depth_reached, new_depth)
	_sync_meta_progress()

# -------------------------
# WAKE FLOW
# -------------------------
func _on_wake_pressed() -> void:
	if prestige_panel == null:
		do_wake()
		return
	var mem_gain := calc_memories_gain() * wake_bonus_mult
	var d := clampi(depth, 1, DepthMetaSystem.MAX_DEPTH)
	var crystal_gain := calc_depth_currency_gain(d) * wake_bonus_mult
	prestige_panel.open_with_depth(mem_gain, crystal_gain, d)

func do_wake() -> void:
	if sound_system != null:
		sound_system.play_wake()
	memories += calc_memories_gain() * wake_bonus_mult
	award_depth_currency(wake_bonus_mult)
	reset_run()
	save_game()

func do_fail() -> void:
	if sound_system != null:
		sound_system.play_fail()
	memories += calc_memories_gain() * fail_penalty_mult
	award_depth_currency(fail_penalty_mult)
	reset_run()
	save_game()

func award_depth_currency(mult: float) -> void:
	if depth_meta_system == null:
		return
	var d := clampi(depth, 1, DepthMetaSystem.MAX_DEPTH)
	var gain := calc_depth_currency_gain(d) * mult
	depth_meta_system.currency[d] += gain

func calc_depth_currency_gain(depth_i: int) -> float:
	var t := maxf(total_thoughts_earned, 0.0)
	return sqrt(t) * (1.0 + float(depth_i) * 0.15) * 0.05

# -------------------------
# ACTIONS
# -------------------------
func do_dive() -> void:
	if dive_cooldown_timer > 0.0:
		return

	dive_cooldown_timer = _get_effective_dive_cooldown()
	depth += 1
	max_depth_reached = maxi(max_depth_reached, depth)

	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", depth)

	var cam := get_tree().current_scene.find_child("Camera3D", true, false)
	if cam and cam.has_method("snap_to_depth"):
		cam.call("snap_to_depth")

	if upgrade_manager.mental_buffer_level > 0:
		var bonus_control: float = float(depth) * upgrade_manager.get_mental_buffer_per_depth()
		control += bonus_control

	_check_abyss_unlock()

	if sound_system != null:
		sound_system.play_dive()

	var thoughts_mult: float = upgrade_manager.get_thoughts_mult() * perk_system.get_thoughts_mult() * nightmare_system.get_thoughts_mult()
	var instability_mult: float = upgrade_manager.get_instability_mult() * perk_system.get_instability_mult() * nightmare_system.get_instability_mult()
	var control_mult: float = perk_system.get_control_mult() * nightmare_system.get_control_mult()

	# GLOBAL depth-meta
	if depth_meta_system != null:
		thoughts_mult *= depth_meta_system.get_global_thoughts_mult()
		control_mult *= depth_meta_system.get_global_control_mult()

	if perm_perk_system != null:
		thoughts_mult *= perm_perk_system.get_thoughts_mult()
		instability_mult *= perm_perk_system.get_instability_mult()
		control_mult *= perm_perk_system.get_control_mult()

	if abyss_perk_system != null:
		thoughts_mult *= abyss_perk_system.get_thoughts_mult()
		control_mult *= abyss_perk_system.get_control_mult()

	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	var deep_risk_per_depth: float = upgrade_manager.get_deep_dives_instab_bonus_per_depth()
	var depth_thoughts_mult: float = 1.0 + (float(depth) * (depth_thoughts_step + deep_bonus_per_depth))
	var depth_instab_mult: float = 1.0 + (float(depth) * (depth_instab_step + deep_risk_per_depth))

	if overclock_system.active:
		thoughts_mult *= overclock_system.thoughts_mult
		instability_mult *= overclock_system.instability_mult

	thoughts += dive_thoughts_gain * thoughts_mult * depth_thoughts_mult
	control += dive_control_gain * control_mult

	var abyss_instab_mult: float = 1.0
	if abyss_perk_system != null:
		abyss_instab_mult = abyss_perk_system.get_instability_reduction_mult(depth)

	var depth_meta_instab_mult: float = 1.0
	if depth_meta_system != null:
		depth_meta_instab_mult = depth_meta_system.get_global_instability_mult()

	instability = risk_system.add_risk(
		instability,
		(dive_instability_gain * instability_mult * depth_instab_mult) * abyss_instab_mult * depth_meta_instab_mult
	)

	_sync_cracks()
	_sync_meta_progress()
	save_game()

func do_overclock() -> void:
	var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
	var duration_mul: float = upgrade_manager.get_overclock_duration_mult()
	var thoughts_add: float = upgrade_manager.get_overclock_thoughts_mult_bonus()
	var thoughts_mul: float = upgrade_manager.get_overclock_thoughts_mult_penalty()
	var instab_mul: float = upgrade_manager.get_overclock_instability_mult()

	var effective_cost: float = overclock_system.base_control_cost * cost_mul
	if control < effective_cost:
		return

	control -= effective_cost
	overclock_system.activate(thoughts_add, thoughts_mul, instab_mul, duration_mul, cost_mul)

	if sound_system != null:
		sound_system.play_overclock()

	save_game()

func reset_run() -> void:
	thoughts = 0.0
	control = 0.0
	instability = 0.0
	time_in_run = 0.0
	total_thoughts_earned = 0.0
	max_instability = 0.0

	# PERM starting bonuses
	if perm_perk_system != null:
		thoughts = perm_perk_system.get_starting_thoughts()
		instability = maxf(0.0, instability - perm_perk_system.get_starting_instability_reduction())

	var start_depth: int = 0
	if abyss_perk_system != null and abyss_unlocked_flag:
		start_depth = maxi(0, abyss_perk_system.get_start_depth_bonus())

	depth = start_depth
	run_start_depth = depth

	upgrade_manager.thoughts_level = 0
	upgrade_manager.stability_level = 0
	upgrade_manager.deep_dives_level = 0
	upgrade_manager.mental_buffer_level = 0
	upgrade_manager.overclock_mastery_level = 0
	upgrade_manager.overclock_safety_level = 0

	overclock_system.active = false
	dive_cooldown_timer = 0.0
	wake_guard_timer = wake_guard_seconds

	if pillar_stack != null and pillar_stack.has_method("reset_visuals"):
		pillar_stack.call("reset_visuals")
	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", depth)

	_sync_cracks()
	_sync_meta_progress()

func _check_abyss_unlock() -> void:
	if abyss_unlocked_flag:
		return
	if run_start_depth != 0:
		return
	if depth < abyss_target_depth:
		return

	abyss_unlocked_flag = true
	emit_signal("abyss_unlocked")
	_sync_meta_progress()
	save_game()

func calc_memories_gain() -> float:
	var t: float = maxf(total_thoughts_earned, 0.0)
	var r: float = clampf(max_instability / 100.0, 0.0, 1.0)
	var time_mult: float = clampf(time_in_run / 60.0, 0.5, 2.0)
	var depth_mult: float = 1.0 + (float(depth) * 0.10)
	return sqrt(t) * (1.0 + r) * time_mult * depth_mult

# -------------------------
# AFK TIMER (GLOBAL depth-meta)
# -------------------------
func get_seconds_until_fail() -> float:
	if instability >= 100.0:
		return 0.0

	var corruption = {"extra_instability": 0.0, "instability_mult": 1.0}
	var instability_mult: float = upgrade_manager.get_instability_mult() * perk_system.get_instability_mult() * nightmare_system.get_instability_mult()
	if perm_perk_system != null:
		instability_mult *= perm_perk_system.get_instability_mult()
	instability_mult *= float(corruption.instability_mult)

	var deep_risk_per_depth: float = upgrade_manager.get_deep_dives_instab_bonus_per_depth()
	var depth_instab_mult: float = 1.0 + (float(depth) * (depth_instab_step + deep_risk_per_depth))

	var abyss_instab_mult: float = 1.0
	if abyss_perk_system != null:
		abyss_instab_mult = abyss_perk_system.get_instability_reduction_mult(depth)

	var depth_meta_instab_mult: float = 1.0
	var depth_meta_idle_instab_mult: float = 1.0
	if depth_meta_system != null:
		depth_meta_instab_mult = depth_meta_system.get_global_instability_mult()
		depth_meta_idle_instab_mult = depth_meta_system.get_global_idle_instability_mult()

	var gain_per_sec := (idle_instability_rate * instability_mult * depth_instab_mult * abyss_instab_mult * depth_meta_instab_mult * depth_meta_idle_instab_mult) + float(corruption.extra_instability)
	if gain_per_sec <= 0.0001:
		return 999999.0
	return (100.0 - instability) / gain_per_sec

# -------------------------
# OFFLINE (GLOBAL depth-meta)
# -------------------------
func _apply_offline_progress() -> void:
	var data = SaveSystem.load_game()
	var now: float = float(Time.get_unix_time_from_system())

	if not data.has("last_play_time"):
		offline_seconds = 0.0
		return

	var last_time: float = float(data.get("last_play_time", now))
	offline_seconds = clampf(now - last_time, 0.0, MAX_OFFLINE_SECONDS)

	if offline_seconds < 1.0:
		offline_seconds = 0.0
		return

	var _corruption = {"extra_instability": 0.0, "thoughts_mult": 1.0, "instability_mult": 1.0}

	var thoughts_mult: float = upgrade_manager.get_thoughts_mult() * perk_system.get_thoughts_mult() * nightmare_system.get_thoughts_mult()
	var instability_mult: float = upgrade_manager.get_instability_mult() * perk_system.get_instability_mult() * nightmare_system.get_instability_mult()
	var control_mult: float = perk_system.get_control_mult() * nightmare_system.get_control_mult()

	# GLOBAL depth-meta
	var depth_meta_thoughts_mult: float = 1.0
	var depth_meta_control_mult: float = 1.0
	var depth_meta_instab_mult: float = 1.0
	var depth_meta_idle_instab_mult: float = 1.0
	if depth_meta_system != null:
		depth_meta_thoughts_mult = depth_meta_system.get_global_thoughts_mult()
		depth_meta_control_mult = depth_meta_system.get_global_control_mult()
		depth_meta_instab_mult = depth_meta_system.get_global_instability_mult()
		depth_meta_idle_instab_mult = depth_meta_system.get_global_idle_instability_mult()

	thoughts_mult *= depth_meta_thoughts_mult
	control_mult *= depth_meta_control_mult

	if perm_perk_system != null:
		thoughts_mult *= perm_perk_system.get_thoughts_mult()
		instability_mult *= perm_perk_system.get_instability_mult()
		control_mult *= perm_perk_system.get_control_mult()

	if abyss_perk_system != null:
		thoughts_mult *= abyss_perk_system.get_thoughts_mult()
		control_mult *= abyss_perk_system.get_control_mult()

	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	var deep_risk_per_depth: float = upgrade_manager.get_deep_dives_instab_bonus_per_depth()
	var depth_thoughts_mult: float = 1.0 + (float(depth) * (depth_thoughts_step + deep_bonus_per_depth))
	var depth_instab_mult: float = 1.0 + (float(depth) * (depth_instab_step + deep_risk_per_depth))

	var offline_mult := 1.0
	if perm_perk_system != null:
		offline_mult = perm_perk_system.get_offline_mult()

	thoughts += idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * offline_seconds * offline_mult
	control += idle_control_rate * control_mult * offline_seconds * offline_mult

	var abyss_instab_mult: float = 1.0
	if abyss_perk_system != null:
		abyss_instab_mult = abyss_perk_system.get_instability_reduction_mult(depth)

	instability = risk_system.add_risk(
		instability,
		(idle_instability_rate * instability_mult * depth_instab_mult * offline_seconds) * abyss_instab_mult * depth_meta_instab_mult * depth_meta_idle_instab_mult
	)

	instability = minf(instability, 99.9)

	time_in_run += offline_seconds
	total_thoughts_earned = maxf(total_thoughts_earned, thoughts)
	max_instability = maxf(max_instability, instability)
	max_depth_reached = maxi(max_depth_reached, depth)

	_check_abyss_unlock()
	_sync_cracks()
	_sync_meta_progress()

# -------------------------
# SAVE / LOAD (unchanged)
# -------------------------
func save_game() -> void:
	var data = SaveSystem.load_game()
	data["memories"] = memories
	data["thoughts"] = thoughts
	data["control"] = control
	data["instability"] = instability
	data["time_in_run"] = time_in_run
	data["total_thoughts_earned"] = total_thoughts_earned
	data["max_instability"] = max_instability
	data["depth"] = depth
	data["max_depth_reached"] = max_depth_reached
	data["abyss_unlocked"] = abyss_unlocked_flag
	data["run_start_depth"] = run_start_depth

	if abyss_perk_system != null:
		data["abyss_echoed_descent_level"] = abyss_perk_system.echoed_descent_level
		data["abyss_abyssal_focus_level"] = abyss_perk_system.abyssal_focus_level
		data["abyss_dark_insight_level"] = abyss_perk_system.dark_insight_level
		data["abyss_veil_level"] = abyss_perk_system.abyss_veil_level

	if perm_perk_system != null:
		data["perm_memory_engine_level"] = perm_perk_system.memory_engine_level
		data["perm_calm_mind_level"] = perm_perk_system.calm_mind_level
		data["perm_focused_will_level"] = perm_perk_system.focused_will_level
		data["perm_starting_insight_level"] = perm_perk_system.starting_insight_level
		data["perm_stability_buffer_level"] = perm_perk_system.stability_buffer_level
		data["perm_offline_echo_level"] = perm_perk_system.offline_echo_level

	if depth_meta_system != null:
		for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
			data["depth_currency_%d" % i] = depth_meta_system.currency[i]
			data["depth_instab_reduce_level_%d" % i] = depth_meta_system.instab_reduce_level[i]
			data["depth_unlock_next_bought_%d" % i] = depth_meta_system.unlock_next_bought[i]

	data["thoughts_level"] = upgrade_manager.thoughts_level
	data["stability_level"] = upgrade_manager.stability_level
	data["deep_dives_level"] = upgrade_manager.deep_dives_level
	data["mental_buffer_level"] = upgrade_manager.mental_buffer_level
	data["overclock_mastery_level"] = upgrade_manager.overclock_mastery_level
	data["overclock_safety_level"] = upgrade_manager.overclock_safety_level

	data["perk1_level"] = perk_system.perk1_level
	data["perk2_level"] = perk_system.perk2_level
	data["perk3_level"] = perk_system.perk3_level

	data["last_play_time"] = Time.get_unix_time_from_system()
	SaveSystem.save_game(data)

func load_game() -> void:
	var data = SaveSystem.load_game()
	if data.is_empty():
		return

	memories = float(data.get("memories", 0.0))
	thoughts = float(data.get("thoughts", 0.0))
	control = float(data.get("control", 0.0))
	instability = float(data.get("instability", 0.0))
	time_in_run = float(data.get("time_in_run", 0.0))
	total_thoughts_earned = float(data.get("total_thoughts_earned", 0.0))
	max_instability = float(data.get("max_instability", 0.0))

	depth = int(data.get("depth", 0))
	max_depth_reached = int(data.get("max_depth_reached", 1))

	abyss_unlocked_flag = bool(data.get("abyss_unlocked", false))
	run_start_depth = int(data.get("run_start_depth", depth))

	if abyss_perk_system != null:
		abyss_perk_system.echoed_descent_level = int(data.get("abyss_echoed_descent_level", 0))
		abyss_perk_system.abyssal_focus_level = int(data.get("abyss_abyssal_focus_level", 0))
		abyss_perk_system.dark_insight_level = int(data.get("abyss_dark_insight_level", 0))
		abyss_perk_system.abyss_veil_level = int(data.get("abyss_veil_level", 0))

	if perm_perk_system != null:
		perm_perk_system.memory_engine_level = int(data.get("perm_memory_engine_level", 0))
		perm_perk_system.calm_mind_level = int(data.get("perm_calm_mind_level", 0))
		perm_perk_system.focused_will_level = int(data.get("perm_focused_will_level", 0))
		perm_perk_system.starting_insight_level = int(data.get("perm_starting_insight_level", 0))
		perm_perk_system.stability_buffer_level = int(data.get("perm_stability_buffer_level", 0))
		perm_perk_system.offline_echo_level = int(data.get("perm_offline_echo_level", 0))

	if depth_meta_system != null:
		depth_meta_system.ensure_ready()
		for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
			depth_meta_system.currency[i] = float(data.get("depth_currency_%d" % i, 0.0))
			depth_meta_system.instab_reduce_level[i] = int(data.get("depth_instab_reduce_level_%d" % i, 0))
			depth_meta_system.unlock_next_bought[i] = int(data.get("depth_unlock_next_bought_%d" % i, 0))

	upgrade_manager.thoughts_level = int(data.get("thoughts_level", 0))
	upgrade_manager.stability_level = int(data.get("stability_level", 0))
	upgrade_manager.deep_dives_level = int(data.get("deep_dives_level", 0))
	upgrade_manager.mental_buffer_level = int(data.get("mental_buffer_level", 0))
	upgrade_manager.overclock_mastery_level = int(data.get("overclock_mastery_level", 0))
	upgrade_manager.overclock_safety_level = int(data.get("overclock_safety_level", 0))

	perk_system.perk1_level = int(data.get("perk1_level", 0))
	perk_system.perk2_level = int(data.get("perk2_level", 0))
	perk_system.perk3_level = int(data.get("perk3_level", 0))

# -------------------------
# UI BINDING
# -------------------------
func _bind_ui_mainui() -> void:
	thoughts_label = _ui_find("ThoughtsLabel") as Label
	control_label = _ui_find("ControlLabel") as Label
	instability_label = _ui_find("InstabilityLabel") as Label
	instability_bar = _ui_find("InstabilityBar") as Range

	overclock_button = _ui_find_button("OverclockButton")
	dive_button = _ui_find_button("DiveButton")
	wake_button = _ui_find_button("WakeButton")
	meta_button = _ui_find_button("Meta")

	auto_dive_toggle = _ui_find_toggle("AutoDiveToggle")
	auto_overclock_toggle = _ui_find_toggle("AutoOverclockToggle")

	meta_panel = _ui_find("MetaPanel") as MetaPanelController
	prestige_panel = _ui_find("PrestigePanel") as PrestigePanel
	_connect_prestige_panel()

func _ui_find(node_name: String) -> Node:
	return get_tree().current_scene.find_child(node_name, true, false)

func _ui_find_button(node_name: String) -> Button:
	return _ui_find(node_name) as Button

func _ui_find_toggle(node_name: String) -> BaseButton:
	return _ui_find(node_name) as BaseButton

# -------------------------
# AUTOMATION
# -------------------------
func _on_auto_dive_toggled(on: bool) -> void:
	automation_system.auto_dive = on

func _on_auto_overclock_toggled(on: bool) -> void:
	automation_system.auto_overclock = on

func _try_auto_overclock() -> void:
	if overclock_system.active:
		return
	var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
	overclock_system.control_cost = overclock_system.base_control_cost * cost_mul
	if not overclock_system.can_activate(control):
		return
	if instability >= 85.0:
		return
	do_overclock()

# -------------------------
# BUTTON HELPERS
# -------------------------
func _press_button(btn: Button) -> void:
	if btn == null or btn.disabled:
		return
	btn.pressed.emit()

func _connect_pressed_once(btn: Button, cb: Callable) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(cb):
		btn.pressed.connect(cb)

# -------------------------
# NUMBER FORMAT
# -------------------------
func _fmt_num(v: float) -> String:
	if v >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	if v >= 1000.0:
		return "%.2fK" % (v / 1000.0)
	return str(int(floor(v)))

# -------------------------
# UpgradeRow compatibility wrappers (unchanged)
# -------------------------
func _apply_thoughts_return(res) -> void:
	if res is float or res is int:
		thoughts = float(res)

func do_buy_thoughts_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_thoughts_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_thoughts_upgrade", thoughts))
		save_game()

func do_buy_stability_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_stability_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_stability_upgrade", thoughts))
		save_game()

func do_buy_deep_dives_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_deep_dives_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_deep_dives_upgrade", thoughts))
		save_game()

func do_buy_mental_buffer_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_mental_buffer_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_mental_buffer_upgrade", thoughts))
		save_game()

func do_buy_overclock_mastery_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_overclock_mastery_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_overclock_mastery_upgrade", thoughts))
		save_game()

func do_buy_overclock_safety_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_overclock_safety_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_overclock_safety_upgrade", thoughts))
		save_game()

func _connect_prestige_panel() -> void:
	if prestige_panel == null:
		return
	if not prestige_panel.confirm_wake.is_connected(Callable(self, "_on_prestige_confirm_wake")):
		prestige_panel.confirm_wake.connect(Callable(self, "_on_prestige_confirm_wake"))
	if not prestige_panel.cancel.is_connected(Callable(self, "_on_prestige_cancel")):
		prestige_panel.cancel.connect(Callable(self, "_on_prestige_cancel"))

func _on_prestige_confirm_wake() -> void:
	do_wake()
	if prestige_panel != null:
		prestige_panel.close()

func _on_prestige_cancel() -> void:
	if prestige_panel != null:
		prestige_panel.close()
