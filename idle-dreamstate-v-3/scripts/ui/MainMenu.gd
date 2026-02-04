extends Control

@export var game_scene_path: String = "res://Main.tscn"
@export var settings_scene_path: String = "res://SettingsMenu.tscn"

var title: Label
var continue_button: Button
var new_button: Button
var settings_button: Button
var quit_button: Button

func _ready() -> void:
	# Find nodes by name anywhere in this scene (so UI layout can change)
	title = _find("Title") as Label
	if title == null:
		# If you renamed it to TitleLabel, support that too
		title = _find("TitleLabel") as Label

	continue_button = _find("ContinueButton") as Button
	new_button = _find("NewGameButton") as Button
	settings_button = _find("SettingsButton") as Button
	quit_button = _find("QuitButton") as Button

	if title == null or continue_button == null or new_button == null or settings_button == null or quit_button == null:
		push_error("MainMenu missing required nodes. Need: Title(or TitleLabel), ContinueButton, NewGameButton, SettingsButton, QuitButton")
		return

	title.text = "Idle Game"
	continue_button.text = "Continue"
	new_button.text = "New Game"
	settings_button.text = "Settings"
	quit_button.text = "Quit"

	continue_button.pressed.connect(_on_continue_pressed)
	new_button.pressed.connect(_on_new_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

	_refresh_buttons()

func _refresh_buttons() -> void:
	var has: bool = SaveSystem.has_save()
	continue_button.disabled = not has

func _on_continue_pressed() -> void:
	SceneManager.goto_path(game_scene_path)

func _on_new_pressed() -> void:
	SaveSystem.delete_save()
	SceneManager.goto_path(game_scene_path)

func _on_settings_pressed() -> void:
	SceneManager.goto_path(settings_scene_path)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _find(node_name: String) -> Node:
	# Godot 4: find_child(name, recursive, owned)
	return find_child(node_name, true, false)
