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
@onready var thoughts_box: Control = $TopBar/MarginContainer/ThoughtsBox

# We'll create these dynamically or you can add them in editor
var piggy_container: HBoxContainer
var piggy_value: Label
var piggy_button: Button
var gems_label: Label
var _run: Node = null

func _create_gems_display() -> void:
	gems_label = Label.new()
	gems_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))  # Blue/cyan for premium
	add_child(gems_label)
	
func _create_piggy_bank_ui() -> void:
	# Prevent double-creation
	if piggy_container != null:
		return
	
	# Create container
	piggy_container = HBoxContainer.new()
	piggy_container.name = "PiggyBankContainer"
	piggy_container.mouse_filter = Control.MOUSE_FILTER_PASS  # Let clicks through to children
	# Icon
	var icon := Label.new()
	icon.text = "🐷 "
	icon.add_theme_font_size_override("font_size", 16)
	piggy_container.add_child(icon)
	
	# Value label
	piggy_value = Label.new()
	piggy_value.name = "PiggyValue"
	piggy_value.text = "0 → 0 Gems"
	piggy_value.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	piggy_container.add_child(piggy_value)
	
	# Break button - IMPORTANT: Connect before adding to tree
	piggy_button = Button.new()
	piggy_button.name = "PiggyButton"
	piggy_button.text = "Break $4.99"
	piggy_button.custom_minimum_size = Vector2(80, 30)
	piggy_button.mouse_filter = Control.MOUSE_FILTER_STOP  # Block clicks from passing through
	piggy_button.z_index = 10  # Bring to front
	piggy_button.focus_mode = Control.FOCUS_ALL
	piggy_button.pressed.connect(_on_piggy_break)
	
	piggy_container.add_child(piggy_button)
	
	# Gems label
	gems_label = Label.new()
	gems_label.name = "GemsLabel"
	gems_label.text = "💎 0"
	gems_label.add_theme_color_override("font_color", Color(0.2, 0.8, 1.0))
	piggy_container.add_child(gems_label)
	
	# Add to TopBar
	var top_bar := $TopBar
	top_bar.add_child(piggy_container)
	top_bar.move_child(piggy_container, 1)
	
	piggy_container.visible = true
	print("Piggy Bank UI created successfully!")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if piggy_button != null and piggy_button.get_global_rect().has_point(event.position):
			if not piggy_button.disabled:
				print("Button clicked via _input!")
				_on_piggy_break()
				
func _on_piggy_break() -> void:
	print("!!! PIGGY BREAK BUTTON CLICKED !!!")
	
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null:
		print("ERROR: GameManager not found")
		return
	
	if not gm.has_method("break_piggy_bank"):
		print("ERROR: GameManager missing break_piggy_bank method")
		return
	
	var result: Dictionary = gm.break_piggy_bank()
	print("Break result: ", result)
	
	if result.success:
		print("SUCCESS! Gained ", result.amount, " ", result.get("currency", "gems"))
	else:
		print("Failed to break piggy bank")
	
	_update_piggy_display()
			
