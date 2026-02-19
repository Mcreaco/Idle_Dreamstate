extends PanelContainer
class_name SettingsPanel

@export var master_bus_name: String = "Master"

# Panel frame
@export var panel_bg: Color = Color(0.04, 0.07, 0.12, 0.92)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 1.0)
@export var panel_border_width: int = 2
@export var panel_radius: int = 12

# Modal coordination (no overlap)
@export var prestige_panel_node_name: String = "PrestigePanel"
@export var shop_panel_node_name: String = "ShopPanel"

const SAVE_MUTE_KEY := "mute"
const SAVE_VOL_KEY := "master_volume"
const SAVE_TUTORIAL_DISABLED_KEY := "tutorials_disabled"

# Lifetime keys (stored in save)
const LT_THOUGHTS := "lifetime_thoughts"
const LT_CONTROL := "lifetime_control"
const LT_DIVES := "total_dives"
const LT_DEEPEST := "deepest_depth"
const LT_PLAYTIME := "total_playtime"

enum StatsMode { RUN, LIFETIME }
var _stats_mode: int = StatsMode.RUN

# Your tree
@onready var _internal_backdrop: CanvasItem = get_node_or_null("Backdrop") as CanvasItem

@onready var title_label: Label = $"Root/Title"
@onready var mute_toggle: CheckButton = $"Root/Mute"
@onready var volume_label: Label = $"Root/VolumeLabel"
@onready var volume_slider: HSlider = $"Root/Volume"
@onready var close_button: Button = $"Root/CloseButton"
@onready var tutorial_toggle: CheckButton = get_node_or_null("Root/TutorialToggle")

@onready var save_btn: Button = $"Root/Actions/SaveButton"
@onready var load_btn: Button = $"Root/Actions/LoadButton"
@onready var stats_btn: Button = $"Root/Actions/StatsButton"

@onready var stats_box: VBoxContainer = $"Root/StatsBox"
@onready var run_tab: Button = $"Root/StatsBox/StatsTabs/RunTabButton"
@onready var lifetime_tab: Button = $"Root/StatsBox/StatsTabs/LifetimeTabButton"
@onready var stat_lines: VBoxContainer = $"Root/StatsBox/StatLines"

var _gm: Node = null
var _t_stats: float = 0.0

func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false)

	_disable_internal_backdrop()
	_apply_panel_frame()

	# Default text
	if is_instance_valid(title_label): title_label.text = "Settings"
	if is_instance_valid(mute_toggle): mute_toggle.text = "Mute"
	if is_instance_valid(save_btn): save_btn.text = "Save"
	if is_instance_valid(load_btn): load_btn.text = "Load"
	if is_instance_valid(stats_btn): stats_btn.text = "Stats"
	if is_instance_valid(run_tab): run_tab.text = "Run"
	if is_instance_valid(lifetime_tab): lifetime_tab.text = "Lifetime"
	if is_instance_valid(close_button): close_button.text = "Close"
	
	# Setup tutorial toggle
	if is_instance_valid(tutorial_toggle):
		tutorial_toggle.text = "Disable Tutorials"
		_style_basebutton(tutorial_toggle)
		_connect_once(tutorial_toggle.toggled, Callable(self, "_on_tutorial_toggled"))

	# Slider setup
	if is_instance_valid(volume_slider):
		volume_slider.min_value = 0.0
		volume_slider.max_value = 1.0
		volume_slider.step = 0.01

	# Blue-outline buttons in SettingsPanel
	_apply_blue_button_style_to_panel()

	visible = false
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP

	if is_instance_valid(stats_box):
		stats_box.visible = false

	_connect_once(close_button.pressed, Callable(self, "close"))
	_connect_once(mute_toggle.toggled, Callable(self, "_on_mute_toggled"))
	_connect_once(volume_slider.value_changed, Callable(self, "_on_volume_changed"))
	_connect_once(save_btn.pressed, Callable(self, "_on_save_pressed"))
	_connect_once(load_btn.pressed, Callable(self, "_on_load_pressed"))
	_connect_once(stats_btn.pressed, Callable(self, "_on_stats_pressed"))
	_connect_once(run_tab.pressed, Callable(self, "_on_run_tab"))
	_connect_once(lifetime_tab.pressed, Callable(self, "_on_lifetime_tab"))

	_load_settings_into_ui()
	_apply_audio()

	set_process(true)
	set_process_unhandled_input(true)

