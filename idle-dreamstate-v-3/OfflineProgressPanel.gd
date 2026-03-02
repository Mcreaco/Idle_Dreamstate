extends "res://UI/StylePopupPanel.gd"

@onready var title_label: Label = $VBox/TitleLabel
@onready var time_label: Label = $VBox/TimeLabel  
@onready var thoughts_label: Label = $VBox/ThoughtsLabel
@onready var control_label: Label = $VBox/ControlLabel
@onready var memories_label: Label = $VBox/MemoriesLabel
@onready var close_button: Button = $VBox/CloseButton

func setup(seconds: float, results: Dictionary):
	var hours = int(seconds / 3600)
	var mins = int(fmod(seconds, 3600.0) / 60.0)
	
	title_label.text = "Welcome Back!"
	time_label.text = "Away for %dh %dm" % [hours, mins] if hours > 0 else "Away for %dm" % mins
	thoughts_label.text = "Thoughts: +%s" % _fmt(results.thoughts)
	control_label.text = "Control: +%s" % _fmt(results.control)
	memories_label.text = "Memories: +%s" % _fmt(results.memories)
	
	close_button.pressed.connect(queue_free)
	await get_tree().create_timer(10.0).timeout
	if is_instance_valid(self): queue_free()

func _fmt(v: float) -> String:
	if v >= 1_000_000: return "%.2fM" % (v / 1_000_000)
	if v >= 1_000: return "%.2fk" % (v / 1_000)
	return str(int(v))
