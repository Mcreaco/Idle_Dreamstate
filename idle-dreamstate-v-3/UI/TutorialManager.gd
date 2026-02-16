class_name TutorialManager
extends CanvasLayer

# ============================================
# IDLE DREAMSTATE - TUTORIAL SYSTEM
# ============================================
# Comprehensive tutorial system with:
# - Automatic triggers based on game state
# - Highlight overlays showing where to click
# - Forced navigation through Meta Panel
# - Replay menu via Tutorials button
# ============================================

signal tutorial_started(tutorial_key: String)
signal tutorial_completed(tutorial_key: String)
signal tutorial_step_advanced(step_idx: int)

enum TutorialState {
	IDLE,
	WAITING_CLICK,
	HIGHLIGHTING,
	FORCED_NAVIGATION
}

# Current state
var current_state: TutorialState = TutorialState.IDLE
var active_tutorial: String = ""
var current_step_idx: int = 0
var completed_tutorials: Array = []
var tutorial_history: Array = []

# UI References
var popup_panel: Panel = null
var highlight_overlay: ColorRect = null
var tutorial_menu: Control = null

# Forced navigation tracking
var expected_click_target: String = ""
var navigation_queue: Array[Dictionary] = []

var arrow_label: Label = null
var block_overlay: ColorRect = null
var pending_continue: bool = false

# ============================================
# TUTORIAL DEFINITIONS
# ============================================

