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
var _fail_save_popup: Node = null
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

#var _crack_sync_timer: float = 0.0

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

var click_combo_window: float = 0.0  # Combo timing window
var click_power: float = 5.0  # Base thoughts per click
var click_control_gain: float = 0.0
var click_instability_reduction: float = 0.0

# Click upgrade levels (saved with run)
var click_power_level: int = 0
var click_control_level: int = 0  
var click_stability_level: int = 0
var click_flow_level: int = 0
var click_resonance_level: int = 0
var click_upgrade_tab: Button = null
var click_upgrade_panel: PanelContainer = null
# Combo system
var _click_combo_count: int = 0
var _click_combo_timer: float = 0.0
@warning_ignore("unused_private_class_variable")
var _click_combo_window: float = 2.0  # Base window, modified by upgrades

# Constants for upgrade formulas
const CLICK_POWER_BASE: float = 5.0
const CLICK_POWER_GROWTH: float = 1.35  # Exponential scaling

var click_upgrade_sidebar: Control = null
var click_upgrade_expanded: bool = false

# Evolution System
var click_power_evolution: int = 0
var click_control_evolution: int = 0
var click_stability_evolution: int = 0
var click_flow_evolution: int = 0
var click_resonance_evolution: int = 0

# Sacrifice Penalties (-0.5 = -50%, stacks multiplicatively)
var power_sacrifice_penalty: float = 1.0
var control_sacrifice_penalty: float = 1.0
var stability_sacrifice_penalty: float = 1.0
var flow_sacrifice_penalty: float = 1.0
var resonance_sacrifice_penalty: float = 1.0

# Auto-dive toggle
var auto_dive_enabled: bool = false
var auto_dive_checkbox: CheckBox = null

# Milestone tracking (for visual effects)
var last_milestone_check: Dictionary = {}

func get_dive_instability_gain(depth: int) -> float:
	return 5.0 + (depth * 1.5)

func _fmt_num(v: float) -> String:
	# Handle infinity and NaN safely
	if v == INF or v == -INF:
		return "∞"
	if v != v:  # NaN check: NaN != NaN
		return "NaN"
	
	# Ensure clean float
	v = float(v)
	
	# Manual scientific notation for large numbers (avoids %e issues in Godot 4.5)
	if v >= 1e15:
		var exponent := int(floor(log(v) / log(10)))
		var mantissa := snappedf(v / pow(10, exponent), 0.01)
		return str(mantissa) + "e+" + str(exponent)
	
	# Standard abbreviations
	if v >= 1_000_000_000_000.0:  # 1 trillion
		return "%.2fT" % (v / 1_000_000_000_000.0)
	if v >= 1_000_000_000.0:      # 1 billion
		return "%.2fB" % (v / 1_000_000_000.0)
	if v >= 1_000_000.0:          # 1 million
		return "%.2fM" % (v / 1_000_000.0)
	if v >= 1_000.0:              # 1 thousand
		return "%.2fk" % (v / 1_000.0)
	
	return str(int(v))

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

func _connect_click_buttons_debug() -> void:
	# Find the click buttons
	var click_names := ["Think", "Control", "Stabilize", "ClickThough", "ClickControl", "ClickInstabili"]
	var found_any := false
	
	for btn_name in click_names:
		var btn := get_tree().current_scene.find_child(btn_name, true, false) as Button
		if btn != null:
			found_any = true
			print("FOUND button: ", btn_name, " at path: ", btn.get_path())
			print("  - disabled: ", btn.disabled)
			print("  - visible: ", btn.visible)
			print("  - mouse_filter: ", btn.mouse_filter)
			print("  - size: ", btn.size)
			
			# Force enable and connect
			btn.disabled = false
			btn.mouse_filter = Control.MOUSE_FILTER_STOP
			
			# Disconnect any existing connections to avoid duplicates
			var connections := btn.pressed.get_connections()
			for conn in connections:
				btn.pressed.disconnect(conn["callable"])
			
			# Connect based on name
			if "Think" in btn_name or "Though" in btn_name:
				btn.pressed.connect(on_manual_focus_clicked)
				print("  -> Connected to on_manual_focus_clicked")
			elif "Control" in btn_name:
				btn.pressed.connect(_on_click_control)
				print("  -> Connected to _on_click_control")
			elif "Stabil" in btn_name or "Instab" in btn_name:
				btn.pressed.connect(_on_click_instability)
				print("  -> Connected to _on_click_instability")
	
	if not found_any:
		push_error("NO CLICK BUTTONS FOUND! Check node names in scene tree.")


func _fix_control_button() -> void:
	var btn := get_tree().current_scene.find_child("ClickControl", true, false) as Button
	if btn == null:
		return
	
	# REMOVE the manual positioning
	btn.top_level = false
	btn.position = Vector2.ZERO
	btn.global_position = Vector2.ZERO  # Reset any forced position
	
	# Force it back into ClickRow layout
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	# Find ClickRow and ensure it's the parent
	var click_row := get_tree().current_scene.find_child("ClickRow", true, false) as HBoxContainer
	if click_row and btn.get_parent() != click_row:
		# Reparent if needed
		btn.get_parent().remove_child(btn)
		click_row.add_child(btn)
		click_row.move_child(btn, 1)  # Position 1 (middle) if needed
	
	# Force refresh
	if click_row:
		click_row.queue_sort()
		
func _fix_click_row_width() -> void:
	var click_row := get_tree().current_scene.find_child("ClickRow", true, false) as HBoxContainer
	if click_row == null:
		return
	
	# Make ClickRow fill the available width
	click_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_row.custom_minimum_size = Vector2(900, 70)  # Force wide enough
	
	# Ensure all 3 buttons are actually in it and fill equally
	for child in click_row.get_children():
		if child is Button:
			child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			child.size_flags_stretch_ratio = 1.0  # Equal width

func _check_for_duplicate_buttons() -> void:
	var all_buttons := get_tree().current_scene.find_children("*", "Button", true)
	var names := {}
	for btn in all_buttons:
		if btn.name in names:
			print("DUPLICATE BUTTON FOUND: ", btn.name, " at ", btn.get_path(), " and ", names[btn.name])
		else:
			names[btn.name] = btn.get_path()

func _check_button_parents() -> void:
	for btn_name in ["Think", "Control", "Stabilize"]:
		var btn := get_tree().current_scene.find_child(btn_name, true, false)
		if btn:
			print(btn_name, " parent: ", btn.get_parent().name, " | path: ", btn.get_path())

func _force_recreate_click_row() -> void:
	var content := get_tree().current_scene.find_child("Content", true, false)
	if content == null:
		push_error("Content not found")
		return
	
	# Remove old ClickRow completely
	var old_row := content.find_child("ClickRow", false, false)
	if old_row:
		old_row.queue_free()
		await get_tree().process_frame
	
	# Create fresh HBoxContainer
	var click_row := HBoxContainer.new()
	click_row.name = "ClickRow"
	click_row.add_theme_constant_override("separation", 12)
	click_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	click_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	click_row.custom_minimum_size = Vector2(0, 70)
	click_row.alignment = BoxContainer.ALIGNMENT_BEGIN  # Left to right
	
	# Create 3 fresh buttons
	var configs := [
		{"name": "Think", "text": "🧠 Think"},
		{"name": "Control", "text": "🛡️ Control"},
		{"name": "Stabilize", "text": "❄️ Stabilize"}
	]
	
	for cfg in configs:
		var btn := Button.new()
		btn.name = cfg["name"]
		btn.text = cfg["text"]
		btn.custom_minimum_size = Vector2(0, 50)  # Width 0 = expand, height 50
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Share width equally
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		btn.size_flags_stretch_ratio = 1.0
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		
		# Connect based on name
		match cfg["name"]:
			"Think":
				btn.pressed.connect(on_manual_focus_clicked)
			"Control":
				btn.pressed.connect(_on_click_control)
			"Stabilize":
				btn.pressed.connect(_on_click_instability)
		
		click_row.add_child(btn)
		print("Created button: ", btn.name, " parent: ", btn.get_parent().name)
	
	# Add to Content at position 0 (above BottomBar)
	content.add_child(click_row)
	content.move_child(click_row, 0)
	
	print("ClickRow recreated with ", click_row.get_child_count(), " children")
	print("ClickRow rect: ", click_row.get_global_rect())
	for btn in click_row.get_children():
		print("  ", btn.name, " rect: ", (btn as Control).get_global_rect())
		