func open() -> void:
	_force_close_overlay(prestige_panel_node_name)
	_force_close_overlay(shop_panel_node_name)

	_disable_internal_backdrop()
	_apply_panel_frame()
	_apply_blue_button_style_to_panel()

	visible = true
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Grab focus so Esc works for THIS panel
	focus_mode = Control.FOCUS_ALL
	grab_focus()

	_load_settings_into_ui()
	_apply_audio()
	_refresh_stats(true)

func close() -> void:
	visible = false

# Click outside closes, Esc closes. (No blocker overlay that can steal clicks.)
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on Esc / ui_cancel and CONSUME so PauseMenu doesn't toggle this frame.
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
			return

	# Click outside closes (no backdrop required)
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not get_global_rect().has_point(mb.position):
				close()
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible or not is_instance_valid(stats_box) or not stats_box.visible:
		return
	_t_stats += delta
	if _t_stats >= 0.5:
		_t_stats = 0.0
		_refresh_stats(false)

# Number formatting helper (100, 1.00k, 1.00M, 1.00B, etc.)
func _fmt_num(v: float) -> String:
	if not is_finite(v):
		return "0"
	if v >= 1.0e15:
		var exp := int(floor(log(v) / log(10)))
		var mant := snappedf(v / pow(10, exp), 0.01)
		return str(mant) + "e+" + str(exp)
	if v >= 1.0e12:
		return str(snappedf(v / 1.0e12, 0.01)) + "T"
	if v >= 1.0e9:
		return str(snappedf(v / 1.0e9, 0.01)) + "B"
	if v >= 1.0e6:
		return str(snappedf(v / 1.0e6, 0.01)) + "M"
	if v >= 1.0e3:
		return str(snappedf(v / 1.0e3, 0.01)) + "k"
	return str(int(v))

# -------------------------
# CRITICAL: stop internal Backdrop painting white
# -------------------------
func _disable_internal_backdrop() -> void:
	if _internal_backdrop == null or not is_instance_valid(_internal_backdrop):
		return
	_internal_backdrop.visible = false
	_internal_backdrop.z_index = -1000
	if _internal_backdrop is ColorRect:
		var cr := _internal_backdrop as ColorRect
		cr.color = Color(0, 0, 0, 0.0)
		cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif _internal_backdrop is Control:
		(_internal_backdrop as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

# -------------------------
# Panel frame
# -------------------------
func _apply_panel_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = panel_bg
	sb.border_color = panel_border
	sb.border_width_left = panel_border_width
	sb.border_width_top = panel_border_width
	sb.border_width_right = panel_border_width
	sb.border_width_bottom = panel_border_width
	sb.corner_radius_top_left = panel_radius
	sb.corner_radius_top_right = panel_radius
	sb.corner_radius_bottom_left = panel_radius
	sb.corner_radius_bottom_right = panel_radius
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)

# -------------------------
# Button styling (blue outline)
# -------------------------
func _apply_blue_button_style_to_panel() -> void:
	_style_button(close_button)
	_style_button(save_btn)
	_style_button(load_btn)
	_style_button(stats_btn)
	_style_button(run_tab)
	_style_button(lifetime_tab)
	_style_basebutton(mute_toggle)

func _mk_btn_style(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _style_button(btn: Button) -> void:
	if btn == null or not is_instance_valid(btn):
		return
	var normal := _mk_btn_style(Color(0.10, 0.11, 0.14, 0.95), Color(0.24, 0.67, 0.94, 0.95), 2, 8)
	var hover := _mk_btn_style(Color(0.13, 0.14, 0.18, 0.98), Color(0.30, 0.75, 0.98, 1.0), 2, 8)
	var pressed := _mk_btn_style(Color(0.07, 0.08, 0.10, 0.95), Color(0.20, 0.60, 0.90, 0.95), 2, 8)
	var disabled := _mk_btn_style(Color(0.08, 0.08, 0.10, 0.55), Color(0.20, 0.40, 0.55, 0.45), 2, 8)

	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)

	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.70, 0.74, 0.80, 1.0))