const TUTORIALS: Dictionary = {
	"start_game": {
		"priority": 100,
		"steps": [
			{
				"header": "Welcome to the Abyss",
				"body": "You are a consciousness adrift in the void. Thoughts crystallize from nothing - your only currency in this endless descent.",
				"highlight": null,
				"wait_for_click": false
			},
			{
				"header": "Depth Progress Multiplier",
				"body": "Watch the Depth 1 bar fill from 0% to 100%. This is your progress multiplier - it boosts thought generation from 1x up to 5x! Higher progress = faster thoughts. Choose wisely when to Wake.",
				"highlight": "DepthBar1",  # Check: is this the correct node name?
				"wait_for_click": false
			},
			{
				"header": "Run Upgrades",
				"body": "Click on the Depth 1 bar to see the Run Upgrades panel. Spend Thoughts on 'Thoughts Flow' to generate more thoughts. 'Stability' reduces instability growth. These reset each run, so spend them before you Wake!",
				"highlight": "DepthBar1",  # Highlights the depth bar to click
				"wait_for_click": true     # Forces them to click it to see upgrades
			}
		]
	},
	
	"wake_unlocked": {
		"priority": 95,
		"steps": [
		{
				"header": "Ready to Wake (Prestige)",
				"body": "Your Depth 1 bar reached 5%! Click WAKE to end your run and PRESTIGE. You'll convert progress into Memories - permanent currency for meta-upgrades. Each Wake/Prestige makes you stronger for the next descent!",
				"highlight": "WakeButton",
				"wait_for_click": true
			}
		]
	},
	
	"post_wake_meta": {  # NEW - Replaces your current "first_wake" 
		"priority": 90,
		"auto_open_meta": true,  # You'll handle this in GameManager
		"steps": [
			{
				"header": "The Meta Panel",
				"body": "Welcome back! You've earned Memories. This panel contains PERMANENT upgrades that last forever, even after waking.",
				"highlight": null,
				"wait_for_click": false
			},
			{
				"header": "Permanent Upgrades",
				"body": "These upgrades boost your thought generation, reduce instability, and improve all future runs. 'Memory Engine' increases ALL thought generation by 5% per level!",
				"highlight": "TabPerm",
				"wait_for_click": false
			},
			{
				"header": "Depth Upgrades Tab",
				"body": "Now click the 'Depth Upgrades' tab to see something important.",
				"highlight": "TabDepth",  # Check: is this your Depth Upgrades tab name?
				"wait_for_click": true  # Forces click on Depth tab
			},
			{
				"header": "Unlocking New Depths",
				"body": "Each depth has its own upgrades. Buy all 10 'Stabilize' upgrades here to permanently unlock the ability to dive to Depth 2!",
				"highlight": null,
				"wait_for_click": false
			}
		]
	},
	
	"depth_2_first_time": {  # NEW - Your current "depth_2_unlock" modified
		"priority": 80,
		"steps": [
			{
				"header": "Depth 2 - The Descent",
				"body": "You've unlocked Depth 2! Deeper depths generate thoughts much faster, but now you face INSTABILITY. As this rises, so does the risk of forced Wake.",
				"highlight": "InstabilityBar",
				"wait_for_click": false
			}
		]
	},
	
	# KEEP your existing ones from here down:
	"depth_3_unlock": {  # Keep existing
		"priority": 80,
		"steps": [
			{
				"header": "The Pressure Builds",
				"body": "Depth Tier 3 unlocked! Pressure now increases with each dive. Higher pressure means faster instability growth.",
				"highlight": "PressureDisplay",
				"wait_for_click": false
			}
		]
	},
	
	"first_instability": {  # Keep existing
		"priority": 85,
		"steps": [
			{
				"header": "The Void Stirs",
				"body": "Instability is rising! As instability increases, the chance of random events grows. At 100%, you will be forced to wake.",
				"highlight": "InstabilityBar",
				"wait_for_click": false
			}
		]
	},
	
	"first_event": {  # Keep existing
		"priority": 85,
		"steps": [
			{
				"header": "Something Notices You",
				"body": "An event has occurred! Events can help or hinder your descent. Choose carefully - some choices have lasting consequences.",
				"highlight": "EventPanel",
				"wait_for_click": false
			}
		]
	},
	
	"overclock_unlock": {  # Keep existing
		"priority": 75,
		"steps": [
			{
				"header": "Overclock Unlocked",
				"body": "You can now OVERCLOCK! Spend crystals to temporarily boost thought generation. Use wisely - crystals are precious.",
				"highlight": "OverclockButton",
				"wait_for_click": false
			}
		]
	},
	
	"first_crystal": {  # Keep existing
		"priority": 80,
		"steps": [
			{
				"header": "Crystallized Potential",
				"body": "You earned a Crystal! Crystals are rare rewards from deep dives and events. Spend them on powerful temporary boosts.",
				"highlight": "CrystalDisplay",
				"wait_for_click": false
			}
		]
	},
	
	"shop_unlock": {  # Keep existing
		"priority": 70,
		"steps": [
			{
				"header": "The Bazaar",
				"body": "The Shop is now available! Purchase time boosters, cosmetic themes, and convenience features. All purchases are optional - everything can be earned through gameplay.",
				"highlight": "ShopButton",
				"wait_for_click": false
			}
		]
	},
	
	"auto_buy_unlock": {  # Keep existing
		"priority": 75,
		"steps": [
			{
				"header": "Automated Mind",
				"body": "Auto-buy unlocked! Your thoughts will now automatically purchase upgrades. Configure which depths to automate in the Meta Panel.",
				"highlight": "MetaButton",
				"wait_for_click": false
			}
		]
	},
	
	"pressure_explained": {  # Keep existing
		"priority": 70,
		"steps": [
			{
				"header": "The Weight of Descent",
				"body": "Pressure increases with each dive. Higher pressure means faster instability growth. Manage your dive lengths carefully!",
				"highlight": "PressureDisplay",
				"wait_for_click": false
			}
		]
	},
}

# ============================================
# LIFECYCLE
# ============================================

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_create_popup_ui()
	_create_highlight_overlay()
	_create_arrow()  # ADD
	_create_block_overlay()  # ADD

func _create_arrow() -> void:
	arrow_label = Label.new()
	arrow_label.name = "TutorialArrow"
	arrow_label.text = "▼ CLICK HERE ▼"
	arrow_label.add_theme_font_size_override("font_size", 18)
	arrow_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0, 1.0))
	arrow_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1.0))
	arrow_label.add_theme_constant_override("shadow_offset_x", 2)
	arrow_label.add_theme_constant_override("shadow_offset_y", 2)
	arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arrow_label.visible = false
	arrow_label.z_index = 101
	add_child(arrow_label)
	
	# Make it flash - fix the tween creation
	var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(arrow_label, "modulate:a", 0.3, 0.5)
	tween.tween_property(arrow_label, "modulate:a", 1.0, 0.5)