func _ready() -> void:
	# DEBUG: Connect click buttons
	_connect_click_buttons_debug()
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
	if drc != null:
		var local_upgs: Dictionary = drc.get("local_upgrades") as Dictionary
		if local_upgs == null:
			local_upgs = {}
		if not local_upgs.has(1):
			local_upgs[1] = {}
			drc.set("local_upgrades", local_upgs)
			
	if time_in_run <= 0.0:
		run_start_depth = get_current_depth()
	
	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", get_current_depth())
	
	if pillar_stack != null and pillar_stack.has_method("reset_visuals"):
		pillar_stack.call("reset_visuals")
		
	
	_create_click_upgrade_sidebar()
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
	
	# After loading game, verify perm perks
	if perm_perk_system != null:
		print("PERK LOAD CHECK:")
		print("  Memory Engine: ", perm_perk_system.memory_engine_level)
		print("  Calm Mind: ", perm_perk_system.calm_mind_level)
		print("  Thoughts Mult: ", perm_perk_system.get_thoughts_mult())
		
		# Verify they match saved data
		var data = SaveSystem.load_game()
		if data.has("perm_memory_engine_level"):
			var saved = data["perm_memory_engine_level"]
			var current = perm_perk_system.memory_engine_level
			if saved != current:
				push_error("MISMATCH: Saved ME=", saved, " but loaded ME=", current)
		
	# Sync auto-buy unlocks from meta system
	var meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null and meta.has_method("get_level"):
		# Automated Mind I unlocks depth 1 auto-buy
		if meta.call("get_level", 3, "automated_mind_1") >= 1:
			if not 1 in auto_buy_unlocked_depths:
				auto_buy_unlocked_depths.append(1)
				print("Unlocked auto-buy for depth 1 via Automated Mind I")
	
	_force_rate_sample()  # Add this
	call_deferred("_create_click_upgrade_sidebar")
	
	if meta != null:
		print("=== CHECKING AUTOMATED MIND ===")
		for d in [1, 2, 3, 4, 5]:
			var lvl = meta.call("get_level", d, "automated_mind")
			print("Depth ", d, " 'automated_mind' level: ", lvl)
			
			# Try alternative IDs
			lvl = meta.call("get_level", d, "automated_mind_i")
			print("Depth ", d, " 'automated_mind_i' level: ", lvl)
			
			lvl = meta.call("get_level", d, "automated_mind_1")
			print("Depth ", d, " 'automated_mind_1' level: ", lvl)
		
	 # Remove old panels first
	var old = get_tree().current_scene.find_child("ClickUpgradesContainer", true, false)
	if old:
		old.queue_free()
		print("Removed old ClickUpgradesContainer")
	
	# Then create new one
	call_deferred("_create_click_upgrade_sidebar")
	
func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mouse_pos := get_viewport().get_mouse_position()
		print("\n=== CLICK DEBUG ===")
		print("Mouse at: ", mouse_pos)
		
		# Check the ClickControl button specifically
		var btn := get_tree().current_scene.find_child("ClickControl", true, false) as Button
		if btn:
			var btn_rect := btn.get_global_rect()
			print("ClickControl global rect: ", btn_rect)
			print("ClickControl position: ", btn.global_position)
			print("ClickControl size: ", btn.size)
			print("Mouse inside button? ", btn_rect.has_point(mouse_pos))
			
			# Check parent containers
			var parent := btn.get_parent()
			while parent:
				if parent is Control:
					var p_rect := (parent as Control).get_global_rect()
					print(parent.name, " rect: ", p_rect, " | mouse inside? ", p_rect.has_point(mouse_pos))
				parent = parent.get_parent()
				if parent.name == "Root":
					break
		
		# Force print all controls under mouse
		print("\n--- All controls under mouse ---")
		_print_controls_under_mouse(get_tree().current_scene, mouse_pos, 0)

func _print_controls_under_mouse(node: Node, mouse_pos: Vector2, depth: int) -> void:
	if not (node is Control):
		return
	var c := node as Control
	if not c.visible:
		return
		
	var rect := c.get_global_rect()
	if rect.has_point(mouse_pos):
		var indent := "  ".repeat(depth)
		print(indent, node.name, " (", node.get_class(), ") at ", rect)
		for child in node.get_children():
			_print_controls_under_mouse(child, mouse_pos, depth + 1)
		
func _force_rate_sample() -> void:
	_last_thoughts_sample = thoughts
	_last_control_sample = control
	_rate_sample_timer = 0.0
	_thoughts_ps = 0.0
	_control_ps = 0.0

func _refresh_top_ui() -> void:
	var current_depth := get_current_depth()
	
	if instability_bar != null:
		instability_bar.visible = (current_depth >= 2)
	var hide_numbers := false
	var cap := depth_meta_system.get_instability_cap(current_depth)  # ADD THIS LINE
	
	if top_bar_panel == null:
		if not _warned_missing_top_bar:
			_warned_missing_top_bar = true
		return

	# In _refresh_top_ui, ensure this line uses proper formatting:
	if thoughts_label != null:
		hide_numbers = false  # Just assign, don't redeclare with 'var'
		
		if hide_numbers:
			thoughts_label.text = "Thoughts: ???"
		else:
			# Show the rate properly
			var rate_str := _fmt_num(_thoughts_ps)  # Make sure _thoughts_ps is actually calculated
			thoughts_label.text = "Thoughts %s +%s/s" % [_fmt_num(thoughts), rate_str]
	if control_label != null:
		control_label.text = "Control: %s" % _fmt_num(control)
		
		# MAKE BAR WIDER AND THICKER
		instability_bar.custom_minimum_size = Vector2(700, 32)  # 700px wide, 32px tall
		instability_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Fill available space
		
		instability_bar.min_value = 0.0
		instability_bar.max_value = cap
		instability_bar.value = clampf(instability, 0.0, cap)
		if instability_bar != null:
			instability_bar.max_value = cap
		instability_bar.show_percentage = false	
	# Get or create label (NOW INSIDE THE NULL CHECK)
	if instability_bar != null:  # ADD THIS LINE
		var label := instability_bar.get_node_or_null("ValueLabel") as Label
		if label == null:
			label = Label.new()
			label.name = "ValueLabel"
			instability_bar.add_child(label)
		
		# CENTER TEXT PROPERLY
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		
		# Ensure text is centered with proper margins
		label.offset_left = 0
		label.offset_right = 0
		label.offset_top = 0
		label.offset_bottom = 0
		
		label.text = "%s / %s" % [_fmt_num(instability), _fmt_num(cap)]
		label.visible = true
		
		instability_bar.visible = (current_depth >= 2)
	# endif  (the closing bracket for the if instability_bar != null check)

	if instability_label != null:
		if current_depth == 1:
			instability_label.text = ""
			instability_label.visible = false
		else:
			var ttf := get_seconds_until_fail()
			var ttf_str := _fmt_time_ui(ttf)
			
			# Show absolute value: "Instability: 230 / 1000 (TTF 2:30)"
			instability_label.text = "Instability: %.0f / %.0f (TTF %s)" % [instability, cap, ttf_str]
			instability_label.visible = true

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
		var current_depth = get_current_depth()
		var can_overclock = current_depth >= 2  # Only unlock at depth 2
		
		overclock_button.disabled = not can_overclock
		
		if can_overclock:
			var cost_mul: float = upgrade_manager.get_overclock_cost_mult()
			var effective_cost: float = overclock_system.base_control_cost * cost_mul
			
			if overclock_system.active:
				var sec_left_o: int = int(ceil(maxf(overclock_system.timer, 0.0)))
				overclock_button.text = "Overclock (%ds)" % sec_left_o
			else:
				overclock_button.text = "Overclock (-%d Control)" % int(round(effective_cost))
		else:
			overclock_button.text = "🔒 Depth 2"  # Locked icon + requirement
			overclock_button.tooltip_text = "Unlocks at Depth 2"

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
	# Notify tutorial
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("WakeButton")
		# Close expanded bars first so wake button isn't blocked
	_close_expanded_depth_bars()
	if prestige_panel == null:
		prestige_panel = _ui_find("PrestigePanel") as PrestigePanel
		_connect_prestige_panel()  # Connect signals now that panel exists
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
	tm = get_node_or_null("/root/TutorialManage")  # Remove 'var' here
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
	# Add these two declarations:
	var tm = get_node_or_null("/root/TutorialManage")
	var drc := get_node_or_null("/root/DepthRunController")
	
	# Notify tutorial that prestige wake was clicked
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("ConfirmWakeB")
	
	# Get accumulated memories/crystals from depth_data
	var accumulated_memories := 0.0
	var accumulated_crystals := 0.0
	
	# Now drc is declared and can be used:
	var active_d: int = drc.get("active_depth") as int
	var run_data: Array = drc.get("run") as Array
	if run_data != null and active_d >= 1 and active_d <= run_data.size():
		var depth_data: Dictionary = run_data[active_d - 1]
		accumulated_memories = float(depth_data.get("memories", 0.0))
		accumulated_crystals = float(depth_data.get("crystals", 0.0))
	
	var result = drc.call("wake_cashout", 1.0, false)
	
	if result is Dictionary:
		var gained_memories = float(result.get("memories", 0.0))
		gained_memories += accumulated_memories
		memories += gained_memories
		var crystals = result.get("crystals_by_name", {})
		
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
	
	# Use 'tm' not 'tutorial_mgr'
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("PrestigeWakeButton")
	
	_force_rate_sample()
	_refresh_top_ui()
	
	_on_meta_pressed()
	
	# Use 'tm' here too
	if tm and tm.has_method("start_tutorial"):
		await get_tree().process_frame
		if tm.active_tutorial == "":
			tm.start_tutorial("post_wake_meta")

