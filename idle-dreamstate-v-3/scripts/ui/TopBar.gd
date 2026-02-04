class_name TopBar
extends Control

@onready var thoughts_label: Label = $MainVBox/StatsRow/ThoughtsLabel
@onready var control_label: Label = $MainVBox/StatsRow/ControlLabel
@onready var memories_label: Label = $MainVBox/StatsRow/MemoriesLabel
@onready var run_time_label: Label = $MainVBox/StatsRow/RunTimeLabel
@onready var best_run_label: Label = $MainVBox/StatsRow/BestRunLabel

@onready var risk_bar: ProgressBar = $MainVBox/RiskRow/RiskBar
@onready var alert_label: Label = $MainVBox/RiskRow/AlertLabel
@onready var nightmare_label: Label = $MainVBox/RiskRow/NightmareLabel
@onready var hint_label: Label = $MainVBox/HintLabel

var flash_timer: float = 0.0
var flashing: bool = false
var flash_speed: float = 0.0
var base_color: Color = Color.WHITE

func _ready() -> void:
	alert_label.text = ""
	nightmare_label.text = ""
	hint_label.text = ""
	alert_label.visible = false
	nightmare_label.visible = false
	hint_label.visible = false
	base_color = risk_bar.modulate

func _process(delta: float) -> void:
	if flashing:
		flash_timer += delta * flash_speed
		var pulse := (sin(flash_timer * TAU) + 1.0) * 0.5
		risk_bar.modulate = base_color.lerp(Color.WHITE, pulse)

func update_display(
	thoughts: float,
	control: float,
	instability: float,
	state: String,
	memories: float,
	corruption_active: bool,
	nightmare_unlocked: bool,
	run_time: float,
	best_run_time: float,
	best_thoughts: float,
	best_memories_gain: float
) -> void:
	thoughts_label.text = "Thoughts: " + str(roundi(thoughts))
	control_label.text = "Control: " + str(roundi(control))
	memories_label.text = "Memories: " + str(roundi(memories))
	run_time_label.text = "Run: " + _fmt_time(run_time)
	best_run_label.text = "Best: " + _fmt_time(best_run_time) \
		+ " | Max T: " + str(roundi(best_thoughts)) \
		+ " | Best +M: " + str(roundi(best_memories_gain))

	risk_bar.max_value = 100.0
	risk_bar.value = instability
	risk_bar.tooltip_text = state

	match state:
		"Stable":
			base_color = Color(0.2, 0.9, 0.3)
			flashing = false
		"Deep":
			base_color = Color(1.0, 0.8, 0.2)
			flashing = false
		_:
			base_color = Color(1.0, 0.2, 0.2)
			flashing = true
			flash_speed = 1.5

	if corruption_active:
		alert_label.visible = true
		alert_label.text = "☣ CORRUPTION"
		flashing = true
		flash_speed = 3.0
	else:
		alert_label.visible = false
		alert_label.text = ""

	nightmare_label.visible = nightmare_unlocked
	if nightmare_unlocked:
		nightmare_label.text = "😈 NIGHTMARE"

	if instability >= 85.0 and instability < 100.0:
		hint_label.visible = true
		hint_label.text = "⚠ WAKE SOON"
	else:
		hint_label.visible = false
		hint_label.text = ""

	risk_bar.modulate = base_color

func _fmt_time(seconds: float) -> String:
	var s: int = int(floor(seconds))
	var m: int = int(floor(s / 60.0))
	var r: int = s - (m * 60)
	return str(m) + ":" + str(r).pad_zeros(2)