func _create_block_overlay() -> void:
	block_overlay = ColorRect.new()
	block_overlay.name = "BlockOverlay"
	block_overlay.color = Color(0, 0, 0, 0.4)  # Semi-transparent black
	block_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	block_overlay.visible = false
	block_overlay.z_index = 49  # Below highlight (50) but above game
	block_overlay.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks
	add_child(block_overlay)
	
func _process(_delta: float) -> void:
	if current_state == TutorialState.IDLE:
		_check_tutorial_triggers()
	
	# Auto-detect when waiting for TabDepth and it becomes visible/active
	if current_state == TutorialState.WAITING_CLICK and expected_click_target == "TabDepth":
		var tab_depth = _find_ui_element("TabDepth")
		if tab_depth:
			# Check if it's the active/selected tab
			if tab_depth is Button and tab_depth.button_pressed:
				on_ui_element_clicked("TabDepth")
			# Or check if panel content changed to depth upgrades
			elif tab_depth.has_method("is_active") and tab_depth.is_active():
				on_ui_element_clicked("TabDepth")


func start_tutorial(tutorial_key: String) -> bool:
	print("Trying to start tutorial: ", tutorial_key)
	
	if not TUTORIALS.has(tutorial_key):
		push_error("Tutorial not found: " + tutorial_key)
		return false
	
	if tutorial_key in completed_tutorials:
		print("Tutorial already completed: ", tutorial_key)
		return false
	
	if active_tutorial != "":
		print("Tutorial already active: ", active_tutorial)
		return false
	
	active_tutorial = tutorial_key
	current_step_idx = 0
	current_state = TutorialState.WAITING_CLICK
	
	print("Starting tutorial: ", tutorial_key)
	tutorial_started.emit(tutorial_key)
	_show_current_step()
	
	return true

func skip_tutorial() -> void:
	if active_tutorial != "":
		_complete_tutorial()

func _complete_tutorial() -> void:
	if active_tutorial == "":
		return
	
	completed_tutorials.append(active_tutorial)
	tutorial_history.append(active_tutorial)
	
	tutorial_completed.emit(active_tutorial)
	
	_hide_popup()      # This should work now
	_hide_highlight()  # Make sure this exists too
	
	active_tutorial = ""
	current_step_idx = 0
	current_state = TutorialState.IDLE
	navigation_queue.clear()
	expected_click_target = ""
	arrow_label.visible = false  # Hide arrow too
	block_overlay.visible = false  # Hide blocker too
	pending_continue = false

func on_meta_opened() -> void:
	if current_state == TutorialState.WAITING_CLICK and pending_continue:
		var step_data = TUTORIALS[active_tutorial]["steps"][current_step_idx]
		if step_data.get("highlight") == "MetaButton":
			pending_continue = false
			block_overlay.visible = false
			arrow_label.visible = false
			var vbox = popup_panel.get_node("MarginBox/ContentContainer")
			var continue_btn: Button = vbox.get_node("ButtonRow/ContinueButton")
			continue_btn.visible = true
			current_state = TutorialState.HIGHLIGHTING
			
func advance_step() -> void:
	if active_tutorial == "":
		return
	
	var tutorial_data: Dictionary = TUTORIALS[active_tutorial]
	var steps: Array = tutorial_data["steps"]
	
	current_step_idx += 1
	
	if current_step_idx >= steps.size():
		_complete_tutorial()
	else:
		tutorial_step_advanced.emit(current_step_idx)
		_show_current_step()

# ============================================
# UI CREATION
# ============================================

