extends CanvasLayer

@export var main_menu_scene_path: String = "res://MainMenu.tscn"

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

	# --- FORCE TEXT ---
	title_label.text = "PAUSED"
	resume_button.text = "Resume"
	menu_button.text = "Menu"
	quit_button.text = "Quit"
	reset_button.text = "Reset"

	# --- FORCE VISIBILITY ---
	title_label.visible = true
	resume_button.visible = true
	menu_button.visible = true
	quit_button.visible = true
	reset_button.visible = true

	# --- FORCE READABLE COLORS (theme overrides) ---
	_force_label_visible(title_label)
	_force_button_text_visible(resume_button)
	_force_button_text_visible(menu_button)
	_force_button_text_visible(quit_button)
	_force_button_text_visible(reset_button)

	resume_button.pressed.connect(_on_resume)
	menu_button.pressed.connect(_on_menu)
	quit_button.pressed.connect(_on_quit)
	reset_button.pressed.connect(_on_reset)

	_set_open(false)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_set_open(not _open)


func _set_open(v: bool) -> void:
	_open = v

	center.visible = v
	panel.visible = v

	get_tree().paused = v
	if v:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _force_label_visible(l: Label) -> void:
	l.modulate = Color(1, 1, 1, 1)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 1))


func _force_button_text_visible(b: Button) -> void:
	b.modulate = Color(1, 1, 1, 1)
	# Make sure text is visible even if theme disabled colors are weird
	b.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 1))
	b.disabled = false


func _on_resume() -> void:
	_set_open(false)


func _on_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(main_menu_scene_path)


func _on_reset() -> void:
	get_tree().paused = false
	if Engine.has_singleton("SaveSystem"):
		SaveSystem.delete_save()
	get_tree().reload_current_scene()


func _on_quit() -> void:
	get_tree().quit()
