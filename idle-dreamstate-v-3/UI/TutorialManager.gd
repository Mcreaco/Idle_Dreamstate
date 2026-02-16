class_name TutorialManager
extends CanvasLayer  # CRITICAL: Was Node, must be CanvasLayer for UI overlay

# ============================================
# IDLE DREAMSTATE - TUTORIAL SYSTEM
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

var current_state: TutorialState = TutorialState.IDLE
var active_tutorial: String = ""
var current_step_idx: int = 0
var tutorial_history: Array[String] = []
var completed_tutorials: Array[String] = []

var popup_panel: Panel = null
var highlight_overlay: Panel = null  # Changed from ColorRect to Panel for borders
var tutorial_menu: Control = null

var expected_click_target: String = ""
var navigation_queue: Array[Dictionary] = []

const TUTORIALS: Dictionary = {
	"first_run": {
		"condition": "first_run",
		"priority": 100,
		"steps": [
			{
				"header": "Welcome to the Abyss",
				"body": "You are a consciousness adrift in the void. Thoughts crystallize from nothing - your only currency in this endless descent.",
				"highlight": null,
				"wait_for_click": false
			},
			{
				"header": "The Thought Stream",
				"body": "Watch as thoughts generate automatically. Click 'DIVE' when you're ready to descend deeper into the abyss.",
				"highlight": "DiveButton",
				"wait_for_click": true
			}
		]
	},
	"first_wake": {
		"condition": "first_wake",
		"priority": 90,
		"steps": [
			{
				"header": "You Have Returned",
				"body": "The abyss released you... this time. Your dive ended, but you brought something back.",
				"highlight": null,
				"wait_for_click": false
			},
			{
				"header": "Memories of the Deep",
				"body": "Memories are earned by reaching depth thresholds. They persist between dives and unlock permanent upgrades.",
				"highlight": "MetaButton",
				"wait_for_click": true
			},
			{
				"header": "The Meta Panel",
				"body": "Open the Meta Panel to spend memories on permanent upgrades that persist forever.",
				"highlight": null,
				"navigate": ["MetaButton", "TabPerm"],
				"wait_for_click": true
			}
		]
	},
	"depth_2_unlock": {
		"condition": "depth_2_unlocked",
		"priority": 80,
		"steps": [
			{
				"header": "Deeper Waters",
				"body": "You have unlocked Depth Tier 2! Deeper depths generate thoughts faster but instability grows more quickly.",
				"highlight": "DepthBar2",
				"wait_for_click": false
			}
		]
	},
	"depth_3_unlock": {
		"condition": "depth_3_unlocked",
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
	"first_instability": {
		"condition": "instability_50",
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
	"first_event": {
		"condition": "first_event",
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
	"overclock_unlock": {
		"condition": "overclock_unlocked",
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
	"first_crystal": {
		"condition": "first_crystal",
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
		"condition": "shop_unlocked",
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
	"auto_buy_unlock": {
		"condition": "auto_buy_unlocked",
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
	"pressure_explained": {
		"condition": "pressure_10",
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
	"prestige_explained": {
		"condition": "prestige_available",
		"priority": 60,
		"steps": [
			{
				"header": "The Cycle Continues",
				"body": "You can now PRESTIGE! Reset your progress to gain powerful permanent bonuses. Each prestige makes future descents faster and deeper.",
				"highlight": "PrestigeButton",
				"wait_for_click": false
			}
		]
	}
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100  # Render on top of everything
	_create_popup_ui()
	_create_highlight_overlay()

func _process(_delta: float) -> void:
	if current_state == TutorialState.IDLE and active_tutorial == "":
		_check_tutorial_triggers()

func start_tutorial(tutorial_key: String) -> bool:
	if not TUTORIALS.has(tutorial_key):
		push_error("Tutorial not found: " + tutorial_key)
		return false
	
	if tutorial_key in completed_tutorials:
		return false
	
	if active_tutorial != "":
		return false
	
	active_tutorial = tutorial_key
	current_step_idx = 0
	current_state = TutorialState.WAITING_CLICK
	
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
	
	_hide_popup()
	_hide_highlight()
	
	active_tutorial = ""
	current_step_idx = 0
	current_state = TutorialState.IDLE
	navigation_queue.clear()
	expected_click_target = ""

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

func _create_popup_ui() -> void:
	popup_panel = Panel.new()
	popup_panel.name = "TutorialPopup"
	popup_panel.custom_minimum_size = Vector2(400, 200)
	popup_panel.size = Vector2(400, 200)
	popup_panel.visible = false
	
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
	# Changed to Panel so we can have borders
	highlight_overlay = Panel.new()
	highlight_overlay.name = "HighlightOverlay"
	highlight_overlay.visible = false
	highlight_overlay.z_index = 50
	highlight_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var highlight_style = StyleBoxFlat.new()
	highlight_style.bg_color = Color(1.0, 1.0, 0.3, 0.2)  # Yellow transparent fill
	highlight_style.border_width_left = 3
	highlight_style.border_width_right = 3
	highlight_style.border_width_top = 3
	highlight_style.border_width_bottom = 3
	highlight_style.border_color = Color(1.0, 0.9, 0.3, 1.0)  # Solid yellow border
	highlight_style.corner_radius_top_left = 4
	highlight_style.corner_radius_top_right = 4
	highlight_style.corner_radius_bottom_left = 4
	highlight_style.corner_radius_bottom_right = 4
	highlight_overlay.add_theme_stylebox_override("panel", highlight_style)
	
	add_child(highlight_overlay)

func _show_current_step() -> void:
	if active_tutorial == "" or popup_panel == null:
		return
	
	var tutorial_data: Dictionary = TUTORIALS[active_tutorial]
	var steps: Array = tutorial_data["steps"]
	
	if current_step_idx >= steps.size():
		_complete_tutorial()
		return
	
	var step_data: Dictionary = steps[current_step_idx]
	
	# Update popup content with null checks
	var margin = popup_panel.get_node_or_null("MarginBox")
	if margin == null:
		return
	var vbox = margin.get_node_or_null("ContentContainer")
	if vbox == null:
		return
		
	var header_label: Label = vbox.get_node_or_null("PopupHeader")
	var body_label: Label = vbox.get_node_or_null("PopupBody")
	
	if header_label:
		header_label.text = step_data.get("header", "")
	if body_label:
		body_label.text = step_data.get("body", "")
	
	# Center popup in viewport
	var viewport_size = get_viewport().get_visible_rect().size
	popup_panel.position = (viewport_size - popup_panel.size) / 2
	popup_panel.visible = true
	
	# Handle highlight
	var highlight_target = step_data.get("highlight", "")
	if highlight_target != "":
		_highlight_element(highlight_target)
	else:
		_hide_highlight()
	
	# Handle forced navigation
	if step_data.has("navigate"):
		var nav_path: Array = step_data["navigate"]
		navigation_queue.clear()
		for nav_item in nav_path:
			navigation_queue.append({"target": nav_item})
		_start_forced_navigation()
	
	# Update button visibility based on wait state
	var button_row = vbox.get_node_or_null("ButtonRow")
	if button_row:
		var skip_btn: Button = button_row.get_node_or_null("SkipButton")
		if skip_btn:
			skip_btn.visible = not step_data.get("wait_for_click", false)
	
	# Set state
	if step_data.get("wait_for_click", false):
		current_state = TutorialState.WAITING_CLICK
	else:
		current_state = TutorialState.HIGHLIGHTING

func _highlight_element(element_key: String) -> void:
	if highlight_overlay == null:
		return
		
	var target_element = _find_ui_element(element_key)
	if target_element == null:
		highlight_overlay.visible = false
		return
	
	var global_pos = target_element.global_position
	var element_size = target_element.size
	
	highlight_overlay.position = global_pos
	highlight_overlay.size = element_size
	highlight_overlay.visible = true

func _hide_highlight() -> void:
	if highlight_overlay:
		highlight_overlay.visible = false

func _hide_popup() -> void:
	if popup_panel:
		popup_panel.visible = false

func _on_continue_pressed() -> void:
	if current_state == TutorialState.WAITING_CLICK:
		return
	advance_step()

func _find_ui_element(target_element_name: String) -> Control:
	var tree = get_tree()
	if tree == null:
		return null
		
	var current_scene = tree.current_scene
	if current_scene == null:
		return null
	
	# Search recursively but only in the current scene
	var found_element = current_scene.find_child(target_element_name, true, false)
	if found_element is Control:
		return found_element as Control
	return null

func _start_forced_navigation() -> void:
	if navigation_queue.is_empty():
		current_state = TutorialState.WAITING_CLICK
		return
	
	current_state = TutorialState.FORCED_NAVIGATION
	var next_nav = navigation_queue.pop_front()
	expected_click_target = next_nav["target"]
	
	_highlight_element(expected_click_target)

func on_ui_element_clicked(clicked_element_name: String) -> bool:
	if current_state != TutorialState.FORCED_NAVIGATION:
		return false
	
	if clicked_element_name != expected_click_target:
		return false
	
	# Correct element clicked
	if navigation_queue.is_empty():
		current_state = TutorialState.WAITING_CLICK
		expected_click_target = ""
		_hide_highlight()
	else:
		_start_forced_navigation()
	
	return true

func _check_tutorial_triggers() -> void:
	# Only check if we have a valid game state
	var game_mgr = get_node_or_null("/root/GameManager")
	if game_mgr == null:
		return
		
	for tutorial_key in TUTORIALS.keys():
		if tutorial_key in completed_tutorials:
			continue
		if tutorial_key in tutorial_history:
			continue
		
		var tutorial_data: Dictionary = TUTORIALS[tutorial_key]
		var condition_type = tutorial_data.get("condition", "")
		
		if _check_condition(condition_type, game_mgr):
			start_tutorial(tutorial_key)
			return

func _check_condition(condition_type: String, game_mgr: Node) -> bool:
	match condition_type:
		"first_run":
			return game_mgr.get("total_runs") == 0 and not game_mgr.get("is_diving")
		
		"first_wake":
			return game_mgr.get("total_runs") == 1 and not game_mgr.get("is_diving")
		
		"depth_2_unlocked":
			return game_mgr.get("max_depth_tier_reached") >= 2
		
		"depth_3_unlocked":
			return game_mgr.get("max_depth_tier_reached") >= 3
		
		"instability_50":
			var drc = game_mgr.get_node_or_null("DepthRunController")
			if drc:
				return drc.get("instability") >= 50.0
			return false
		
		"first_event":
			return false  # Implement via save flag
		
		"overclock_unlocked":
			return game_mgr.get("crystals") > 0
		
		"first_crystal":
			return game_mgr.get("crystals") > 0 and not "first_crystal" in completed_tutorials
		
		"shop_unlocked":
			return game_mgr.get("total_runs") >= 2
		
		"auto_buy_unlocked":
			var levels = game_mgr.get("depth_upgrade_levels")
			if levels is Dictionary:
				return levels.get("automated_mind_1", 0) > 0
			return false
		
		"pressure_10":
			return game_mgr.get("pressure") >= 10.0
		
		"prestige_available":
			return game_mgr.get("memories") >= 100
		
		_:
			return false

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
	completed_tutorials.erase(tutorial_key)
	tutorial_history.erase(tutorial_key)
	hide_tutorial_menu()
	start_tutorial(tutorial_key)

func get_save_data() -> Dictionary:
	return {
		"completed_tutorials": completed_tutorials.duplicate(),
		"tutorial_history": tutorial_history.duplicate()
	}

func load_save_data(data: Dictionary) -> void:
	if data.has("completed_tutorials"):
		completed_tutorials = data["completed_tutorials"].duplicate()
	if data.has("tutorial_history"):
		tutorial_history = data["tutorial_history"].duplicate()