func _close_expanded_depth_bars() -> void:
	var panel = get_tree().current_scene.find_child("DepthBarsPanel", true, false)
	if panel != null:
		# Try different method names depending on your setup
		if panel.has_method("close_all_expanded"):
			panel.call("close_all_expanded")
		elif panel.has_method("set_expanded_depth"):
			panel.call("set_expanded_depth", -1)
		elif panel.has_method("close_expand_overlay"):
			panel.call("close_expand_overlay")
	
	# Also close via overlay if exists
	var overlay = get_tree().current_scene.find_child("ExpandOverlay", true, false)
	if overlay:
		overlay.visible = false
		
func do_fail() -> void:
	push_warning("do_fail() WAS CALLED - this resets all depth progress!")
	print_stack()  # This shows what triggered the fail
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
		
		var run_data = drc.get("run")
		if run_data == null or not (run_data is Array):
			run_data = []
			
		var active_d: int = drc.get("active_depth") as int
		
		if run_data.size() > 0 and active_d >= 1 and active_d <= run_data.size():
			var depth_data = run_data[active_d - 1]
			if depth_data is Dictionary:
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
	var drc := get_node_or_null("/root/DepthRunController")
	
	# CRITICAL FIX: Check if we can actually dive first
	if drc != null and drc.has_method("can_dive"):
		if not drc.call("can_dive"):
			return  # Exit early if can't dive
	
	total_dives += 1
	
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
				var next_depth_data: Dictionary = run_data[next_depth - 1]  # FIXED: Use next_depth - 1
				next_depth_data["progress"] = start_progress
				run_data[next_depth - 1] = next_depth_data  # FIXED: Use next_depth - 1
				drc.set("run", run_data)
				print("Applied Shallow Start: Depth ", next_depth, " starts at ", start_progress * 100, "% progress")
		
	# Actually change the active depth in the controller
	var dive_succeeded := false
	if drc.has_method("dive"):
		dive_succeeded = drc.call("dive")  # Will return false if can_dive failed
	else:
		# Manual fallback
		drc.set("active_depth", next_depth)
		if drc.has_signal("active_depth_changed"):
			drc.emit_signal("active_depth_changed", next_depth)
		dive_succeeded = true
	
	# CRITICAL FIX: Only proceed if dive actually succeeded
	if not dive_succeeded:
		print("DO_DIVE: Dive failed in controller")
		return
	
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
	# Trigger depth 2 tutorial if we just arrived at depth 2
	if next_depth == 2:
		var tm = get_node_or_null("/root/TutorialManage")
		if tm != null and tm.has_method("start_tutorial"):
			if tm.get("active_tutorial") == "":
				await get_tree().create_timer(0.1).timeout
				tm.start_tutorial("depth_2_first_time")
	
	# NEW: Trigger depth 3 tutorial if we just arrived at depth 3
	if next_depth == 3:
		print("ARRIVED AT DEPTH 3 - Triggering tutorial")
		var tm = get_node_or_null("/root/TutorialManage")
		if tm != null and tm.has_method("start_tutorial"):
			if tm.get("active_tutorial") == "":
				await get_tree().create_timer(0.1).timeout
				tm.start_tutorial("depth_3_unlock")
	
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
	frozen_depth_multipliers = {}
	
	# Apply starting perks
	if perm_perk_system != null:
		thoughts = perm_perk_system.get_starting_thoughts()
		instability = maxf(0.0, instability - perm_perk_system.get_starting_instability_reduction())
	
	run_start_depth = 1
	
	# Reset upgrade manager levels
	upgrade_manager.thoughts_level = 0
	upgrade_manager.stability_level = 0
	upgrade_manager.deep_dives_level = 0
	upgrade_manager.mental_buffer_level = 0
	upgrade_manager.overclock_mastery_level = 0
	upgrade_manager.overclock_safety_level = 0
	
	overclock_system.active = false
	wake_guard_timer = wake_guard_seconds
	
	# Reset DepthRunController data
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		var saved_max_unlocked: int = drc.get("max_unlocked_depth")
		if saved_max_unlocked == null or saved_max_unlocked < 1:
			saved_max_unlocked = 1
		
		drc.set("active_depth", 1)
		drc.set("local_upgrades", {1: {}})
		drc.set("frozen_upgrades", {})
		drc.set("_last_depth", 1)
		
		# Reset run array but keep max_unlocked_depth
		var run_data = drc.get("run")
		if run_data == null or not (run_data is Array):
			drc.call("_init_run")
		else:
			# Reset all depths to 0 progress but keep array structure
			for i in range(run_data.size()):
				var depth_data = run_data[i]
				if depth_data is Dictionary:
					depth_data["progress"] = 0.0
					depth_data["memories"] = 0.0
					depth_data["crystals"] = 0.0
					run_data[i] = depth_data
			drc.set("run", run_data)
		
		drc.set("max_unlocked_depth", maxi(saved_max_unlocked, 1))
	
	# CRITICAL FIX: Don't rebuild UI rows, just clear data
	var panel := get_tree().current_scene.find_child("DepthBarsPanel", true, false)
	if panel != null and panel.has_method("clear_all_row_data"):
		panel.call("clear_all_row_data")
	# REMOVED: panel.call("_build_rows") - This was causing the freeze!
	
	# Reset visual elements
	if pillar_stack != null and pillar_stack.has_method("reset_visuals"):
		pillar_stack.call("reset_visuals")
	
	if pillar_stack != null and pillar_stack.has_method("set_depth"):
		pillar_stack.call("set_depth", 1)
	
	# Hide instability UI for depth 1
	if instability_bar != null:
		instability_bar.visible = false
	if instability_label != null:
		instability_label.visible = false
	
	_depth_cache = 1
	_sync_cracks()
	_sync_meta_progress()
	_force_rate_sample()
	
	_refresh_top_ui()
	
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
	var current_depth := get_current_depth()
	var cap := depth_meta_system.get_instability_cap(current_depth)
	
	if instability >= cap:
		return 0.0
	
	var gain_per_sec := get_idle_instability_gain_per_sec()
	if gain_per_sec <= 0.0001:
		return 999999.0
		
	return (cap - instability) / gain_per_sec
	
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
		var run_data = drc.get("run")
		if run_data == null or not (run_data is Array):
			run_data = []
		
		var active_d: int = drc.get("active_depth") as int
		
		if run_data.size() > 0 and active_d >= 1 and active_d <= run_data.size():
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
		data["perm_recursive_memory_level"] = perm_perk_system.recursive_memory_level
		data["perm_lucid_dreaming_level"] = perm_perk_system.lucid_dreaming_level
		data["perm_deep_sleeper_level"] = perm_perk_system.deep_sleeper_level
		data["perm_night_owl_level"] = perm_perk_system.night_owl_level
		data["perm_dream_catcher_level"] = perm_perk_system.dream_catcher_level
		data["perm_subconscious_miner_level"] = perm_perk_system.subconscious_miner_level
		data["perm_void_walker_level"] = perm_perk_system.void_walker_level
		data["perm_rapid_eye_level"] = perm_perk_system.rapid_eye_level
		data["perm_sleep_paralysis_level"] = perm_perk_system.sleep_paralysis_level
		data["perm_oneiromancy_level"] = perm_perk_system.oneiromancy_level
		
	if depth_meta_system != null:
		for i in range(1, DepthMetaSystem.MAX_DEPTH + 1):
			var val = depth_meta_system.currency[i]
			data["depth_currency_%d" % i] = val
		
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
	
	# Click upgrades
	data["click_power_level"] = click_power_level
	data["click_control_level"] = click_control_level
	data["click_stability_level"] = click_stability_level
	data["click_flow_level"] = click_flow_level
	data["click_resonance_level"] = click_resonance_level
	
		# Click upgrades evolution
	data["click_power_evolution"] = click_power_evolution
	data["click_control_evolution"] = click_control_evolution
	data["click_stability_evolution"] = click_stability_evolution
	data["click_flow_evolution"] = click_flow_evolution
	data["click_resonance_evolution"] = click_resonance_evolution
	
	# Sacrifice penalties
	data["power_sacrifice"] = power_sacrifice_penalty
	data["control_sacrifice"] = control_sacrifice_penalty
	data["stability_sacrifice"] = stability_sacrifice_penalty
	data["flow_sacrifice"] = flow_sacrifice_penalty
	data["resonance_sacrifice"] = resonance_sacrifice_penalty
	
	# Auto-dive
	data["auto_dive_enabled"] = auto_dive_enabled
	
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
		if data.has("depth_run_data") and data["depth_run_data"] is Array:
			var loaded_run: Array = data["depth_run_data"]
			var typed_run: Array[Dictionary] = []
			
			for item in loaded_run:
				if item is Dictionary:
					var dict: Dictionary = item
					typed_run.append({
						"depth": int(dict.get("depth", 1)),
						"progress": float(dict.get("progress", 0.0)),
						"memories": float(dict.get("memories", 0.0)),
						"crystals": float(dict.get("crystals", 0.0))
					})
				else:
					# Fallback for corrupted data
					typed_run.append({"depth": typed_run.size() + 1, "progress": 0.0, "memories": 0.0, "crystals": 0.0})
			
			drc.set("run", typed_run)
		else:
			# Initialize fresh if no save data
			drc.call("_init_run")
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
		perm_perk_system.recursive_memory_level = int(data.get("perm_recursive_memory_level", 0))
		perm_perk_system.lucid_dreaming_level = int(data.get("perm_lucid_dreaming_level", 0))
		perm_perk_system.deep_sleeper_level = int(data.get("perm_deep_sleeper_level", 0))
		perm_perk_system.night_owl_level = int(data.get("perm_night_owl_level", 0))
		perm_perk_system.dream_catcher_level = int(data.get("perm_dream_catcher_level", 0))
		perm_perk_system.subconscious_miner_level = int(data.get("perm_subconscious_miner_level", 0))
		perm_perk_system.void_walker_level = int(data.get("perm_void_walker_level", 0))
		perm_perk_system.rapid_eye_level = int(data.get("perm_rapid_eye_level", 0))
		perm_perk_system.sleep_paralysis_level = int(data.get("perm_sleep_paralysis_level", 0))
		perm_perk_system.oneiromancy_level = int(data.get("perm_oneiromancy_level", 0))
	
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
	
	click_power_level = int(data.get("click_power_level", 0))
	click_control_level = int(data.get("click_control_level", 0))
	click_stability_level = int(data.get("click_stability_level", 0))
	click_flow_level = int(data.get("click_flow_level", 0))
	click_resonance_level = int(data.get("click_resonance_level", 0))
	recalculate_click_stats()
	
	# Evolution
	click_power_evolution = int(data.get("click_power_evolution", 0))
	click_control_evolution = int(data.get("click_control_evolution", 0))
	click_stability_evolution = int(data.get("click_stability_evolution", 0))
	click_flow_evolution = int(data.get("click_flow_evolution", 0))
	click_resonance_evolution = int(data.get("click_resonance_evolution", 0))
	
	# Sacrifices
	power_sacrifice_penalty = float(data.get("power_sacrifice", 1.0))
	control_sacrifice_penalty = float(data.get("control_sacrifice", 1.0))
	stability_sacrifice_penalty = float(data.get("stability_sacrifice", 1.0))
	flow_sacrifice_penalty = float(data.get("flow_sacrifice", 1.0))
	resonance_sacrifice_penalty = float(data.get("resonance_sacrifice", 1.0))
	
	# Auto-dive
	auto_dive_enabled = bool(data.get("auto_dive_enabled", false))
	if auto_dive_checkbox != null:
		auto_dive_checkbox.button_pressed = auto_dive_enabled
	
	# Sync panel at end (only once)
	call_deferred("_sync_panel_after_load")
	
		# Ensure instability bar visibility is correct after loading
		# CRITICAL: If loaded at Depth 1, instability must be 0 (no mechanic at Shallows)
	if get_current_depth() == 1:
		instability = 0.0
		print("LOAD: Reset instability to 0 (Depth 1)")
		
	# MIGRATE: Convert old 0-1 progress to new fixed scale
	drc = get_node_or_null("/root/DepthRunController")
	if drc != null:
		var run_data = drc.get("run")
		if run_data == null or not (run_data is Array):
			run_data = []
		
		if run_data.size() > 0:
			for i in range(run_data.size()):
				var depth_data: Dictionary = run_data[i]
				var old_progress: float = float(depth_data.get("progress", 0.0))
				
				# If progress is between 0 and 1 (old format), convert to cap
				if old_progress > 0.0 and old_progress < 1.0:
					var cap: float = drc.get_depth_progress_cap(i + 1)
					depth_data["progress"] = old_progress * cap
					run_data[i] = depth_data
					print("Migrated depth ", i + 1, " progress from ", old_progress, " to ", depth_data["progress"])
			
			drc.set("run", run_data)
	
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
	
	# ASSIGN BUTTONS BEFORE THE NULL CHECK
	wake_button = _ui_find_button("WakeButton")
	meta_button = _ui_find_button("Meta")
	overclock_button = _ui_find_button("OverclockButton")
	dive_button = find_button_recursive("DiveButton")
	
	# Now safe to check and return
	if thoughts_label == null:
		push_warning("ThoughtsLabel not found")
		return
	if instability_bar != null:
		var cap := depth_meta_system.get_instability_cap(get_current_depth())
		
		# MAKE BAR WIDER AND THICKER
		instability_bar.custom_minimum_size = Vector2(700, 32)
		instability_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		instability_bar.min_value = 0.0
		instability_bar.max_value = cap
		instability_bar.value = clampf(instability, 0.0, cap)
		instability_bar.show_percentage = false
	
		# Get or create label (NOW INSIDE THE NULL CHECK)
		var label := instability_bar.get_node_or_null("ValueLabel") as Label
		if label == null:
			label = Label.new()
			label.name = "ValueLabel"
			instability_bar.add_child(label)
		
		# CENTER TEXT PROPERLY
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
		label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)
		
		# Ensure text is centered with proper margins
		label.offset_left = 0
		label.offset_right = 0
		label.offset_top = 0
		label.offset_bottom = 0
		
		label.text = "%s / %s" % [_fmt_num(instability), _fmt_num(cap)]
		label.visible = true
		
		instability_bar.visible = (get_current_depth() >= 2)
		
	_style_action_buttons()
	_style_run_upgrades()

	wake_button = _ui_find_button("WakeButton")
	meta_button = _ui_find_button("Meta")
	overclock_button = _ui_find_button("OverclockButton")
	dive_button = find_button_recursive("DiveButton")
	# Add Auto-dive checkbox next to dive button
	if dive_button != null:
		var parent := dive_button.get_parent()
		auto_dive_checkbox = CheckBox.new()
		auto_dive_checkbox.name = "AutoDiveCheckBox"
		auto_dive_checkbox.text = "Auto"
		auto_dive_checkbox.tooltip_text = "Automatically dive when depth progress is complete"
		auto_dive_checkbox.toggled.connect(func(on): auto_dive_enabled = on)
		parent.add_child(auto_dive_checkbox)
		parent.move_child(auto_dive_checkbox, dive_button.get_index() + 1)

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

