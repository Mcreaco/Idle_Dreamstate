extends Node
class_name GameManager

signal abyss_unlocked

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
@onready var top_bar_panel: TopBarPanel = $"../MainUI/Root/TopBarPanel"
@onready var ad_service: AdService = get_node_or_null("/root/AdService")

@export var dive_cd_min: float = 0.0
@export var perk2_cd_reduction_per_level: float = 0.0
func _get_effective_dive_cooldown() -> float:
	return 0.0
@export var auto_overclock_instability_limit: float = 85.0
var auto_buy_unlocked_depths: Array[int] = []
var _last_wake_depth_for_meta: int = 1
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

var thoughts: float = 0.0
var control: float = 0.0
var instability: float = 0.0
var time_in_run: float = 0.0
var total_thoughts_earned: float = 0.0
var max_instability: float = 0.0
var max_depth_reached: int = 1
var frozen_depth_multipliers: Dictionary
var abyss_unlocked_flag: bool = false
var run_start_depth: int = 0
var abyss_target_depth: int = 15
var lifetime_thoughts: float = 0.0
var lifetime_control: float = 0.0
var total_dives: int = 0
var total_playtime: float = 0.0
const LT_THOUGHTS := "lifetime_thoughts"
const LT_CONTROL := "lifetime_control"
const LT_DIVES := "total_dives"
const LT_DEEPEST := "deepest_depth"
const LT_PLAYTIME := "total_playtime"
var memories: float = 0.0

var idle_thoughts_rate: float = 0.8
var idle_control_rate: float = 0.5
var idle_instability_rate: float = 0.12

var dive_thoughts_gain: float = 18.0
var dive_control_gain: float = 6.0

var wake_bonus_mult: float = 1.35
var fail_penalty_mult: float = 0.60

var depth_thoughts_step: float = 0.05
var depth_instab_step: float = 0.08

var wake_guard_seconds: float = 0.35
var wake_guard_timer: float = 0.0

const MAX_OFFLINE_SECONDS: float = 3600.0
var offline_seconds: float = 0.0

var autosave_timer: float = 0.0
var autosave_interval: float = 10.0

var _crack_sync_timer: float = 0.0

var _rate_sample_timer: float = 0.0
var _last_thoughts_sample: float = 0.0
var _last_control_sample: float = 0.0
var _thoughts_ps: float = 0.0
var _control_ps: float = 0.0

var _warned_missing_top_bar: bool = false
var _warned_missing_pillar: bool = false
var _warned_missing_sound: bool = false

var _ui_flash_phase: float = 0.0

static var _persist_debug_visible: bool = false
var _debug_overlay_layer: CanvasLayer
var _debug_label: Label
var _debug_visible: bool = false
var _depth_cache: int = 1
var run_time: float = 0.0

var timed_boost_timer: float = 0.0
var timed_boost_active: bool = false
var _fail_save_prompt_shown: bool = false
var _fail_save_used: bool = false
var tutorial_manager: TutorialManager = null

var total_runs: int = 0  # Increment this when waking
var is_diving: bool = false  # Set to true when diving, false when idle
var max_depth_tier_reached: int = 1  # Track highest depth unlocked

func get_dive_instability_gain(depth: int) -> float:
	return 5.0 + (depth * 1.5)

func _fmt_num(v: float) -> String:
	if v >= 1000000.0:
		return "%.2fM" % (v / 1000000.0)
	if v >= 1000.0:
		return "%.2fK" % (v / 1000.0)
	return str(int(floor(v)))

func _fmt_time_ui(sec: float) -> String:
	if sec >= 999900.0:
		return "--:--"
	sec = maxf(sec, 0.0)
	var m: int = int(floor(sec / 60.0))
	var s: int = int(fmod(sec, 60.0))
	return "%d:%02d" % [m, s]

func get_current_depth() -> int:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		var ad = drc.get("active_depth")
		if ad != null:
			_depth_cache = int(ad)
			return _depth_cache
	return _depth_cache

func _on_depth_changed_from_controller(new_depth: int) -> void:
	_depth_cache = new_depth
	_update_depth_ui()
	
	# Show/hide instability bar based on depth
	var show_instability := (new_depth >= 2)
	if instability_bar != null:
		instability_bar.visible = show_instability
	if instability_label != null:
		instability_label.visible = show_instability
	
	save_game()
	
func _safe_mult(v: float) -> float:
	return v if v > 0.0 else 1.0

func _update_depth_ui() -> void:
	if top_bar_panel != null and top_bar_panel.has_method("set_depth_ui") and pillar_stack != null:
		top_bar_panel.set_depth_ui(get_current_depth(), pillar_stack.get_child_count())
		
func _sync_cracks() -> void:
	if pillar_stack != null and pillar_stack.has_method("set_instability"):
		pillar_stack.call("set_instability", instability, 100.0)

func _warn_missing_nodes_once() -> void:
	if pillar_stack == null and not _warned_missing_pillar:
		push_warning("pillar_stack missing (Segments).")
		_warned_missing_pillar = true
	if sound_system == null and not _warned_missing_sound:
		push_warning("sound_system missing at ../SoundSystem.")
		_warned_missing_sound = true

func _ready() -> void:
	_warn_missing_nodes_once()
	set_process_priority(1000)
	
	# Wait for next frame to ensure DepthRunController is ready
	await get_tree().process_frame
	
	# Now load game
	load_game()
	
	# Apply offline progress AFTER loading
	_apply_offline_progress()
	
	_bind_ui_mainui()
	
	_last_thoughts_sample = thoughts
	_last_control_sample = control
	
	_sync_meta_progress()
	
	_connect_pressed_once(overclock_button, Callable(self, "do_overclock"))
	_connect_pressed_once(dive_button, Callable(self, "_on_dive_pressed"))
	_connect_pressed_once(wake_button, Callable(self, "_on_wake_pressed"))
	_connect_pressed_once(meta_button, Callable(self, "_on_meta_pressed"))
	
	if ad_service != null:
		if not ad_service.reward_timed_boost.is_connected(Callable(self, "_on_ad_timed_boost")):
			ad_service.reward_timed_boost.connect(Callable(self, "_on_ad_timed_boost"))
		if not ad_service.reward_fail_save.is_connected(Callable(self, "_on_ad_fail_save_reward")):
			ad_service.reward_fail_save.connect(Callable(self, "_on_ad_fail_save_reward"))
	
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
	
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		var panel := get_tree().current_scene.find_child("DepthBarsPanel", true, false)
		if panel != null and drc.has_method("bind_panel"):
			drc.bind_panel(panel)
		# NOW sync after binding
		if drc.has_method("_sync_all_to_panel"):
			drc.call("_sync_all_to_panel")
	
	if time_in_run <= 0.0:
		run_start_depth = get_current_depth()
	
	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", get_current_depth())
	
	if pillar_stack != null and pillar_stack.has_method("reset_visuals"):
		pillar_stack.call("reset_visuals")
		
	
	
	_update_depth_ui()
	_sync_cracks()
	_refresh_top_ui()
	_update_buttons_ui()
	_force_cooldown_texts()
	save_game()
	
	_debug_visible = _persist_debug_visible
	if _debug_visible:
		_toggle_debug_overlay()
		_debug_visible = true
	_update_debug_overlay()
	
	# TEST: Force tutorial after 2 seconds
	await get_tree().create_timer(2.0).timeout
	var tm = get_node_or_null("/root/TutorialManage")  # Not TutorialManager
	if tm:
		tm.start_tutorial("wake_unlocked")
	else:
		print("ERROR: TutorialManager not found at /root/TutorialManager")
		
	load_game()
	print("LOADED - Total dives: ", total_dives)  # Check if loading works

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		print("Current total_dives: ", total_dives)
		print("Lifetime thoughts: ", lifetime_thoughts)
		
func _force_rate_sample() -> void:
	_last_thoughts_sample = thoughts
	_last_control_sample = control
	_rate_sample_timer = 0.0
	_thoughts_ps = 0.0
	_control_ps = 0.0

func _refresh_top_ui() -> void:
	if top_bar_panel == null:
		if not _warned_missing_top_bar:
			push_warning("TopBarPanel missing at ../MainUI/Root/TopBarPanel")
			_warned_missing_top_bar = true
		return

	if thoughts_label != null:
		thoughts_label.text = "Thoughts: %s" % _fmt_num(thoughts)
	if control_label != null:
		control_label.text = "Control: %s" % _fmt_num(control)
	if instability_bar != null:
		instability_bar.min_value = 0.0
		instability_bar.max_value = 100.0
		instability_bar.value = clampf(instability, 0.0, 100.0)
		# CRITICAL FIX: Only show bar at depth 2+
		# var current_depth = get_current_depth()
		instability_bar.visible = (get_current_depth() >= 2)
	if instability_label != null:
		instability_label.text = "Instability"
		instability_label.visible = (get_current_depth() >= 2)

	if top_bar_panel.has_method("update_top_bar"):
		var inst_pct: float = clampf(instability, 0.0, 100.0)
		var overclock_time_left: float = 0.0
		if overclock_system != null and overclock_system.active:
			overclock_time_left = maxf(overclock_system.timer, 0.0)
		var ttf: float = get_seconds_until_fail()
		var inst_gain: float = get_idle_instability_gain_per_sec()

		var disp_thoughts_ps := maxf(_thoughts_ps, 0.0)
		var disp_control_ps := maxf(_control_ps, 0.0)

		top_bar_panel.update_top_bar(
			thoughts,
			disp_thoughts_ps,
			control,
			disp_control_ps,
			inst_pct,
			overclock_system != null and overclock_system.active,
			overclock_time_left,
			ttf,
			inst_gain
		)
	
	# Silence (Depth 9) - hide numbers if rule active and not upgraded
	var current_depth := get_current_depth()
	var hide_numbers := false
	
	if current_depth == 9:
		var drc := get_node_or_null("/root/DepthRunController")
		if drc != null:
			var def: Dictionary = drc.get_depth_def(9)
			var rules: Dictionary = def.get("rules", {})
			if rules.get("hide_all_numbers", false):
				# Check if player bought Inner Eye upgrade
				var inner_eye_lvl := 0
				if drc.has_method("_get_local_level"):
					inner_eye_lvl = drc.call("_get_local_level", 9, "inner_eye")
				if inner_eye_lvl == 0:
					hide_numbers = true
	
	if thoughts_label != null:
		if hide_numbers:
			thoughts_label.text = "Thoughts: ???"
			thoughts_label.modulate = Color(0.5, 0.5, 0.5, 0.3)
		else:
			thoughts_label.text = "Thoughts: %s" % _fmt_num(thoughts)
			thoughts_label.modulate = Color(1, 1, 1, 1)

	_update_depth_ui()

