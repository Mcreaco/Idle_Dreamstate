extends PanelContainer
class_name SettingsPanel

@export var master_bus_name: String = "Master"

# Panel frame (blue border)
@export var panel_bg: Color = Color(0.06, 0.08, 0.12, 0.70)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 0.95)
@export var panel_border_width: int = 2
@export var panel_radius: int = 10

# Close these overlays when Settings opens (prevents overlap)
@export var prestige_panel_node_name: String = "PrestigePanel"
@export var shop_panel_node_name: String = "ShopPanel"

const SAVE_MUTE_KEY := "mute"
const SAVE_VOL_KEY := "master_volume"

# Lifetime keys (stored in save)
const LT_THOUGHTS := "lifetime_thoughts"
const LT_CONTROL := "lifetime_control"
const LT_DIVES := "total_dives"
const LT_DEEPEST := "deepest_depth"
const LT_PLAYTIME := "total_playtime"

enum StatsMode { RUN, LIFETIME }
var _stats_mode: int = StatsMode.RUN

# --- YOUR TREE (with Root) ---
@onready var title_label: Label = $"Root/Title"
@onready var mute_toggle: CheckButton = $"Root/Mute"
@onready var volume_label: Label = $"Root/VolumeLabel"
@onready var volume_slider: HSlider = $"Root/Volume"
@onready var close_button: Button = $"Root/CloseButton"

@onready var save_btn: Button = $"Root/Actions/SaveButton"
@onready var load_btn: Button = $"Root/Actions/LoadButton"
@onready var stats_btn: Button = $"Root/Actions/StatsButton"

@onready var stats_box: VBoxContainer = $"Root/StatsBox"
@onready var run_tab: Button = $"Root/StatsBox/StatsTabs/RunTabButton"
@onready var lifetime_tab: Button = $"Root/StatsBox/StatsTabs/LifetimeTabButton"
@onready var stat_lines: VBoxContainer = $"Root/StatsBox/StatLines"

var _gm: Node = null
var _t_stats: float = 0.0

# SIBLING backdrop (won't darken UI text)
var _backdrop: ColorRect = null

func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false)

	_apply_panel_frame()
	_ensure_backdrop()

	title_label.text = "Settings"
	mute_toggle.text = "Mute"
	close_button.text = "Close"
	save_btn.text = "Save"
	load_btn.text = "Load"
	stats_btn.text = "Stats"
	run_tab.text = "Run"
	lifetime_tab.text = "Lifetime"

	volume_slider.min_value = 0.0
	volume_slider.max_value = 1.0
	volume_slider.step = 0.01

	visible = false
	stats_box.visible = false
	if _backdrop: _backdrop.visible = false

	close_button.pressed.connect(close)
	mute_toggle.toggled.connect(_on_mute_toggled)
	volume_slider.value_changed.connect(_on_volume_changed)

	save_btn.pressed.connect(_on_save_pressed)
	load_btn.pressed.connect(_on_load_pressed)
	stats_btn.pressed.connect(_on_stats_pressed)

	run_tab.pressed.connect(_on_run_tab)
	lifetime_tab.pressed.connect(_on_lifetime_tab)

	_load_settings_into_ui()
	_apply_audio()

	set_process(true)

func open() -> void:
	_apply_panel_frame()
	visible = true
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP

	if _backdrop:
		_backdrop.visible = true
		_backdrop.z_index = z_index - 1

	_load_settings_into_ui()
	_apply_audio()
	_refresh_stats(true)

func close() -> void:
	visible = false
	if _backdrop:
		_backdrop.visible = false

func _process(delta: float) -> void:
	if not visible or not stats_box.visible:
		return
	_t_stats += delta
	if _t_stats >= 0.5:
		_t_stats = 0.0
		_refresh_stats(false)

# -------------------------
# Backdrop (SIBLING, behind panel)
# -------------------------
func _ensure_backdrop() -> void:
	if _backdrop != null and is_instance_valid(_backdrop):
		return

	var parent := get_parent()
	if parent == null:
		return

	_backdrop = parent.get_node_or_null("SettingsBackdrop") as ColorRect
	if _backdrop == null:
		_backdrop = ColorRect.new()
		_backdrop.name = "SettingsBackdrop"
		parent.add_child(_backdrop)

	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.offset_left = 0
	_backdrop.offset_top = 0
	_backdrop.offset_right = 0
	_backdrop.offset_bottom = 0
	_backdrop.color = Color(0, 0, 0, 0.35)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false

	if not _backdrop.gui_input.is_connected(_on_backdrop_input):
		_backdrop.gui_input.connect(_on_backdrop_input)

