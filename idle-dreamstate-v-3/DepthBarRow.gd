# res://UI/DepthBarRow.gd
extends PanelContainer
class_name DepthBarRow

signal clicked_depth(depth_index: int)
signal request_close(depth_index: int)

const COLOR_BLUE: Color = Color(0.24, 0.67, 0.94)

@export var details_open_height: float = 260.0
@export var row_height := 64.0
@export var bar_height := 14.0
@export var title_font := 18
@export var reward_font := 16
@export var percent_font := 14
@export var top_bottom_padding: float = 6.0
@export var v_separation := 2

# Row background images
const BG_DIR := "res://UI/DepthBarBG/"
const ROW_BORDER_INSET := 2 # must match border width below
var _auto_buy_enabled: Dictionary = {}  # id -> bool
const AUTO_BUY_SAVE_KEY := "auto_buy_enabled"
var depth_index: int = 1
var _active: bool = false
var _frozen: bool = false
var _locked: bool = false
var _details_open: bool = false
var _overlay_mode: bool = false
var _upgrade_ui_refs: Dictionary = {}  # id -> {button, cost_label, lvl_label, base_cost, growth, max_lvl}
var _auto_buy_cooldown: float = 0.0
const AUTO_BUY_DELAY: float = 0.5  # Half second between purchases
var _data: Dictionary = {"progress": 0.0, "memories": 0.0, "crystals": 0.0}
var _local_upgrades: Dictionary = {}
var _frozen_upgrades: Dictionary = {}

var _run: Node = null

# Scene nodes
var progress_bar: ProgressBar = null
var percent_label: Label = null
var details: Control = null
var upgrades_box: VBoxContainer = null
var dive_button: Button = null
var close_button: Button = null

# Runtime UI
var _margin: MarginContainer = null
var _layout_root: VBoxContainer = null
var _title_label: Label = null
var _reward_label: Label = null
var _row_bg: TextureRect = null

var _block_click_until_msec: int = 0

var partial_memories: float = 0.0
var partial_crystals: float = 0.0

var _dive_confirm_popup: Node = null

func is_details_open() -> bool:
	return _details_open

func block_row_clicks(ms: int = 200) -> void:
	_block_click_until_msec = Time.get_ticks_msec() + ms


# basename_lower -> full_path (keeps actual case)
var _bg_map: Dictionary = {}

func _fmt_num(v: float) -> String:
	if v >= 1e15:
		return "%.2e" % v
	if v >= 1_000_000_000_000.0:
		return "%.2fT" % (v / 1_000_000_000_000.0)
	if v >= 1_000_000_000.0:
		return "%.2fB" % (v / 1_000_000_000.0)
	if v >= 1_000_000.0:
		return "%.2fM" % (v / 1_000_000.0)
	if v >= 1_000.0:
		return "%.2fk" % (v / 1_000.0)
	return str(int(v))
	
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = row_height
	_run = get_node_or_null("/root/DepthRunController")
	progress_bar = null
	percent_label = null
	_hide_extra_progress_bars()
	percent_label = get_node_or_null("Progress/PercentLabel") as Label
	if percent_label == null:
		percent_label = get_node_or_null("ProgressBar/PercentLabel") as Label

	details = get_node_or_null("Details") as Control
	upgrades_box = find_child("RunUpgradesBox", true, false) as VBoxContainer
	dive_button = find_child("DiveButton", true, false) as Button
	close_button = find_child("CloseButton", true, false) as Button

	_ensure_bg_map()
	_build_layout_bar_then_bottom_text()
	_arrange_dive_close_buttons()
	_apply_bar_style()
	_style_progress_bar()
	_apply_row_background_texture()

	if details != null:
		details.visible = false
		details.custom_minimum_size.y = 0.0
		# Make details background transparent so the row image shows through when expanded
		if details is PanelContainer:
			(details as PanelContainer).add_theme_stylebox_override("panel", StyleBoxEmpty.new())

		# Also remove any PanelContainer backgrounds inside Details (common cause)
		for n in details.find_children("", "PanelContainer", true, false):
			(n as PanelContainer).add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	if dive_button != null:
		_apply_blue_button_style(dive_button)
		if not dive_button.pressed.is_connected(Callable(self, "_on_dive_pressed")):
			dive_button.pressed.connect(Callable(self, "_on_dive_pressed"))

	if close_button != null:
		_apply_blue_button_style(close_button)
		if not close_button.pressed.is_connected(Callable(self, "_on_close_pressed")):
			close_button.pressed.connect(Callable(self, "_on_close_pressed"))

	_apply_visuals()
	
		# Hide any mystery buttons (buttons with no text/icon that aren't dive/close)
	for child in find_children("", "Button", true, false):
		var btn := child as Button
		if btn == dive_button or btn == close_button:
			continue
		# Hide buttons with no text and no icon
		if btn.text == "" and btn.icon == null:
			btn.visible = false

func _gui_input(event: InputEvent) -> void:
	# Debounce after closing overlay (prevents instant re-open bug)
	if Time.get_ticks_msec() < _block_click_until_msec:
		return

	# When expanded/overlayed, the row itself should not react to clicks
	if _overlay_mode or _details_open:
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _active and not _locked and not _frozen:
				clicked_depth.emit(depth_index)



# -----------------------
# Public API
# -----------------------
func set_depth_index(d: int) -> void:
	depth_index = d
	_apply_bar_style()
	_style_progress_bar()
	_apply_row_background_texture()
	_apply_visuals()