func _set_button_dim(btn: Button, enabled: bool) -> void:
	if btn == null:
		return
	btn.modulate = Color(1, 1, 1, 1) if enabled else Color(0.65, 0.65, 0.65, 1)

func _update_buttons_ui() -> void:
	if overclock_button != null:
		var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
		var effective_overclock_cost: float = overclock_system.base_control_cost * cost_mul
		var disabled_reason := ""
		if overclock_system.active:
			disabled_reason = "Overclock already active."
		elif control < effective_overclock_cost:
			disabled_reason = "Need %d Control." % int(round(effective_overclock_cost))
		overclock_button.disabled = overclock_system.active or (control < effective_overclock_cost)
		if overclock_button.disabled and disabled_reason != "":
			overclock_button.tooltip_text = disabled_reason + "\n" + overclock_button.tooltip_text
		_set_button_dim(overclock_button, not overclock_button.disabled)

	if dive_button != null:
		var drc := get_node_or_null("/root/DepthRunController")
		var can_dive_now := false
		var dive_tooltip := ""
		
		if drc != null and drc.has_method("can_dive"):
			can_dive_now = drc.can_dive()
			
			# Specific messaging for Depth 2
			if not can_dive_now and drc.get("active_depth") == 1:
				dive_tooltip = "Complete Depth 1 to unlock Dive"
			elif not can_dive_now and drc.get("active_depth") == 2:
				var info = drc.get_run_upgrade_info(2, "stabilize")
				var current_lv = info.get("current_level", 0)
				dive_tooltip = "LOCKED: Need Stabilize Lv 3 (Current: Lv %d/3)" % current_lv
			elif not can_dive_now:
				dive_tooltip = "Unlock next depth in Meta panel first"
			else:
				dive_tooltip = "Dive to next depth"
		
		dive_button.visible = (drc != null and drc.get("active_depth") < drc.get("max_depth"))
		dive_button.disabled = not can_dive_now
		dive_button.tooltip_text = dive_tooltip

	if wake_button != null:
		wake_button.tooltip_text = "End run and convert to memories."
		_set_button_dim(wake_button, not wake_button.disabled)
		
func _build_overclock_tooltip(cost: float, duration_mul: float, thoughts_add: float, thoughts_mul: float, instab_mul: float, active: bool, sec_left: float, extra: String) -> String:
	if active:
		return "Overclock active. Remaining: %ds.\nThoughts: +%.2f add, x%.2f mult\nInstability: x%.2f%s" % [
			int(ceil(sec_left)),
			thoughts_add,
			thoughts_mul,
			instab_mul,
			("" if extra == "" else "\n" + extra)
		]
	return "Cost: %d Control\nDuration x%.2f\nThoughts: +%.2f add, x%.2f mult\nInstability: x%.2f%s" % [
		int(round(cost)),
		duration_mul,
		thoughts_add,
		thoughts_mul,
		instab_mul,
		("" if extra == "" else "\n" + extra)
	]

func _force_cooldown_texts() -> void:
	var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
	var effective_cost: float = overclock_system.base_control_cost * cost_mul
	var duration_mul: float = upgrade_manager.get_overclock_duration_mult()
	var thoughts_add: float = upgrade_manager.get_overclock_thoughts_mult_bonus()
	var thoughts_mul: float = upgrade_manager.get_overclock_thoughts_mult_penalty()
	var instab_mul: float = upgrade_manager.get_overclock_instability_mult()

	if overclock_button != null:
		if overclock_system.active:
			var sec_left_o: int = int(ceil(maxf(overclock_system.timer, 0.0)))
			overclock_button.text = "Overclock (%ds)" % sec_left_o
			overclock_button.tooltip_text = _build_overclock_tooltip(effective_cost, duration_mul, thoughts_add, thoughts_mul, instab_mul, true, sec_left_o, "")
		else:
			overclock_button.text = "Overclock (-%d Control)" % int(round(effective_cost))
			overclock_button.tooltip_text = _build_overclock_tooltip(effective_cost, duration_mul, thoughts_add, thoughts_mul, instab_mul, false, 0.0, "")

	if dive_button != null:
		dive_button.text = "Dive"

	if wake_button != null:
		wake_button.text = "Wake"

func _on_meta_pressed() -> void:
	if meta_panel == null:
		meta_panel = _ui_find("MetaPanel") as MetaPanelController
	if meta_panel == null:
		push_warning("MetaPanelController not found on MetaPanel.")
		return
	_sync_meta_progress()
	meta_panel.toggle_open()
	_force_rate_sample()
	_refresh_top_ui()
	
	# Notify tutorial manager
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_meta_opened"):
		tm.on_meta_opened()

func _sync_meta_progress() -> void:
	var current_depth = get_current_depth()
	max_depth_reached = maxi(max_depth_reached, maxi(1, current_depth))
	
	if meta_panel == null:
		meta_panel = _ui_find("MetaPanel") as MetaPanelController
	
	if meta_panel != null:
		meta_panel.set_progress(max_depth_reached, abyss_unlocked_flag)

func force_unlock_depth_tab(new_depth: int) -> void:
	max_depth_reached = maxi(max_depth_reached, new_depth)
	_sync_meta_progress()

func _on_wake_pressed() -> void:
	if prestige_panel == null:
		prestige_panel = _ui_find("PrestigePanel") as PrestigePanel
	if prestige_panel == null:
		push_warning("GameManager: PrestigePanel not found; Wake blocked.")
		return

	var drc := get_node_or_null("/root/DepthRunController")
	var d: int = 1
	var mem_gain: float = 0.0
	var crystals_by_name: Dictionary = {}

	if drc != null and "active_depth" in drc:
		d = int(drc.get("active_depth"))

	if drc != null and drc.has_method("preview_wake"):
		var prev: Dictionary = drc.call("preview_wake", 1.0, false)
		mem_gain = float(prev.get("memories", 0.0))
		crystals_by_name = prev.get("crystals_by_name", {})
	else:
		mem_gain = calc_memories_gain() * wake_bonus_mult
		var current_depth = get_current_depth()
		for depth_i in range(1, current_depth + 1):
			var cry_name = DepthMetaSystem.get_depth_currency_name(depth_i)
			var cry_amt = calc_depth_currency_gain(depth_i) * wake_bonus_mult
			crystals_by_name[cry_name] = float(crystals_by_name.get(cry_name, 0.0)) + cry_amt

	_last_wake_depth_for_meta = d
	prestige_panel.open_with_depth(mem_gain, crystals_by_name, d)
	
	total_runs += 1
	# Notify tutorial that wake was clicked
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("WakeButton")

# Connect button clicks to tutorial manager
func _connect_tutorial_signals() -> void:
	# This should be called after UI is ready
	var meta = find_child("MetaPanelController", true, false)
	if meta != null and tutorial_manager != null:
		var tab_perm = meta.find_child("TabPerm", true, false) as Button
		var tab_depth = meta.find_child("TabDepth", true, false) as Button
		var close_btn = meta.find_child("CloseButton", true, false) as Button
		
		if tab_perm:
			tab_perm.pressed.connect(func(): tutorial_manager.on_button_clicked("TabPerm"))
		if tab_depth:
			tab_depth.pressed.connect(func(): tutorial_manager.on_button_clicked("TabDepth"))
		if close_btn:
			close_btn.pressed.connect(func(): tutorial_manager.on_button_clicked("CloseButton"))
		
func _on_prestige_confirm_wake() -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return
	
	# ACCUMULATE LIFETIME STATS BEFORE RESET
	lifetime_thoughts += total_thoughts_earned
	lifetime_control += control  # or track control spent/gained
	total_playtime += time_in_run
	
	# Get accumulated memories/crystals from depth_data
	var accumulated_memories := 0.0
	var accumulated_crystals := 0.0
	var active_d: int = drc.get("active_depth") as int
	var run_data: Array = drc.get("run") as Array
	if run_data != null and active_d >= 1 and active_d <= run_data.size():
		var depth_data: Dictionary = run_data[active_d - 1]
		accumulated_memories = float(depth_data.get("memories", 0.0))
		accumulated_crystals = float(depth_data.get("crystals", 0.0))
	
	var result = drc.call("wake_cashout", 1.0, false)
	
	if result is Dictionary:
		var gained_memories = float(result.get("memories", 0.0))
		# ADD accumulated memories from depth_data
		gained_memories += accumulated_memories
		memories += gained_memories
		var crystals = result.get("crystals_by_name", {})
		
		# ADD accumulated crystals from depth_data
		var active_currency_name := DepthMetaSystem.get_depth_currency_name(active_d)
		if accumulated_crystals > 0:
			crystals[active_currency_name] = float(crystals.get(active_currency_name, 0.0)) + accumulated_crystals
		
		for currency_name in crystals.keys():
			var amount = float(crystals[currency_name])
			for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
				if DepthMetaSystem.get_depth_currency_name(i) == currency_name:
					if depth_meta_system != null:
						depth_meta_system.currency[i] += amount
					break
	
	reset_run()
	save_game()
	
	if prestige_panel != null:
		prestige_panel.close()
	
	_force_rate_sample()
	_refresh_top_ui()

