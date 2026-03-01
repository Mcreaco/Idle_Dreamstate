extends PanelContainer
class_name TopBarPanel

const COLOR_TEXT: Color = Color(0.87, 0.91, 1.0)
const COLOR_BAR_BLUE: Color = Color(0.24, 0.67, 0.94)
const COLOR_BAR_AMBER: Color = Color(0.95, 0.65, 0.15)
const COLOR_BAR_RED: Color = Color(0.85, 0.18, 0.18)

@export var depth_label_path: NodePath
@onready var depth_label: Label = _resolve_depth_label()

# Center elements (keep existing references)
@onready var inst_title: Label = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityTitle
@onready var inst_bar: ProgressBar = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityBar
@onready var inst_hint: Label = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityHint
@export var instability_per_sec: float = 0.0
# Layout containers
var left_buttons_container: HBoxContainer
var currencies_container: HBoxContainer

# Currency displays (Right side)
var thoughts_display: HBoxContainer
var control_display: HBoxContainer
var gems_display: HBoxContainer

# Left side buttons
var piggy_container: HBoxContainer
var piggy_value: Label
var piggy_button: Button
var time_warp_button: Button
var watch_ad_button: Button
var dream_current: float = 1.0
# References
var _run: Node = null
var time_warp_panel: Control

func _ready() -> void:
	_style_top_bar_panel()
	_remove_all_existing_buttons()
	_setup_layout_safe()
	_create_piggy_bank_ui()
	_create_watch_ad_button()
	_create_time_warp_button()
	_setup_currency_displays()
	_hide_old_ui()
	
	# CRITICAL FIX: Hide the TimeWarpPanel's internal Watch Ad button
	_hide_timewarp_watch_ad()
	
	time_warp_panel = get_node_or_null("/root/Main/MainUI/TimeWarpPanel")
	if time_warp_panel:
		time_warp_panel.visible = false
	
	if inst_hint:
		inst_hint.visible = false
	if inst_bar:
		inst_bar.tooltip_text = "Instability rises from idle gain and events. Reaching 100 ends the run."
	if inst_title:
		inst_title.tooltip_text = "Time to fail (TTF) is estimated from current idle instability gain."
	
	_style_inst_bar()
	# CRITICAL FIX: Ensure all buttons can receive input
	call_deferred("_fix_button_input")
	
	set_process(true)

func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	
	var mouse_pos = get_global_mouse_position()
	
	# Check each button directly
	if piggy_button and piggy_button.visible and not piggy_button.disabled:
		if piggy_button.get_global_rect().has_point(mouse_pos):
			print("PIGGY BUTTON CLICKED")
			_on_piggy_break()
			return
	
	if watch_ad_button and watch_ad_button.visible and not watch_ad_button.disabled:
		if watch_ad_button.get_global_rect().has_point(mouse_pos):
			print("WATCH AD CLICKED")
			_on_watch_ad_pressed()
			return
	
	if time_warp_button and time_warp_button.visible:
		if time_warp_button.get_global_rect().has_point(mouse_pos):
			print("TIME WARP CLICKED")
			_on_time_warp_pressed()
			return
			
func _fix_button_input() -> void:
	# Make sure containers don't block buttons
	if left_buttons_container:
		left_buttons_container.mouse_filter = Control.MOUSE_FILTER_PASS
		for child in left_buttons_container.get_children():
			if child is HBoxContainer:  # Piggy container
				child.mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Ensure buttons capture input
	if piggy_button:
		piggy_button.mouse_filter = Control.MOUSE_FILTER_STOP
		piggy_button.z_index = 10
		print("Piggy button fixed: ", piggy_button.get_global_rect())
	
	if watch_ad_button:
		watch_ad_button.mouse_filter = Control.MOUSE_FILTER_STOP
		watch_ad_button.z_index = 10
	
	if time_warp_button:
		time_warp_button.mouse_filter = Control.MOUSE_FILTER_STOP
		time_warp_button.z_index = 10
		
