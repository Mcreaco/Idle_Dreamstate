extends Node
class_name AbyssButtonBinder

@export var abyss_button_path: NodePath
@export var abyss_panel_path: NodePath

var _gm: GameManager
var _btn: Button
var _panel: AbyssPanel


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_btn = get_node_or_null(abyss_button_path) as Button
	_panel = get_node_or_null(abyss_panel_path) as AbyssPanel

	if _btn == null:
		return

	_btn.visible = (_gm != null and _gm.abyss_unlocked_flag)

	if _gm != null and not _gm.abyss_unlocked.is_connected(Callable(self, "_on_abyss_unlocked")):
		_gm.abyss_unlocked.connect(Callable(self, "_on_abyss_unlocked"))

	if not _btn.pressed.is_connected(Callable(self, "_on_pressed")):
		_btn.pressed.connect(Callable(self, "_on_pressed"))


func _on_abyss_unlocked() -> void:
	if _btn != null:
		_btn.visible = true


func _on_pressed() -> void:
	if _panel != null:
		_panel.open()
