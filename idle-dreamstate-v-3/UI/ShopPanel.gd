# ShopPanel.gd
# Restores visible content (simple "coming soon" + Close) and uses same blue panel styling.
# No backdrop/overlay creation; no modal blocker; no weird resizing.
extends PanelContainer
class_name ShopPanel

@export var panel_min_size: Vector2 = Vector2(720, 420)

@export var panel_bg: Color = Color(0.04, 0.07, 0.12, 0.92)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 1.0)
@export var panel_border_width: int = 2
@export var panel_radius: int = 12

@export var settings_panel_node_name: String = "SettingsPanel"
@export var prestige_panel_node_name: String = "PrestigePanel"

var _root: VBoxContainer
var _close_btn: Button

func _ready() -> void:
	_apply_center_layout(panel_min_size)
	_apply_panel_frame()

	_build_ui()

	visible = false
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)

func open() -> void:
	_force_close_overlay(settings_panel_node_name)
	_force_close_overlay(prestige_panel_node_name)

	_apply_center_layout(panel_min_size)
	_apply_panel_frame()

	visible = true
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP

	focus_mode = Control.FOCUS_ALL
	grab_focus()

func close() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not get_global_rect().has_point(mb.position):
				close()
				get_viewport().set_input_as_handled()

func _build_ui() -> void:
	# Clear existing children (in case you added nodes in editor later)
	for c in get_children():
		c.queue_free()

	_root = VBoxContainer.new()
	_root.name = "Root"
	_root.add_theme_constant_override("separation", 10)
	add_child(_root)

	var header := HBoxContainer.new()
	_root.add_child(header)

	var title := Label.new()
	title.text = "Shop"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)

	_style_button(_close_btn)

	_root.add_child(HSeparator.new())

	var info := Label.new()
	info.text = "Shop coming soon."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(info)

func _apply_center_layout(min_sz: Vector2) -> void:
	custom_minimum_size = min_sz
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -min_sz.x * 0.5
	offset_top = -min_sz.y * 0.5
	offset_right = min_sz.x * 0.5
	offset_bottom = min_sz.y * 0.5

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
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)

func _mk_btn_style(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
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
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _style_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := _mk_btn_style(Color(0.10, 0.11, 0.14, 0.95), Color(0.24, 0.67, 0.94, 0.95), 2, 8)
	var hover := _mk_btn_style(Color(0.13, 0.14, 0.18, 0.98), Color(0.30, 0.75, 0.98, 1.0), 2, 8)
	var pressed := _mk_btn_style(Color(0.07, 0.08, 0.10, 0.95), Color(0.20, 0.60, 0.90, 0.95), 2, 8)
	var disabled := _mk_btn_style(Color(0.08, 0.08, 0.10, 0.55), Color(0.20, 0.40, 0.55, 0.45), 2, 8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.70, 0.74, 0.80, 1.0))

func _force_close_overlay(node_name: String) -> void:
	if node_name.strip_edges() == "":
		return
	var n := get_tree().current_scene.find_child(node_name, true, false)
	if n == null:
		return
	if n.has_method("close"):
		n.call("close")
	elif n is CanvasItem:
		(n as CanvasItem).visible = false