func _on_backdrop_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		close()

# -------------------------
# Panel frame (blue border)
# -------------------------
func _apply_panel_frame() -> void:
	var sb := StyleBoxFlat.new()

	# Dark glass background
	sb.bg_color = Color(0.04, 0.07, 0.12, 0.92)

	# Blue border
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2

	# Rounded corners
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12

	# Padding so content doesn’t touch the edge
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16

	# 🔑 THIS LINE IS CRITICAL
	add_theme_stylebox_override("panel", sb)


# -------------------------
# Audio
# -------------------------
func _load_settings_into_ui() -> void:
	var data: Dictionary = SaveSystem.load_game()
	var mute: bool = bool(data.get(SAVE_MUTE_KEY, false))
	var vol: float = float(data.get(SAVE_VOL_KEY, 1.0))
	mute_toggle.button_pressed = mute
	volume_slider.value = vol
	_update_volume_text(vol)

func _save_settings_from_ui() -> void:
	var data: Dictionary = SaveSystem.load_game()
	data[SAVE_MUTE_KEY] = bool(mute_toggle.button_pressed)
	data[SAVE_VOL_KEY] = float(volume_slider.value)
	SaveSystem.save_game(data)

func _apply_audio() -> void:
	var idx := AudioServer.get_bus_index(master_bus_name)
	if idx < 0:
		return
	var mute := bool(mute_toggle.button_pressed)
	var vol := clampf(float(volume_slider.value), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, mute)
	var db := linear_to_db(maxf(vol, 0.0001))
	AudioServer.set_bus_volume_db(idx, db)

func _on_mute_toggled(_on: bool) -> void:
	_apply_audio()
	_save_settings_from_ui()

func _on_volume_changed(v: float) -> void:
	_update_volume_text(v)
	_apply_audio()
	_save_settings_from_ui()

func _update_volume_text(vol: float) -> void:
	volume_label.text = "Volume  %d%%" % int(round(vol * 100.0))

# -------------------------
# Save / Load / Stats
# -------------------------
func _on_save_pressed() -> void:
	_save_settings_from_ui()
	print("Saved.")

func _on_load_pressed() -> void:
	_load_settings_into_ui()
	_apply_audio()
	print("Loaded.")

func _on_stats_pressed() -> void:
	stats_box.visible = not stats_box.visible
	_refresh_stats(true)

func _on_run_tab() -> void:
	_stats_mode = StatsMode.RUN
	_refresh_stats(true)

func _on_lifetime_tab() -> void:
	_stats_mode = StatsMode.LIFETIME
	_refresh_stats(true)

func _refresh_stats(_force: bool) -> void:
	var lines: Array[Label] = []
	for c in stat_lines.get_children():
		if c is Label:
			lines.append(c as Label)
	if lines.size() < 6:
		return

	if _stats_mode == StatsMode.RUN:
		lines[0].text = "RUN"
		lines[1].text = "Depth: %d" % _get_int_from_gm("depth")
		lines[2].text = "Thoughts: %s" % str(_get_float_from_gm("thoughts"))
		lines[3].text = "Thoughts/s: %s" % str(_get_float_from_gm("thoughts_per_sec"))
		lines[4].text = "Control: %s" % str(_get_float_from_gm("control"))
		lines[5].text = "Instability: %s" % str(_get_float_from_gm("instability"))
	else:
		var data: Dictionary = SaveSystem.load_game()
		lines[0].text = "LIFETIME"
		lines[1].text = "Total Thoughts: %s" % str(data.get(LT_THOUGHTS, 0))
		lines[2].text = "Total Control: %s" % str(data.get(LT_CONTROL, 0))
		lines[3].text = "Total Dives: %s" % str(data.get(LT_DIVES, 0))
		lines[4].text = "Deepest Depth: %s" % str(data.get(LT_DEEPEST, 0))
		lines[5].text = "Playtime (s): %s" % str(data.get(LT_PLAYTIME, 0))

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
# Close other overlays (no overlap)
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