func _create_popup_ui() -> void:
	popup_panel = Panel.new()
	popup_panel.name = "TutorialPopup"
	popup_panel.custom_minimum_size = Vector2(500, 250)
	popup_panel.size = Vector2(500, 250)
	popup_panel.visible = false
	popup_panel.z_index = 200  # INCREASED from 100 to be above depth panels
	
	var popup_style = StyleBoxFlat.new()
	popup_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	popup_style.border_width_left = 2
	popup_style.border_width_right = 2
	popup_style.border_width_top = 2
	popup_style.border_width_bottom = 2
	popup_style.border_color = Color(0.3, 0.5, 0.7, 1.0)
	popup_style.corner_radius_top_left = 8
	popup_style.corner_radius_top_right = 8
	popup_style.corner_radius_bottom_left = 8
	popup_style.corner_radius_bottom_right = 8
	popup_panel.add_theme_stylebox_override("panel", popup_style)
	
	var margin = MarginContainer.new()
	margin.name = "MarginBox"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 15)
	margin.add_theme_constant_override("margin_bottom", 15)
	popup_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.name = "ContentContainer"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	
	var header_label = Label.new()
	header_label.name = "PopupHeader"
	header_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_label.add_theme_font_size_override("font_size", 20)
	header_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 1.0))
	vbox.add_child(header_label)
	
	var body_label = Label.new()
	body_label.name = "PopupBody"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_label.add_theme_font_size_override("font_size", 14)
	vbox.add_child(body_label)
	
	var button_row = HBoxContainer.new()
	button_row.name = "ButtonRow"
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 20)
	vbox.add_child(button_row)
	
	var continue_btn = Button.new()
	continue_btn.name = "ContinueButton"
	continue_btn.text = "Continue"
	continue_btn.pressed.connect(_on_continue_pressed)
	button_row.add_child(continue_btn)
	
	var skip_btn = Button.new()
	skip_btn.name = "SkipButton"
	skip_btn.text = "Skip Tutorial"
	skip_btn.pressed.connect(skip_tutorial)
	button_row.add_child(skip_btn)
	
	add_child(popup_panel)

func _create_highlight_overlay() -> void:
	highlight_overlay = ColorRect.new()
	highlight_overlay.name = "HighlightOverlay"
	highlight_overlay.color = Color(1.0, 1.0, 0.3, 0.3)
	highlight_overlay.visible = false
	highlight_overlay.z_index = 250  # INCREASED - above popup
	highlight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(highlight_overlay)
	
	var highlight_style = StyleBoxFlat.new()
	highlight_style.border_width_left = 3
	highlight_style.border_width_right = 3
	highlight_style.border_width_top = 3
	highlight_style.border_width_bottom = 3
	highlight_style.border_color = Color(1.0, 0.9, 0.3, 1.0)
	highlight_style.corner_radius_top_left = 4
	highlight_style.corner_radius_top_right = 4
	highlight_style.corner_radius_bottom_left = 4
	highlight_style.corner_radius_bottom_right = 4

# ============================================
# UI DISPLAY
# ============================================

func _show_current_step() -> void:
	if active_tutorial == "":
		return
	
	var tutorial_data: Dictionary = TUTORIALS[active_tutorial]
	var steps: Array = tutorial_data["steps"]
	
	if current_step_idx >= steps.size():
		_complete_tutorial()
		return
	
	var step_data: Dictionary = steps[current_step_idx]
	
	# Update popup content
	var vbox = popup_panel.get_node("MarginBox/ContentContainer")
	var header_label: Label = vbox.get_node("PopupHeader")
	var body_label: Label = vbox.get_node("PopupBody")
	var continue_btn: Button = vbox.get_node("ButtonRow/ContinueButton")
	var skip_btn: Button = vbox.get_node("ButtonRow/SkipButton")
	
	header_label.text = step_data.get("header", "")
	body_label.text = step_data.get("body", "")
	
	# Center popup
	var viewport_size = get_viewport().get_visible_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2
	popup_panel.visible = true
	
	# Handle highlight and blocking
	var highlight_target = step_data.get("highlight", "")
	if highlight_target != null and highlight_target != "":
		_highlight_element(highlight_target)
		_position_arrow(highlight_target)
		if step_data.get("wait_for_click", false):
			expected_click_target = highlight_target  # ADD THIS LINE
			continue_btn.visible = false
			skip_btn.visible = false
		else:
			continue_btn.visible = true
			arrow_label.visible = false
	else:
		_hide_highlight()
		arrow_label.visible = false
		expected_click_target = ""  # ADD THIS LINE
		continue_btn.visible = true
	
	current_state = TutorialState.WAITING_CLICK if step_data.get("wait_for_click", false) else TutorialState.HIGHLIGHTING
	
	# Handle forced navigation
	if step_data.has("navigate"):
		var nav_path: Array = step_data["navigate"]
		navigation_queue.clear()
		for nav_item in nav_path:
			navigation_queue.append({"target": nav_item})
		_start_forced_navigation()
	
	current_state = TutorialState.WAITING_CLICK if step_data.get("wait_for_click", false) else TutorialState.HIGHLIGHTING