func set_active(v: bool) -> void:
	_active = v
	if not _active and _details_open:
		set_details_open(false)
	_apply_visuals()

func set_frozen(v: bool) -> void:
	_frozen = v
	if _frozen and _details_open:
		set_details_open(false)
	_apply_visuals()

func set_locked(v: bool) -> void:
	_locked = v
	if _locked and _details_open:
		set_details_open(false)
	_apply_visuals()

func set_overlay_mode(v: bool) -> void:
	_overlay_mode = v

	# In overlay, remove padding so the PNG can reach the border
	if _margin != null and is_instance_valid(_margin):
		if _overlay_mode:
			_margin.add_theme_constant_override("margin_left", 0)
			_margin.add_theme_constant_override("margin_right", 0)
			_margin.add_theme_constant_override("margin_top", 0)
			_margin.add_theme_constant_override("margin_bottom", 0)
		else:
			_margin.add_theme_constant_override("margin_left", 10)
			_margin.add_theme_constant_override("margin_right", 10)
			_margin.add_theme_constant_override("margin_top", int(top_bottom_padding))
			_margin.add_theme_constant_override("margin_bottom", int(top_bottom_padding))

	_apply_bar_style()
	_apply_row_background_texture()
	_apply_visuals()



func set_data(data: Dictionary) -> void:
	# Update internal data - ensure we have valid values
	if data.has("progress"):
		_data = data.duplicate(true)
	else:
		_data = {"progress": 0.0, "memories": 0.0, "crystals": 0.0}
	
	# Reset partial accumulators when data is explicitly set (prevents double-counting)
	partial_memories = 0.0
	partial_crystals = 0.0
	
	# Force visual update
	_apply_visuals()
	
func set_local_upgrades(d: Dictionary) -> void:
	_local_upgrades = d
	if _details_open:
		_build_upgrades_ui()
		# Refresh all upgrade UIs
		for id in _upgrade_ui_refs.keys():
			_update_upgrade_row_ui(id)

func set_frozen_upgrades(d: Dictionary) -> void:
	_frozen_upgrades = d
	if _details_open:
		_build_upgrades_ui()

func refresh_details() -> void:
	if _details_open:
		_build_upgrades_ui()

func set_details_open(open: bool) -> void:
	if not _active or _locked or _frozen:
		open = false

	_details_open = open
	if details == null:
		return

	if open:
		details.visible = true
		var tw := create_tween()
		tw.tween_property(details, "custom_minimum_size:y", details_open_height, 0.18)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_build_upgrades_ui()
		_hide_extra_progress_bars() # <-- removes the random 0% bar
	else:
		var tw2 := create_tween()
		tw2.tween_property(details, "custom_minimum_size:y", 0.0, 0.16)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw2.tween_callback(func(): details.visible = false)

	_apply_visuals()
	_apply_bar_style()
	_apply_row_background_texture()
	
	# Notify tutorial manager when expanded/closed
	if open:
		var tm = get_node_or_null("/root/TutorialManage")
		if tm and tm.has_method("on_depth_bar_expanded"):
			tm.on_depth_bar_expanded(depth_index)

# -----------------------
# Layout
# -----------------------
func _build_layout_bar_then_bottom_text() -> void:
	# Keep the original early return
	if _layout_root != null and is_instance_valid(_layout_root):
		return

	# Remove existing children
	var old_children: Array = []
	for c in get_children():
		old_children.append(c)
	for c in old_children:
		remove_child(c)

	_row_bg = null

	# Margin wrapper
	_margin = MarginContainer.new()
	_margin.name = "RowMargin"
	_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin.add_theme_constant_override("margin_left", 10)
	_margin.add_theme_constant_override("margin_right", 10)
	_margin.add_theme_constant_override("margin_top", int(top_bottom_padding))
	_margin.add_theme_constant_override("margin_bottom", int(top_bottom_padding))
	add_child(_margin)

	_layout_root = VBoxContainer.new()
	_layout_root.name = "RowLayout"
	_layout_root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_root.add_theme_constant_override("separation", int(v_separation))
	_margin.add_child(_layout_root)

	# --- CREATE PROGRESS BAR IN CODE ---
	progress_bar = ProgressBar.new()
	progress_bar.name = "ProgressBar"
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.custom_minimum_size.x = 0
	progress_bar.custom_minimum_size.y = bar_height
	progress_bar.show_percentage = false
	_layout_root.add_child(progress_bar)
	
	# Style the progress bar
	_style_progress_bar()

	# Percent label inside bar
	percent_label = Label.new()
	percent_label.name = "PercentLabel"
	percent_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	percent_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	percent_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	percent_label.z_index = 50
	percent_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	percent_label.add_theme_font_size_override("font_size", percent_font)
	progress_bar.add_child(percent_label)

	# --- Bottom row: title left + reward right ---
	var bottom := HBoxContainer.new()
	bottom.name = "BottomRow"
	bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_layout_root.add_child(bottom)

	_title_label = Label.new()
	_title_label.name = "TitleLabel"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_title_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.95))
	_title_label.add_theme_font_size_override("font_size", title_font)
	bottom.add_child(_title_label)

	_reward_label = Label.new()
	_reward_label.name = "RewardLabel"
	_reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_reward_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reward_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reward_label.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 0.95))
	_reward_label.add_theme_font_size_override("font_size", reward_font)
	bottom.add_child(_reward_label)

	# Put back other original nodes (Details, etc.)
	for c in old_children:
		if c is ProgressBar:
			c.queue_free()  # Delete old progress bars
			continue
		_layout_root.add_child(c)

	_apply_row_background_texture()
	
		
