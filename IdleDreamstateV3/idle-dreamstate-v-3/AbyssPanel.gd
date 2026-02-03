extends PanelContainer
class_name AbyssPanel

@export var close_button_path: NodePath

var _gm: GameManager
var _close_btn: Button
var _info: Label


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_close_btn = get_node_or_null(close_button_path) as Button
	_info = find_child("PerkInfoLabel", true, false) as Label

	visible = false

	if _close_btn != null and not _close_btn.pressed.is_connected(Callable(self, "_on_close")):
		_close_btn.pressed.connect(Callable(self, "_on_close"))

	set_process(true)
	_refresh()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func open() -> void:
	visible = true
	_refresh()


func _on_close() -> void:
	visible = false


func _refresh() -> void:
	if _gm == null or _info == null:
		return

	if _gm.abyss_unlocked_flag:
		_info.text = "Memories: %d" % int(round(_gm.memories))
	else:
		_info.text = "..."