func _ready() -> void:
	_style_top_bar_panel()
	_set_label_colors()
	_create_piggy_bank_ui()
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

	# Read values from DRC (GameManager pushes them here)
	var thoughts: float = float(_run.get("thoughts"))
	var control: float = float(_run.get("control"))
	var thoughts_ps: float = float(_run.get("thoughts_per_sec"))
	var control_ps: float = 0.0
	if _run.has_method("get_control_per_sec"):
		control_ps = float(_run.call("get_control_per_sec"))

	var active_depth: int = int(_run.get("active_depth"))
	var max_depth: int = 0
	if _run.get("max_unlocked_depth") != null:
		max_depth = int(_run.get("max_unlocked_depth"))

	set_depth_ui(active_depth, max_depth)

	# Get instability RATE from DRC (GameManager updates this)
	var inst_gain: float = 0.0
	if _run != null:
		inst_gain = float(_run.get("instability_per_sec"))
	if _run.has_method("get_instability_per_sec"):
		inst_gain = float(_run.call("get_instability_per_sec"))
	elif _run.get("instability_per_sec") != null:
		inst_gain = float(_run.get("instability_per_sec"))

	var is_overclock: bool = false
	var overclock_time_left: float = 0.0

	# Pass 0 for inst_pct and ttf since we don't use them anymore
	# (GameManager sets the bar value directly in _refresh_top_ui)
	update_top_bar(
		thoughts,
		thoughts_ps,
		control,
		control_ps,
		0.0,  # inst_pct - not used
		is_overclock,
		overclock_time_left,
		0.0,  # ttf - not used
		inst_gain
	)
	
	# Update piggy bank every 60 frames (~1 second)
	if Engine.get_process_frames() % 60 == 0:
		_update_piggy_display()
	
	# Update gems display
	var gm := get_node_or_null("/root/Main/GameManager")
	if gems_label and gm:
		var gems_count: int = gm.gems if "gems" in gm else 0
		gems_label.text = "💎 %d" % gems_count
	
	if Engine.get_process_frames() % 60 == 0:
		if piggy_button != null:
			print("Button exists. Disabled: ", piggy_button.disabled, " Visible: ", piggy_button.visible)

func _update_piggy_display() -> void:
	if piggy_value == null or piggy_button == null:
		return
	
	# Try multiple paths
	var gm := get_node_or_null("/root/GameManager")
	if gm == null:
		gm = get_node_or_null("/root/Main/GameManager")
	if gm == null:
		# Walk up tree
		var parent := get_parent()
		while parent != null:
			var candidate := parent.get_node_or_null("GameManager")
			if candidate != null:
				gm = candidate
				break
			parent = parent.get_parent()
	
	if gm == null:
		piggy_value.text = "GM NOT FOUND"
		return
		
	if not ("piggy_bank" in gm):
		piggy_value.text = "NO PIGGY VAR"
		return
	
	# If we get here, it's working
	var amount: float = float(gm.piggy_bank)
	var usd: float = amount * 0.01
	piggy_value.text = "%d ($%.2f)" % [int(amount), usd]
	
	# ALWAYS VISIBLE (for testing)
	if piggy_container:
		piggy_container.visible = true
	
	# Update button
	var can_break: bool = false
	if gm.has_method("can_break_piggy_bank"):
		can_break = gm.can_break_piggy_bank()
	else:
		can_break = amount >= 100.0
	
	piggy_button.disabled = not can_break
	if can_break:
		piggy_button.text = "Break $4.99"
		piggy_button.modulate = Color(1, 1, 1)
	else:
		piggy_button.text = "Save..."
		piggy_button.modulate = Color(0.5, 0.5, 0.5)
		
	# Show gems instead of $
	var gem_value := int(amount / 10.0)  # 10 thoughts = 1 gem
	piggy_value.text = "%d → %d Gems" % [int(amount), gem_value]
	var gems_count: int = gm.gems if "gems" in gm else 0
	var gems_lbl := piggy_container.get_node_or_null("GemsLabel")
	if gems_lbl:
		gems_lbl.text = "💎 %d" % gems_count
		
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
	_inst_pct: float,
	_is_overclock: bool,
	_overclock_time_left: float,
	_ttf: float,
	inst_gain: float
) -> void:
	if thoughts_value:
		thoughts_value.text = "%s" % _fmt_num(thoughts)
	if thoughts_gain:
		thoughts_gain.text = "+%s/s" % _fmt_num(thoughts_ps)

	if control_value:
		control_value.text = "%s" % _fmt_num(control)
	if control_gain:
		control_gain.text = "+%s/s" % _fmt_num(control_ps)

	# REMOVE THIS - GameManager._refresh_top_ui() handles the bar value now
	# if inst_bar:
	#     inst_bar.value = inst_pct

	if inst_title:
		inst_title.text = "Instability (+%s/s)" % _fmt_num(inst_gain)
		inst_title.tooltip_text = "+%.2f instability per second" % inst_gain

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
