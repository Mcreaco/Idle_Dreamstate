extends Node
class_name AbyssBarBinder

@export var refresh_interval: float = 0.2
@export var abyss_target_depth: int = 15

# Drag/drop in Inspector
@export var abyss_bar_path: NodePath
@export var reveal_label_path: NodePath # optional label, can be blank

# Keep mystery: no text while filling
@export var reveal_only_at_target: bool = true
@export var reveal_text: String = "Something stirs..."

var _gm: GameManager
var _bar: ProgressBar
var _label: Label
var _t: float = 0.0
var _revealed: bool = false


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_bar = get_node_or_null(abyss_bar_path) as ProgressBar
	_label = get_node_or_null(reveal_label_path) as Label

	if _bar != null:
		_bar.min_value = 0.0
		_bar.max_value = float(maxi(abyss_target_depth, 1))
		_bar.value = 0.0
		_bar.show_percentage = false # just in case

	if _label != null and reveal_only_at_target:
		_label.text = ""
		_label.visible = false

	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _gm == null or _bar == null:
		return

	var target: int = maxi(abyss_target_depth, 1)
	var d: int = clampi(_gm.depth, 0, target)

	_bar.max_value = float(target)
	_bar.value = float(d)

	# Mystery: only reveal when it hits target (optional)
	if _label != null and reveal_only_at_target:
		if (not _revealed) and d >= target:
			_revealed = true
			_label.text = reveal_text
			_label.visible = true
