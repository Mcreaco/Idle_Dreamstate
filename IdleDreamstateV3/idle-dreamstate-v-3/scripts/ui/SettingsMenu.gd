extends Control

@export var back_scene_path: String = "res://MainMenu.tscn"

var title_label: Label
var mute_toggle: CheckButton
var volume_label: Label
var volume_slider: HSlider
var back_button: Button

func _ready() -> void:
	# Find by node name anywhere in this scene (prevents path mismatch issues)
	title_label = _find_named("TitleLabel") as Label
	mute_toggle = _find_named("MuteToggle") as CheckButton
	volume_label = _find_named("VolumeLabel") as Label
	volume_slider = _find_named("VolumeSlider") as HSlider
	back_button = _find_named("BackButton") as Button

	if title_label == null or mute_toggle == null or volume_label == null or volume_slider == null or back_button == null:
		push_error("SettingsMenu missing required nodes. Need: TitleLabel, MuteToggle, VolumeLabel, VolumeSlider, BackButton")
		return

	title_label.text = "Settings"
	mute_toggle.text = "Mute"
	back_button.text = "Back"

	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01

	_load_settings_into_ui()

	mute_toggle.toggled.connect(_on_mute_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)
	back_button.pressed.connect(_on_back_pressed)

	_update_volume_text(float(volume_slider.value))

func _find_named(name_to_find: String) -> Node:
	return _find_named_recursive(self, name_to_find)

func _find_named_recursive(root: Node, name_to_find: String) -> Node:
	if root.name == name_to_find:
		return root
	for c in root.get_children():
		var found := _find_named_recursive(c, name_to_find)
		if found != null:
			return found
	return null

func _load_settings_into_ui() -> void:
	var data: Dictionary = SaveSystem.load_game()

	var mute: bool = bool(data.get("mute", false))
	var vol: float = float(data.get("master_volume", 1.0))

	mute_toggle.button_pressed = mute
	volume_slider.value = vol

	_apply_to_sound_system(mute, vol)

func _save_settings(mute: bool, vol: float) -> void:
	var data: Dictionary = SaveSystem.load_game()
	data["mute"] = mute
	data["master_volume"] = vol
	SaveSystem.save_game(data)

func _apply_to_sound_system(mute: bool, vol: float) -> void:
	# SoundSystem exists only in Main scene; guard it
	var ss: Node = get_tree().root.get_node_or_null("Main/SoundSystem")
	if ss != null:
		ss.set_enabled(not mute)
		ss.set_master_volume(vol)

func _on_mute_toggled(on: bool) -> void:
	var vol: float = float(volume_slider.value)
	_apply_to_sound_system(on, vol)
	_save_settings(on, vol)

func _on_volume_changed(v: float) -> void:
	var mute: bool = mute_toggle.button_pressed
	var vol: float = float(v)
	_update_volume_text(vol)
	_apply_to_sound_system(mute, vol)
	_save_settings(mute, vol)

func _update_volume_text(vol: float) -> void:
	volume_label.text = "Volume: " + str(roundi(vol * 100.0)) + "%"

func _on_back_pressed() -> void:
	SceneManager.goto_path(back_scene_path)
