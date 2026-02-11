extends Control
class_name TopPanelsHUD

@export var thoughts_label_path: NodePath
@export var control_label_path: NodePath
@export var instability_label_path: NodePath

var _thoughts_label: Label
var _control_label: Label
var _instability_label: Label

func _ready() -> void:
	_thoughts_label = get_node_or_null(thoughts_label_path) as Label
	_control_label = get_node_or_null(control_label_path) as Label
	_instability_label = get_node_or_null(instability_label_path) as Label
	var run := get_node_or_null("/root/DepthRunController")
	if run: 
		run.call("bind_hud", self)

func set_values(thoughts: float, thoughts_per_s: float, control: float, control_per_s: float, instability: float) -> void:
	if _thoughts_label:
		_thoughts_label.text = "Thoughts %d %+d/s" % [int(round(thoughts)), int(round(thoughts_per_s))]
	if _control_label:
		_control_label.text = "Control %d %+d/s" % [int(round(control)), int(round(control_per_s))]
	if _instability_label:
		_instability_label.text = "Instability %d%%" % int(round(instability * 100.0))