func _position_arrow(element_key: String) -> void:
	var target = _find_ui_element(element_key)
	if target == null:
		arrow_label.visible = false
		return
	
	var pos = target.global_position
	var size = target.size
	
	# Position arrow above the target
	arrow_label.position = Vector2(
		pos.x + size.x / 2 - arrow_label.size.x / 2,
		pos.y - 40  # 40 pixels above
	)
	arrow_label.visible = true

func _highlight_element(element_key: String) -> void:
	var target_element = _find_ui_element(element_key)
	if target_element == null:
		highlight_overlay.visible = false
		return
	
	var global_pos = target_element.global_position
	var element_size = target_element.size
	
	highlight_overlay.position = global_pos
	highlight_overlay.size = element_size
	highlight_overlay.visible = true
	
	# Also store current target for click detection
	expected_click_target = element_key

func _hide_highlight() -> void:
	highlight_overlay.visible = false
	arrow_label.visible = false
	block_overlay.visible = false

func _on_continue_pressed() -> void:
	if current_state == TutorialState.WAITING_CLICK and pending_continue:
		# Check if we're on the Meta step and Meta panel is open
		var step_data = TUTORIALS[active_tutorial]["steps"][current_step_idx]
		if step_data.get("highlight") == "MetaButton":
			var meta_panel = _find_ui_element("MetaPanel")
			if meta_panel and meta_panel.visible:
				pending_continue = false
				block_overlay.visible = false
				advance_step()
				return
		return
	
	advance_step()

func _input(_event: InputEvent) -> void:  # Added underscore to _event
	# Detect when Meta panel opens while waiting
	if current_state == TutorialState.WAITING_CLICK and pending_continue:
		var step_data = TUTORIALS[active_tutorial]["steps"][current_step_idx]
		if step_data.get("highlight") == "MetaButton":
			var meta_panel = _find_ui_element("MetaPanel")
			if meta_panel and meta_panel.visible:
				# Meta is open, show continue button
				var vbox = popup_panel.get_node("MarginBox/ContentContainer")
				var continue_btn: Button = vbox.get_node("ButtonRow/ContinueButton")
				continue_btn.visible = true
				block_overlay.visible = false
				arrow_label.visible = false
				current_state = TutorialState.HIGHLIGHTING
	
# ============================================
# UI ELEMENT FINDING
# ============================================
func _hide_popup() -> void:
	if popup_panel:
		popup_panel.visible = false

func _find_ui_element(target_element_name: String) -> Control:
	var current_scene = get_tree().current_scene
	if current_scene == null:
		return null
	
	var found_element = current_scene.find_child(target_element_name, true, false) as Control
	return found_element

# ============================================
# FORCED NAVIGATION
# ============================================

func _start_forced_navigation() -> void:
	if navigation_queue.is_empty():
		current_state = TutorialState.WAITING_CLICK
		return
	
	current_state = TutorialState.FORCED_NAVIGATION
	var next_nav = navigation_queue.pop_front()
	expected_click_target = next_nav["target"]
	
	# Highlight the expected target
	_highlight_element(expected_click_target)

