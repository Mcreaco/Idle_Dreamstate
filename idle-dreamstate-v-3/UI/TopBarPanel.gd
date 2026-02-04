extends PanelContainer

const COLOR_TEXT: Color = Color(0.87, 0.91, 1.0)
const COLOR_BAR_BLUE: Color = Color(0.24, 0.67, 0.94)
const COLOR_BAR_AMBER: Color = Color(0.95, 0.65, 0.15)
const COLOR_BAR_RED: Color = Color(0.85, 0.18, 0.18)

@onready var thoughts_value: Label = $TopBar/MarginContainer/ThoughtsBox/ThoughtsValue
@onready var thoughts_gain: Label = $TopBar/MarginContainer/ThoughtsBox/ThoughtsGain
@onready var control_value: Label = $TopBar/ControlPad/ControlBox/ControlValue
@onready var control_gain: Label = $TopBar/ControlPad/ControlBox/ControlGain
@onready var inst_title: Label = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityTitle
@onready var inst_bar: ProgressBar = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityBar
@onready var inst_hint: Label = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityHint

func _ready() -> void:
	_validate_nodes()
	_set_label_colors()
	if inst_hint:
		inst_hint.visible = false

func _validate_nodes() -> void:
	var nodes_ok := true
	var paths := {
		"thoughts_value": thoughts_value,
		"thoughts_gain": thoughts_gain,
		"control_value": control_value,
		"control_gain": control_gain,
		"inst_title": inst_title,
		"inst_bar": inst_bar,
		"inst_hint": inst_hint
	}
	for k in paths.keys():
		if paths[k] == null:
			nodes_ok = false
			push_error("TopBarPanel.gd: Missing node at path for %s" % k)
	if not nodes_ok:
		set_process(false)

func _set_label_colors() -> void:
	var labels: Array[Label] = [
		thoughts_value, thoughts_gain,
		control_value, control_gain,
		inst_hint, inst_title
	]
	for l in labels:
		if l and not l.has_theme_color_override("font_color"):
			l.add_theme_color_override("font_color", COLOR_TEXT)

func _fmt_num(n: float) -> String:
	if n >= 1_000_000.0:
		return "%.2fM" % (n / 1_000_000.0)
	elif n >= 1_000.0:
		return "%.2fK" % (n / 1_000.0)
	elif n >= 10.0:
		return "%.0f" % n
	return "%.1f" % n

func _fmt_time(sec: float) -> String:
	if sec >= 999900.0:
		return "--:--"
	sec = maxf(sec, 0.0)
	var m: float = floor(sec / 60.0)
	var s: float = fmod(sec, 60.0)
	return "%d:%02d" % [int(m), int(s)]

func update_top_bar(
		thoughts: float,
		thoughts_ps: float,
		control: float,
		control_ps: float,
		instability_pct: float,
		overclock_active: bool,
		_overclock_time_left: float,
		time_to_fail_sec: float
	) -> void:
	if thoughts_value == null:
		return

	thoughts_value.text = _fmt_num(thoughts)
	thoughts_gain.text = "+%s/s" % _fmt_num(thoughts_ps)

	control_value.text = _fmt_num(control)
	control_gain.text = "+%s/s" % _fmt_num(control_ps)

	var pct: float = clampf(instability_pct, 0.0, 100.0)
	inst_bar.value = pct

	var c: Color = COLOR_BAR_BLUE
	if pct >= 80.0:
		c = COLOR_BAR_RED
	elif pct >= 60.0:
		c = COLOR_BAR_AMBER
	inst_bar.add_theme_color_override("fill_color", c)

	inst_title.text = "Instability (%s)" % _fmt_time(time_to_fail_sec)

	if overclock_active:
		inst_bar.modulate = Color(1, 0.6, 0.6)
	else:
		inst_bar.modulate = Color(1, 1, 1)