func do_fail() -> void:
	if ad_service != null and ad_service.can_show(AdService.AD_FAIL_SAVE) and not _fail_save_prompt_shown:
		_show_fail_save_prompt()
		return
	
	if sound_system != null:
		sound_system.play_fail()
	
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null and drc.has_method("wake_cashout"):
		# CRITICAL FIX: Get accumulated memories/crystals from depth_data
		var accumulated_memories := 0.0
		var accumulated_crystals := 0.0
		var active_d: int = drc.get("active_depth") as int
		var run_data: Array = drc.get("run") as Array
		if run_data != null and active_d >= 1 and active_d <= run_data.size():
			var depth_data: Dictionary = run_data[active_d - 1]
			accumulated_memories = float(depth_data.get("memories", 0.0))
			accumulated_crystals = float(depth_data.get("crystals", 0.0))
		
		var result = drc.call("wake_cashout", 1.0, true)
		if result is Dictionary:
			var gained_memories = float(result.get("memories", 0.0))
			# CRITICAL FIX: Add accumulated memories from offline progress
			gained_memories += accumulated_memories
			memories += gained_memories
			
			
			var crystals = result.get("crystals_by_name", {})
			
			# CRITICAL FIX: Add accumulated crystals from offline progress
			var active_currency_name := DepthMetaSystem.get_depth_currency_name(active_d)
			if accumulated_crystals > 0:
				crystals[active_currency_name] = float(crystals.get(active_currency_name, 0.0)) + accumulated_crystals
			
			for currency_name in crystals.keys():
				var amount = float(crystals[currency_name])
				for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
					if DepthMetaSystem.get_depth_currency_name(i) == currency_name:
						if depth_meta_system != null:
							depth_meta_system.currency[i] += amount
						break
	
	# ACCUMULATE LIFETIME STATS (same as wake)
	lifetime_thoughts += total_thoughts_earned
	lifetime_control += control
	total_playtime += time_in_run
	
	reset_run()
	save_game()

func freeze_current_depth_multiplier() -> void:
	var current_depth = get_current_depth()
	var current_multiplier = _get_current_depth_progress_multiplier(current_depth)
	frozen_depth_multipliers[current_depth] = current_multiplier
	
func calc_depth_currency_gain(depth_i: int) -> float:
	var t := maxf(total_thoughts_earned, 0.0)
	return sqrt(t) * (1.0 + float(depth_i) * 0.15) * 0.05
	
func do_dive() -> void:
	print("DO_DIVE CALLED")  # Debug print to confirm it's being called
	total_dives += 1  # MUST BE FIRST LINE
	print("Total dives is now: ", total_dives)
	# CRITICAL: Freeze the current depth's multiplier BEFORE diving
	freeze_current_depth_multiplier()
	
	var current_depth := get_current_depth()
	var next_depth := current_depth + 1
	
	# Dive calculations - do these BEFORE changing depth
	var thoughts_mult: float = _safe_mult(upgrade_manager.get_thoughts_mult()) * _safe_mult(perk_system.get_thoughts_mult()) * _safe_mult(nightmare_system.get_thoughts_mult()) * _get_run_upgrades_thoughts_mult()
	var instability_mult: float = _safe_mult(upgrade_manager.get_instability_mult()) * _safe_mult(perk_system.get_instability_mult()) * _safe_mult(nightmare_system.get_thoughts_mult())
	var control_mult: float = _safe_mult(perk_system.get_control_mult()) * _safe_mult(nightmare_system.get_control_mult())
	
	if depth_meta_system != null:
		thoughts_mult *= _safe_mult(depth_meta_system.get_global_thoughts_mult())
		control_mult *= _safe_mult(depth_meta_system.get_global_control_mult())
	
	if perm_perk_system != null:
		thoughts_mult *= _safe_mult(perm_perk_system.get_thoughts_mult())
		instability_mult *= _safe_mult(perm_perk_system.get_instability_mult())
		control_mult *= _safe_mult(perm_perk_system.get_control_mult())
	
	if abyss_perk_system != null:
		thoughts_mult *= _safe_mult(abyss_perk_system.get_thoughts_mult())
		control_mult *= _safe_mult(abyss_perk_system.get_control_mult())
	
	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	var deep_risk_per_depth: float = upgrade_manager.get_deep_dives_instab_bonus_per_depth()
	
	var depth_thoughts_mult: float = 1.0 + (float(next_depth) * (depth_thoughts_step + deep_bonus_per_depth))
	var depth_instab_mult: float = 1.0 + (float(next_depth) * (depth_instab_step + deep_risk_per_depth))
	
	if overclock_system.active:
		thoughts_mult *= _safe_mult(overclock_system.thoughts_mult)
		instability_mult *= _safe_mult(overclock_system.instability_mult)
	
	# Apply dive gains
	thoughts += dive_thoughts_gain * thoughts_mult * depth_thoughts_mult
	control += dive_control_gain * control_mult
	
	var abyss_instab_mult: float = 1.0
	if abyss_perk_system != null:
		abyss_instab_mult = abyss_perk_system.get_instability_reduction_mult(next_depth)
	
	var depth_meta_instab_mult: float = 1.0
	if depth_meta_system != null:
		depth_meta_instab_mult = _safe_mult(depth_meta_system.get_global_instability_mult())
	
	# Apply dive instability (using current_depth for the calculation)
	instability = risk_system.add_risk(
		instability,
		((5.0 + (current_depth * 1.5)) * instability_mult * depth_instab_mult) * abyss_instab_mult * depth_meta_instab_mult
	)
	
	# CRITICAL: Reset to 0% when entering Depth 2
	if next_depth == 2:
		instability = 0.0
		_sync_cracks()
	
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return
	
	# Check current run data before any changes
	var run_before: Array = drc.get("run") as Array
	if run_before != null and current_depth >= 1 and current_depth <= run_before.size():
		print("DO_DIVE: Depth ", current_depth, " progress before: ", run_before[current_depth - 1].get("progress"))
	
	# Apply dive start progress from meta upgrade (only if > 0)
	if depth_meta_system != null:
		var start_progress: float = depth_meta_system.get_dive_start_progress(next_depth)
		if start_progress > 0.0:
			var run_data: Array = drc.get("run") as Array
			if run_data != null and next_depth >= 1 and next_depth <= run_data.size():
				var next_depth_data: Dictionary = run_data[current_depth]
				next_depth_data["progress"] = start_progress
				run_data[current_depth] = next_depth_data
				drc.set("run", run_data)
	
	# Actually change the active depth in the controller
	if drc.has_method("dive"):
		drc.call("dive")
	else:
		print("DO_DIVE: WARNING - dive method not found, setting manually")
		drc.set("active_depth", next_depth)
		if drc.has_signal("active_depth_changed"):
			drc.emit_signal("active_depth_changed", next_depth)
	
	# Check data after dive
	var run_after: Array = drc.get("run") as Array
	if run_after != null and current_depth >= 1 and current_depth <= run_after.size():
		print("DO_DIVE: Depth ", current_depth, " progress after: ", run_after[current_depth - 1].get("progress"))
	
	# Sync the panel
	if drc.has_method("_sync_all_to_panel"):
		drc.call("_sync_all_to_panel")
	
	SaveSystem.set_max_stat("deepest_depth", next_depth)
	max_depth_reached = maxi(max_depth_reached, next_depth)
	
	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", next_depth)
	
	var cam := get_tree().current_scene.find_child("Camera3D", true, false)
	if cam and cam.has_method("snap_to_depth"):
		cam.call("snap_to_depth", next_depth)
	
	if upgrade_manager.mental_buffer_level > 0:
		var bonus_control: float = float(next_depth) * upgrade_manager.get_mental_buffer_per_depth()
		control += bonus_control
	
	_check_abyss_unlock()
	
	if sound_system != null:
		sound_system.play_dive()
	
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
	# Reset frozen multipliers for new run
	frozen_depth_multipliers = {}
	
	# DO NOT reset total_dives here! It's a lifetime stat.
	# DO NOT reset lifetime_thoughts, lifetime_control, or total_playtime here!
	
	if perm_perk_system != null:
		thoughts = perm_perk_system.get_starting_thoughts()
		instability = maxf(0.0, instability - perm_perk_system.get_starting_instability_reduction())
	
	run_start_depth = 1
	
	upgrade_manager.thoughts_level = 0
	upgrade_manager.stability_level = 0
	upgrade_manager.deep_dives_level = 0
	upgrade_manager.mental_buffer_level = 0
	upgrade_manager.overclock_mastery_level = 0
	upgrade_manager.overclock_safety_level = 0
	
	overclock_system.active = false
	wake_guard_timer = wake_guard_seconds
	
	 # Reset DepthRunController completely
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		# DON'T call _init_run - it clears everything!
		# Just manually reset what we need
		drc.set("active_depth", 1)
		drc.set("max_unlocked_depth", 1)
		drc.set("local_upgrades", {1: {}})
		drc.set("frozen_upgrades", {})
		drc.set("_last_depth", 1)
		
		# Reset run array manually
		var run_data: Array = drc.get("run") as Array
		if run_data != null:
			for i in range(run_data.size()):
				var depth_data: Dictionary = run_data[i]
				depth_data["progress"] = 0.0
				depth_data["memories"] = 0.0
				depth_data["crystals"] = 0.0
				run_data[i] = depth_data
			drc.set("run", run_data)
	
	# FORCE RESET THE PANEL VISUALS
	var panel := get_tree().current_scene.find_child("DepthBarsPanel", true, false)
	if panel != null:
		if panel.has_method("clear_all_row_data"):
			panel.call("clear_all_row_data")
		# Force a full sync from controller
		if panel.has_method("_build_rows"):
			panel.call("_build_rows")
		if drc != null and drc.has_method("_sync_all_to_panel"):
			drc.call("_sync_all_to_panel")
	
	if pillar_stack != null and pillar_stack.has_method("reset_visuals"):
		pillar_stack.call("reset_visuals")
	
	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", 1)
		
	# Hide instability bar since we're back at Depth 1
	if instability_bar != null:
		instability_bar.visible = false
	if instability_label != null:
		instability_label.visible = false
	
	# Reset instability value too
	instability = 0.0
	
	_depth_cache = 1
	_sync_cracks()
	_sync_meta_progress()
	
