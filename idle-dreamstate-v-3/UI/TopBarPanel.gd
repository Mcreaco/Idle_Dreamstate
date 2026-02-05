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
	if inst_bar:
		inst_bar.tooltip_text = "Instability rises from idle gain and events. Reaching 100 ends the run."
	if inst_title:
		inst_title.tooltip_text = "Time to fail (TTF) is estimated from current idle instability gain; overclock increases gain."
	_style_inst_bar()
	
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

func _style_inst_bar() -> void:
	if inst_bar == null:
		return
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	bg.border_color = Color(1, 1, 1, 0.12)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.corner_radius_top_left = 8
	bg.corner_radius_top_right = 8
	bg.corner_radius_bottom_left = 8
	bg.corner_radius_bottom_right = 8
	bg.shadow_color = Color(0, 0, 0, 0.25)
	bg.shadow_size = 2

	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.9, 0.2, 0.2, 1.0)
	fg.border_color = Color(1, 1, 1, 0.18)
	fg.border_width_left = 1
	fg.border_width_top = 1
	fg.border_width_right = 1
	fg.border_width_bottom = 1
	fg.corner_radius_top_left = 8
	fg.corner_radius_top_right = 8
	fg.corner_radius_bottom_left = 8
	fg.corner_radius_bottom_right = 8
	fg.shadow_color = Color(0, 0, 0, 0.2)
	fg.shadow_size = 1

	inst_bar.add_theme_stylebox_override("bg", bg)
	inst_bar.add_theme_stylebox_override("fg", fg)
	
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
		overclock_time_left: float,
		time_to_fail_sec: float,
		instability_gain_per_sec: float
	) -> void:
	if thoughts_value == null:
		return

	thoughts_value.text = _fmt_num(thoughts)
	thoughts_gain.text = "+%s/s" % _fmt_num(thoughts_ps)

	control_value.text = _fmt_num(control)
	control_gain.text = "+%s/s" % _fmt_num(control_ps)

	var pct: float = clampf(instability_pct, 0.0, 100.0)
	inst_bar.value = pct

	# Smooth ramp from amber to red between 60..100
	var c: Color
	if pct < 60.0:
		c = COLOR_BAR_BLUE
	elif pct >= 100.0:
		c = COLOR_BAR_RED
	else:
		var t: float = clampf((pct - 60.0) / 40.0, 0.0, 1.0)
		c = COLOR_BAR_AMBER.lerp(COLOR_BAR_RED, t)
	inst_bar.add_theme_color_override("fill_color", c)

	# Color-blind friendly cue: lighten bar when high instability
	var high_risk: bool = pct >= 80.0
	var base_mod: Color = Color(1, 0.9, 0.9) if (high_risk and not overclock_active) else Color(1, 1, 1)

	var ttf_disp: float = min(time_to_fail_sec, 999999.0)
	var gain_disp: float = maxf(instability_gain_per_sec, 0.0)
	if inst_bar:
		inst_bar.tooltip_text = "Instability gain: %.4f/s\nTTF: %s" % [gain_disp, _fmt_time(ttf_disp)]
	if inst_title:
		inst_title.tooltip_text = inst_bar.tooltip_text

	if overclock_active:
		var ending: bool = overclock_time_left < 1.5
		var bar_mod: Color = Color(1, 0.45, 0.45) if ending else Color(1, 0.6, 0.6)
		inst_bar.modulate = bar_mod
		if ending:
			inst_title.text = "Instability (%s • ending… %.1fs)" % [_fmt_time(ttf_disp), overclock_time_left]
		else:
			inst_title.text = "Instability (%s • OC %.1fs)" % [_fmt_time(ttf_disp), overclock_time_left]
	else:
		inst_bar.modulate = base_mod
		inst_title.text = "Instability (%s)" % _fmt_time(ttf_disp)