func _on_manual_click() -> void:
	if not _active or _locked:
		return
	
	# Get current progress rate from controller (1 second worth)
	var drc := get_node_or_null("/root/DepthRunController")
	var progress_per_second := 0.000833  # Default base rate
	
	if drc != null:
		# Calculate actual per-second progress like the controller does
		var base_progress: float = float(drc.get("base_progress_per_sec"))
		var length: float = 1.0
		if drc.has_method("get_depth_length"):
			length = drc.call("get_depth_length", depth_index)
		
		# Get speed multipliers from local upgrades
		var speed_mul: float = 1.0
		var local_upgs: Dictionary = _local_upgrades
		var speed_lvl: int = int(local_upgs.get("progress_speed", 0))
		speed_mul += 0.25 * float(speed_lvl)
		
		# Get depth rules multiplier
		var def: Dictionary = {}
		if drc.has_method("get_depth_def"):
			def = drc.call("get_depth_def", depth_index)
		var rules: Dictionary = def.get("rules", {})
		var depth_prog_mul: float = float(rules.get("progress_mul", 1.0))
		
		progress_per_second = (base_progress * speed_mul * depth_prog_mul) / maxf(length, 0.0001)
	
	# Get click power from meta upgrade (adds extra seconds per click)
	var click_seconds := 1.0  # Base 1 second
	var meta := _depth_meta()
	if meta != null:
		var click_level := int(meta.get_level(1, "manual_click"))
		click_seconds = 1.0 + float(click_level)  # +1 second per level
	
	var total_progress_add := progress_per_second * click_seconds
	
	# Add progress
	var data: Dictionary = _data.duplicate(true)
	var current_progress: float = float(data.get("progress", 0.0))
	data["progress"] = minf(1.0, current_progress + total_progress_add)
	
	# Update display
	set_data(data)
	
	# Visual feedback
	if progress_bar != null:
		var tween := create_tween()
		tween.tween_property(progress_bar, "modulate", Color(1.3, 1.3, 1.3, 1.0), 0.05)
		tween.tween_property(progress_bar, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.1)
	
	# Update button text to show seconds
	if _details_open and upgrades_box != null:
		var click_btn := upgrades_box.get_node_or_null("ClickButton")
		if click_btn != null:
			var new_level := int(meta.get_level(1, "manual_click")) if meta != null else 0
			var seconds := 1 + new_level
			click_btn.text = "Focus (+%ds)" % seconds
	
	# Save progress
	if drc != null:
		var run_data: Array = drc.get("run") as Array
		if run_data != null and depth_index >= 1 and depth_index <= run_data.size():
			run_data[depth_index - 1] = data
			drc.set("run", run_data)
# -----------------------
# Visuals
# -----------------------
func _apply_visuals() -> void:
	# When expanded/overlayed, NEVER dim the whole row
	if _overlay_mode or _details_open:
		modulate = Color(1, 1, 1, 1)
	else:
		if _locked:
			modulate = Color(1, 1, 1, 0.45)
		elif _frozen:
			modulate = Color(1, 1, 1, 0.70)
		else:
			modulate = Color(1, 1, 1, 1.0)

	# Determine what to show in progress bar
	var display_pct: float = 0.0
	
	if _locked:
		display_pct = 0.0
	elif _active or _frozen:
		display_pct = _data.get("progress", 0.0) * 100.0
	else:
		display_pct = 0.0

	if progress_bar != null:
		progress_bar.value = display_pct
		progress_bar.show_percentage = false

	if percent_label != null and progress_bar != null:
		percent_label.text = "%d%%" % int(round(display_pct))

	# NULL CHECKS ADDED HERE:
	if _title_label != null:
		_title_label.text = _depth_title_text()

	if _reward_label != null:
		# Check if this is Murk (Depth 4) with hidden rewards
		var show_hidden := false
		if depth_index == 4:
			var drc := get_node_or_null("/root/DepthRunController")
			if drc != null:
				var local_upgs := drc.get("local_upgrades") as Dictionary
				if local_upgs.has(4):
					var dark_adapt := int(local_upgs[4].get("dark_adaptation", 0))
					if dark_adapt == 0:
						show_hidden = true
		
		if show_hidden:
			_reward_label.text = "+??? Mem  +??? %s" % _crystal_name()
		else:
			var mem := float(_data.get("memories", 0.0))
			var cry := float(_data.get("crystals", 0.0))
			_reward_label.text = "+%.1f Mem  +%.1f %s" % [mem, cry, _crystal_name()]

	if dive_button != null:
		var can := false
		if _run != null and _run.has_method("can_dive"):
			can = bool(_run.call("can_dive"))
		
		# Force enable if we're at depth 1 and unlock is bought (special case)
		if depth_index == 1 and _active:
			var meta := _depth_meta()
			if meta != null and meta.has_method("is_next_depth_unlocked"):
				if meta.call("is_next_depth_unlocked", 1):
					can = true
		
		dive_button.disabled = not can
		dive_button.visible = _active

	if _row_bg != null:
		var a := 0.70
		if _locked:
			a = 0.28
		elif _frozen:
			a = 0.45
		elif _active:
			a = 0.80
		if _overlay_mode or _details_open:
			a = 1.0
		_row_bg.modulate = Color(1, 1, 1, a)
		
	# If Murk and not upgraded, hide crystal numbers
	if depth_index == 4:
		var dark_adapt := 0 # Get from local upgrades
		if dark_adapt == 0:
			_reward_label.text = "+??? Mem  +??? %s" % _crystal_name()
		else:
			# Show partial based on upgrade level
			var mem := float(_data.get("memories", 0.0))
			var cry := float(_data.get("crystals", 0.0))
			_reward_label.text = "+%.1f Mem  +%.1f %s" % [mem, cry, _crystal_name()]