func find_button_recursive(button_name: String) -> Button:
	return get_tree().current_scene.find_child(button_name, true, false) as Button
	
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
	if depth_meta_system == null:
		push_error("depth_meta_system is null!")
		return
	var current_depth := get_current_depth()
	
	# Only process instability for depth 2+ (Depth 1 has no instability mechanic)
	if current_depth >= 2:
		var _instab_per_sec := depth_meta_system.get_instability_per_sec(current_depth)
		var _instability_mult: float = _safe_mult(upgrade_manager.get_instability_mult()) * _safe_mult(perk_system.get_instability_mult())
		
		if perm_perk_system != null:
			_instability_mult *= _safe_mult(perm_perk_system.get_instability_mult())
		
		instability += _instab_per_sec * delta * _instability_mult
		
		# Check for death/fail
		if depth_meta_system != null:
			var cap := depth_meta_system.get_instability_cap(current_depth)
			if instability >= cap:
				do_fail()
				return
	
	run_time += delta
	_update_click_combo(delta)
	
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
		return  # REMOVED - let game logic continue
	
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
	
	# Apply conditional multipliers
	if overclock_system.active:
		thoughts_mult *= _safe_mult(overclock_system.thoughts_mult)
	
	thoughts_mult *= _safe_mult(_corruption.thoughts_mult)
	
	var boost_mult := 2.0 if timed_boost_active else 1.0
	thoughts_mult *= boost_mult
	control_mult *= boost_mult
	
	var progress_mult := _get_total_progress_multiplier()
	thoughts_mult *= progress_mult
	control_mult *= progress_mult
	
	# Calculate and add thoughts
	var thoughts_to_add := idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * _get_shop_boost() * delta
	thoughts += thoughts_to_add
	control += idle_control_rate * control_mult * delta
	
	# Instability calculation
	var instab_per_sec := depth_meta_system.get_instability_per_sec(current_depth)
	var instability_mult: float = _safe_mult(upgrade_manager.get_instability_mult()) * _safe_mult(perk_system.get_instability_mult()) * _safe_mult(nightmare_system.get_thoughts_mult())
	if perm_perk_system != null:
		instability_mult *= _safe_mult(perm_perk_system.get_instability_mult())
	
	instability += instab_per_sec * delta * instability_mult
	
	# Check for death
	if depth_meta_system != null:
		var cap := depth_meta_system.get_instability_cap(current_depth)
		if current_depth >= 2 and instability >= cap:  # Only fail for depth 2+
			do_fail()
			return
	
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
	
	var thoughts_ps_display := idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * _get_shop_boost()
	var control_ps_display := idle_control_rate * control_mult

	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		drc.instability = instability
		drc.instability_per_sec = get_idle_instability_gain_per_sec()
		drc.set("thoughts", thoughts)
		drc.set("control", control)
		drc.set("thoughts_per_sec", thoughts_ps_display)
		drc.set("control_per_sec", control_ps_display)
	
	_refresh_top_ui()
	_update_buttons_ui()
	_force_cooldown_texts()
	_update_overclock_flash(delta)
	
	if _debug_visible:
		_update_debug_overlay()