func _hide_timewarp_watch_ad() -> void:
	var twp = get_node_or_null("/root/Main/MainUI/TimeWarpPanel")
	if twp:
		# Hide the Watch Ad button inside TimeWarpPanel
		var watch_ad_btn = twp.get_node_or_null("Watch Ad")
		if watch_ad_btn:
			watch_ad_btn.visible = false
			print("Hidden TimeWarpPanel's Watch Ad button")
			
func _remove_all_existing_buttons() -> void:
	var top_bar = $TopBar
	
	# Find and remove any existing WatchAd buttons anywhere in the tree
	for btn in find_children("*", "Button", true):
		if "Watch" in btn.name or "Ad" in btn.name or btn.name == "TimeWarpButton":
			print("Removing old button: ", btn.name)
			btn.queue_free()
	
	# Also check in TopBar specifically
	for child in top_bar.get_children():
		if child is Button:
			child.queue_free()
		elif child is HBoxContainer and child != left_buttons_container:
			# Check if this contains our buttons
			for sub in child.get_children():
				if sub is Button and ("Watch" in sub.name or "Ad" in sub.name or "Warp" in sub.name):
					sub.queue_free()
					
func _hide_old_ui() -> void:
	# Hide old MarginContainer completely
	var old_margin = get_node_or_null("TopBar/MarginContainer")
	if old_margin:
		old_margin.visible = false
		# Also hide all its children
		for child in old_margin.get_children():
			child.visible = false
	
	# Hide old ControlPad
	var old_control = get_node_or_null("TopBar/ControlPad")
	if old_control:
		old_control.visible = false
	
	# CRITICAL: Find any stray "Watch Ad" labels or buttons that might be in old UI
	for child in get_tree().current_scene.find_children("*", "Button", true):
		if child != watch_ad_button and child != time_warp_button and child != piggy_button:
			if "Watch" in child.text or "Ad" in child.text:
				child.visible = false
				child.queue_free()

func _setup_layout_safe() -> void:
	var top_bar = $TopBar
	
	# Check if we already created the layout
	if top_bar.has_node("MainHBox"):
		left_buttons_container = top_bar.get_node("MainHBox/LeftButtons")
		currencies_container = top_bar.get_node("MainHBox/RightCurrencies")
		return
	
	# Create main HBox for 3-column layout (WITHOUT removing existing children)
	var main_hbox = HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_theme_constant_override("separation", 10)
	
	# Insert at the beginning, before existing nodes
	top_bar.add_child(main_hbox)
	top_bar.move_child(main_hbox, 0)
	
	# LEFT SECTION (33% width)
	left_buttons_container = HBoxContainer.new()
	left_buttons_container.name = "LeftButtons"
	left_buttons_container.add_theme_constant_override("separation", 8)
	left_buttons_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_buttons_container.size_flags_stretch_ratio = 1.0
	left_buttons_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	main_hbox.add_child(left_buttons_container)
	
	# CENTER SECTION (33% width) - Move existing InstabilityCenter here
	var center_section = CenterContainer.new()
	center_section.name = "CenterSection"
	center_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center_section.size_flags_stretch_ratio = 1.0
	main_hbox.add_child(center_section)
	
	# Move the existing InstabilityCenter into our center section
	if top_bar.has_node("InstabilityCenter"):
		var inst_center = top_bar.get_node("InstabilityCenter")
		inst_center.get_parent().remove_child(inst_center)
		center_section.add_child(inst_center)
	
	# RIGHT SECTION (33% width)
	currencies_container = HBoxContainer.new()
	currencies_container.name = "RightCurrencies"
	currencies_container.add_theme_constant_override("separation", 12)
	currencies_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	currencies_container.size_flags_stretch_ratio = 1.0
	currencies_container.alignment = BoxContainer.ALIGNMENT_END
	main_hbox.add_child(currencies_container)

func _remove_duplicate_buttons() -> void:
	# Remove any existing buttons in left container
	if left_buttons_container:
		for child in left_buttons_container.get_children():
			if child is Button or child.name == "PiggyBankContainer":
				child.queue_free()