# NEW: Calculate upgrade completion % for this depth
func _get_upgrade_completion_percent() -> float:
	var meta := _depth_meta()
	if meta == null:
		return 0.0  # Silently return 0, don't warn
	
	var total_levels := 0
	var completed_levels := 0
	
	if not meta.has_method("get_depth_upgrade_defs"):
		return 0.0
	
	if not meta.has_method("get_level"):
		return 0.0
	
	var defs := meta.call("get_depth_upgrade_defs", depth_index) as Array
	
	for def in defs:
		var id := String(def.get("id", ""))
		var max_level := int(def.get("max", 1))
		var current_level := int(meta.call("get_level", depth_index, id))
		
		total_levels += max_level
		completed_levels += current_level
	
	if total_levels == 0:
		return 0.0
	
	return float(completed_levels) / float(total_levels) * 100.00

# -----------------------
# Meta + text
# -----------------------
func _depth_meta() -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null

	var cs := tree.current_scene
	if cs != null:
		var meta := cs.find_child("DepthMetaSystem", true, false)
		if meta != null:
			return meta

	var root := tree.root
	if root != null:
		return root.find_child("DepthMetaSystem", true, false)

	return null

func _depth_title_text() -> String:
	var meta := _depth_meta()
	if meta != null and meta.has_method("get_depth_name"):
		var nm := str(meta.call("get_depth_name", depth_index)).strip_edges()
		var prefix := "Depth %d" % depth_index
		if nm.begins_with(prefix) or nm.begins_with("Depth "):
			return nm
		return "%s — %s" % [prefix, nm]
	return "Depth %d" % depth_index

func _crystal_name() -> String:
	var meta := _depth_meta()
	if meta != null and meta.has_method("get_depth_currency_name"):
		return str(meta.call("get_depth_currency_name", depth_index))
	return "Cry"

# -----------------------
# Panel styling
# -----------------------
func _apply_bar_style() -> void:
	
	
	var sb := StyleBoxFlat.new()
	
	# Thicker border for expanded view
	var border_width := 4 if (_overlay_mode or _details_open) else 2
	var bg_alpha := 0.0 if (_overlay_mode or _details_open) else 0.16
	
	sb.bg_color = Color(0, 0, 0, bg_alpha)
	sb.border_color = COLOR_BLUE
	sb.border_width_left = border_width
	sb.border_width_top = border_width
	sb.border_width_right = border_width
	sb.border_width_bottom = border_width
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10

	add_theme_stylebox_override("panel", sb)
	
	# Thicker progress bar when expanded
	if progress_bar != null and (_overlay_mode or _details_open):
		progress_bar.custom_minimum_size.y = 24  # Was 14, now thicker
		progress_bar.add_theme_constant_override("outline_size", 2)


func _style_progress_bar() -> void:
	if progress_bar == null:
		return
	
	# Thicker when expanded
	var target_height: float = 24.0 if (_overlay_mode or _details_open) else bar_height
	progress_bar.custom_minimum_size.y = target_height

	progress_bar.custom_minimum_size.y = bar_height
	progress_bar.custom_minimum_size.x = 0
	progress_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_bar.show_percentage = false

	# Track (dark)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.07, 0.10, 0.85)
	bg.border_color = Color(0.20, 0.35, 0.55, 0.45)
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.corner_radius_top_left = 10
	bg.corner_radius_top_right = 10
	bg.corner_radius_bottom_left = 10
	bg.corner_radius_bottom_right = 10

	# Fill (blue gradient)
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.18, 0.55, 0.95, 0.95),
		Color(0.25, 0.85, 1.00, 0.98),
	])
	grad.offsets = PackedFloat32Array([0.0, 1.0])

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.width = 256
	tex.height = 1

	var fg := StyleBoxTexture.new()
	fg.texture = tex

	progress_bar.add_theme_stylebox_override("background", bg)
	progress_bar.add_theme_stylebox_override("fill", fg)

# -----------------------
# Row background image (full row, inside border)
# -----------------------
func _ensure_bg_map() -> void:
	if _bg_map.size() > 0:
		return

	var dir := DirAccess.open(BG_DIR)
	if dir == null:
		push_warning("DepthBarRow: cannot open " + BG_DIR)
		return

	dir.list_dir_begin()
	while true:
		var f := dir.get_next()
		if f == "":
			break
		if dir.current_is_dir():
			continue
		if not f.to_lower().ends_with(".png"):
			continue

		var base := f.get_basename().to_lower()
		_bg_map[base] = BG_DIR + f # preserves actual case on disk
	dir.list_dir_end()

func _depth_bg_texture() -> Texture2D:
	# Depth index -> exact filename (make sure these match your real filenames)
	var by_depth: Dictionary = {
		1: "shallow.png",
		2: "descent.png",
		3: "pressure.png",
		4: "murk.png",
		5: "rift.png",
		6: "hollow.png",
		7: "dread.png",
		8: "chasm.png",
		9: "silence.png",
		10: "veil.png",
		11: "ruin.png",
		12: "eclipse.png",
		13: "voidline.png",
		14: "blackwater.png",
		15: "abyss.png",
	}

	var v_file: Variant = by_depth.get(depth_index)
	if v_file == null:
		return null

	var file: String = String(v_file)
	if file.is_empty():
		return null

	var path: String = BG_DIR + file
	if not ResourceLoader.exists(path):
		push_warning("DepthBarRow: missing BG texture: " + path)
		return null

	var tex: Resource = load(path)
	if tex is Texture2D:
		return tex as Texture2D

	return null