func _check_abyss_unlock() -> void:
	if abyss_unlocked_flag:
		return
	if run_start_depth != 0:
		return
	
	var current_depth = get_current_depth()
	if current_depth < abyss_target_depth:
		return
	
	abyss_unlocked_flag = true
	emit_signal("abyss_unlocked")
	_sync_meta_progress()
	save_game()
	
func calc_memories_gain() -> float:
	var t: float = maxf(total_thoughts_earned, 0.0)
	var r: float = clampf(max_instability / 100.0, 0.0, 1.0)
	var time_mult: float = clampf(time_in_run / 60.0, 0.5, 2.0)
	var current_depth = get_current_depth()
	var depth_mult: float = 1.0 + (float(current_depth) * 0.10)
	return sqrt(t) * (1.0 + r) * time_mult * depth_mult

func get_idle_instability_gain_per_sec() -> float:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		# Get the ACTUAL rate from DepthRunController
		return float(drc.get("instability_per_sec"))
	
	# Fallback if DRC not found
	return 0.0

func get_seconds_until_fail() -> float:
	if instability >= 100.0:
		return 0.0
	var gain_per_sec := get_idle_instability_gain_per_sec()
	if gain_per_sec <= 0.0001:
		return 999999.0
	return (100.0 - instability) / gain_per_sec

func _apply_offline_progress() -> void:
	
	var data: Dictionary = SaveSystem.load_game()
	var now: float = float(Time.get_unix_time_from_system())
	
	if data.is_empty() or not data.has("last_play_time"):
		offline_seconds = 0.0
		return
	
	var last_time: float = float(data.get("last_play_time", now))
	offline_seconds = clampf(now - last_time, 0.0, MAX_OFFLINE_SECONDS)
	
	if offline_seconds < 1.0:
		offline_seconds = 0.0
		return
	
	
	var current_depth = get_current_depth()
	
	# Calculate multipliers
	var thoughts_mult: float = _safe_mult(upgrade_manager.get_thoughts_mult()) * _safe_mult(perk_system.get_thoughts_mult()) * _safe_mult(nightmare_system.get_thoughts_mult()) * _get_run_upgrades_thoughts_mult()
	var control_mult: float = _safe_mult(perk_system.get_control_mult()) * _safe_mult(nightmare_system.get_control_mult())
	
	if depth_meta_system != null:
		thoughts_mult *= _safe_mult(depth_meta_system.get_global_thoughts_mult())
		control_mult *= _safe_mult(depth_meta_system.get_global_control_mult())
	
	if perm_perk_system != null:
		thoughts_mult *= _safe_mult(perm_perk_system.get_thoughts_mult())
		control_mult *= _safe_mult(perm_perk_system.get_control_mult())
	
	if abyss_perk_system != null:
		thoughts_mult *= _safe_mult(abyss_perk_system.get_thoughts_mult())
		control_mult *= _safe_mult(abyss_perk_system.get_control_mult())
	
	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	var depth_thoughts_mult: float = 1.0 + (float(current_depth) * (depth_thoughts_step + deep_bonus_per_depth))
	
	# Apply thoughts/control gain
	var thoughts_gained := idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * offline_seconds
	var control_gained := idle_control_rate * control_mult * offline_seconds
	thoughts += thoughts_gained
	control += control_gained
	
	
	# Instability (Depth 2+ only)
	if current_depth >= 2:
		var instability_mult: float = _safe_mult(upgrade_manager.get_instability_mult()) * _safe_mult(perk_system.get_instability_mult()) * _safe_mult(nightmare_system.get_instability_mult())
		if perm_perk_system != null:
			instability_mult *= _safe_mult(perm_perk_system.get_instability_mult())
		
		var deep_risk_per_depth: float = upgrade_manager.get_deep_dives_instab_bonus_per_depth()
		var depth_instab_mult: float = 1.0 + (float(current_depth) * (depth_instab_step + deep_risk_per_depth))
		
		var abyss_instab_mult: float = 1.0
		if abyss_perk_system != null:
			abyss_instab_mult = abyss_perk_system.get_instability_reduction_mult(current_depth)
		
		instability = risk_system.add_risk(
			instability,
			(idle_instability_rate * instability_mult * depth_instab_mult * offline_seconds) * abyss_instab_mult
		)
		instability = minf(instability, 99.9)
	
	# DEPTH PROGRESS - Match online calculation exactly
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null and current_depth >= 1:
		var run_data: Array = drc.get("run") as Array
		var active_d: int = drc.get("active_depth") as int
		
		if run_data != null and active_d >= 1 and active_d <= run_data.size():
			var depth_data: Dictionary = run_data[active_d - 1]
			
			# Get base values from DRC
			var base_progress: float = float(drc.get("base_progress_per_sec"))
			var base_mem: float = float(drc.get("base_memories_per_sec"))
			var base_cry: float = float(drc.get("base_crystals_per_sec"))
			
			# Get depth length
			var depth_length: float = 1.0
			if drc.has_method("get_depth_length"):
				depth_length = drc.call("get_depth_length", active_d)
			
			# Get local upgrades
			var local_upgrades: Dictionary = drc.get("local_upgrades") as Dictionary
			var depth_upgs: Dictionary = local_upgrades.get(active_d, {})
			
			# Get upgrade levels
			var speed_lvl: int = int(depth_upgs.get("progress_speed", 0))
			var mem_lvl: int = int(depth_upgs.get("memories_gain", 0))
			var cry_lvl: int = int(depth_upgs.get("crystals_gain", 0))
			
			# Get frozen effects
			var frozen_speed: float = 0.0
			var frozen_mem: float = 0.0
			var frozen_cry: float = 0.0
			if drc.has_method("_frozen_effect"):
				frozen_speed = drc.call("_frozen_effect", active_d, "progress_speed", 0.15)
				frozen_mem = drc.call("_frozen_effect", active_d, "memories_gain", 0.15)
				frozen_cry = drc.call("_frozen_effect", active_d, "crystals_gain", 0.12)
			
			# Calculate multipliers (SAME AS ONLINE)
			var speed_mul: float = 1.0 + 0.25 * float(speed_lvl) + frozen_speed
			var mem_mul: float = 1.0 + 0.15 * float(mem_lvl) + frozen_mem
			var cry_mul: float = 1.0 + 0.12 * float(cry_lvl) + frozen_cry
			
			# Get depth rules multiplier
			var depth_prog_mul: float = 1.0
			if drc.has_method("get_depth_def"):
				var depth_def: Dictionary = drc.call("get_depth_def", active_d)
				var rules: Dictionary = depth_def.get("rules", {})
				depth_prog_mul = float(rules.get("progress_mul", 1.0))
			
			# Calculate per-second rates (SAME AS ONLINE)
			var per_sec: float = (base_progress * speed_mul * depth_prog_mul) / maxf(depth_length, 0.0001)
			
			# Calculate gains over offline time
			var progress_gained: float = per_sec * offline_seconds
			var mem_gained: float = base_mem * mem_mul * offline_seconds
			var cry_gained: float = base_cry * cry_mul * offline_seconds
			
			# Apply gains
			var current_progress: float = float(depth_data.get("progress", 0.0))
			var new_progress: float = minf(1.0, current_progress + progress_gained)
			
			depth_data["progress"] = new_progress
			depth_data["memories"] = float(depth_data.get("memories", 0.0)) + mem_gained
			depth_data["crystals"] = float(depth_data.get("crystals", 0.0)) + cry_gained
			
			run_data[active_d - 1] = depth_data
			drc.set("run", run_data)
			
	
	time_in_run += offline_seconds
	total_thoughts_earned = maxf(total_thoughts_earned, thoughts)
	max_instability = maxf(max_instability, instability)
	max_depth_reached = maxi(max_depth_reached, current_depth)
	
	_check_abyss_unlock()
	_sync_cracks()
	_sync_meta_progress()
	_force_rate_sample()
	
	if offline_seconds >= 5.0:
		_show_offline_progress_popup(thoughts_gained, control_gained, 0.0, 0.0, 0.0, current_depth)
	
	save_game()


