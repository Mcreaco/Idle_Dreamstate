# res://UI/DepthBarRow.gd
extends PanelContainer
class_name DepthBarRow

signal clicked_depth(depth_index: int)
signal request_dive(depth_index: int)
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

var depth_index: int = 1
var _active: bool = false
var _frozen: bool = false
var _locked: bool = false
var _details_open: bool = false
var _overlay_mode: bool = false

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

func block_row_clicks(ms: int = 200) -> void:
	_block_click_until_msec = Time.get_ticks_msec() + ms


# basename_lower -> full_path (keeps actual case)
var _bg_map: Dictionary = {}

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



func set_data(d: Dictionary) -> void:
	_data = d
	_apply_visuals()

func set_local_upgrades(d: Dictionary) -> void:
	_local_upgrades = d
	if _details_open:
		_build_upgrades_ui()

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

# -----------------------
# Layout
# -----------------------
func _build_layout_bar_then_bottom_text() -> void:
	# Prevent duplicate rebuild
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
# -----------------------
# Visuals
# -----------------------
func _apply_visuals() -> void:
	# When expanded in overlay, NEVER dim the whole row (keeps PNG visible)
	if _overlay_mode or _details_open:
		modulate = Color(1, 1, 1, 1)
	else:
		if _locked:
			modulate = Color(1, 1, 1, 0.45)
		elif _frozen:
			modulate = Color(1, 1, 1, 0.70)
		else:
			modulate = Color(1, 1, 1, 1.0)

	# NEW: Calculate upgrade completion % instead of depth progress
	var completion_pct := _get_upgrade_completion_percent()
	if progress_bar != null:
		progress_bar.value = completion_pct
		progress_bar.show_percentage = false

	if percent_label != null and progress_bar != null:
		percent_label.text = "%d%%" % int(round(progress_bar.value))

	if _title_label != null:
		_title_label.text = _depth_title_text()

	if _reward_label != null:
		var mem := float(_data.get("memories", 0.0))
		var cry := float(_data.get("crystals", 0.0))
		_reward_label.text = "+%.1f Mem  +%.1f %s" % [mem, cry, _crystal_name()]

	if dive_button != null:
		var can := false
		if _run != null and _run.has_method("can_dive"):
			can = bool(_run.call("can_dive"))
		dive_button.disabled = not (_active and can)

	# Background strength (ONLY ONCE — fixes your "double modulate" bug)
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

	# IMPORTANT:
	# In overlay/details, the panel must be transparent so the PNG behind can show.
	sb.bg_color = Color(0, 0, 0, 0.0) if (_overlay_mode or _details_open) else Color(0.06, 0.08, 0.12, 0.16)

	# Keep the blue border ALWAYS (so border wraps the PNG in overlay too)
	sb.border_color = COLOR_BLUE
	sb.border_width_left = ROW_BORDER_INSET
	sb.border_width_top = ROW_BORDER_INSET
	sb.border_width_right = ROW_BORDER_INSET
	sb.border_width_bottom = ROW_BORDER_INSET

	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10

	add_theme_stylebox_override("panel", sb)


func _style_progress_bar() -> void:
	if progress_bar == null:
		return

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
	for c in upgrades_box.get_children():
		c.queue_free()

	var title := Label.new()
	title.text = "Run Upgrades (Depth %d)" % depth_index
	upgrades_box.add_child(title)

	_add_upgrade_row("progress_speed", "Progress Speed")
	_add_upgrade_row("memories_gain", "Memories Gain")
	_add_upgrade_row("crystals_gain", "Crystals Gain")

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
	request_dive.emit(depth_index)

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

func _process(_delta: float) -> void:
	_apply_visuals()  # Force refresh every frame