func _ensure_row_background() -> void:
	if _row_bg != null and is_instance_valid(_row_bg):
		return

	_row_bg = TextureRect.new()
	_row_bg.name = "RowBG"
	_row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_row_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_row_bg.stretch_mode = TextureRect.STRETCH_SCALE

	add_child(_row_bg)
	move_child(_row_bg, 0) # behind everything


func _apply_row_background_texture() -> void:
	_ensure_row_background()
	if _row_bg == null:
		return

	_row_bg.texture = _depth_bg_texture()
	_row_bg.visible = (_row_bg.texture != null)

	# Always sit FLUSH inside the blue border
	_row_bg.offset_left = ROW_BORDER_INSET
	_row_bg.offset_top = ROW_BORDER_INSET
	_row_bg.offset_right = -ROW_BORDER_INSET
	_row_bg.offset_bottom = -ROW_BORDER_INSET


# -----------------------
# Upgrades UI (unchanged)
# -----------------------
func _build_upgrades_ui() -> void:
	if upgrades_box == null:
		return
	
	# CRITICAL: Clear old data when rebuilding UI
	_auto_buy_enabled.clear()
	_upgrade_ui_refs.clear()
		
	# Clear existing children first
	for c in upgrades_box.get_children():
		c.queue_free()
	
	# --- MANUAL FOCUS SECTION (ALL DEPTHS) ---
	# Create fresh section for each depth row
	var click_section := HBoxContainer.new()
	click_section.name = "ClickSection"
	click_section.alignment = BoxContainer.ALIGNMENT_BEGIN
	click_section.add_theme_constant_override("separation", 12)
	upgrades_box.add_child(click_section)
	
	var click_title := Label.new()
	click_title.text = "Manual Focus"
	click_title.add_theme_font_size_override("font_size", 22)
	click_title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	click_section.add_child(click_title)
	
	# Info label showing the amount
	var click_info := Label.new()
	click_info.name = "ClickInfoLabel"
	click_info.add_theme_font_size_override("font_size", 16)
	click_info.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 0.8))
	
	# Get level from Depth 1 meta (regardless of which depth row this is)
	var meta := _depth_meta()
	var click_level := 0
	if meta != null:
		click_level = int(meta.get_level(1, "manual_click"))
	var seconds := 1.0 + (click_level * 0.5)
	click_info.text = "(%.1fs idle Thoughts)" % seconds
	
	click_section.add_child(click_info)
	
	var click_btn := Button.new()
	click_btn.name = "ClickButton"
	click_btn.custom_minimum_size = Vector2(120, 40)
	click_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	click_btn.text = "Focus"
	_apply_blue_button_style(click_btn)
	
	click_btn.pressed.connect(func():
		var gm = get_tree().current_scene.find_child("GameManager", true, false)
		if gm != null and gm.has_method("on_manual_focus_clicked"):
			gm.call("on_manual_focus_clicked")
	)
	click_section.add_child(click_btn)
	
	# Add separator
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 20)
	upgrades_box.add_child(sep)
	
	# --- RUN UPGRADES SECTION ---
	var title := Label.new()
	title.text = "Run Upgrades (Depth %d)" % depth_index
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	upgrades_box.add_child(title)
	
	upgrades_box.add_theme_constant_override("separation", 12)

	# Get dynamic upgrades from DepthRunController
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		push_warning("DepthBarRow: DepthRunController not found, using fallback upgrades")
		_add_upgrade_row("progress_speed", "Progress Speed")
		_add_upgrade_row("memories_gain", "Memories Gain")
		_add_upgrade_row("crystals_gain", "Crystals Gain")
		return
	
	# Get upgrade IDs for this depth
	var upgrade_ids: Array[String] = []
	if drc.has_method("get_run_upgrade_ids"):
		upgrade_ids = drc.call("get_run_upgrade_ids", depth_index)
	else:
		upgrade_ids = ["progress_speed", "memories_gain", "crystals_gain"]
	
	# Build UI for each upgrade
	for upg_id in upgrade_ids:
		var upg_data: Dictionary = {}
		if drc.has_method("get_run_upgrade_data"):
			upg_data = drc.call("get_run_upgrade_data", depth_index, upg_id)
		else:
			upg_data = {"name": upg_id.capitalize(), "description": ""}
		
		_add_upgrade_row_dynamic(upg_id, upg_data)

func _add_upgrade_row(id: String, label_text: String) -> void:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var lvl := int(_local_upgrades.get(id, 0))
	var lvl_label := Label.new()
	lvl_label.text = "Lv %d" % lvl

	var btn := Button.new()
	btn.text = "+"
	_apply_blue_button_style(btn)
	btn.pressed.connect(func():
		if _run != null and _run.has_method("add_local_upgrade"):
			_run.call("add_local_upgrade", depth_index, id, 1)
	)

	row.add_child(name_label)
	row.add_child(lvl_label)
	row.add_child(btn)
	upgrades_box.add_child(row)

func _apply_blue_button_style(b: Button) -> void:
	if b == null:
		return

	b.custom_minimum_size = Vector2(44, 44)
	b.size_flags_horizontal = Control.SIZE_FILL

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.16, 0.95)
	sb.border_color = COLOR_BLUE
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6

	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("pressed", sb)