# Safe helper function - add this to your GameManager class too
func _safe_update_depth_data(depth: int, mem: float, cry: float, prog: float) -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return
	
	var run_data = drc.get("run")
	if run_data == null or typeof(run_data) != TYPE_ARRAY:
		return
	
	var idx = depth - 1
	if idx < 0 or idx >= run_data.size():
		return
	
	var depth_data = run_data[idx]
	if depth_data == null or typeof(depth_data) != TYPE_DICTIONARY:
		return
	
	# Safe update
	var old_mem = float(depth_data.get("memories", 0.0))
	var old_cry = float(depth_data.get("crystals", 0.0))
	var old_prog = float(depth_data.get("progress", 0.0))
	
	depth_data["memories"] = old_mem + mem
	depth_data["crystals"] = old_cry + cry
	depth_data["progress"] = minf(1.0, old_prog + prog)
	
	run_data[idx] = depth_data
	drc.set("run", run_data)

func _update_depth_data_offline(mem_gained: float, cry_gained: float, progress_gained: float) -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		print("DRC null, skipping depth data update")
		return
	
	var active_d = drc.get("active_depth")
	if active_d == null:
		return
	
	var run_data = drc.get("run")
	if run_data == null:
		return
	if not (run_data is Array):
		return
	
	var idx = int(active_d) - 1
	if idx < 0 or idx >= run_data.size():
		return
	
	var depth_data = run_data[idx]
	if depth_data == null:
		return
	if not (depth_data is Dictionary):
		return
	
	# Update values
	var old_mem = float(depth_data.get("memories", 0.0))
	var old_cry = float(depth_data.get("crystals", 0.0))
	var old_prog = float(depth_data.get("progress", 0.0))
	
	depth_data["memories"] = old_mem + mem_gained
	depth_data["crystals"] = old_cry + cry_gained
	depth_data["progress"] = minf(1.0, old_prog + progress_gained)
	
	run_data[idx] = depth_data
	drc.set("run", run_data)
	

func save_game() -> void:
	var data: Dictionary = {}
	
	# Current run stats
	data["memories"] = memories
	data["thoughts"] = thoughts
	data["control"] = control
	data["instability"] = instability if get_current_depth() >= 2 else 0.0
	data["time_in_run"] = time_in_run
	data["total_thoughts_earned"] = total_thoughts_earned
	data["max_instability"] = max_instability
	
	# LIFETIME STATS - Use the exact keys SettingsPanel expects
	data["lifetime_thoughts"] = lifetime_thoughts + total_thoughts_earned
	data["lifetime_control"] = lifetime_control + control  
	data["total_dives"] = total_dives  # This is the key!
	data["deepest_depth"] = max_depth_reached
	data["total_playtime"] = total_playtime + time_in_run
	
	data["depth"] = get_current_depth()
	data["max_depth_reached"] = max_depth_reached
	data["abyss_unlocked"] = abyss_unlocked_flag
	data["run_start_depth"] = run_start_depth
	data["frozen_depth_multipliers"] = frozen_depth_multipliers
	
	# SAVE DepthRunController data (fixes the "not saving" bug)
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		data["depth_run_data"] = drc.get("run")
		data["active_depth"] = drc.get("active_depth")
		data["max_unlocked_depth"] = drc.get("max_unlocked_depth")
		data["local_upgrades"] = drc.get("local_upgrades")
		data["frozen_upgrades"] = drc.get("frozen_upgrades")
		data["depth_thoughts"] = drc.get("thoughts")
		data["depth_control"] = drc.get("control")
		data["depth_instability"] = drc.get("instability")
	
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
		print("SAVING currencies:")
		for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
			var val = depth_meta_system.currency[i]
			data["depth_currency_%d" % i] = val
			if i <= 3:  # Only print first 3
				print("  depth ", i, ": ", val)
		
		# Also save all upgrade levels
		for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
			var upgrades = depth_meta_system.get_depth_upgrade_defs(i)
			for upgrade in upgrades:
				var uid = String(upgrade.get("id", ""))
				if uid != "":
					var level = depth_meta_system.get_level(i, uid)
					data["depth_%d_upg_%s" % [i, uid]] = level
	
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
	var data: Dictionary = SaveSystem.load_game()
	
	if data.is_empty():
		return
	
	# Load lifetime stats
	lifetime_thoughts = float(data.get(LT_THOUGHTS, 0.0))
	lifetime_control = float(data.get(LT_CONTROL, 0.0))
	total_dives = int(data.get(LT_DIVES, 0))
	total_playtime = float(data.get(LT_PLAYTIME, 0.0))
	max_depth_reached = int(data.get(LT_DEEPEST, 1))
	# Load basic stats first
	memories = float(data.get("memories", 0.0))
	thoughts = float(data.get("thoughts", 0.0))
	control = float(data.get("control", 0.0))
	instability = float(data.get("instability", 0.0))
	time_in_run = float(data.get("time_in_run", 0.0))
	total_thoughts_earned = float(data.get("total_thoughts_earned", 0.0))
	max_instability = float(data.get("max_instability", 0.0))
		# Load frozen multipliers
	frozen_depth_multipliers = data.get("frozen_depth_multipliers", {})
	if not (frozen_depth_multipliers is Dictionary):
		frozen_depth_multipliers = {}
	var loaded_depth = int(data.get("depth", 1))
	max_depth_reached = int(data.get("max_depth_reached", 1))
	abyss_unlocked_flag = bool(data.get("abyss_unlocked", false))
	run_start_depth = int(data.get("run_start_depth", loaded_depth))
	
	# Restore DepthRunController state
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		# RESTORE RUN DATA with proper type casting (fixes TypedArray error)
		if data.has("depth_run_data"):
			var loaded_run: Array = data["depth_run_data"]
			var typed_run: Array[Dictionary] = []
			
			for item in loaded_run:
				var dict: Dictionary = item
				typed_run.append({
					"depth": int(dict.get("depth", 1)),
					"progress": float(dict.get("progress", 0.0)),
					"memories": float(dict.get("memories", 0.0)),
					"crystals": float(dict.get("crystals", 0.0))
				})
			
			drc.set("run", typed_run)
		# Set other values
		if data.has("max_unlocked_depth"):
			drc.set("max_unlocked_depth", int(data["max_unlocked_depth"]))
		if data.has("local_upgrades"):
			var loaded_local = data["local_upgrades"]
			var fixed_local := {}
			for key in loaded_local.keys():
				fixed_local[int(key)] = loaded_local[key]
			drc.set("local_upgrades", fixed_local)
		if data.has("frozen_upgrades"):
			var loaded_frozen = data["frozen_upgrades"]
			var fixed_frozen := {}
			for key in loaded_frozen.keys():
				fixed_frozen[int(key)] = loaded_frozen[key]
			drc.set("frozen_upgrades", fixed_frozen)
		if data.has("depth_thoughts"):
			drc.set("thoughts", float(data["depth_thoughts"]))
		if data.has("depth_control"):
			drc.set("control", float(data["depth_control"]))
		if data.has("depth_instability"):
			drc.set("instability", float(data["depth_instability"]))
		
		# Set active depth LAST (and only if different)
		var current_active: int = drc.get("active_depth")
		if data.has("active_depth"):
			var saved_active: int = int(data["active_depth"])
			if saved_active != current_active:
				drc.call("set_active_depth", saved_active)
			else:
				drc.set("active_depth", saved_active)
			_depth_cache = saved_active
	
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
			
			# LOAD ALL UPGRADE LEVELS FOR THIS DEPTH
			var upgrades = depth_meta_system.get_depth_upgrade_defs(i)
			for upgrade in upgrades:
				var uid = String(upgrade.get("id", ""))
				if uid != "":
					var level = int(data.get("depth_%d_upg_%s" % [i, uid], 0))
					if level > 0:
						depth_meta_system.set_level(i, uid, level)
	
	upgrade_manager.thoughts_level = int(data.get("thoughts_level", 0))
	upgrade_manager.stability_level = int(data.get("stability_level", 0))
	upgrade_manager.deep_dives_level = int(data.get("deep_dives_level", 0))
	upgrade_manager.mental_buffer_level = int(data.get("mental_buffer_level", 0))
	upgrade_manager.overclock_mastery_level = int(data.get("overclock_mastery_level", 0))
	upgrade_manager.overclock_safety_level = int(data.get("overclock_safety_level", 0))
	
	perk_system.perk1_level = int(data.get("perk1_level", 0))
	perk_system.perk2_level = int(data.get("perk2_level", 0))
	perk_system.perk3_level = int(data.get("perk3_level", 0))
	
	
	# Sync panel at end (only once)
	call_deferred("_sync_panel_after_load")
	
		# Ensure instability bar visibility is correct after loading
		# CRITICAL: If loaded at Depth 1, instability must be 0 (no mechanic at Shallows)
	if get_current_depth() == 1:
		instability = 0.0
		print("LOAD: Reset instability to 0 (Depth 1)")
	
	# Final UI refresh to ensure bar visibility is correct
	_refresh_top_ui()
	

func _sync_panel_after_load() -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null and drc.has_method("_sync_all_to_panel"):
		drc.call("_sync_all_to_panel")
			