func on_ui_element_clicked(clicked_element_name: String) -> bool:
	# Handle forced navigation queue (existing logic)
	if current_state == TutorialState.FORCED_NAVIGATION:
		if clicked_element_name != expected_click_target:
			return false
		
		if navigation_queue.is_empty():
			current_state = TutorialState.WAITING_CLICK
			expected_click_target = ""
			_hide_highlight()
			arrow_label.visible = false
		else:
			_start_forced_navigation()
		return true
	
	# Handle simple wait-for-click on specific element (NEW)
	elif current_state == TutorialState.WAITING_CLICK and expected_click_target != "":
		if clicked_element_name != expected_click_target:
			return false
		
		# Correct element clicked - advance tutorial
		expected_click_target = ""
		_hide_highlight()
		arrow_label.visible = false
		advance_step()
		return true
	
	return false

# ============================================
# TRIGGER CHECKING
# ============================================

func _check_tutorial_triggers() -> void:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr == null:
		return
	
	# Check depth 1 progress for wake tutorial (5%)
	if not "wake_unlocked" in completed_tutorials and not "wake_unlocked" in tutorial_history:
		if game_mgr.has_method("get_depth_progress"):
			var progress = game_mgr.call("get_depth_progress", 1)
			if progress >= 0.05:
				start_tutorial("wake_unlocked")
				return
	
	# Check post-wake meta tutorial (after wake with memories)
	if not "post_wake_meta" in completed_tutorials and not "post_wake_meta" in tutorial_history:
		if game_mgr.has("memories") and game_mgr.memories > 0 and not game_mgr.is_diving:
			# Only trigger if wake_unlocked was completed
			if "wake_unlocked" in completed_tutorials:
				start_tutorial("post_wake_meta")
				return
	
	# Check depth 2 entry
	if not "depth_2_first_time" in completed_tutorials:
		if game_mgr.has("current_depth") and game_mgr.current_depth == 2:
			start_tutorial("depth_2_first_time")
			return
	
	# Keep existing condition checks for other tutorials
	for tutorial_key in ["depth_3_unlock", "first_instability", "first_event", "overclock_unlock", 
						"first_crystal", "shop_unlock", "auto_buy_unlock", "pressure_explained"]:
		if tutorial_key in completed_tutorials or tutorial_key in tutorial_history:
			continue
		
		var tutorial_data: Dictionary = TUTORIALS[tutorial_key]
		var condition_type = tutorial_data.get("condition", "")
		
		if _check_condition(condition_type):
			start_tutorial(tutorial_key)
			return

# Alias for GameManager compatibility
func _check_trigger_tutorials() -> void:
	_check_tutorial_triggers()

func _check_condition(condition_type: String) -> bool:
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr == null:
		return false
	
	match condition_type:
		"first_run":
			return game_mgr.total_runs == 0 and not game_mgr.is_diving
		
		"first_wake":
			return game_mgr.total_runs == 1 and not game_mgr.is_diving
		
		"depth_2_unlocked":
			return game_mgr.max_depth_tier_reached >= 2
		
		"depth_3_unlocked":
			return game_mgr.max_depth_tier_reached >= 3
		
		"instability_50":
			var drc = game_mgr.get_node_or_null("DepthRunController")
			if drc:
				return drc.instability >= 50.0
			return false
		
		"first_event":
			# Track via separate flag in save
			return false
		
		"overclock_unlocked":
			return game_mgr.crystals > 0
		
		"first_crystal":
			return game_mgr.crystals > 0 and not "first_crystal" in completed_tutorials
		
		"shop_unlocked":
			return game_mgr.total_runs >= 2
		
		"auto_buy_unlocked":
			return game_mgr.depth_upgrade_levels.get("automated_mind_1", 0) > 0
		
		"pressure_10":
			return game_mgr.pressure >= 10.0
		
		"prestige_available":
			return game_mgr.memories >= 100
		
		_:
			return false

# ============================================
# TUTORIAL MENU (REPLAY)
# ============================================

func show_tutorial_menu() -> void:
	if tutorial_menu != null:
		tutorial_menu.visible = true
		return
	
	tutorial_menu = _create_tutorial_menu()
	add_child(tutorial_menu)

func hide_tutorial_menu() -> void:
	if tutorial_menu != null:
		tutorial_menu.visible = false

