extends PanelContainer
class_name TopBarPanel

const COLOR_TEXT: Color = Color(0.87, 0.91, 1.0)
const COLOR_BAR_BLUE: Color = Color(0.24, 0.67, 0.94)
const COLOR_BAR_AMBER: Color = Color(0.95, 0.65, 0.15)
const COLOR_BAR_RED: Color = Color(0.85, 0.18, 0.18)

@export var depth_label_path: NodePath

@onready var depth_label: Label = _resolve_depth_label()

@onready var thoughts_value: Label = $TopBar/MarginContainer/ThoughtsBox/ThoughtsValue
@onready var thoughts_gain: Label = $TopBar/MarginContainer/ThoughtsBox/ThoughtsGain

@onready var control_value: Label = $TopBar/ControlPad/ControlBox/ControlValue
@onready var control_gain: Label = $TopBar/ControlPad/ControlBox/ControlGain

@onready var inst_title: Label = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityTitle
@onready var inst_bar: ProgressBar = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityBar
@onready var inst_hint: Label = $TopBar/InstabilityCenter/InstabilityVBox/InstabilityHint

var _run: Node = null

func _ready() -> void:
	_style_top_bar_panel()
	_set_label_colors()
	if inst_hint:
		inst_hint.visible = false # hide inline; tooltip only

	if inst_bar:
		inst_bar.tooltip_text = "Instability rises from idle gain and events. Reaching 100 ends the run."

	_style_inst_bar()

	if inst_title:
		inst_title.tooltip_text = "Time to fail (TTF) is estimated from current idle instability gain."

	set_process(true)

func _process(_delta: float) -> void:
	if _run == null:
		_run = get_node_or_null("/root/DepthRunController")
		if _run == null:
			return

	# EXPLICIT CASTS to float to prevent type errors
	var thoughts: float = float(_run.get("thoughts"))
	var control: float = float(_run.get("control"))

	var thoughts_ps: float = 0.0
	if _run.has_method("get_thoughts_per_sec"):
		thoughts_ps = float(_run.call("get_thoughts_per_sec"))

	var control_ps: float = 0.0
	if _run.has_method("get_control_per_sec"):
		control_ps = float(_run.call("get_control_per_sec"))

	var inst_raw: float = float(_run.get("instability"))
	var inst_pct: float = inst_raw
	if inst_pct <= 1.0:
		inst_pct = inst_raw * 100.0

	var active_depth: int = int(_run.get("active_depth"))
	var max_depth: int = 0
	if _run.get("max_unlocked_depth") != null:
		max_depth = int(_run.get("max_unlocked_depth"))

	set_depth_ui(active_depth, max_depth)

	var inst_gain: float = 0.0
	if _run.has_method("get_instability_per_sec"):
		inst_gain = float(_run.call("get_instability_per_sec"))
	elif _run.get("instability_per_sec") != null:
		inst_gain = float(_run.get("instability_per_sec"))

	var ttf: float = 999999.0
	if inst_gain > 0.000001:
		ttf = (100.0 - inst_pct) / inst_gain

	var is_overclock: bool = false
	var overclock_time_left: float = 0.0

	update_top_bar(
		thoughts,
		thoughts_ps,
		control,
		control_ps,
		inst_pct,
		is_overclock,
		overclock_time_left,
		ttf,
		inst_gain
	)

func _resolve_depth_label() -> Label:
	if depth_label_path != NodePath(""):
		var n := get_node_or_null(depth_label_path)
		if n and n is Label:
			return n as Label
	return find_child("DepthLabel", true, false) as Label

func _set_label_colors() -> void:
	var labels: Array[Label] = [
		thoughts_value, thoughts_gain,
		control_value, control_gain,
		inst_hint, inst_title,
		depth_label
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

func set_depth_ui(current_depth: int, _max_depth: int) -> void:
	if depth_label:
		depth_label.text = "Depth: %d" % current_depth

func update_top_bar(
	thoughts: float,
	thoughts_ps: float,
	control: float,
	control_ps: float,
	inst_pct: float,
	is_overclock: bool,
	overclock_time_left: float,
	ttf: float,
	inst_gain: float
) -> void:
	if thoughts_value:
		thoughts_value.text = "%s" % _fmt_num(thoughts)
	if thoughts_gain:
		thoughts_gain.text = "+%s/s" % _fmt_num(thoughts_ps)  # Fixed: was %.1f

	if control_value:
		control_value.text = "%s" % _fmt_num(control)
	if control_gain:
		control_gain.text = "+%s/s" % _fmt_num(control_ps)  # Fixed: was %.1f

	if inst_bar:
		inst_bar.value = inst_pct

	if inst_title:
		inst_title.text = "Instability (TTF %s)" % _fmt_time_ui(ttf)
		inst_title.tooltip_text = "Instab +%.3f/s%s" % [
			inst_gain,
			(" | OC %.1fs" % overclock_time_left) if is_overclock else ""
		]

	if inst_hint:
		inst_hint.visible = false

func _fmt_num(v: float) -> String:
	# Handle infinity and NaN safely
	if v == INF or v == -INF:
		return "∞"
	if v != v:  # NaN check: NaN != NaN
		return "NaN"
	
	# Ensure clean float
	v = float(v)
	
	# Manual scientific notation for large numbers (avoids %e issues)
	if v >= 1e15:
		var exponent := int(floor(log(v) / log(10)))
		var mantissa := snappedf(v / pow(10, exponent), 0.01)
		return str(mantissa) + "e+" + str(exponent)
	
	# Standard abbreviations
	if v >= 1e12:
		return "%.2fT" % (v / 1e12)
	if v >= 1e9:
		return "%.2fB" % (v / 1e9)
	if v >= 1e6:
		return "%.2fM" % (v / 1e6)
	if v >= 1e3:
		return "%.2fK" % (v / 1e3)
	
	return str(int(v))

func _fmt_time_ui(sec: float) -> String:
	if sec >= 999900.0:
		return "--:--"
	sec = maxf(sec, 0.0)
	var m: int = int(floor(sec / 60.0))
	var s: int = int(fmod(sec, 60.0))
	return "%d:%02d" % [m, s]

func _style_top_bar_panel() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.06, 0.10, 0.95)
	sb.border_color = COLOR_BAR_BLUE
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 8

	add_theme_stylebox_override("panel", sb)