func _bind_ui_mainui() -> void:
	thoughts_label = _ui_find("ThoughtsLabel") as Label
	control_label = _ui_find("ControlLabel") as Label
	instability_label = _ui_find("InstabilityLabel") as Label
	instability_bar = _ui_find("InstabilityBar") as Range
	if instability_bar:
		instability_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		instability_bar.custom_minimum_size.x = 600
	_style_action_buttons()
	_style_run_upgrades()

	overclock_button = _ui_find_button("OverclockButton")
	wake_button = _ui_find_button("WakeButton")
	meta_button = _ui_find_button("Meta")
	dive_button = _ui_find_button("DiveButton")
	if dive_button != null:
		dive_button.visible = false
		dive_button.disabled = true

	for b in [dive_button, overclock_button, wake_button, meta_button]:
		if b == null:
			continue
		_style_button(b)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_stretch_ratio = 1
		b.custom_minimum_size.x = 0
		b.add_theme_constant_override("content_margin_left", 10)
		b.add_theme_constant_override("content_margin_right", 10)
		b.add_theme_constant_override("h_separation", 4)

	auto_dive_toggle = _ui_find_toggle("AutoDiveToggle")
	auto_overclock_toggle = _ui_find_toggle("AutoOverclockToggle")

	meta_panel = _ui_find("MetaPanel") as MetaPanelController
	prestige_panel = _ui_find("PrestigePanel") as PrestigePanel
	_connect_prestige_panel()

	_style_action_buttons()
	_style_run_upgrades()
	_style_run_panel()
	_style_action_panel()
	
func _ui_find(node_name: String) -> Node:
	return get_tree().current_scene.find_child(node_name, true, false)

func _ui_find_button(node_name: String) -> Button:
	return _ui_find(node_name) as Button

func _ui_find_toggle(node_name: String) -> BaseButton:
	return _ui_find(node_name) as BaseButton
	
func _make_stylebox(bg: Color, border: Color = Color(0.55, 0.65, 0.9, 0.8), border_w: int = 2, radius: int = 8, shadow_color: Color = Color(0, 0, 0, 0.25), shadow_size: int = 2) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.shadow_color = shadow_color
	sb.shadow_size = shadow_size
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb
	