func _update_depth_progress(delta: float, current_depth: int) -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return
	
	# CRITICAL FIX: Safe type checking instead of invalid cast
	var run_data_variant = drc.get("run")
	if run_data_variant == null:
		return
	if typeof(run_data_variant) != TYPE_ARRAY:
		push_warning("Run data is not an array, got type: " + str(typeof(run_data_variant)))
		return
	
	var run_data: Array = run_data_variant
	
	if current_depth < 1 or current_depth > run_data.size():
		return
	
	var depth_data = run_data[current_depth - 1]
	if depth_data == null or typeof(depth_data) != TYPE_DICTIONARY:
		return
	
	# Initialize depth 1 upgrades if missing
	var local_upgs = drc.get("local_upgrades")
	if local_upgs == null or not (local_upgs is Dictionary):
		local_upgs = {}
		drc.set("local_upgrades", local_upgs)
	
	if not local_upgs.has(1):
		local_upgs[1] = {}
		drc.set("local_upgrades", local_upgs)
	
	var depth_upgs = local_upgs.get(current_depth, {})
	if depth_upgs == null:
		depth_upgs = {}
	
	# Get cap safely
	var cap: float = 1000.0
	if drc.has_method("get_depth_progress_cap"):
		cap = drc.call("get_depth_progress_cap", current_depth)
	
	# Calculate progress
	var base_rate: float = cap / 100.0
	var speed_lvl: int = int(depth_upgs.get("progress_speed", 0))
	var speed_mult: float = 1.0 + (speed_lvl * 0.25)
	
	if overclock_system != null and overclock_system.active:
		speed_mult *= 2.0
	
	var increment: float = base_rate * speed_mult * delta
	var current_progress: float = float(depth_data.get("progress", 0.0))
	var new_progress: float = minf(cap, current_progress + increment)
	
	# Calculate memories/crystals
	var base_mem: float = float(drc.get("base_memories_per_sec"))
	var base_cry: float = float(drc.get("base_crystals_per_sec"))
	if base_mem <= 0: base_mem = 0.5
	if base_cry <= 0: base_cry = 0.3
	
	var mem_lvl: int = int(depth_upgs.get("memories_gain", 0))
	var cry_lvl: int = int(depth_upgs.get("crystals_gain", 0))
	var mem_mult: float = 1.0 + (0.15 * float(mem_lvl))
	var cry_mult: float = 1.0 + (0.12 * float(cry_lvl))
	
	# Update data
	depth_data["progress"] = new_progress
	depth_data["memories"] = float(depth_data.get("memories", 0.0)) + (base_mem * mem_mult * delta)
	depth_data["crystals"] = float(depth_data.get("crystals", 0.0)) + (base_cry * cry_mult * delta)
	
	# Write back to DRC's run array
	run_data[current_depth - 1] = depth_data
	drc.set("run", run_data)
	
	# Update panel
	var panel = get_tree().current_scene.find_child("DepthBarsPanel", true, false)
	if panel != null and panel.has_method("set_row_data"):
		panel.call("set_row_data", current_depth, depth_data)


	