func _create_piggy_bank_ui() -> void:
	piggy_container = HBoxContainer.new()
	piggy_container.name = "PiggyBankContainer"
	piggy_container.add_theme_constant_override("separation", 4)
	
	# Piggy icon + value
	var icon := Label.new()
	icon.text = "🐷"
	icon.add_theme_font_size_override("font_size", 16)
	piggy_container.add_child(icon)
	
	piggy_value = Label.new()
	piggy_value.name = "PiggyValue"
	piggy_value.text = "0→0💎"
	piggy_value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	piggy_container.add_child(piggy_value)
	
	# Break button
	piggy_button = Button.new()
	piggy_button.name = "PiggyButton"
	piggy_button.text = "Break"
	piggy_button.custom_minimum_size = Vector2(60, 28)
	piggy_button.pressed.connect(_on_piggy_break)
	piggy_container.add_child(piggy_button)
	
	left_buttons_container.add_child(piggy_container)

func _create_watch_ad_button() -> void:
	watch_ad_button = Button.new()
	watch_ad_button.name = "WatchAdButton"
	watch_ad_button.text = "Watch Ad [10]"
	watch_ad_button.custom_minimum_size = Vector2(100, 28)
	watch_ad_button.pressed.connect(_on_watch_ad_pressed)
	left_buttons_container.add_child(watch_ad_button)

func _create_time_warp_button() -> void:
	time_warp_button = Button.new()
	time_warp_button.name = "TimeWarpButton"
	time_warp_button.text = "⏱️ Warp"
	time_warp_button.custom_minimum_size = Vector2(70, 28)
	time_warp_button.pressed.connect(_on_time_warp_pressed)
	left_buttons_container.add_child(time_warp_button)

func _setup_currency_displays() -> void:
	# Thoughts: 🧠 icon + value
	thoughts_display = _create_currency_display("🧠", Color(1.0, 0.85, 0.4))
	currencies_container.add_child(thoughts_display)
	
	# Control: 🛡️ icon + value  
	control_display = _create_currency_display("🛡️", Color(0.4, 0.85, 1.0))
	currencies_container.add_child(control_display)
	
	# Gems: 💎 icon + value
	gems_display = _create_currency_display("💎", Color(0.2, 0.8, 1.0))
	currencies_container.add_child(gems_display)
	
		# DREAM CURRENT DISPLAY - Single display
	var dream_display = _create_currency_display("🌊", Color(0.4, 0.8, 1.0))
	dream_display.name = "DreamCurrentDisplay"
	currencies_container.add_child(dream_display)
	
func _create_currency_display(icon: String, color: Color) -> HBoxContainer:
	var container = HBoxContainer.new()
	container.add_theme_constant_override("separation", 4)
	
	var icon_label = Label.new()
	icon_label.text = icon
	icon_label.add_theme_font_size_override("font_size", 18)
	container.add_child(icon_label)
	
	var value_label = Label.new()
	value_label.name = "ValueLabel"
	value_label.add_theme_color_override("font_color", color)
	value_label.add_theme_font_size_override("font_size", 16)
	container.add_child(value_label)
	
	return container

func _on_watch_ad_pressed() -> void:
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm and gm.has_method("watch_ad_for_time_warp"):
		var success = gm.watch_ad_for_time_warp(1.0)
		if success:
			print("Ad watch initiated for 1 hour warp")

func _on_piggy_break() -> void:
	print("!!! PIGGY BREAK BUTTON CLICKED !!!")
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null:
		print("ERROR: GameManager not found")
		return
	
	if not gm.has_method("break_piggy_bank"):
		print("ERROR: GameManager missing break_piggy_bank method")
		return
	
	var result: Dictionary = gm.break_piggy_bank()
	print("Break result: ", result)
	
	if result.get("success", false):
		print("SUCCESS! Gained ", result.get("amount", 0), " ", result.get("currency", "gems"))
		_show_gem_popup(result.get("amount", 0))
	
	_update_piggy_display()

