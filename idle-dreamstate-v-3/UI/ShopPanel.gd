extends PanelContainer
class_name ShopPanel

@export var panel_size: Vector2 = Vector2(720, 420)

# Panel frame (blue border)
@export var panel_bg: Color = Color(0.06, 0.08, 0.12, 0.70)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 0.95)
@export var panel_border_width: int = 2
@export var panel_radius: int = 10

var _ref_button: Button = null

func _ready() -> void:
	_ref_button = _find_any_upgrade_button()

	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = panel_size
	z_index = 50
	visible = false

	_apply_panel_frame()
	_build()

func open() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = panel_size
	z_index = 50
	_apply_panel_frame()
	visible = true

func _apply_panel_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = panel_bg
	sb.border_color = panel_border
	sb.border_width_left = panel_border_width
	sb.border_width_top = panel_border_width
	sb.border_width_right = panel_border_width
	sb.border_width_bottom = panel_border_width
	sb.corner_radius_top_left = panel_radius
	sb.corner_radius_top_right = panel_radius
	sb.corner_radius_bottom_left = panel_radius
	sb.corner_radius_bottom_right = panel_radius
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	add_theme_stylebox_override("panel", sb)

func _build() -> void:
	for c in get_children():
		c.queue_free()

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	var title := Label.new()
	title.text = "Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	header.add_child(close)
	_apply_theme_to_button(close)

	root.add_child(HSeparator.new())

	var info := Label.new()
	info.text = "Shop coming next."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)

	for item_name in ["Starter Pack", "Boost x2 (5 min)", "Cosmetic: Neon Theme"]:
		var b := Button.new()
		b.text = item_name
		b.pressed.connect(func(): print("Clicked:", item_name))
		root.add_child(b)
		_apply_theme_to_button(b)

# ----------------------------
# Theme copying (upgrade-button look)
# ----------------------------
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

func _apply_theme_to_button(btn: Button) -> void:
	if btn == null or _ref_button == null:
		return

	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _ref_button.get_theme_stylebox(k)
		if sb:
			btn.add_theme_stylebox_override(k, sb)

	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		var col := _ref_button.get_theme_color(k)
		btn.add_theme_color_override(k, col)

	for k in ["h_separation", "content_margin_left", "content_margin_right", "content_margin_top", "content_margin_bottom"]:
		var v := _ref_button.get_theme_constant(k)
		btn.add_theme_constant_override(k, v)