func _get_shop_boost() -> float:
	var shop_panel = get_tree().current_scene.find_child("ShopPanel", true, false)
	if shop_panel:
		var mult = shop_panel.get_active_thoughts_multiplier()
		return mult if mult > 0 else 1.0  # Prevent 0
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
	
	# Check if DRC exists and has run data
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		do_fail()
		return
		
	var run_data = drc.get("run")
	if run_data == null or not (run_data is Array):
		do_fail()
		return
	
	# Create CanvasLayer to ensure we're above EVERYTHING
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "FailSaveLayer"
	canvas_layer.layer = 300
	_fail_save_popup = canvas_layer
	
	get_tree().current_scene.add_child(canvas_layer)
	
	# Dimmer background
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(dimmer)
	
	# Click outside to cancel
	dimmer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_fail_save()
			do_fail()
	)
	
	# Center container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(center)
	
	# Popup panel
	var panel := Panel.new()
	panel.name = "FailSavePanel"
	panel.custom_minimum_size = Vector2(400, 200)
	center.add_child(panel)
	
	# Style the panel
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
	panel.add_theme_stylebox_override("panel", sb)
	
	# Content
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "Instability Critical!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95, 1.0))
	vbox.add_child(title)
	
	# Description
	var desc := Label.new()
	desc.text = "Watch an ad to stabilize your mind and continue?"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)
	
	# Buttons
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	
	var watch_btn := Button.new()
	watch_btn.text = "Watch Ad (Continue)"
	watch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	watch_btn.pressed.connect(func():
		_close_fail_save()
		if ad_service != null:
			ad_service.show_rewarded(AdService.AD_FAIL_SAVE)
		instability = 75.0
		_sync_cracks()
		_fail_save_used = true
		await get_tree().create_timer(3.0).timeout
		_fail_save_used = false
		_fail_save_prompt_shown = false
	)
	hbox.add_child(watch_btn)
	
	var give_up_btn := Button.new()
	give_up_btn.text = "Give Up"
	give_up_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	give_up_btn.pressed.connect(func():
		_close_fail_save()
		_fail_save_prompt_shown = false
		do_fail()
	)
	hbox.add_child(give_up_btn)
	
	canvas_layer.visible = true
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
	# Check direct array (for manual/debug unlocks)
	if depth in auto_buy_unlocked_depths:
		return true
	
	# Check DepthMetaSystem for Automated Mind upgrades
	var meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null and meta.has_method("get_level"):
		# Pattern discovered from debug:
		# - automated_mind_1 is bought in Depth 3, unlocks auto-buy for Depth 1
		# - automated_mind_2 is bought in Depth 4, unlocks auto-buy for Depth 2  
		# - automated_mind_3 is bought in Depth 5, unlocks auto-buy for Depth 3
		var upgrade_id := "automated_mind_" + str(depth)
		var source_depth := depth + 2  # Depth 3 has upgrade for depth 1, etc.
		
		if meta.call("get_level", source_depth, upgrade_id) >= 1:
			return true
	
	# Check shop early unlock
	var shop = get_tree().current_scene.find_child("ShopPanel", true, false)
	if shop and shop.has_method("has_early_auto_buy"):
		if shop.has_early_auto_buy():
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

func on_manual_focus_clicked() -> void:
	var base_power := get_click_power()
	var combo_mult := get_combo_multiplier()
	var idle_bonus := get_click_idle_bonus()
	var idle_portion := get_idle_thoughts_per_second() * idle_bonus
	var thoughts_gained := (base_power * combo_mult) + idle_portion
	
	thoughts += thoughts_gained
	total_thoughts_earned += thoughts_gained
	control += click_control_gain * combo_mult
	
	# REMOVED: Instability reduction - only Stabilize button should do this
	# if click_instability_reduction > 0:
	# 	instability = maxf(0.0, instability - click_instability_reduction)
	
	_register_click_for_combo()
	_show_click_feedback(thoughts_gained, "thoughts")
	_refresh_top_ui()
	
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("FocusButton")

func get_click_power() -> float:
	var base := 10.0 * pow(10.0, float(click_power_level) / 3.0)
	var milestones := _get_milestone_count(click_power_level)
	var milestone_mult := pow(1.5, milestones)
	var evolution_mult := pow(2.0, click_power_evolution)
	
	return base * milestone_mult * evolution_mult * power_sacrifice_penalty

func get_click_stability_reduction() -> float:
	var base := 5.0 * pow(1.15, float(click_stability_level))
	var milestones := _get_milestone_count(click_stability_level)
	var milestone_mult := pow(1.3, milestones)
	var evolution_mult := pow(2.0, click_stability_evolution)
	
	return base * milestone_mult * evolution_mult * stability_sacrifice_penalty

func get_click_control_gain() -> float:
	var base := 0.5 * pow(1.2, float(click_control_level))
	var milestones := _get_milestone_count(click_control_level)
	var milestone_mult := pow(1.4, milestones)
	var evolution_mult := pow(2.0, click_control_evolution)
	
	return base * milestone_mult * evolution_mult * control_sacrifice_penalty

func get_combo_window() -> float:
	var base := 2.0 + (float(click_flow_level) * 0.02)
	var milestones := _get_milestone_count(click_flow_level)
	base += milestones * 0.5  # +0.5s per milestone
	return base * flow_sacrifice_penalty

func get_combo_multiplier() -> float:
	if click_flow_level <= 0:
		return 1.0
	var base_mult := 1.0 + (float(click_flow_level) * 0.005)
	var milestones := _get_milestone_count(click_flow_level)
	base_mult *= pow(1.2, milestones)  # ×1.2 per milestone
	return base_mult * flow_sacrifice_penalty

func get_click_idle_bonus() -> float:
	if click_resonance_level <= 0:
		return 0.0
	var base := float(click_resonance_level) * 0.001  # 0.1% per level
	var milestones := _get_milestone_count(click_resonance_level)
	base *= pow(1.5, milestones)
	return base * resonance_sacrifice_penalty

func _get_milestone_count(level: int) -> int:
	var milestones := 0
	for m in [10, 25, 50, 100, 200, 300, 400, 500, 750, 1000]:
		if level >= m:
			milestones += 1
	return milestones

func can_evolve(upgrade_type: String) -> bool:
	var level := 0
	match upgrade_type:
		"power": level = click_power_level
		"control": level = click_control_level
		"stability": level = click_stability_level
		"flow": level = click_flow_level
		"resonance": level = click_resonance_level
	return level >= 1000

func evolve_upgrade(upgrade_type: String, sacrifice_type: String) -> bool:
	if not can_evolve(upgrade_type):
		return false
	
	# Apply evolution
	match upgrade_type:
		"power": click_power_evolution += 1
		"control": click_control_evolution += 1
		"stability": click_stability_evolution += 1
		"flow": click_flow_evolution += 1
		"resonance": click_resonance_evolution += 1
	
	# Apply sacrifice penalty (-50%, stacks multiplicatively)
	var penalty := 0.5
	# Evolution Mastery reduces penalty
	if perm_perk_system != null:
		var mastery := perm_perk_system.get_evolution_mastery_reduction()
		penalty = 0.5 - mastery  # Level 10 mastery = 0.4 penalty (only -40%)
	
	match sacrifice_type:
		"power": power_sacrifice_penalty *= penalty
		"control": control_sacrifice_penalty *= penalty
		"stability": stability_sacrifice_penalty *= penalty
		"flow": flow_sacrifice_penalty *= penalty
		"resonance": resonance_sacrifice_penalty *= penalty
	
	save_game()
	return true

func _get_total_idle_multiplier() -> float:
	# Calculate just the multipliers that apply to idle generation
	# (Copy the relevant parts from your _process calculations, but exclude click-based gains)
	var mult := _safe_mult(upgrade_manager.get_thoughts_mult()) * _safe_mult(perk_system.get_thoughts_mult()) * _safe_mult(nightmare_system.get_thoughts_mult())
	
	if depth_meta_system != null:
		mult *= _safe_mult(depth_meta_system.get_global_thoughts_mult())
	
	return mult

func get_idle_thoughts_per_second() -> float:
	var current_depth := get_current_depth()
	
	# Calculate base multipliers (without overclock/corruption/manual effects)
	var thoughts_mult: float = _safe_mult(upgrade_manager.get_thoughts_mult()) * _safe_mult(perk_system.get_thoughts_mult()) * _safe_mult(nightmare_system.get_thoughts_mult())
	
	if depth_meta_system != null:
		thoughts_mult *= _safe_mult(depth_meta_system.get_global_thoughts_mult())
	
	if perm_perk_system != null:
		thoughts_mult *= _safe_mult(perm_perk_system.get_thoughts_mult())
	
	if abyss_perk_system != null:
		thoughts_mult *= _safe_mult(abyss_perk_system.get_thoughts_mult())
	
	var deep_bonus_per_depth: float = upgrade_manager.get_deep_dives_thoughts_bonus_per_depth()
	var depth_thoughts_mult: float = 1.0 + (float(current_depth) * (depth_thoughts_step + deep_bonus_per_depth))
	
	# Include timed boosts and depth multipliers
	var boost_mult := 2.0 if timed_boost_active else 1.0
	thoughts_mult *= boost_mult
	
	# Include frozen depth multipliers
	var progress_mult := _get_total_progress_multiplier()
	thoughts_mult *= progress_mult
	
	# Return base idle rate (this is the TRUE idle rate without manual clicks)
	return idle_thoughts_rate * thoughts_mult * depth_thoughts_mult * _get_shop_boost()

