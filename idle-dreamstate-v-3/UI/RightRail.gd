extends PanelContainer
class_name RightRail

@export var settings_panel_path: NodePath
@export var shop_panel_path: NodePath

# Position
@export var right_margin: float = 18.0
@export var button_size: Vector2 = Vector2(44, 44)
@export var gap: float = 8.0
@export var top_margin: float = 150.0

@onready var settings_btn: Button = $"VBoxContainer/SettingsButton"
@onready var shop_btn: Button = $"VBoxContainer/ShopButton"

var settings_panel: Control
var shop_panel: Control
var tutorials_btn: Button = null  # Store reference

func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# Position rail
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0

	var h := (button_size.y * 3.0) + (gap * 2)
	offset_left = -button_size.x - right_margin
	offset_right = -right_margin
	offset_top = top_margin
	offset_bottom = top_margin + h

	mouse_filter = Control.MOUSE_FILTER_PASS

	# Panels - try exported paths first, then find in tree
	settings_panel = get_node_or_null(settings_panel_path) as Control
	shop_panel = get_node_or_null(shop_panel_path) as Control
	
	# FALLBACK: Find by name if exports not set (fixes null panel issue)
	if settings_panel == null:
		settings_panel = get_tree().current_scene.find_child("SettingsPanel", true, false) as Control
	if shop_panel == null:
		shop_panel = get_tree().current_scene.find_child("ShopPanel", true, false) as Control
		
	print("RightRail panels found - Settings:", settings_panel != null, " Shop:", shop_panel != null)

	if settings_panel: 
		settings_panel.visible = false
	if shop_panel: 
		shop_panel.visible = false

	# Setup buttons
	_setup_button(settings_btn, "⚙")
	_setup_button(shop_btn, "🛒")

	# Copy upgrade button style
	var ref_btn := _find_any_upgrade_button()
	if ref_btn != null:
		_copy_button_theme(ref_btn, settings_btn)
		_copy_button_theme(ref_btn, shop_btn)

	# Connect clicks - AND FIX MOUSE FILTER
	if settings_btn:
		if not settings_btn.pressed.is_connected(_on_settings_pressed):
			settings_btn.pressed.connect(_on_settings_pressed)
		settings_btn.mouse_filter = Control.MOUSE_FILTER_PASS  # FIX: Was STOP, use PASS like tutorial button
			
	if shop_btn:
		if not shop_btn.pressed.is_connected(_on_shop_pressed):
			shop_btn.pressed.connect(_on_shop_pressed)
		shop_btn.mouse_filter = Control.MOUSE_FILTER_PASS  # FIX: Was STOP, use PASS like tutorial button

	# ADD TUTORIALS BUTTON
	_add_tutorials_button(ref_btn)

func _add_tutorials_button(ref_btn: Button) -> void:
	tutorials_btn = Button.new()
	tutorials_btn.name = "TutorialsButton"
	tutorials_btn.text = "📖"
	tutorials_btn.custom_minimum_size = button_size
	tutorials_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	tutorials_btn.mouse_filter = Control.MOUSE_FILTER_PASS
	
	if ref_btn != null:
		_copy_button_theme(ref_btn, tutorials_btn)
	
	tutorials_btn.pressed.connect(_on_tutorials_pressed)
	
	var vbox = $VBoxContainer
	if vbox:
		vbox.add_child(tutorials_btn)
		print("Tutorial button added to VBoxContainer")
		print("RightRail buttons - Settings:", settings_btn != null, " Shop:", shop_btn != null, " Tutorial:", tutorials_btn != null)
	else:
		push_error("VBoxContainer not found in RightRail")
	
func _on_tutorials_pressed() -> void:
	print("Tutorial button pressed!")
	if settings_panel:
		settings_panel.visible = false
	if shop_panel:
		shop_panel.visible = false
	
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("show_tutorial_menu"):
		tm.show_tutorial_menu()
	else:
		push_error("TutorialManage not found")

func _copy_button_theme(from_btn: Button, to_btn: Button) -> void:
	if from_btn == null or to_btn == null:
		return

	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := from_btn.get_theme_stylebox(k)
		if sb:
			to_btn.add_theme_stylebox_override(k, sb)
	
	# FIX: Ensure blue border is applied (in case reference button has no theme)
	var border_color := Color(0.3, 0.5, 0.7, 1.0)  # Blue border
	for k in ["normal", "hover", "pressed"]:
		var existing := to_btn.get_theme_stylebox(k)
		if existing is StyleBoxFlat:
			existing.border_width_left = 2
			existing.border_width_right = 2
			existing.border_width_top = 2
			existing.border_width_bottom = 2
			existing.border_color = border_color

func _setup_button(btn: Button, text: String) -> void:
	if btn == null:
		return

	btn.text = text
	btn.custom_minimum_size = button_size
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	btn.add_theme_constant_override("h_separation", 0)
	btn.add_theme_constant_override("content_margin_left", 6)
	btn.add_theme_constant_override("content_margin_right", 6)
	btn.add_theme_constant_override("content_margin_top", 6)
	btn.add_theme_constant_override("content_margin_bottom", 6)

func _on_settings_pressed() -> void:
	if shop_panel:
		shop_panel.visible = false
	if tutorials_btn:
		# Optional: hide tutorials indicator
		pass
	if settings_panel:
		if settings_panel.has_method("open"):
			settings_panel.call("open")
		else:
			settings_panel.visible = not settings_panel.visible

func _on_shop_pressed() -> void:
	if settings_panel:
		settings_panel.visible = false
	if shop_panel:
		if shop_panel.has_method("open"):
			shop_panel.call("open")
		else:
			shop_panel.visible = not shop_panel.visible

func _find_any_upgrade_button() -> Button:
	var row := get_tree().current_scene.find_child("UpgradeRow", true, false)
	if row == null:
		return get_tree().current_scene.find_child("Button", true, false) as Button
	return _find_first_button(row)

func _find_first_button(n: Node) -> Button:
	if n is Button:
		return n as Button
	for c in n.get_children():
		var b := _find_first_button(c)
		if b != null:
			return b
	return null
