extends Node
class_name MemoriesLabelBinder

@export var refresh_interval: float = 0.2
@export var debug_print: bool = false

var _gm: GameManager
var _label: Label
var _t: float = 0.0


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_label = get_tree().current_scene.find_child("MemoriesLabel", true, false) as Label

	if debug_print:
		print("MemoriesLabelBinder ready | gm=", _gm, " label=", _label)

	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _gm == null or _label == null:
		return
	_label.text = "Memories: " + str(int(round(_gm.memories)))