# -----------------------
# Button callbacks
# -----------------------
func _on_dive_pressed() -> void:
	_show_dive_confirmation()
	
func _show_dive_confirmation() -> void:
	# Remove existing popup if any
	if _dive_confirm_popup != null and is_instance_valid(_dive_confirm_popup):
		_dive_confirm_popup.queue_free()
	
	# Create CanvasLayer to ensure we're above EVERYTHING
	var canvas_layer := CanvasLayer.new()
	canvas_layer.name = "DiveConfirmLayer"
	canvas_layer.layer = 300
	_dive_confirm_popup = canvas_layer
	
	get_tree().current_scene.add_child(canvas_layer)
	
	# Dimmer background
	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.color = Color(0, 0, 0, 0.6)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas_layer.add_child(dimmer)
	
	# Click outside to cancel
	dimmer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_dive_confirmation()
	)
	
	# Center container
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas_layer.add_child(center)
	
	# Popup panel
	var panel := Panel.new()
	panel.name = "DiveConfirmPanel"
	panel.custom_minimum_size = Vector2(450, 220)
	center.add_child(panel)
	
	# Style the panel
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.98)
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	panel.add_theme_stylebox_override("panel", sb)
	
	# Content
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 25)
	margin.add_theme_constant_override("margin_right", 25)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 15)
	margin.add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = "Prepare to Dive?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	vbox.add_child(title)
	
	# Warning
	var warning := Label.new()
	warning.text = "You are about to dive to Depth %d.\nInstability will increase and current progress will be converted." % (depth_index + 1)
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD
	warning.add_theme_font_size_override("font_size", 15)
	vbox.add_child(warning)
	
	# Spacer
	vbox.add_child(Control.new())
	
	# Buttons container
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 25)
	vbox.add_child(hbox)
	
	# DIVE BUTTON - CRITICAL FIX
	var dive_btn := Button.new()
	dive_btn.name = "DiveConfirmButton"
	dive_btn.text = "Dive"
	dive_btn.custom_minimum_size = Vector2(130, 45)
	_apply_blue_button_style(dive_btn)
	
	dive_btn.pressed.connect(func():
		print("DIVE CONFIRMED - executing dive")
		
		# 1. EXECUTE DIVE
		var gm = get_tree().current_scene.find_child("GameManager", true, false)
		if gm != null and gm.has_method("do_dive"):
			gm.call("do_dive")
		
		# 2. CRITICAL: Explicitly refresh the panel immediately
		var bars_panel = get_tree().current_scene.find_child("DepthBarsPanel", true, false)  # Changed name
		var drc = get_node_or_null("/root/DepthRunController")
		if bars_panel != null and drc != null:  # Changed variable name here too
			var new_depth = drc.get("active_depth")
			print("Setting panel active depth to: ", new_depth)
			bars_panel.call("set_active_depth", int(new_depth))
			bars_panel.call("_apply_row_states")  # Force immediate refresh
		
		# 3. Close popup
		_close_dive_confirmation()
		set_details_open(false)
		request_close.emit(depth_index)
	)
	
	# CRITICAL: Must add the button to the scene!
	hbox.add_child(dive_btn)
	
	# CANCEL BUTTON
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(130, 45)
	_apply_blue_button_style(cancel_btn)
	cancel_btn.pressed.connect(_close_dive_confirmation)
	hbox.add_child(cancel_btn)
	
	canvas_layer.visible = true


func _close_dive_confirmation() -> void:
	if _dive_confirm_popup != null and is_instance_valid(_dive_confirm_popup):
		_dive_confirm_popup.queue_free()
	_dive_confirm_popup = null


func _proceed_with_dive() -> void:
	print("Proceeding with dive from depth: ", depth_index)
	
	# CRITICAL: Call GameManager FIRST, before we get freed by request_close
	var gm = get_tree().current_scene.find_child("GameManager", true, false)
	if gm != null and gm.has_method("do_dive"):
		print("Calling GameManager.do_dive()")
		gm.call("do_dive")
	else:
		push_error("GameManager.do_dive not found")
	
	# NOW close the popup and overlay (this frees this node)
	_close_dive_confirmation()
	set_details_open(false)
	request_close.emit(depth_index)
	
	# Small delay to let UI settle, then dive
	await get_tree().create_timer(0.05).timeout
	
	# FIX: Explicitly update the panel to show the new active depth
	await get_tree().create_timer(0.1).timeout  # Wait for dive to complete
	var drc := get_node_or_null("/root/DepthRunController")
	var panel = get_tree().current_scene.find_child("DepthBarsPanel", true, false)
	if drc != null and panel != null:
		var new_depth = drc.get("active_depth")
		if new_depth != null:
			print("Updating panel to new depth: ", new_depth)
			panel.call("set_active_depth", int(new_depth))
			# Also trigger a full row state refresh
			panel.call("_apply_row_states")

func _on_dive_confirmed() -> void:
	print("Dive confirmed button pressed")
	_proceed_with_dive()
		
func _on_close_pressed() -> void:
	request_close.emit(depth_index)

func _apply_expanded_opacity() -> void:
	# Row image strength
	if _row_bg != null:
		_row_bg.modulate = Color(1, 1, 1, 1.0) if _details_open else Color(1, 1, 1, 0.38)

	# Panel background opacity (blocks seeing through)
	var sb := get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var s := sb as StyleBoxFlat
		s.bg_color.a = 1.0 if _details_open else 0.30
		add_theme_stylebox_override("panel", s)