func try_buy_click_power_upgrade() -> bool:
	var cost := get_click_power_cost()
	if thoughts < cost:
		return false
	
	thoughts -= cost
	click_power_level += 1
	recalculate_click_stats()
	save_game()
	return true

func try_buy_click_control_upgrade() -> bool:
	var cost := get_click_control_cost()
	if thoughts < cost:
		return false
	
	thoughts -= cost
	click_control_level += 1
	recalculate_click_stats()
	save_game()
	return true

func try_buy_click_stability_upgrade() -> bool:
	var cost := get_click_stability_cost()
	if thoughts < cost:
		return false
	
	thoughts -= cost
	click_stability_level += 1
	recalculate_click_stats()
	save_game()
	return true

func try_buy_click_flow_upgrade() -> bool:
	var cost := get_click_flow_cost()
	if thoughts < cost:
		return false
	
	thoughts -= cost
	click_flow_level += 1
	recalculate_click_stats()
	save_game()
	return true

func try_buy_click_resonance_upgrade() -> bool:
	var cost := get_click_resonance_cost()
	if thoughts < cost:
		return false
	
	thoughts -= cost
	click_resonance_level += 1
	recalculate_click_stats()
	save_game()
	return true

func recalculate_click_stats() -> void:
	# Update cached values based on levels
	click_control_gain = float(click_control_level) * 0.3
	click_instability_reduction = float(click_stability_level) * 0.8

func get_click_power_cost() -> float:
	return 50.0 * pow(10.0, float(click_power_level) / 2.5)

func get_click_stability_cost() -> float:
	return 100.0 * pow(10.0, float(click_stability_level) / 2.8)

func get_click_control_cost() -> float:
	return 75.0 * pow(10.0, float(click_control_level) / 2.6)

func get_click_flow_cost() -> float:
	return 150.0 * pow(10.0, float(click_flow_level) / 2.4)

func get_click_resonance_cost() -> float:
	return 200.0 * pow(10.0, float(click_resonance_level) / 2.3)

# Don't forget to fix the path here:
func _create_click_upgrade_panel() -> void:
	# Try to find existing RunUpgradesPanel by different names
	var target_parent = get_tree().current_scene.find_child("RunUpgradesPanel", true, false)
	if target_parent == null:
		target_parent = get_tree().current_scene.find_child("UpgradesPanel", true, false)
	if target_parent == null:
		target_parent = get_tree().current_scene.find_child("MainUI", true, false)
	if target_parent == null:
		target_parent = get_tree().current_scene  # Fallback to root
	
	print("Click upgrades parent: ", target_parent)
	
	# Check if already created
	if target_parent.has_node("ClickUpgradesContainer"):
		return
	
	# Create a PanelContainer to hold the upgrades
	var container = PanelContainer.new()
	container.name = "ClickUpgradesContainer"
	
	# Style it
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	sb.border_color = Color(0.5, 0.6, 0.9, 0.6)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	container.add_theme_stylebox_override("panel", sb)
	
	# Position it (bottom-left area, above the action buttons)
	container.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	container.position = Vector2(20, -300)  # Adjust as needed
	container.custom_minimum_size = Vector2(600, 280)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.add_theme_constant_override("margin_left", 12)
	vbox.add_theme_constant_override("margin_right", 12)
	vbox.add_theme_constant_override("margin_top", 12)
	vbox.add_theme_constant_override("margin_bottom", 12)
	container.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "— Focus Upgrades —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	vbox.add_child(title)
	
	var sep := HSeparator.new()
	vbox.add_child(sep)
	
	# Create rows
	var upgrade_types := ["power", "control", "stability", "flow", "resonance"]
	for type in upgrade_types:
		if ResourceLoader.exists("res://UI/ClickUpgradeRow.gd"):
			var row = preload("res://UI/ClickUpgradeRow.gd").new()
			row.upgrade_type = type
			row.name = "ClickUpgrade_" + type.capitalize()
			vbox.add_child(row)
		else:
			push_error("ClickUpgradeRow.gd not found at res://UI/ClickUpgradeRow.gd")
	
	target_parent.add_child(container)
	print("Click upgrades UI created")

func _update_click_combo(delta: float) -> void:
	if _click_combo_count > 0:
		_click_combo_timer -= delta
		if _click_combo_timer <= 0:
			_click_combo_count = 0
			_click_combo_timer = 0.0

func _create_click_upgrade_sidebar() -> void:
	var root = get_tree().current_scene
	
	# CRITICAL: Remove ALL existing instances first
	for child in root.get_children():
		if child.name == "ClickUpgradeSidebar":
			child.queue_free()
			print("Removed duplicate sidebar")
	# IMPORTANT: Remove ALL old instances
	var to_remove = []
	for child in root.get_children():
		if child.name == "ClickUpgradeSidebar" or child.name == "ClickUpgradesContainer":
			to_remove.append(child)
	
	for old in to_remove:
		old.queue_free()
		print("Removed old panel: ", old.name)
	
	# Remove any existing
	var existing = root.find_child("ClickUpgradeSidebar", true, false)
	if existing:
		existing.queue_free()
	
	# Main container - anchored to left edge
	click_upgrade_sidebar = Control.new()
	click_upgrade_sidebar.name = "ClickUpgradeSidebar"
	click_upgrade_sidebar.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	click_upgrade_sidebar.position = Vector2(0, 0)
	click_upgrade_sidebar.custom_minimum_size = Vector2(450, 600)
	root.add_child(click_upgrade_sidebar)
	
	# Vertical Tab Button - FIXED POSITION on left edge
	var tab_btn := Button.new()
	tab_btn.name = "VerticalTab"
	tab_btn.custom_minimum_size = Vector2(32, 180)
	tab_btn.position = Vector2(0, -90)  # Fixed position, never changes
	
	# Style tab
	var tab_style := StyleBoxFlat.new()
	tab_style.bg_color = Color(0.08, 0.1, 0.14, 0.95)
	tab_style.border_color = Color(0.4, 0.6, 0.9, 0.8)
	tab_style.border_width_top = 2
	tab_style.border_width_right = 2
	tab_style.border_width_bottom = 2
	tab_style.corner_radius_top_right = 8
	tab_style.corner_radius_bottom_right = 8
	tab_btn.add_theme_stylebox_override("normal", tab_style)
	tab_btn.add_theme_stylebox_override("hover", tab_style)
	tab_btn.add_theme_stylebox_override("pressed", tab_style)
	
	# Rotated text - centered properly
	var label := Label.new()
	label.text = "Click Upgrades"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.9, 0.95, 1))

	# Set size first
	label.custom_minimum_size = Vector2(180, 32)

	# Calculate center position manually
	# Button is 32x180, label (unrotated) is 180x32
	# After -90° rotation, label becomes 32x180
	# We want it centered in the 32x180 button
	label.position = Vector2(0, 74)  # (button_height - label_width) / 2 = (180 - 32) / 2 = 74
	label.rotation = -PI / 2
	label.pivot_offset = Vector2(53, 53)  # Half of label size

	tab_btn.add_child(label)
		
	tab_btn.pressed.connect(_toggle_click_upgrade_panel)
	click_upgrade_sidebar.add_child(tab_btn)
	
	# Store reference to tab for repositioning
	click_upgrade_tab = tab_btn
	
	# Expanded Panel - positioned at left edge (behind tab)
	var panel := PanelContainer.new()
	panel.name = "ExpandedPanel"
	panel.position = Vector2(-450, -250)  # Hidden off-screen to left initially
	panel.custom_minimum_size = Vector2(450, 0)  # Auto-height based on content
	panel.visible = false
	
	# Panel style
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.05, 0.06, 0.08, 0.98)
	panel_style.border_color = Color(0.4, 0.6, 0.9, 0.6)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", panel_style)
	
	# ... rest of panel setup (vbox, header, rows) same as before ...
	var vbox := VBoxContainer.new()
	vbox.name = "ClickUpgradesList"
	vbox.add_theme_constant_override("separation", 12)
	vbox.add_theme_constant_override("margin_left", 16)
	vbox.add_theme_constant_override("margin_right", 16)
	vbox.add_theme_constant_override("margin_top", 16)
	vbox.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(vbox)
	
	# Header
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(header)
	
	var title := Label.new()
	title.text = "— Focus Upgrades —"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	header.add_child(title)
	
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	close_btn.pressed.connect(_toggle_click_upgrade_panel)
	header.add_child(close_btn)
	
	vbox.add_child(HSeparator.new())
	
	var rows_vbox := VBoxContainer.new()
	rows_vbox.name = "RowsContainer"
	rows_vbox.add_theme_constant_override("separation", 12)
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Don't expand vertical - let it grow naturally
	vbox.add_child(rows_vbox)
		
	var upgrade_types := ["power", "control", "stability", "flow", "resonance"]
	for type in upgrade_types:
		if ResourceLoader.exists("res://UI/ClickUpgradeRow.gd"):
			var row = preload("res://UI/ClickUpgradeRow.gd").new()
			row.upgrade_type = type
			row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rows_vbox.add_child(row)
	
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.05, 0.06, 0.08, 1.0)  # Fully opaque
	panel_bg.border_color = Color(0.4, 0.6, 0.9, 0.6)
	panel_bg.border_width_left = 2
	panel_bg.border_width_top = 2
	panel_bg.border_width_right = 2
	panel_bg.border_width_bottom = 2
	panel.add_theme_stylebox_override("panel", panel_bg)

	# Ensure it draws on top
	panel.z_index = 100
	
	click_upgrade_sidebar.add_child(panel)
	click_upgrade_panel = panel
	click_upgrade_panel.custom_minimum_size = Vector2(450, 0) 

