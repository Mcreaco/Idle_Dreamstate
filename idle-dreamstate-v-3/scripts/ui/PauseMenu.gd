# PauseMenu.gd
# Fixes the remaining issue in your screenshot:
# - Resume button was showing the engine's "disabled/invalid" visual (white block)
# This script forces Resume/Quit to always use your blue-outline style in ALL states.

extends CanvasLayer

@export var enable_escape_toggle: bool = true

@onready var center: Control = $CenterContainer
@onready var panel: Control = $CenterContainer/Panel
@onready var title_label: Label = $CenterContainer/Panel/MarginContainer/VBox/TitleLabel
@onready var resume_button: Button = $CenterContainer/Panel/MarginContainer/VBox/ResumeButton
@onready var menu_button: Button = $CenterContainer/Panel/MarginContainer/VBox/MenuButton
@onready var quit_button: Button = $CenterContainer/Panel/MarginContainer/VBox/QuitButton
@onready var reset_button: Button = $CenterContainer/Panel/MarginContainer/VBox/ResetSaveButton

var _open: bool = false

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Text
	if is_instance_valid(title_label):
		title_label.text = "PAUSED"
	if is_instance_valid(resume_button):
		resume_button.text = "Resume"
	if is_instance_valid(quit_button):
		quit_button.text = "Quit"

	# Remove unused buttons + collapse their space
	_hide_and_collapse(menu_button)
	_hide_and_collapse(reset_button)

	# HARD force these to behave/paint as enabled buttons
	_force_enabled_button(resume_button)
	_force_enabled_button(quit_button)

	# Style
	_apply_panel_style(panel)
	_apply_button_style(resume_button)
	_apply_button_style(quit_button)

	# Signals
	if is_instance_valid(resume_button) and not resume_button.pressed.is_connected(_on_resume):
		resume_button.pressed.connect(_on_resume)
	if is_instance_valid(quit_button) and not quit_button.pressed.is_connected(_on_quit):
		quit_button.pressed.connect(_on_quit)

	_set_open(false)

func _input(event: InputEvent) -> void:
	if not enable_escape_toggle:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_set_open(not _open)
			get_viewport().set_input_as_handled()

func _set_open(v: bool) -> void:
	_open = v
	if is_instance_valid(center):
		center.visible = v

	# Re-assert (some themes flip visuals when tree pauses/unpauses)
	_force_enabled_button(resume_button)
	_force_enabled_button(quit_button)
	_apply_button_style(resume_button)
	_apply_button_style(quit_button)

	get_tree().paused = v
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_resume() -> void:
	_set_open(false)

func _on_quit() -> void:
	get_tree().quit()

func _hide_and_collapse(c: Control) -> void:
	if c == null or not is_instance_valid(c):
		return
	c.visible = false
	if c is BaseButton:
		(c as BaseButton).disabled = true
	c.custom_minimum_size = Vector2.ZERO
	c.size_flags_horizontal = 0
	c.size_flags_vertical = 0
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _force_enabled_button(b: Button) -> void:
	if b == null or not is_instance_valid(b):
		return
	b.disabled = false
	b.visible = true
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.focus_mode = Control.FOCUS_ALL
	b.modulate = Color(1, 1, 1, 1)

	# Prevent "disabled" palette from ever bleeding through
	b.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.92, 0.96, 1.0, 1.0))

func _apply_panel_style(p: Control) -> void:
	if p == null or not is_instance_valid(p):
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.95)
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)

func _mk_btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _apply_button_style(b: Button) -> void:
	if b == null or not is_instance_valid(b):
		return

	var normal := _mk_btn(Color(0.08, 0.10, 0.16, 0.95), Color(0.24, 0.67, 0.94, 1.0))
	var hover := _mk_btn(Color(0.10, 0.12, 0.19, 0.98), Color(0.34, 0.77, 1.00, 1.0))
	var pressed := _mk_btn(Color(0.06, 0.08, 0.12, 0.95), Color(0.20, 0.60, 0.90, 1.0))
	var disabled := _mk_btn(Color(0.08, 0.10, 0.16, 0.95), Color(0.24, 0.67, 0.94, 1.0)) # never white

	# Cover ALL states so nothing falls back to default theme
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)