func _style_basebutton(b: BaseButton) -> void:
	if b == null or not is_instance_valid(b):
		return
	var normal := _mk_btn_style(Color(0.10, 0.11, 0.14, 0.95), Color(0.24, 0.67, 0.94, 0.95), 2, 8)
	var hover := _mk_btn_style(Color(0.13, 0.14, 0.18, 0.98), Color(0.30, 0.75, 0.98, 1.0), 2, 8)
	var pressed := _mk_btn_style(Color(0.07, 0.08, 0.10, 0.95), Color(0.20, 0.60, 0.90, 0.95), 2, 8)
	var disabled := _mk_btn_style(Color(0.08, 0.08, 0.10, 0.55), Color(0.20, 0.40, 0.55, 0.45), 2, 8)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)

	b.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.70, 0.74, 0.80, 1.0))

# -------------------------
# Audio
# -------------------------
func _load_settings_into_ui() -> void:
	var data: Dictionary = SaveSystem.load_game()
	var mute: bool = bool(data.get(SAVE_MUTE_KEY, false))
	var vol: float = clampf(float(data.get(SAVE_VOL_KEY, 1.0)), 0.0, 1.0)
	var tutorials_disabled: bool = bool(data.get(SAVE_TUTORIAL_DISABLED_KEY, false))

	if is_instance_valid(mute_toggle):
		mute_toggle.button_pressed = mute
	if is_instance_valid(volume_slider):
		volume_slider.value = vol
	if is_instance_valid(tutorial_toggle):
		tutorial_toggle.button_pressed = tutorials_disabled
	_update_volume_text(vol)
	
	# Apply tutorial state immediately
	_apply_tutorial_state(tutorials_disabled)

func _save_settings_from_ui() -> void:
	var data: Dictionary = SaveSystem.load_game()
	if is_instance_valid(mute_toggle):
		data[SAVE_MUTE_KEY] = bool(mute_toggle.button_pressed)
	if is_instance_valid(volume_slider):
		data[SAVE_VOL_KEY] = float(volume_slider.value)
	if is_instance_valid(tutorial_toggle):
		data[SAVE_TUTORIAL_DISABLED_KEY] = bool(tutorial_toggle.button_pressed)
	SaveSystem.save_game(data)

func _apply_audio() -> void:
	var idx := AudioServer.get_bus_index(master_bus_name)
	if idx < 0:
		return
	var mute := bool(mute_toggle.button_pressed)
	var vol := clampf(float(volume_slider.value), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, mute)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))

func _on_mute_toggled(_on: bool) -> void:
	_apply_audio()
	_save_settings_from_ui()

func _on_volume_changed(v: float) -> void:
	var vol := clampf(v, 0.0, 1.0)
	_update_volume_text(vol)
	_apply_audio()
	_save_settings_from_ui()

func _on_tutorial_toggled(disabled: bool) -> void:
	_save_settings_from_ui()
	_apply_tutorial_state(disabled)

func _apply_tutorial_state(disabled: bool) -> void:
	var tm = get_node_or_null("/root/TutorialManage")
	if tm == null:
		return
		
	if disabled:
		# Mark all tutorials as completed so they don't trigger
		if tm.has_method("get_save_data"):
			var save_data = tm.call("get_save_data")
			if save_data.has("completed_tutorials"):
				# Get all possible tutorial keys from the TUTORIALS dict
				if tm.get("TUTORIALS") != null:
					var all_tutorials = tm.get("TUTORIALS").keys()
					for key in all_tutorials:
						if not key in save_data["completed_tutorials"]:
							save_data["completed_tutorials"].append(key)
					if tm.has_method("load_save_data"):
						tm.call("load_save_data", save_data)
	else:
		# Re-enable by clearing history (optional - you might want to keep completed ones)
		# This will allow tutorials to trigger again on new runs
		if tm.has_method("get_save_data"):
			var save_data = tm.call("get_save_data")
			if save_data.has("completed_tutorials"):
				save_data["completed_tutorials"] = []
				if tm.has_method("load_save_data"):
					tm.call("load_save_data", save_data)

