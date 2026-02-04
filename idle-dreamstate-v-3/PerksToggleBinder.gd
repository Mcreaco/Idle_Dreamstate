extends Node
class_name PerksToggleBinder

@export var perks_panel_name: String = "PerksPanel"
@export var perks_button_name: String = "PerksButton"
@export var debug_print: bool = false

var _panel: PerksPanel
var _btn: Button

func _ready() -> void:
	_panel = get_tree().current_scene.find_child(perks_panel_name, true, false) as PerksPanel
	_btn = get_tree().current_scene.find_child(perks_button_name, true, false) as Button

	if debug_print:
		print("PerksToggleBinder ready | panel=", _panel, " btn=", _btn)

	if _btn != null:
		if not _btn.pressed.is_connected(Callable(self, "_on_pressed")):
			_btn.pressed.connect(Callable(self, "_on_pressed"))

func _on_pressed() -> void:
	if _panel == null:
		return
	_panel.toggle()
