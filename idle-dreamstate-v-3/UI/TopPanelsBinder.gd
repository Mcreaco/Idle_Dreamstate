extends Node

@export var thoughts_label_path: NodePath
@export var control_label_path: NodePath
@export var instability_label_path: NodePath
@export var depth_percent_label_path: NodePath   # optional (if you show depth % in top panel)

var _thoughts_label: Label
var _control_label: Label
var _instability_label: Label
var _depth_pct_label: Label

func _ready() -> void:
	_thoughts_label = get_node_or_null(thoughts_label_path) as Label
	_control_label = get_node_or_null(control_label_path) as Label
	_instability_label = get_node_or_null(instability_label_path) as Label
	_depth_pct_label = get_node_or_null(depth_percent_label_path) as Label

	var run := get_node_or_null("/root/DepthRunController")
	if run == null:
		push_error("TopPanelsBinder: Autoload /root/DepthRunController not found.")
		return

	run.top_stats_changed.connect(_on_top_stats_changed)
	run.instability_changed.connect(_on_instability_changed)
	run.depth_progress_changed.connect(_on_depth_progress_changed)

func _on_top_stats_changed(thoughts: float, tps: float, control: float, cps: float) -> void:
	if _thoughts_label != null:
		_thoughts_label.text = "Thoughts %d %+0.1f/s" % [int(thoughts), tps]
	if _control_label != null:
		_control_label.text = "Control %d %+0.1f/s" % [int(control), cps]

func _on_instability_changed(instability: float) -> void:
	if _instability_label != null:
		_instability_label.text = "Instability %d" % int(instability)

func _on_depth_progress_changed(_active_depth: int, progress_0_1: float) -> void:
	if _depth_pct_label != null:
		_depth_pct_label.text = "%d%%" % int(round(progress_0_1 * 100.0))
