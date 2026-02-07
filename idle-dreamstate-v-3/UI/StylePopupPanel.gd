extends PanelContainer
class_name StyledPopupPanel

@export var start_hidden: bool = true
@export var center_on_screen: bool = true
@export var min_size: Vector2 = Vector2(520, 360)

# Panel look (dark + blue border like your UI)
@export var bg_color: Color = Color(0.06, 0.08, 0.12, 0.78)
@export var border_color: Color = Color(0.24, 0.67, 0.94, 0.95) # nice UI blue
@export var border_width: int = 2
@export var corner_radius: int = 10

# Optional subtle inner highlight
@export var inner_highlight: bool = true
@export var highlight_color: Color = Color(0.80, 0.90, 1.00, 0.06)

func _ready() -> void:
	if start_hidden:
		visible = false

	if center_on_screen:
		set_anchors_preset(Control.PRESET_CENTER)
		custom_minimum_size = min_size

	# Build panel style
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.border_color = border_color
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.corner_radius_top_left = corner_radius
	sb.corner_radius_top_right = corner_radius
	sb.corner_radius_bottom_left = corner_radius
	sb.corner_radius_bottom_right = corner_radius
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14

	# Tiny “glass” highlight
	if inner_highlight:
		sb.shadow_color = highlight_color
		sb.shadow_size = 1
		sb.shadow_offset = Vector2(0, 0)

	add_theme_stylebox_override("panel", sb)