func _toggle_click_upgrade_panel() -> void:
	if click_upgrade_sidebar == null:
		return
	
	var panel = click_upgrade_panel
	var tab = click_upgrade_tab
	
	click_upgrade_expanded = not click_upgrade_expanded
	
	if click_upgrade_expanded:
		# OPEN: Panel slides out from left covering the tab's original spot
		# Tab moves to right edge of panel
		panel.position = Vector2(0, -250)      # Panel at left edge (x=0)
		panel.visible = true
		tab.position = Vector2(450, -90)       # Tab at right edge of panel (panel width 450)
	else:
		# CLOSED: Panel hides off-screen left, tab returns to left edge
		panel.position = Vector2(-450, -250)   # Hide off left
		panel.visible = false
		tab.position = Vector2(0, -90)         # Tab back at left edge

func _setup_click_buttons() -> void:
	var click_row := get_tree().current_scene.find_child("ClickRow", true, false)
	if click_row == null:
		push_warning("ClickRow not found - add it to BottomBarPan above BottomBar")
		return
	
	# Find the buttons
	var thoughts_btn := click_row.find_child("ClickThoughts", false, false) as Button
	var control_btn := click_row.find_child("ClickControl", false, false) as Button
	var instability_btn := click_row.find_child("ClickInstability", false, false) as Button
	
	# Connect to existing functions
	if thoughts_btn and not thoughts_btn.pressed.is_connected(on_manual_focus_clicked):
		thoughts_btn.pressed.connect(on_manual_focus_clicked)
		_style_click_button(thoughts_btn, "🧠 Focus", Color(0.35, 0.8, 0.95))  # Blue
	
	if control_btn:
		# You'll need to add this function or use existing logic
		if not control_btn.pressed.is_connected(_on_click_control):
			control_btn.pressed.connect(_on_click_control)
		_style_click_button(control_btn, "🛡️ Breathe", Color(0.4, 0.9, 0.5))  # Green
	
	if instability_btn:
		if not instability_btn.pressed.is_connected(_on_click_instability):
			instability_btn.pressed.connect(_on_click_instability)
		_style_click_button(instability_btn, "❄️ Calm", Color(0.9, 0.5, 0.5))  # Red/calm

func _register_click_for_combo() -> void:
	_click_combo_count += 1
	_click_combo_timer = get_combo_window()

func _show_click_feedback(_amount: float, _type: String) -> void:
	# Optional visual feedback - can be empty for now
	pass
	
func _on_click_instability() -> void:
	# Reduce instability by flat amount (absolute system, not %)
	var reduction := click_instability_reduction  # e.g., 5.0 points per click
	instability = maxf(0.0, instability - reduction)
	_register_click_for_combo()
	_show_click_feedback(reduction, "instability")
	_refresh_top_ui()
	

func _style_click_button(btn: Button, text: String, accent: Color) -> void:
	btn.text = text
	btn.custom_minimum_size = Vector2(140, 60)
	btn.add_theme_font_size_override("font_size", 18)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	sb.border_color = accent
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)

func _connect_click_buttons() -> void:
	var click_row := get_tree().current_scene.find_child("ClickRow", true, false)
	if click_row == null:
		return
	
	# Map button names to functions
	var connections := {
		"Think": on_manual_focus_clicked,           # or _on_click_think
		"Control": _on_click_control,
		"Stabilize": _on_click_stabilize,
		# Fallback names if different
		"ClickThoughts": on_manual_focus_clicked,
		"ClickControl": _on_click_control,
		"ClickInstability": _on_click_stabilize
	}
	
	for btn_name in connections.keys():
		var btn := click_row.find_child(btn_name, false, false) as Button
		if btn and not btn.pressed.is_connected(connections[btn_name]):
			btn.pressed.connect(connections[btn_name])
			print("Connected: ", btn_name)

func _on_click_think() -> void:
	# Generate thoughts based on click power upgrade
	var base_power := get_click_power()
	var combo := get_combo_multiplier()
	var idle_bonus := get_click_idle_bonus()
	
	var thoughts_gained := (base_power * combo) + (get_idle_thoughts_per_second() * idle_bonus)
	thoughts += thoughts_gained
	total_thoughts_earned += thoughts_gained
	
	_register_click_for_combo()
	_show_click_feedback(thoughts_gained, "thoughts")
	_refresh_top_ui()

func _on_click_control() -> void:
	var gain := click_control_gain * get_combo_multiplier()
	control += gain
	_register_click_for_combo()
	_show_click_feedback(gain, "control")
	_refresh_top_ui()

func _on_click_stabilize() -> void:
	var reduction := click_instability_reduction
	if reduction <= 0.0:
		return  # No levels purchased
	
	# Apply reduction
	instability = maxf(0.0, instability - reduction)
	
	# Push to DRC so save/load keeps the stabilized value
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null:
		drc.instability = instability
	
	_register_click_for_combo()
	_show_click_feedback(reduction, "instability")
	_refresh_top_ui()

func _style_instability_bar() -> void:
	if instability_bar == null:
		return
	
	# Width: Make it much wider (900px minimum)
	instability_bar.custom_minimum_size = Vector2(900, 30)
	instability_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# BACKGROUND (dark track)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.12, 0.8)
	bg.border_color = Color(0.3, 0.3, 0.4, 0.8)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.corner_radius_top_left = 4
	bg.corner_radius_top_right = 4
	bg.corner_radius_bottom_left = 4
	bg.corner_radius_bottom_right = 4
	
	# FILL (red progress)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.15, 0.15, 1.0)  # Bright red
	fill.corner_radius_top_left = 3
	fill.corner_radius_top_right = 3
	fill.corner_radius_bottom_left = 3
	fill.corner_radius_bottom_right = 3
	
	instability_bar.add_theme_stylebox_override("background", bg)
	instability_bar.add_theme_stylebox_override("fill", fill)

func _close_fail_save() -> void:
	if _fail_save_popup != null and is_instance_valid(_fail_save_popup):
		_fail_save_popup.queue_free()
	_fail_save_popup = null
	set_process(true)