func _hide_extra_progress_bars() -> void:
	# If your Details tree contains any ProgressBars, hide them.
	# Keeps ONLY the main row progress_bar visible.
	var bars := find_children("", "ProgressBar", true, false)
	for n in bars:
		if n == progress_bar:
			continue
		var pb := n as ProgressBar
		pb.show_percentage = false
		pb.visible = false

func _add_upgrade_row_dynamic(id: String, data: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "UpgradeRow_%s" % id
	row.add_theme_constant_override("separation", 12)
	
	# NAME + DESCRIPTION
	var name_desc_hbox := HBoxContainer.new()
	name_desc_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_desc_hbox.add_theme_constant_override("separation", 12)
	name_desc_hbox.custom_minimum_size.x = 450
	
	# AUTO-BUY CHECKBOX - only show if unlocked for this depth
	var show_auto_buy := false
	var gm = get_tree().current_scene.find_child("GameManager", true, false)
	if gm != null:
		# Check array directly
		if depth_index in gm.auto_buy_unlocked_depths:
			show_auto_buy = true
			print("Auto-buy enabled for depth ", depth_index, " via array")
		
		# Debug output
		if gm.has_method("is_auto_buy_unlocked_for_depth"):
			var method_result = gm.call("is_auto_buy_unlocked_for_depth", depth_index)
			print("Depth ", depth_index, " auto_buy check: array=", depth_index in gm.auto_buy_unlocked_depths, " method=", method_result)

	if show_auto_buy:
		var auto_check := CheckBox.new()
		auto_check.name = "AutoCheck"
		auto_check.tooltip_text = "Auto-buy this upgrade when affordable"
		
		# FORCE UNCHECKED
		auto_check.button_pressed = false
		_auto_buy_enabled[id] = false
		
		auto_check.pressed.connect(func():
			var new_state := auto_check.button_pressed
			_auto_buy_enabled[id] = new_state
			print("CHECKBOX: ", id, " = ", new_state)  # Should only print when YOU click
		)
		
		row.add_child(auto_check)
	
	var name_label := Label.new()
	name_label.text = data.get("name", id.capitalize())
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	var desc_label := Label.new()
	desc_label.text = data.get("description", "")
	desc_label.add_theme_font_size_override("font_size", 15)
	
	# FIX: Darker text for Depth 1 (light background), lighter for others
	if depth_index == 1:
		desc_label.add_theme_color_override("font_color", Color(0.1, 0.12, 0.18, 1.0))  # Dark blue-black
	else:
		desc_label.add_theme_color_override("font_color", Color(0.75, 0.85, 0.95, 1.0))  # Light blue-white
	
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.max_lines_visible = 1
	desc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	name_desc_hbox.add_child(name_label)
	name_desc_hbox.add_child(desc_label)
	
	# Get upgrade data
	var lvl := int(_local_upgrades.get(id, 0))
	var max_lvl: int = data.get("max_level", 1)
	var base_cost: float = data.get("base_cost", 100.0)
	var growth: float = data.get("cost_growth", 1.5)
	
	# LEVEL LABEL
	var lvl_label := Label.new()
	lvl_label.name = "LevelLabel"
	if max_lvl >= 999999:
		lvl_label.text = "Lv %d" % lvl
	else:
		lvl_label.text = "Lv %d/%d" % [lvl, max_lvl]
	lvl_label.add_theme_font_size_override("font_size", 18)
	lvl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_label.custom_minimum_size.x = 90
	
	# COST LABEL (will be updated dynamically)
	var cost_label := Label.new()
	cost_label.name = "CostLabel"
	cost_label.add_theme_font_size_override("font_size", 16)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.custom_minimum_size.x = 140
	
	# BUTTON (will be updated dynamically)
	var btn := Button.new()
	btn.text = "+" if lvl < max_lvl else "MAX"
	_apply_blue_button_style(btn)
	btn.custom_minimum_size = Vector2(50, 50)
	
	# Store references for real-time updates
	_upgrade_ui_refs[id] = {
		"button": btn,
		"cost_label": cost_label,
		"lvl_label": lvl_label,
		"base_cost": base_cost,
		"growth": growth,
		"max_lvl": max_lvl,
		"row": row
	}
	
	# Initial update
	_update_upgrade_row_ui(id)
	
	# Button pressed logic
	btn.pressed.connect(func():
		_attempt_purchase(id, data)
	)
	
	row.add_child(name_desc_hbox)
	row.add_child(lvl_label)
	row.add_child(cost_label)
	row.add_child(btn)
	upgrades_box.add_child(row)

func _attempt_purchase(id: String, data: Dictionary) -> bool:
	var game_mgr := get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	if game_mgr == null:
		return false
	
	var current_lvl := int(_local_upgrades.get(id, 0))
	var max_lvl: int = data.get("max_level", 1)
	
	if current_lvl >= max_lvl:
		return false
	
	var base_cost: float = data.get("base_cost", 100.0)
	var growth: float = data.get("cost_growth", 1.5)
	var depth_multiplier := pow(float(depth_index), 2.5) * 3.0
	var effective_base := base_cost * depth_multiplier
	var current_cost := effective_base * pow(growth, current_lvl)
	
	if game_mgr.thoughts >= current_cost:
		game_mgr.thoughts -= current_cost
		
		if _run != null and _run.has_method("add_local_upgrade"):
			_run.call("add_local_upgrade", depth_index, id, 1)
		
		if game_mgr.has_method("_refresh_top_ui"):
			game_mgr._refresh_top_ui()
		return true
	return false
	
func _update_upgrade_row_ui(id: String) -> void:
	if not _upgrade_ui_refs.has(id):
		return
	
	var refs := _upgrade_ui_refs[id] as Dictionary
	var btn: Button = refs["button"]
	var cost_label: Label = refs["cost_label"]
	var lvl_label: Label = refs["lvl_label"]
	var base_cost: float = refs["base_cost"]
	var growth: float = refs["growth"]
	var max_lvl: int = refs["max_lvl"]
	
	var gm := get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	var current_thoughts := 0.0
	if gm != null:
		current_thoughts = gm.thoughts
	
	var lvl := int(_local_upgrades.get(id, 0))
	if max_lvl >= 999999:
		lvl_label.text = "Lv %d" % lvl
	else:
		lvl_label.text = "Lv %d/%d" % [lvl, max_lvl]
	
	if lvl >= max_lvl:
		btn.text = "MAX"
		btn.disabled = true
		cost_label.text = ""
		cost_label.modulate = Color(1, 1, 1)
	else:
		var depth_multiplier := pow(float(depth_index), 2.5) * 3.0  # Exponential scaling
		var effective_base := base_cost * depth_multiplier
		var cost := effective_base * pow(growth, lvl)
		var can_afford := current_thoughts >= cost
		
		btn.text = "+"
		btn.disabled = not can_afford
		cost_label.text = "%s Thoughts" % _fmt_num(cost)
		cost_label.modulate = Color(0.6, 0.6, 0.6) if not can_afford else Color(1, 1, 1)
	
	# DEBUG: Show effect of upgrade
	if id == "stabilize" and depth_index == 2:
		if lvl > 0:
			cost_label.text += " (-%d%% inst)" % (lvl * 5)  # Show -5% per level
			

func _process(_delta: float) -> void:
	# ABSOLUTE SAFETY: Don't run if no checkboxes should exist
	if not _details_open:
		return
	
	_apply_visuals()
	
	# Only process for active depth
	if _run != null:
		var active_depth = _run.get("active_depth")
		if active_depth != depth_index:
			return
	
	# Update cooldown
	if _auto_buy_cooldown > 0:
		_auto_buy_cooldown -= _delta
	
	if _details_open and upgrades_box != null and upgrades_box.visible:
		# Update UI states
		for id in _upgrade_ui_refs.keys():
			_update_upgrade_row_ui(id)
		
		# NUCLEAR AUTO-BUY: Only buy if explicitly enabled in dictionary
		if _auto_buy_cooldown <= 0:
			var game_mgr := get_tree().current_scene.find_child("GameManager", true, false) as GameManager
			if game_mgr != null:
				# Debug: Show current states
				if Engine.get_process_frames() % 300 == 0:  # Every 5 seconds
					print("Depth ", depth_index, " auto-buy states: ", _auto_buy_enabled)
				
				# Iterate through ALL upgrades but only buy checked ones
				for id in _upgrade_ui_refs.keys():
					# ABSOLUTE CHECK: Must exist AND be true
					if _auto_buy_enabled.has(id) and _auto_buy_enabled[id] == true:
						var current_lvl := int(_local_upgrades.get(id, 0))
						
						if _run != null and _run.has_method("get_run_upgrade_data"):
							var upg_data: Dictionary = _run.call("get_run_upgrade_data", depth_index, id)
							var max_lvl: int = upg_data.get("max_level", 1)
							
							if current_lvl < max_lvl:
								# Check cost
								var base_cost: float = upg_data.get("base_cost", 100.0)
								var growth: float = upg_data.get("cost_growth", 1.5)
								var depth_multiplier := pow(float(depth_index), 2.5) * 3.0
								var cost := (base_cost * depth_multiplier) * pow(growth, current_lvl)
								
								if game_mgr.thoughts >= cost:
									# BUY IT
									if _attempt_purchase(id, upg_data):
										_auto_buy_cooldown = AUTO_BUY_DELAY
										print("AUTO-BUY: ", id, " level ", current_lvl + 1)
										break  # Only one per frame
								else:
									# Can't afford, skip
									continue

func _refresh_upgrade_row(id: String, lvl_label: Label, btn: Button, max_lvl: int) -> void:
	var current_lvl := int(_local_upgrades.get(id, 0))
	lvl_label.text = "Lv %d/%d" % [current_lvl, max_lvl]
	if current_lvl >= max_lvl:
		btn.text = "MAX"
		btn.disabled = true

func _arrange_dive_close_buttons() -> void:
	if dive_button == null or close_button == null:
		return
	
	var parent = dive_button.get_parent()
	if parent == null:
		return
	
	# Ensure parent fills the width
	parent.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Order: X first, then spacer, then Dive (right-aligned)
	parent.move_child(close_button, 0)
	
	# Check if we already added a spacer
	var spacer = parent.get_node_or_null("ButtonSpacer")
	if spacer == null:
		spacer = Control.new()
		spacer.name = "ButtonSpacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(spacer)
		parent.move_child(spacer, 1)
	
	if dive_button.get_index() != 2:
		parent.move_child(dive_button, 2)
	
	# X button: Small, anchored left
	close_button.custom_minimum_size = Vector2(50, 44)
	close_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	close_button.size_flags_stretch_ratio = 0
	close_button.text = "X"
	
	# Dive button: Wide, anchored right (near the + buttons)
	dive_button.custom_minimum_size = Vector2(400, 44)
	dive_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	dive_button.size_flags_stretch_ratio = 0
	dive_button.text = "Dive"