func _create_tutorial_menu() -> Control:
	var menu_panel = Panel.new()
	menu_panel.name = "TutorialMenuPanel"
	menu_panel.custom_minimum_size = Vector2(500, 400)
	menu_panel.size = Vector2(500, 400)
	
	var viewport_size = get_viewport().get_visible_rect().size
	menu_panel.position = (viewport_size - menu_panel.size) / 2
	menu_panel.z_index = 100
	
	var menu_style = StyleBoxFlat.new()
	menu_style.bg_color = Color(0.08, 0.08, 0.12, 0.98)
	menu_style.border_width_left = 2
	menu_style.border_width_right = 2
	menu_style.border_width_top = 2
	menu_style.border_width_bottom = 2
	menu_style.border_color = Color(0.3, 0.5, 0.7, 1.0)
	menu_style.corner_radius_top_left = 10
	menu_style.corner_radius_top_right = 10
	menu_style.corner_radius_bottom_left = 10
	menu_style.corner_radius_bottom_right = 10
	menu_panel.add_theme_stylebox_override("panel", menu_style)
	
	var margin = MarginContainer.new()
	margin.name = "MenuMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	menu_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.name = "MenuContent"
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	var menu_header = Label.new()
	menu_header.name = "MenuHeaderLabel"
	menu_header.text = "Tutorials"
	menu_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_header.add_theme_font_size_override("font_size", 24)
	menu_header.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0, 1.0))
	vbox.add_child(menu_header)
	
	var scroll = ScrollContainer.new()
	scroll.name = "TutorialScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	
	var scroll_vbox = VBoxContainer.new()
	scroll_vbox.name = "TutorialList"
	scroll_vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(scroll_vbox)
	
	# Add tutorial entries
	for tutorial_key in TUTORIALS.keys():
		var tutorial_data: Dictionary = TUTORIALS[tutorial_key]
		var entry = _create_tutorial_menu_entry(tutorial_key, tutorial_data)
		scroll_vbox.add_child(entry)
	
	var close_btn = Button.new()
	close_btn.name = "MenuCloseButton"
	close_btn.text = "Close"
	close_btn.pressed.connect(hide_tutorial_menu)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vbox.add_child(close_btn)
	
	return menu_panel

func _create_tutorial_menu_entry(tutorial_key: String, tutorial_data: Dictionary) -> Control:
	var entry = HBoxContainer.new()
	entry.name = "TutorialEntry_" + tutorial_key
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var status_label = Label.new()
	status_label.name = "StatusLabel"
	if tutorial_key in completed_tutorials:
		status_label.text = "[Viewed]"
		status_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.4, 1.0))
	else:
		status_label.text = "[New]"
		status_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4, 1.0))
	entry.add_child(status_label)
	
	var steps: Array = tutorial_data.get("steps", [])
	var first_step: Dictionary = steps[0] if steps.size() > 0 else {}
	var display_header = first_step.get("header", tutorial_key)
	
	var title_label = Label.new()
	title_label.name = "EntryTitleLabel"
	title_label.text = display_header
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.add_child(title_label)
	
	var play_btn = Button.new()
	play_btn.name = "PlayButton"
	play_btn.text = "Watch"
	play_btn.pressed.connect(func(): _replay_tutorial(tutorial_key))
	entry.add_child(play_btn)
	
	return entry

func _replay_tutorial(tutorial_key: String) -> void:
	# Remove from completed to allow replay
	completed_tutorials.erase(tutorial_key)
	tutorial_history.erase(tutorial_key)
	hide_tutorial_menu()
	start_tutorial(tutorial_key)

# ============================================
# SAVE/LOAD
# ============================================

func get_save_data() -> Dictionary:
	return {
		"completed_tutorials": completed_tutorials.duplicate(),
		"tutorial_history": tutorial_history.duplicate()
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("completed_tutorials"):
		# Cast to Array[String] to fix type mismatch
		var loaded_completed = data["completed_tutorials"] as Array
		completed_tutorials.clear()
		for item in loaded_completed:
			completed_tutorials.append(str(item))
			
	if data.has("tutorial_history"):
		# Cast to Array[String] to fix type mismatch  
		var loaded_history = data["tutorial_history"] as Array
		tutorial_history.clear()
		for item in loaded_history:
			tutorial_history.append(str(item))
