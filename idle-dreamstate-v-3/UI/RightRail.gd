extends PanelContainer
class_name RightRail

@export var settings_panel_path: NodePath
@export var shop_panel_path: NodePath

# Position
@export var right_margin: float = 18.0
@export var button_size: Vector2 = Vector2(44, 44)
@export var gap: float = 8.0
@export var top_margin: float = 150.0 # optional: push down a bit

@onready var settings_btn: Button = $"VBoxContainer/SettingsButton"
@onready var shop_btn: Button = $"VBoxContainer/ShopButton"

var settings_panel: Control
var shop_panel: Control

func _ready() -> void:
	# --- IMPORTANT: remove the PanelContainer background so nothing "sticks out" ---
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	# --- Position rail ---
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0

	# Height: 2 buttons + gap (no extra padding)
	var h := (button_size.y * 2.0) + gap
	offset_left = -button_size.x - right_margin
	offset_right = -right_margin
	offset_top = top_margin
	offset_bottom = top_margin + h

	mouse_filter = Control.MOUSE_FILTER_PASS

	# --- Panels ---
	settings_panel = get_node_or_null(settings_panel_path) as Control
	shop_panel = get_node_or_null(shop_panel_path) as Control
	if settings_panel: settings_panel.visible = false
	if shop_panel: shop_panel.visible = false

	# --- Buttons base setup ---
	_setup_button(settings_btn, "⚙")
	_setup_button(shop_btn, "🛒")



	# Copy upgrade button style
	var ref_btn := _find_any_upgrade_button()
	if ref_btn != null:
		_copy_button_theme(ref_btn, settings_btn)
		_copy_button_theme(ref_btn, shop_btn)

	# Connect clicks
	if settings_btn and not settings_btn.pressed.is_connected(_on_settings_pressed):
		settings_btn.pressed.connect(_on_settings_pressed)
	if shop_btn and not shop_btn.pressed.is_connected(_on_shop_pressed):
		shop_btn.pressed.connect(_on_shop_pressed)

func _setup_button(btn: Button, text: String) -> void:
	if btn == null:
		return

	btn.text = text
	btn.custom_minimum_size = button_size
	btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	btn.mouse_filter = Control.MOUSE_FILTER_STOP

	# remove extra width/padding pressure
	btn.add_theme_constant_override("h_separation", 0)
	btn.add_theme_constant_override("content_margin_left", 6)
	btn.add_theme_constant_override("content_margin_right", 6)
	btn.add_theme_constant_override("content_margin_top", 6)
	btn.add_theme_constant_override("content_margin_bottom", 6)
	
	#settings_btn.text = ""
	#settings_btn.icon = preload("res://UI/Icons/settings.png")
	#shop_btn.text = ""
	#shop_btn.icon = preload("res://UI/Icons/shop.png")



func _on_settings_pressed() -> void:
	if shop_panel:
		shop_panel.visible = false
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

func _toggle_panel(show_panel: Control, hide_panel: Control) -> void:
	if hide_panel:
		hide_panel.visible = false
	if show_panel:
		show_panel.visible = not show_panel.visible

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

func _copy_button_theme(from_btn: Button, to_btn: Button) -> void:
	if from_btn == null or to_btn == null:
		return

	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := from_btn.get_theme_stylebox(k)
		if sb:
			to_btn.add_theme_stylebox_override(k, sb)

	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		var col := from_btn.get_theme_color(k)
		to_btn.add_theme_color_override(k, col)

	for k in ["h_separation", "content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		var v := from_btn.get_theme_constant(k)
		to_btn.add_theme_constant_override(k, v)
