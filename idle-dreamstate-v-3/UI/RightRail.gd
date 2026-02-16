class_name RightRail
extends PanelContainer

# ============================================
# IDLE DREAMSTATE - RIGHT RAIL UI
# ============================================
# Contains Settings, Shop, and Tutorials buttons
# ============================================

signal settings_pressed
signal shop_pressed
signal tutorials_pressed

var settings_btn: Button = null
var shop_btn: Button = null
var tutorials_btn: Button = null

func _ready() -> void:
	custom_minimum_size = Vector2(60, 400)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var rail_style = StyleBoxFlat.new()
	rail_style.bg_color = Color(0.06, 0.06, 0.1, 0.9)
	rail_style.border_width_left = 1
	rail_style.border_color = Color(0.2, 0.2, 0.3, 1.0)
	add_theme_stylebox_override("panel", rail_style)
	
	_create_buttons()

func _create_buttons() -> void:
	var vbox = VBoxContainer.new()
	vbox.name = "ButtonContainer"
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	vbox.add_theme_constant_override("separation", 10)
	
	var margin = MarginContainer.new()
	margin.name = "ButtonMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	add_child(margin)
	margin.add_child(vbox)
	
	# Settings button
	settings_btn = Button.new()
	settings_btn.name = "SettingsButton"
	settings_btn.text = ""
	settings_btn.custom_minimum_size = Vector2(40, 40)
	settings_btn.tooltip_text = "Settings"
	
	var settings_icon = _create_settings_icon()
	settings_btn.add_child(settings_icon)
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)
	
	# Shop button
	shop_btn = Button.new()
	shop_btn.name = "ShopButton"
	shop_btn.text = ""
	shop_btn.custom_minimum_size = Vector2(40, 40)
	shop_btn.tooltip_text = "Shop"
	
	var shop_icon = _create_shop_icon()
	shop_btn.add_child(shop_icon)
	shop_btn.pressed.connect(_on_shop_pressed)
	vbox.add_child(shop_btn)
	
	# Tutorials button
	tutorials_btn = Button.new()
	tutorials_btn.name = "TutorialsButton"
	tutorials_btn.text = ""
	tutorials_btn.custom_minimum_size = Vector2(40, 40)
	tutorials_btn.tooltip_text = "Tutorials"
	
	var tutorials_icon = _create_tutorials_icon()
	tutorials_btn.add_child(tutorials_icon)
	tutorials_btn.pressed.connect(_on_tutorials_pressed)
	vbox.add_child(tutorials_btn)

func _create_settings_icon() -> Control:
	var icon = Control.new()
	icon.name = "SettingsIcon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	return icon

func _create_shop_icon() -> Control:
	var icon = Control.new()
	icon.name = "ShopIcon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	return icon

func _create_tutorials_icon() -> Control:
	var icon = Control.new()
	icon.name = "TutorialsIcon"
	icon.custom_minimum_size = Vector2(24, 24)
	icon.set_anchors_preset(Control.PRESET_CENTER)
	return icon

func _on_settings_pressed() -> void:
	settings_pressed.emit()

func _on_shop_pressed() -> void:
	shop_pressed.emit()

func _on_tutorials_pressed() -> void:
	tutorials_pressed.emit()
	var tutorial_mgr = get_node_or_null("/root/TutorialManager")
	if tutorial_mgr:
		tutorial_mgr.show_tutorial_menu()