func _show_gem_popup(amount: int) -> void:
	var popup = Label.new()
	popup.text = "+%d 💎" % amount
	popup.add_theme_font_size_override("font_size", 24)
	popup.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	popup.set_anchors_preset(Control.PRESET_CENTER)
	add_child(popup)
	
	var tween = create_tween()
	tween.tween_property(popup, "position:y", popup.position.y - 50, 1.0)
	tween.tween_property(popup, "modulate:a", 0.0, 0.5)
	tween.tween_callback(popup.queue_free)

func _on_time_warp_pressed() -> void:
	if time_warp_panel:
		time_warp_panel.visible = !time_warp_panel.visible
		print("Time Warp toggled: ", time_warp_panel.visible)
	else:
		push_warning("TimeWarpPanel not found!")

func _process(_delta: float) -> void:
	if _run == null:
		_run = get_node_or_null("/root/DepthRunController")
		if _run == null:
			return

	var thoughts: float = float(_run.get("thoughts"))
	var control: float = float(_run.get("control"))
	var thoughts_ps: float = float(_run.get("thoughts_per_sec"))
	var control_ps: float = 0.0
	if _run.has_method("get_control_per_sec"):
		control_ps = float(_run.call("get_control_per_sec"))

	var active_depth: int = int(_run.get("active_depth"))
	var max_depth: int = 0
	if _run.get("max_unlocked_depth") != null:
		max_depth = int(_run.get("max_unlocked_depth"))

	set_depth_ui(active_depth, max_depth)
	var inst_gain: float = 0.0
	if _run != null:
		var raw = _run.get("instability_per_sec")
		if raw != null:
			inst_gain = float(raw)

	if inst_title:
		inst_title.text = "Instability (+%s/s)" % _fmt_num(inst_gain)
	
	# Update currency displays with tooltips
	_update_currency_display(thoughts_display, thoughts, thoughts_ps, "Thoughts")
	_update_currency_display(control_display, control, control_ps, "Control")
	
	# Update gems
	var gm := get_node_or_null("/root/Main/GameManager")
	if gems_display and gm:
		var gems_count: int = gm.gems if "gems" in gm else 0
		gems_display.get_node("ValueLabel").text = _fmt_num_compact(gems_count)
		gems_display.tooltip_text = "Premium Currency"
	
	# Update center instability info
	if inst_title:
		inst_title.text = "Instability (+%s/s)" % _fmt_num(inst_gain)
		inst_title.tooltip_text = "+%.2f instability per second" % inst_gain
	
	# Update buttons
	if Engine.get_process_frames() % 60 == 0:
		_update_piggy_display()
		_update_time_warp_button()
		_update_watch_ad_button()
		
	# Update Dream Current
	var dream_display = currencies_container.get_node_or_null("DreamCurrentDisplay")
	if dream_display:
		if gm:
			var label = dream_display.get_node_or_null("ValueLabel")
			if label and "dream_current" in gm:
				label.text = "%.1f/s" % gm.dream_current
			
func _update_currency_display(container: HBoxContainer, value: float, rate: float, display_name: String) -> void:
	var label = container.get_node("ValueLabel")
	label.text = _fmt_num_compact(value)
	container.tooltip_text = "%s\n+%s per second" % [display_name, _fmt_num(rate)]

func _update_piggy_display() -> void:
	if piggy_value == null or piggy_button == null:
		return
	
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null:
		return
	
	var amount: float = float(gm.piggy_bank) if "piggy_bank" in gm else 0.0
	var can_break = gm.can_break_piggy_bank() if gm.has_method("can_break_piggy_bank") else amount >= 100.0
	
	var gem_value := int(amount / 10.0)
	piggy_value.text = "%d→%d💎" % [int(amount), gem_value]
	
	piggy_button.disabled = not can_break
	if can_break:
		piggy_button.text = "Break"
		piggy_button.modulate = Color(1, 1, 1)
	else:
		piggy_button.text = "Save..."
		piggy_button.modulate = Color(0.5, 0.5, 0.5)