func _update_volume_text(vol: float) -> void:
	if is_instance_valid(volume_label):
		volume_label.text = "Volume  %d%%" % int(round(vol * 100.0))

# -------------------------
# Save / Load / Stats
# -------------------------
func _on_save_pressed() -> void:
	_save_settings_from_ui()

func _on_load_pressed() -> void:
	_load_settings_into_ui()
	_apply_audio()

func _on_stats_pressed() -> void:
	# This MUST NOT close the panel: only toggles StatsBox
	if not is_instance_valid(stats_box):
		return
	stats_box.visible = true
	_refresh_stats(true)

func _on_run_tab() -> void:
	_stats_mode = StatsMode.RUN
	_refresh_stats(true)

func _on_lifetime_tab() -> void:
	_stats_mode = StatsMode.LIFETIME
	_refresh_stats(true)

func _refresh_stats(_force: bool) -> void:
	if not is_instance_valid(stat_lines):
		return

	var lines: Array[Label] = []
	for c in stat_lines.get_children():
		if c is Label:
			lines.append(c as Label)
	if lines.size() < 6:
		return

	if _stats_mode == StatsMode.RUN:
		lines[0].text = "RUN"
		# FIX: Get depth from method instead of property
		var current_depth := 1
		if _gm != null and _gm.has_method("get_current_depth"):
			current_depth = _gm.call("get_current_depth")
		lines[1].text = "Depth: %d" % current_depth
		lines[2].text = "Thoughts: %s" % _fmt_num(_get_float_from_gm("thoughts"))
		lines[3].text = "Thoughts/s: %s" % _fmt_num(_get_float_from_gm("_thoughts_ps"))
		lines[4].text = "Control: %s" % _fmt_num(_get_float_from_gm("control"))
		lines[5].text = "Instability: %s" % _fmt_num(_get_float_from_gm("instability"))
	else:
		var data: Dictionary = SaveSystem.load_game()
		lines[0].text = "LIFETIME"
		lines[1].text = "Total Thoughts: %s" % _fmt_num(float(data.get(LT_THOUGHTS, 0)))
		lines[2].text = "Total Control: %s" % _fmt_num(float(data.get(LT_CONTROL, 0)))
		lines[3].text = "Total Dives: %s" % _fmt_num(float(data.get(LT_DIVES, 0)))
		lines[4].text = "Deepest Depth: %d" % int(data.get(LT_DEEPEST, 1))
		lines[5].text = "Playtime (s): %s" % _fmt_num(float(data.get(LT_PLAYTIME, 0)))

func _get_int_from_gm(prop: String) -> int:
	if _gm == null:
		return 0
	var v: Variant = _gm.get(prop)
	if typeof(v) == TYPE_INT: return int(v)
	if typeof(v) == TYPE_FLOAT: return int(v)
	return 0

func _get_float_from_gm(prop: String) -> float:
	if _gm == null:
		return 0.0
	var v: Variant = _gm.get(prop)
	if typeof(v) == TYPE_FLOAT: return float(v)
	if typeof(v) == TYPE_INT: return float(v)
	return 0.0

# -------------------------
# Close other overlays
# -------------------------
func _force_close_overlay(node_name: String) -> void:
	if node_name.strip_edges() == "":
		return
	var n := get_tree().current_scene.find_child(node_name, true, false)
	if n == null:
		return
	if n.has_method("close"):
		n.call("close")
	elif n is CanvasItem:
		(n as CanvasItem).visible = false

func _connect_once(sig: Signal, cb: Callable) -> void:
	if sig.is_connected(cb):
		return
	sig.connect(cb)