func _style_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := _make_stylebox(Color(0.12, 0.12, 0.14, 0.95), Color(0.55, 0.65, 0.9, 0.8), 2, 8)
	var hover := _make_stylebox(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 8)
	var pressed := _make_stylebox(Color(0.09, 0.09, 0.11, 0.95), Color(0.50, 0.60, 0.85, 0.8), 2, 8)
	var disabled := _make_stylebox(Color(0.08, 0.08, 0.10, 0.60), Color(0.40, 0.45, 0.55, 0.5), 2, 8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
	
func _style_tab_button(btn: Button) -> void:
	if btn == null:
		return
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 1
	btn.custom_minimum_size.x = 0
	btn.add_theme_constant_override("content_margin_left", 10)
	btn.add_theme_constant_override("content_margin_right", 10)
	btn.add_theme_constant_override("h_separation", 6)
	btn.clip_text = false
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.add_theme_stylebox_override("normal",   _make_stylebox(Color(0.12, 0.12, 0.14, 0.95), Color(0.55, 0.65, 0.9, 0.8), 2, 8))
	btn.add_theme_stylebox_override("hover",    _make_stylebox(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 8))
	btn.add_theme_stylebox_override("pressed",  _make_stylebox(Color(0.09, 0.09, 0.11, 0.95), Color(0.50, 0.60, 0.85, 0.8), 2, 8))
	btn.add_theme_stylebox_override("disabled", _make_stylebox(Color(0.08, 0.08, 0.10, 0.60), Color(0.40, 0.45, 0.55, 0.5), 2, 8))
	btn.add_theme_stylebox_override("focus",    _make_stylebox(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 8))

func _style_upgrade_panel() -> void:
	var panel := _ui_find("UpgradesPanel")
	if panel == null:
		return
	for child in panel.get_children():
		if child is Button:
			_style_button(child)
	
func _style_action_buttons() -> void:
	_style_button(dive_button)
	_style_button(overclock_button)
	_style_button(wake_button)
	_style_button(meta_button)
	
func _style_action_panel() -> void:
	var candidate := overclock_button
	if candidate == null:
		candidate = dive_button
	if candidate == null:
		candidate = wake_button
	if candidate == null:
		candidate = meta_button
	if candidate == null:
		return

	var panel := candidate.get_parent()
	while panel != null and not (panel is Panel or panel is PanelContainer):
		panel = panel.get_parent()
	if panel == null:
		return

	var bg := Color(0.05, 0.06, 0.08, 0.85)
	var border := Color(0.5, 0.6, 0.9, 0.6)
	var sb := _make_stylebox(bg, border, 2, 10, Color(0, 0, 0, 0.35), 3)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	var container := candidate.get_parent()
	if container is BoxContainer:
		container.add_theme_constant_override("separation", 10)
	
func _style_run_upgrades() -> void:
	var rows := get_tree().current_scene.find_children("*", "UpgradeRow", true, false)
	for row in rows:
		var btns := row.find_children("*", "Button", true, false)
		for b in btns:
			_style_button(b)
			
func _style_run_panel() -> void:
	var rows := get_tree().current_scene.find_children("*", "UpgradeRow", true, false)
	if rows.is_empty():
		return
	var panel := rows[0].get_parent()
	while panel != null and not (panel is Panel or panel is PanelContainer):
		panel = panel.get_parent()
	if panel == null:
		return
	var bg := Color(0.05, 0.06, 0.08, 0.85)
	var border := Color(0.5, 0.6, 0.9, 0.6)
	var sb := _make_stylebox(bg, border, 2, 10, Color(0, 0, 0, 0.35), 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

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
	if instability >= auto_overclock_instability_limit:
		return
	do_overclock()

func _press_button(btn: Button) -> void:
	if btn == null or btn.disabled:
		return
	btn.pressed.emit()

func _connect_pressed_once(btn: Button, cb: Callable) -> void:
	if btn == null:
		return
	if not btn.pressed.is_connected(cb):
		btn.pressed.connect(cb)

func _apply_thoughts_return(res) -> void:
	if res is Dictionary:
		if res.get("bought", false):
			thoughts = maxf(0.0, thoughts - float(res.get("cost", 0.0)))
		return
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
	_force_cooldown_texts()
	_update_buttons_ui()

func do_buy_overclock_safety_upgrade(_unused: float = 0.0) -> void:
	if upgrade_manager == null:
		return
	if upgrade_manager.has_method("try_buy_overclock_safety_upgrade"):
		_apply_thoughts_return(upgrade_manager.call("try_buy_overclock_safety_upgrade", thoughts))
		save_game()
	_force_cooldown_texts()
	_update_buttons_ui()

func _connect_prestige_panel() -> void:
	if prestige_panel == null:
		return
	if not prestige_panel.confirm_wake.is_connected(Callable(self, "_on_prestige_confirm_wake")):
		prestige_panel.confirm_wake.connect(Callable(self, "_on_prestige_confirm_wake"))
	if not prestige_panel.cancel.is_connected(Callable(self, "_on_prestige_cancel")):
		prestige_panel.cancel.connect(Callable(self, "_on_prestige_cancel"))

func _on_prestige_cancel() -> void:
	if prestige_panel != null:
		prestige_panel.close()
	_force_rate_sample()
	_refresh_top_ui()

func _update_overclock_flash(delta: float) -> void:
	if overclock_button == null:
		return
	if overclock_system != null and overclock_system.active and overclock_system.timer < 1.5:
		_ui_flash_phase += delta * 12.0
		var pulse := 0.75 + 0.25 * sin(_ui_flash_phase)
		overclock_button.modulate = Color(1, pulse, pulse, 1)
	else:
		overclock_button.modulate = Color(1, 1, 1, 1)
		_ui_flash_phase = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F8:
			_toggle_debug_overlay()

func _toggle_debug_overlay() -> void:
	_debug_visible = not _debug_visible
	_persist_debug_visible = _debug_visible
	if _debug_visible and _debug_label == null:
		_debug_overlay_layer = CanvasLayer.new()
		_debug_overlay_layer.layer = 50
		add_child(_debug_overlay_layer)
		var panel := ColorRect.new()
		panel.color = Color(0, 0, 0, 0.55)
		panel.size = Vector2(340, 180)
		panel.position = Vector2(12, 12)
		panel.corner_radius_top_left = 6
		panel.corner_radius_top_right = 6
		panel.corner_radius_bottom_left = 6
		panel.corner_radius_bottom_right = 6
		_debug_overlay_layer.add_child(panel)
		_debug_label = Label.new()
		_debug_label.position = Vector2(8, 8)
		_debug_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		_debug_label.size = Vector2(324, 164)
		_debug_label.clip_text = true
		panel.add_child(_debug_label)
	if _debug_overlay_layer != null:
		_debug_overlay_layer.visible = _debug_visible

func _update_debug_overlay() -> void:
	if _debug_label == null:
		return
	
	var ttf := get_seconds_until_fail()
	var oc_left: float = overclock_system.timer if (overclock_system != null and overclock_system.active) else 0.0
	var gain := get_idle_instability_gain_per_sec()
	var current_depth = get_current_depth()
	
	_debug_label.text = "Debug (F8)\n" \
		+ "Thoughts: %s (%.3f/s)\n" % [_fmt_num(thoughts), maxf(_thoughts_ps, 0.0)] \
		+ "Control: %s (%.3f/s)\n" % [_fmt_num(control), maxf(_control_ps, 0.0)] \
		+ "Instability: %.2f\n" % instability \
		+ "Instab gain/s: %.4f\n" % gain \
		+ "TTF: %s (raw %.1fs)\n" % [_fmt_time_ui(ttf), ttf] \
		+ "Overclock: %s (%.2fs left)\n" % [(overclock_system.active if overclock_system != null else false), oc_left] \
		+ "Depth: %d\n" % current_depth
		
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		print("QUIT: Saving game...")
		save_game()
		await get_tree().create_timer(0.1).timeout
		get_tree().quit()
		
func _process(delta: float) -> void:
	run_time += delta
	
	# AD_TIMED_BOOST: Handle countdown
	if timed_boost_active:
		timed_boost_timer -= delta
		if timed_boost_timer <= 0:
			timed_boost_active = false
			timed_boost_timer = 0.0
	
	autosave_timer += delta
	if autosave_timer >= autosave_interval:
		autosave_timer = 0.0
		save_game()
	
	if prestige_panel != null and prestige_panel.visible:
		_refresh_top_ui()
		_update_buttons_ui()
		_force_cooldown_texts()
		return
	
	wake_guard_timer = maxf(wake_guard_timer - delta, 0.0)
	time_in_run += delta
	
	overclock_system.update(delta)
	
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
	
	# Calculate multipliers
	var thoughts_mult: float = _safe_mult(upgrade_manager.get_thoughts_mult()) * _safe_mult(perk_system.get_thoughts_mult()) * _safe_mult(nightmare_system.get_thoughts_mult()) * _get_run_upgrades_thoughts_mult()
	var control_mult: float = _safe_mult(perk_system.get_control_mult()) * _safe_mult(nightmare_system.get_control_mult())
	
	var depth_meta_thoughts_mult: float = 1.0
	var depth_meta_control_mult: float = 1.0
	
	if depth_meta_system != null:
		depth_meta_thoughts_mult = _safe_mult(depth_meta_system.get_global_thoughts_mult())
		depth_meta_control_mult = _safe_mult(depth_meta_system.get_global_control_mult())
	
	thoughts_mult *= depth_meta_thoughts_mult
	control_mult *= depth_meta_control_mult
	
	if perm_perk_system != null:
		thoughts_mult *= _safe_mult(perm_perk_system.get_thoughts_mult())
		control_mult *= _safe_mult(perm_perk_system.get_control_mult())
	
	if abyss_perk_system != null:
		thoughts_mult *= _safe_mult(abyss_perk_system.get_thoughts_mult())
		control_mult *= _safe_mult(abyss_perk_system.get_control_mult())
	
	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	
	var current_depth = get_current_depth()
	var depth_thoughts_mult: float = 1.0 + (float(current_depth) * (depth_thoughts_step + deep_bonus_per_depth))
	
	if overclock_system.active:
		thoughts_mult *= _safe_mult(overclock_system.thoughts_mult)
	
	thoughts_mult *= _safe_mult(_corruption.thoughts_mult)
	
	# AD_TIMED_BOOST: Apply 2x multiplier
	var boost_mult := 2.0 if timed_boost_active else 1.0
	thoughts_mult *= boost_mult
	control_mult *= boost_mult
	
	# PROGRESS BAR MULTIPLIERS: Stack all frozen depths + current
	var progress_mult := _get_total_progress_multiplier()
	thoughts_mult *= progress_mult
	control_mult *= progress_mult
	
	# Generate thoughts and control
	thoughts += idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * _get_shop_boost() * delta
	control += idle_control_rate * control_mult * delta
	
	# SYNC instability FROM DepthRunController (source of truth)
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		instability = drc.get("instability")
	
	_crack_sync_timer += delta
	if _crack_sync_timer >= 0.1:
		_crack_sync_timer = 0.0
		_sync_cracks()
	
	total_thoughts_earned = maxf(total_thoughts_earned, thoughts)
	max_instability = maxf(max_instability, instability)
	
	nightmare_system.check_unlock(max_instability)
	
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
	_update_overclock_flash(delta)
	
	if _debug_visible:
		_update_debug_overlay()
	
	if instability >= 100.0:
		do_fail()
	
	# Auto-buy timer
	_auto_buy_timer += delta
	if _auto_buy_timer >= 5.0:
		_auto_buy_timer = 0.0
		_try_auto_buy()

var _auto_buy_timer: float = 0.0

func _try_auto_buy() -> void:
	var drc = get_node_or_null("/root/DepthRunController")
	if not drc:
		return
	
	# Try to auto-buy for each depth that has it unlocked
	for depth in range(1, 16):
		if not is_auto_buy_unlocked_for_depth(depth):
			continue
		
		_auto_buy_for_depth(depth, drc)

func _auto_buy_for_depth(depth: int, drc: Node) -> void:
	var upgrade_ids = []
	if drc.has_method("get_run_upgrade_ids"):
		upgrade_ids = drc.call("get_run_upgrade_ids", depth)
	
	# Get the depth definition to check actual max levels
	var meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	var depth_def = {}
	if meta and meta.has_method("get_depth_def"):
		depth_def = meta.call("get_depth_def", depth)
	
	var upgrades_def = depth_def.get("upgrades", {})
	
	for upg_id in upgrade_ids:
		var upg_data = {}
		if drc.has_method("get_run_upgrade_data"):
			upg_data = drc.call("get_run_upgrade_data", depth, upg_id)
		
		# Get current level
		var lvl = 0
		if drc.has_method("get_local_upgrades"):
			var local_upgs = drc.call("get_local_upgrades")
			if local_upgs.has(depth):
				lvl = int(local_upgs[depth].get(upg_id, 0))
		
		# Get actual max level from depth definition
		var upgrade_def = upgrades_def.get(upg_id, {})
		var max_lvl = upgrade_def.get("max_level", 1)
		
		# Double check - don't buy if at or over cap
		if lvl >= max_lvl:
			continue
		
		var base_cost = upg_data.get("base_cost", 100.0)
		var growth = upg_data.get("cost_growth", 1.5)
		var cost = base_cost * pow(growth, lvl)
		
		if thoughts >= cost:
			thoughts -= cost
			drc.call("add_local_upgrade", depth, upg_id, 1)
			
func _try_auto_buy_upgrades() -> void:
	var shop = get_tree().current_scene.find_child("ShopPanel", true, false)
	if not shop or not shop.has_method("has_auto_buy"):
		return
	if not shop.has_auto_buy():
		return
	
	var drc = get_node_or_null("/root/DepthRunController")
	if not drc:
		return
	
	var current_depth = get_current_depth()
	var upgrades = drc.get_run_upgrade_ids(current_depth) if drc.has_method("get_run_upgrade_ids") else []
	
	for upg_id in upgrades:
		var upg_data = {}
		if drc.has_method("get_run_upgrade_data"):
			upg_data = drc.call("get_run_upgrade_data", current_depth, upg_id)
		
		var lvl = int(drc.local_upgrades.get(upg_id, 0)) if drc.has_method("get_local_upgrades") else 0
		var max_lvl = upg_data.get("max_level", 1)
		
		if lvl >= max_lvl:
			continue
		
		var base_cost = upg_data.get("base_cost", 100.0)
		var growth = upg_data.get("cost_growth", 1.5)
		var cost = base_cost * pow(growth, lvl)
		
		if thoughts >= cost:
			thoughts -= cost
			drc.call("add_local_upgrade", current_depth, upg_id, 1)

func _get_shop_boost() -> float:
	var shop_panel = get_tree().current_scene.find_child("ShopPanel", true, false)
	if shop_panel:
		return shop_panel.get_active_thoughts_multiplier()
	return 1.0
	
func _get_depth_progress_multiplier() -> float:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return 1.0
	
	var active_d = drc.get("active_depth")
	if active_d == null:
		return 1.0
	
	var run_data = drc.get("run")
	if run_data == null or not (run_data is Array):
		return 1.0
	
	var idx = int(active_d) - 1
	if idx < 0 or idx >= run_data.size():
		return 1.0
	
	var depth_data = run_data[idx]
	if depth_data == null or not (depth_data is Dictionary):
		return 1.0
	
	var progress = float(depth_data.get("progress", 0.0))
	# 0% progress = 1x, 100% progress = 5x
	return 1.0 + (4.0 * progress)
	
func _show_fail_save_prompt() -> void:
	_fail_save_prompt_shown = true
	
	# Check if mobile - if not, just fail immediately
	var os_name := OS.get_name()
	if os_name != "Android" and os_name != "iOS":
		# On PC, skip the ad prompt and just fail
		do_fail()
		return
	
	var popup := PanelContainer.new()
	popup.name = "FailSavePopup"
	popup.set_anchors_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(400, 200)
	popup.z_index = 300  # HIGHER than depth bars to appear on top
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.98)  # More opaque background
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	popup.add_theme_stylebox_override("panel", sb)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	popup.add_child(vbox)
	
	var title := Label.new()
	title.text = "Instability Critical!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Watch an ad to stabilize your mind and continue?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	vbox.add_child(hbox)
	
	var watch_btn := Button.new()
	watch_btn.text = "Watch Ad (Continue)"
	watch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	watch_btn.pressed.connect(Callable(self, "_on_watch_ad_save").bind(popup))
	hbox.add_child(watch_btn)
	
	var give_up_btn := Button.new()
	give_up_btn.text = "Give Up"
	give_up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_up_btn.pressed.connect(Callable(self, "_on_give_up").bind(popup))
	hbox.add_child(give_up_btn)
	
	# Add to a CanvasLayer to ensure it's on top of everything
	var layer := CanvasLayer.new()
	layer.layer = 100  # Above everything else
	layer.add_child(popup)
	add_child(layer)
	
	set_process(false)
	
func _on_watch_ad_save(layer: Node) -> void:
	layer.queue_free()
	set_process(true)
	
	if ad_service != null:
		ad_service.show_rewarded(AdService.AD_FAIL_SAVE)
	
	instability = 75.0
	_sync_cracks()
	
	_fail_save_used = true
	await get_tree().create_timer(3.0).timeout
	_fail_save_used = false
	_fail_save_prompt_shown = false
	
func _on_give_up(layer: Node) -> void:
	layer.queue_free()
	set_process(true)
	_fail_save_prompt_shown = false
	do_fail()
	
func _on_ad_timed_boost(seconds: float) -> void:
	timed_boost_timer = seconds
	timed_boost_active = true
	
	var notif := Label.new()
	notif.text = "TIMED BOOST ACTIVE: 2x Production for %d minutes!" % int(seconds / 60.0)
	notif.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notif.add_theme_font_size_override("font_size", 18)
	notif.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95, 1.0))
	
	notif.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notif.position.y = 50
	
	add_child(notif)
	
	await get_tree().create_timer(3.0).timeout
	notif.queue_free()

