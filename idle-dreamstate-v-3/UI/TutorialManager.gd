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

var _glow_button: Button = null
var _glow_phase: float = 0.0

# ============================================
# TUTORIAL DEFINITIONS
# ============================================

const TUTORIALS: Dictionary = {
	"start_game": {
		"priority": 100,
		"steps": [
			{
				"header": "Consciousness Awakens",
				"body": "You exist in the void. Thoughts crystallize from nothing - your only currency. Control keeps you stable. Gather Thoughts to purchase upgrades and descend deeper into the Dreamstate.",
				"highlight": "ThoughtsLabel",
				"wait_for_click": false
			},
			{
				"header": "Depth Progress Multiplier", 
				"body": "Watch the Depth 1 bar fill from 0% to 100%. This is your progress multiplier - it boosts thought generation from 1x up to 5x! Higher progress = faster thoughts.",
				"highlight": "DepthBar1",
				"wait_for_click": false
			},
			{
				"header": "Run Upgrades",
				"body": "Click on the Depth 1 bar to see the Run Upgrades panel. Spend Thoughts on upgrades to boost this run. These reset each time you Wake, so spend them!",
				"highlight": "DepthBar1",
				"wait_for_click": true,
				"wait_for_expand": true
			},
			{
				"header": "Prepare to Wake",
				"body": "Close the Depth Bar by clicking the X, then click the WAKE button when you're ready to prestige and convert your progress into Memories.",
				"highlight": "WakeButton",    # Ensure this matches your scene's Button node name
				"wait_for_click": true        # This makes them click the actual button to proceed
			},
			{
				"header": "Ready to Wake (Prestige)",
				"body": "Click WAKE to end your run and convert progress into Memories - permanent currency for meta-upgrades. Each Wake makes you stronger for the next descent!",
				"highlight": "ConfirmWakeB",  # Ensure this matches the PrestigePanel's confirm button name
				"wait_for_click": true
			}
		]
	},
	
	"post_wake_meta": {  
		"priority": 90,
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
				"highlight": "TabDepth",
				"wait_for_click": false,
				"wait_for_expand": false
			},
			{
				"header": "Unlocking New Depths",
				"body": "Each depth has its own upgrades. Buy all 10 'Stabilize' upgrades here to permanently unlock the ability to dive to Depth 2!",
				"highlight": null,
				"wait_for_click": false
			},
			{
				"header": "Close the Meta Panel",
				"body": "Click the X button in the top right to close the Meta Panel. Then check out the Shop for boosters and convenience features!",
				"highlight": "CloseButton",
				"wait_for_click": true
			}
		]
	},
	
	"depth_2_first_time": {
		"priority": 80,
		"steps": [
			{
				"header": "Depth 2 - The Descent",
				"body": "You've unlocked Depth 2! Deeper depths generate thoughts much faster, but now you face INSTABILITY. As this rises, so does the risk of forced Wake.",
				"highlight": "InstabilityBar",
				"wait_for_click": false
			},
			{
				"header": "Overclock Unlocked",
				"body": "OVERCLOCK is now available! Spend Control to temporarily boost thought generation. Use it wisely - it increases instability while active!",
				"highlight": "OverclockButton",
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
	
	"shop_unlock": {
		"priority": 70,
		"steps": [
			{
				"header": "The Bazaar",
				"body": "The Shop is now available! Purchase time boosters, cosmetic themes, and convenience features.",
				"highlight": "ShopButton",
				"wait_for_click": false  # Must be false to show Continue immediately
			},
			{
				"header": "Optional Purchases",
				"body": "All purchases are optional - everything can be earned through gameplay. Check it out when you're ready!",
				"highlight": null,        # No highlight on this step (or set to "ShopButton" if you want)
				"wait_for_click": false   # CRITICAL: Must be false for Continue to appear and work
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
	layer = 500
	_create_popup_ui()
	_create_highlight_overlay()
	_create_arrow()
	_create_block_overlay()
	
	# DEBUG: Clear history so tutorial always triggers for testing
	completed_tutorials.clear()
	tutorial_history.clear()
	print("TutorialManager ready - forcing start_game for testing")
	
	# Wait a frame then start
	await get_tree().process_frame
	start_tutorial("start_game")

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
	
func _process(delta: float) -> void:
	if current_state == TutorialState.IDLE:
		_check_tutorial_triggers()
	
	# Handle wait_for_expand detection (Run Upgrades)
	if current_state == TutorialState.WAITING_CLICK and active_tutorial == "start_game":
		var step_data = TUTORIALS["start_game"]["steps"][current_step_idx]
		if step_data.get("wait_for_expand", false):
			var dbar = _find_ui_element("DepthBar1")
			if dbar != null and dbar.has_method("is_details_open"):
				if dbar.is_details_open():
					# Show continue button now
					var vbox = popup_panel.get_node("MarginBox/ContentContainer")
					var continue_btn: Button = vbox.get_node("ButtonRow/ContinueButton")
					var _skip_btn: Button = vbox.get_node("ButtonRow/SkipButton")
					continue_btn.visible = true
					_skip_btn.visible = true
					current_state = TutorialState.HIGHLIGHTING
	
	# Handle button glowing
	if _glow_button != null and is_instance_valid(_glow_button) and active_tutorial != "":
		_glow_phase += delta * 8.0
		var pulse := 0.7 + 0.3 * sin(_glow_phase)
		_glow_button.modulate = Color(1.0, pulse, 0.5, 1.0)
	else:
		if _glow_button != null:
			_stop_glow()
		_glow_phase = 0.0


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
	
	var just_completed = active_tutorial
	completed_tutorials.append(active_tutorial)
	tutorial_history.append(active_tutorial)
	tutorial_completed.emit(active_tutorial)
	
	# CRITICAL: Stop glow and hide everything
	_hide_highlight()
	_stop_glow()
	_hide_popup()  # ADD THIS LINE - hides the tutorial popup
	
	active_tutorial = ""
	current_step_idx = 0
	current_state = TutorialState.IDLE
	navigation_queue.clear()
	expected_click_target = ""
	arrow_label.visible = false
	block_overlay.visible = false
	pending_continue = false
	
	# Chain shop_unlock after post_wake_meta
	if just_completed == "post_wake_meta":
		start_tutorial("shop_unlock")

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
	
	# STOP GLOW on current button before advancing
	_stop_glow()
	
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
	
	var vbox = popup_panel.get_node("MarginBox/ContentContainer")
	var header_label: Label = vbox.get_node("PopupHeader")
	var body_label: Label = vbox.get_node("PopupBody")
	var continue_btn: Button = vbox.get_node("ButtonRow/ContinueButton")
	var _skip_btn: Button = vbox.get_node("ButtonRow/SkipButton")
	
	header_label.text = step_data.get("header", "")
	body_label.text = step_data.get("body", "")
	
	var viewport_size = get_viewport().get_visible_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2
	popup_panel.visible = true
	
	# Handle highlight and blocking
	var highlight_target = step_data.get("highlight", "")
	var _wait_for_expand = step_data.get("wait_for_expand", false)
	var wait_for_click = step_data.get("wait_for_click", false)
	
	arrow_label.visible = false  # Never show arrow
	
	if highlight_target != null and highlight_target != "":
		_highlight_element(highlight_target)
		
		if wait_for_click:
			# Waiting for user to click something - hide continue button
			continue_btn.visible = false
			_skip_btn.visible = false
			# Set up to wait for click
			expected_click_target = highlight_target
			current_state = TutorialState.WAITING_CLICK
			
			# Special handling for wait_for_expand (Run Upgrades step)
			if step_data.get("wait_for_expand", false):
				# Will be handled by _process detecting expansion
				pass
		else:
			# Not waiting for click - show continue immediately
			continue_btn.visible = true
			_skip_btn.visible = true
			expected_click_target = ""
			current_state = TutorialState.HIGHLIGHTING
	else:
		# No highlight - just text
		_hide_highlight()
		continue_btn.visible = true
		_skip_btn.visible = true
		expected_click_target = ""
		current_state = TutorialState.HIGHLIGHTING
	
	# Handle forced navigation
	if step_data.has("navigate"):
		var nav_path: Array = step_data["navigate"]
		navigation_queue.clear()
		for nav_item in nav_path:
			navigation_queue.append({"target": nav_item})
		_start_forced_navigation()


func _position_arrow(element_key: String) -> void:
	var target = _find_ui_element(element_key)
	if target == null:
		arrow_label.visible = false
		return
	
	# For buttons in panels, wait a frame for layout to settle
	if target is Button:
		_position_arrow_deferred(target)
	else:
		_position_arrow_immediate(target)

func _position_arrow_immediate(target: Control) -> void:
	var pos = target.global_position
	var size = target.size
	
	arrow_label.position = Vector2(
		pos.x + size.x / 2 - arrow_label.size.x / 2,
		pos.y - 40
	)
	arrow_label.visible = true

func _position_arrow_deferred(target: Control) -> void:
	# Wait for container layout to settle
	await get_tree().process_frame
	
	if not is_instance_valid(target):
		return
		
	var pos = target.global_position
	var size = target.size
	
	# For top-right buttons (like CloseButton), position arrow below instead of above
	if pos.x > get_viewport().get_visible_rect().size.x * 0.8:
		# Button is on right side - point from below
		arrow_label.position = Vector2(
			pos.x + size.x / 2 - arrow_label.size.x / 2,
			pos.y + size.y + 10  # Below button
		)
		arrow_label.text = "▲ CLICK HERE ▲"  # Point up
	else:
		arrow_label.position = Vector2(
			pos.x + size.x / 2 - arrow_label.size.x / 2,
			pos.y - 40
		)
		arrow_label.text = "▼ CLICK HERE ▼"  # Point down
	
	arrow_label.visible = true

func _highlight_element(element_key: String) -> void:
	var target_element = _find_ui_element(element_key)
	if target_element == null:
		_stop_glow()
		highlight_overlay.visible = false
		print("ERROR: Could not find element: ", element_key)
		return
	
	print("Found element: ", element_key, " type: ", target_element.get_class())
	
	# Check if it's a button (more robust check)
	var is_button = false
	if target_element is Button:
		is_button = true
	elif target_element.get_class() == "Button":
		is_button = true
	elif target_element.has_method("set_pressed"):
		# Might be a button subclass
		is_button = true
	
	if is_button:
		print("Starting glow for button: ", element_key)
		_start_glow(target_element as Button)
	else:
		print("Using overlay for: ", element_key)
		_stop_glow()
		var global_pos = target_element.global_position
		var element_size = target_element.size
		highlight_overlay.position = global_pos
		highlight_overlay.size = element_size
		highlight_overlay.visible = true
	
	expected_click_target = element_key

func _start_glow(button: Button) -> void:
	# Stop any existing glow first
	_stop_glow()
	
	_glow_button = button
	_glow_phase = 0.0
	highlight_overlay.visible = false
	
	# Apply initial glow immediately
	button.modulate = Color(1.0, 0.7, 0.5, 1.0)
	
	print("Glow started on: ", button.name)

func _stop_glow() -> void:
	if _glow_button != null and is_instance_valid(_glow_button):
		_glow_button.modulate = Color(1, 1, 1, 1)
	_glow_button = null

func _hide_highlight() -> void:
	highlight_overlay.visible = false
	arrow_label.visible = false  # Always hide arrow
	block_overlay.visible = false
	_stop_glow()

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
	
	# Search in current scene first
	var found = current_scene.find_child(target_element_name, true, false) as Control
	if found:
		print("Found ", target_element_name, " at: ", found.get_path())
		return found
	
	# Search in GameManager (autoload) for UI buttons
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr:
		found = game_mgr.find_child(target_element_name, true, false) as Control
		if found:
			print("Found ", target_element_name, " in GameManager: ", found.get_path())
			return found
	
	# Special search for MetaPanel CloseButton
	if target_element_name == "CloseButton":
		var meta = current_scene.find_child("MetaPanel", true, false)
		if meta:
			found = meta.find_child("CloseButton", true, false) as Control
			if found:
				return found
	
	# Special search for PrestigePanel ConfirmWakeB
	if target_element_name == "ConfirmWakeB":
		var prestige = current_scene.find_child("PrestigePanel", true, false)
		if not prestige and game_mgr:
			# Check in GameManager if not in scene
			prestige = game_mgr.find_child("PrestigePanel", true, false)
		if prestige:
			found = prestige.find_child("ConfirmWakeB", true, false) as Control
			if found:
				print("Found ConfirmWakeB in PrestigePanel")
				return found
	
	return null
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
	# Handle forced navigation queue
	if current_state == TutorialState.FORCED_NAVIGATION:
		if clicked_element_name != expected_click_target:
			return false
		
		if navigation_queue.is_empty():
			current_state = TutorialState.WAITING_CLICK
			expected_click_target = ""
			_hide_highlight()
		else:
			_start_forced_navigation()
		return true
	
	# Handle simple wait-for-click on specific element
	elif current_state == TutorialState.WAITING_CLICK and expected_click_target != "":
		if clicked_element_name != expected_click_target:
			return false
		
		# Check if we need to wait for expand (Run Upgrades)
		var step_data = TUTORIALS[active_tutorial]["steps"][current_step_idx]
		if step_data.get("wait_for_expand", false):
			# Click happened, now wait for expand via _process
			expected_click_target = ""  # Stop checking for clicks
			return true
		
		# Normal click - advance immediately
		expected_click_target = ""
		_hide_highlight()
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
	
	# Check start_game first
	if not "start_game" in completed_tutorials and not "start_game" in tutorial_history:
		start_tutorial("start_game")
		return
	
	# FIX: Check depth 2 tutorial - must be done BEFORE checking if tutorial is active
	if not "depth_2_first_time" in completed_tutorials and not "depth_2_first_time" in tutorial_history:
		# Check if currently at depth 2
		var current_depth = 1
		if game_mgr.has_method("get_current_depth"):
			current_depth = game_mgr.call("get_current_depth")
		
		if current_depth == 2:
			print("Triggering depth 2 tutorial! Current depth: ", current_depth)
			start_tutorial("depth_2_first_time")
			return
	
	# Only check other tutorials if no tutorial is currently active
	if active_tutorial != "":
		return
	
	# Check other tutorials...
	for tutorial_key in ["depth_3_unlock", "first_instability", 
						"first_event", "overclock_unlock", "first_crystal", 
						"shop_unlock", "auto_buy_unlock", "pressure_explained"]:
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

func on_depth_bar_expanded(depth_idx: int) -> void:
	if depth_idx != 1:
		return
	# If we're waiting for depth bar 1 to expand in run upgrades step
	if active_tutorial == "start_game" and current_step_idx == 2:  # Step 2 is the run upgrades step
		expected_click_target = ""
		_hide_highlight()
		arrow_label.visible = false
		block_overlay.visible = false
		
		# Show continue button now
		if popup_panel:
			var vbox = popup_panel.get_node("MarginBox/ContentContainer")
			if vbox:
				var continue_btn: Button = vbox.get_node("ButtonRow/ContinueButton")
				var skip_btn: Button = vbox.get_node("ButtonRow/SkipButton")
				if continue_btn:
					continue_btn.visible = true
				if skip_btn:
					skip_btn.visible = true
				current_state = TutorialState.HIGHLIGHTING