func _update_time_warp_button() -> void:
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null or not gm.has_method("get_daily_stats"):
		return
	
	var stats = gm.get_daily_stats()
	var ads_left = stats.get("ads_remaining", 0)
	var remaining = stats.get("purchased_remaining", 0)
	
	time_warp_button.tooltip_text = "Time Warp\nPurchased: %.1fh left\nAds: %d left" % [remaining, ads_left]
	time_warp_button.disabled = (remaining <= 0 and ads_left <= 0)

func _update_watch_ad_button() -> void:
	if watch_ad_button == null:
		return
		
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null or not gm.has_method("get_daily_stats"):
		return
	
	var stats = gm.get_daily_stats()
	var ads_left = stats.get("ads_remaining", 0)
	
	watch_ad_button.text = "Watch Ad [%d]" % ads_left
	watch_ad_button.disabled = ads_left <= 0
	
	if ads_left <= 0:
		watch_ad_button.modulate = Color(0.5, 0.5, 0.5)
	else:
		watch_ad_button.modulate = Color(1, 1, 1)

func _fmt_num_compact(v: float) -> String:
	if v >= 1e15:
		var exponent := int(floor(log(v) / log(10)))
		var mantissa := snappedf(v / pow(10, exponent), 0.01)
		return str(mantissa) + "e+" + str(exponent)
	if v >= 1e12:
		return "%.1fT" % (v / 1e12)
	if v >= 1e9:
		return "%.1fB" % (v / 1e9)
	if v >= 1e6:
		return "%.1fM" % (v / 1e6)
	if v >= 1e3:
		return "%.1fK" % (v / 1e3)
	return "%.1f" % v

func _fmt_num(v: float) -> String:
	if v == INF or v == -INF:
		return "∞"
	if v != v:
		return "NaN"
	v = float(v)
	if v >= 1e15:
		var exponent := int(floor(log(v) / log(10)))
		var mantissa := snappedf(v / pow(10, exponent), 0.01)
		return str(mantissa) + "e+" + str(exponent)
	if v >= 1e12:
		return "%.2fT" % (v / 1e12)
	if v >= 1e9:
		return "%.2fB" % (v / 1e9)
	if v >= 1e6:
		return "%.2fM" % (v / 1e6)
	if v >= 1e3:
		return "%.2fK" % (v / 1e3)
	return "%.1f" % v

func _resolve_depth_label() -> Label:
	if depth_label_path != NodePath(""):
		var n := get_node_or_null(depth_label_path)
		if n and n is Label:
			return n as Label
	return find_child("DepthLabel", true, false) as Label

func _style_inst_bar() -> void:
	if inst_bar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.border_color = Color(1, 1, 1, 0.12)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.corner_radius_top_left = 8
	bg.corner_radius_top_right = 8
	bg.corner_radius_bottom_left = 8
	bg.corner_radius_bottom_right = 8
	bg.shadow_color = Color(0, 0, 0, 0.25)
	bg.shadow_size = 2

	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.9, 0.2, 0.2, 1.0)
	fg.border_color = Color(1, 1, 1, 0.18)
	fg.border_width_left = 1
	fg.border_width_top = 1
	fg.border_width_right = 1
	fg.border_width_bottom = 1
	fg.corner_radius_top_left = 8
	fg.corner_radius_top_right = 8
	fg.corner_radius_bottom_left = 8
	fg.corner_radius_bottom_right = 8
	fg.shadow_color = Color(0, 0, 0, 0.2)
	fg.shadow_size = 1

	inst_bar.add_theme_stylebox_override("bg", bg)
	inst_bar.add_theme_stylebox_override("fg", fg)

func set_depth_ui(current_depth: int, _max_depth: int) -> void:
	if depth_label:
		depth_label.text = "Depth: %d" % current_depth

func update_top_bar(
	_thoughts: float,
	_thoughts_ps: float,
	_control: float,
	_control_ps: float,
	_inst_pct: float,
	_is_overclock: bool,
	_overclock_time_left: float,
	_ttf: float,
	_inst_gain: float
) -> void:
	# Legacy method - kept for compatibility
	pass

func _style_top_bar_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.95)
	sb.border_color = COLOR_BAR_BLUE
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8
	add_theme_stylebox_override("panel", sb)