func _on_ad_fail_save_reward() -> void:
	pass

func get_depth_progress(depth_idx: int) -> float:
	var drc = get_node_or_null("/root/DepthRunController")
	if not drc:
		return 0.0
	var run_data = drc.get("run")
	if run_data and depth_idx <= run_data.size():
		return float(run_data[depth_idx - 1].get("progress", 0.0))
	return 0.0
	
func can_dive_to_next_depth() -> bool:
	# Can only dive if current depth instability upgrade is maxed
	var current_instab_upgrade_level: int = upgrade_manager.stability_level
	var max_instab_upgrade: int = 10  # Default max, or get from upgrade_manager if it exists
	
	# Check if upgrade_manager has max_stability_level property
	if "max_stability_level" in upgrade_manager:
		max_instab_upgrade = upgrade_manager.max_stability_level
	
	# Get current depth from DepthRunController
	var current_depth: int = get_current_depth()
	
	# Check if next depth is unlocked (permanently unlocked via meta progression)
	# This should check depth_meta_system or similar
	var next_depth_unlocked: bool = false
	if depth_meta_system != null:
		# Check if next depth is unlocked (depth + 1)
		next_depth_unlocked = depth_meta_system.is_depth_unlocked(current_depth + 1)
	
	if not next_depth_unlocked:
		return false
	
	return current_instab_upgrade_level >= max_instab_upgrade

func _show_offline_progress_popup(thoughts_gained: float, control_gained: float, progress_gained: float, mem_gained: float, cry_gained: float, active_depth: int) -> void:
	var existing_layer := get_tree().current_scene.find_child("OfflineProgressLayer", true, false)
	if existing_layer != null:
		existing_layer.queue_free()
		await get_tree().process_frame
	
	if offline_seconds < 5.0:
		return
	
	var layer := CanvasLayer.new()
	layer.name = "OfflineProgressLayer"
	layer.layer = 100
	get_tree().current_scene.add_child(layer)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	
	var popup := PanelContainer.new()
	popup.name = "OfflineProgressPopup"
	popup.custom_minimum_size = Vector2(500, 380)
	center.add_child(popup)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.98)
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	popup.add_theme_stylebox_override("panel", sb)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "Welcome Back"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95, 1.0))
	vbox.add_child(title)
	
	# Time away
	var time_label := Label.new()
	var minutes: int = int(offline_seconds / 60.0)
	var seconds: int = int(fmod(offline_seconds, 60.0))
	if minutes > 0:
		time_label.text = "Away for %d:%02d" % [minutes, seconds]
	else:
		time_label.text = "Away for %d seconds" % seconds
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(time_label)
	
	var sep := HSeparator.new()
	vbox.add_child(sep)
	
	# Resources gained section
	var resources_label := Label.new()
	resources_label.text = "Resources Gained"
	resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resources_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(resources_label)
	
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 30)
	vbox.add_child(grid)
	
	# Thoughts
	@warning_ignore("shadowed_variable")
	var thoughts_label := Label.new()
	thoughts_label.text = "Thoughts:"
	thoughts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(thoughts_label)
	
	var thoughts_value := Label.new()
	thoughts_value.text = "+%s" % _fmt_num(thoughts_gained)
	thoughts_value.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4, 1.0))
	grid.add_child(thoughts_value)
	
	# Control
	@warning_ignore("shadowed_variable")
	var control_label := Label.new()
	control_label.text = "Control:"
	control_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(control_label)
	
	var control_value := Label.new()
	control_value.text = "+%s" % _fmt_num(control_gained)
	control_value.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9, 1.0))
	grid.add_child(control_value)
	
	# Separator for depth-specific
	var sep2 := HSeparator.new()
	vbox.add_child(sep2)
	
	# Depth info
	if active_depth >= 2 and (mem_gained > 0 or cry_gained > 0 or progress_gained > 0):
		var depth_label := Label.new()
		depth_label.text = "Depth %d Progress" % active_depth
		depth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		depth_label.add_theme_font_size_override("font_size", 18)
		vbox.add_child(depth_label)
		
		# Progress bar showing gain
		var progress_bar := ProgressBar.new()
		progress_bar.custom_minimum_size.y = 20
		progress_bar.value = progress_gained * 100.0  # Show the gain amount
		progress_bar.show_percentage = true
		vbox.add_child(progress_bar)
		
		var progress_label := Label.new()
		progress_label.text = "+%.1f%% progress" % (progress_gained * 100.0)
		progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(progress_label)
		
		var depth_grid := GridContainer.new()
		depth_grid.columns = 2
		depth_grid.add_theme_constant_override("h_separation", 20)
		vbox.add_child(depth_grid)
		
		# Memories gained
		var mem_label := Label.new()
		mem_label.text = "Memories:"
		mem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		depth_grid.add_child(mem_label)
		
		var mem_value := Label.new()
		mem_value.text = "+%.1f" % mem_gained
		mem_value.add_theme_color_override("font_color", Color(0.9, 0.6, 0.9, 1.0))
		depth_grid.add_child(mem_value)
		
		# Crystals gained
		var cry_label := Label.new()
		cry_label.text = "Crystals:"
		cry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		depth_grid.add_child(cry_label)
		
		var cry_value := Label.new()
		var currency_name := DepthMetaSystem.get_depth_currency_name(active_depth)
		cry_value.text = "+%.1f %s" % [cry_gained, currency_name]
		cry_value.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2, 1.0))
		depth_grid.add_child(cry_value)
	
	# Close button
	var close_btn := Button.new()
	close_btn.text = "Continue"
	close_btn.custom_minimum_size.y = 40
	close_btn.pressed.connect(func():
		layer.queue_free()
	)
	vbox.add_child(close_btn)
	
	# Auto-close after 8 seconds
	await get_tree().create_timer(8.0).timeout
	if is_instance_valid(layer):
		layer.queue_free()

func _get_run_upgrades_thoughts_mult() -> float:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null and drc.has_method("get_run_thoughts_mult"):
		return drc.call("get_run_thoughts_mult")
	return 1.0

func _get_total_progress_multiplier() -> float:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return 1.0
	
	var active_d = drc.get("active_depth")
	if active_d == null:
		return 1.0
	
	var current_depth_idx = int(active_d)
	
	# Start with 1.0, multiply all frozen depths + current
	var total_mult := 1.0
	
	# Multiply all frozen multipliers from previous depths
	for depth_idx in frozen_depth_multipliers.keys():
		total_mult *= frozen_depth_multipliers[depth_idx]
	
	# Multiply current depth's progress multiplier (0% = 1x, 100% = 5x)
	var current_mult := _get_current_depth_progress_multiplier(current_depth_idx)
	total_mult *= current_mult
	
	
	return total_mult

func _get_current_depth_progress_multiplier(depth_idx: int) -> float:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		
		return 1.0
	
	var run_data = drc.get("run")
	if run_data == null or not (run_data is Array):
		
		return 1.0
	
	var array_idx = depth_idx - 1
	if array_idx < 0 or array_idx >= run_data.size():
		
		return 1.0
	
	var depth_data = run_data[array_idx]
	if depth_data == null or not (depth_data is Dictionary):
		
		return 1.0
	
	var progress = float(depth_data.get("progress", 0.0))
	var multiplier = 1.0 + (4.0 * progress)
	
	
	
	return multiplier
	
func is_auto_buy_unlocked_for_depth(depth: int) -> bool:
	# Check shop early unlock
	var shop = get_tree().current_scene.find_child("ShopPanel", true, false)
	if shop and shop.has_method("has_early_auto_buy"):
		if shop.has_early_auto_buy():
			return true
	
	# Check depth meta upgrades
	var meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if not meta:
		return false
	
	# Check if any unlocked upgrade grants auto-buy for this depth
	for upgrade_id in meta.auto_buy_unlocks.keys():
		var unlocks_depth: int = meta.auto_buy_unlocks[upgrade_id]
		if unlocks_depth == depth:
			# Check if player has this upgrade
			var level = meta.get_level(depth, upgrade_id)  # or however you check upgrade levels
			if level > 0:
				return true
	
	return false

func _update_run_upgrade_text_color(depth: int) -> void:
	# Find all description labels in the run upgrades panel
	var run_panel = get_tree().current_scene.find_child("RunUpgradesPanel", true, false)
	if not run_panel:
		return
	
	# Find all description labels (assuming they have "Desc" in the name or are Labels)
	var labels = run_panel.find_children("*", "Label", true)
	
	for label in labels:
		# Only change description labels, not headers or costs
		if "desc" in label.name.to_lower() or "description" in label.name.to_lower():
			if depth == 1:
				# Dark text for light background (Depth 1)
				label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))  # Near black
			else:
				# Light text for dark backgrounds (Depth 2+)
				label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))  # Light gray/white

func fix_depth1_text_color() -> void:
	var current_depth = get_current_depth()
	if current_depth != 1:
		return
	
	# Find all description labels in upgrade rows
	var rows = get_tree().current_scene.find_children("*", "UpgradeRow", true, false)
	for row in rows:
		var desc_label = row.find_child("DescLabel", false, false)  # Adjust name if different
		if desc_label:
			desc_label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.15, 1.0))  # Dark blue-black
			desc_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.5))  # White shadow for contrast
