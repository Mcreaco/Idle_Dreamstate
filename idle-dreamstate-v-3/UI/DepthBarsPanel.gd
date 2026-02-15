# res://UI/DepthBarsPanel.gd
extends Control
class_name DepthBarsPanel

@export var depth_row_scene: PackedScene
@export var big_depth_index: int = 15
@export var bars_margin_left: float = 0
@export var bars_margin_right: float = 220.0 # leaves room for Settings/Shop
@export var bars_margin_top: float = 60
@export var bars_margin_bottom: float = 0.0 # keeps bottom buttons safe
@export var safe_top: int = 74        # keeps off the top HUD bar
@export var safe_bottom: int = 110    # keeps off the bottom buttons bar
@export var safe_right: int = 240     # keeps off Settings/Shop
@export var safe_left: int = 240      # match right to keep bars centered

@onready var left_col: VBoxContainer = $BarsRoot/BarsGrid/LeftColumn
@onready var right_col: VBoxContainer = $BarsRoot/BarsGrid/RightColumn
@onready var depth15_slot: Control = $BarsRoot/Depth15Slot

var active_depth: int = 1
var max_unlocked_depth: int = 1

var _rows: Dictionary = {}          # int -> DepthBarRow (Node)
var _expanded_depth: int = -1
var _depth_run: Node = null         # Autoload instance (/root/DepthRunController)

# ---- overlay plumbing (center popup) ----
var _overlay: Control = null
var _overlay_slot: VBoxContainer = null
var _overlay_dimmer: ColorRect = null
var _overlay_frame: PanelContainer = null
var _overlay_row: Node = null
var _overlay_prev_parent: Node = null
var _overlay_prev_index: int = -1
var _overlay_placeholder: Control = null
var _ignore_row_clicks_until_msec: int = 0
# ---- cached row state (so overlay clone shows identical data) ----
var _row_data_cache: Dictionary = {}            # depth -> Dictionary
var _row_local_upgrades_cache: Dictionary = {}  # depth -> Dictionary
var _row_frozen_upgrades_cache: Dictionary = {} # depth -> Dictionary


func _apply_bars_margins_force() -> void:
	var bars_root := $BarsRoot as Control
	if bars_root == null:
		push_warning("DepthBarsPanel: BarsRoot not found.")
		return

	# Apply AFTER containers finish layout
	await get_tree().process_frame

	# If BarsRoot is controlled by a Container, offsets won't stick.
	# So we wrap it in a MarginContainer at runtime (once) and drive margins there.
	var p := bars_root.get_parent()
	if p is MarginContainer:
		var mc := p as MarginContainer
		mc.add_theme_constant_override("margin_left", int(bars_margin_left))
		mc.add_theme_constant_override("margin_right", int(bars_margin_right))
		mc.add_theme_constant_override("margin_top", int(bars_margin_top))
		mc.add_theme_constant_override("margin_bottom", int(bars_margin_bottom))
		return

	# Create wrapper and reparent BarsRoot into it
	var wrapper := MarginContainer.new()
	wrapper.name = "BarsRootWrap"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Reparent
	if p != null:
		var idx := p.get_children().find(bars_root)
		p.remove_child(bars_root)
		p.add_child(wrapper)
		if idx >= 0:
			p.move_child(wrapper, idx)
	wrapper.add_child(bars_root)

	# Make BarsRoot fill wrapper
	bars_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_root.offset_left = 0
	bars_root.offset_right = 0
	bars_root.offset_top = 0
	bars_root.offset_bottom = 0

	# Apply margins
	wrapper.add_theme_constant_override("margin_left", int(bars_margin_left))
	wrapper.add_theme_constant_override("margin_right", int(bars_margin_right))
	wrapper.add_theme_constant_override("margin_top", int(bars_margin_top))
	wrapper.add_theme_constant_override("margin_bottom", int(bars_margin_bottom))
	
func _ready() -> void:
	_depth_run = get_node_or_null("/root/DepthRunController")
	_build_rows()
	 # Force refresh after a brief delay to ensure controller has loaded data
	call_deferred("_refresh_all_rows")
	_apply_bars_root_rect()
	_ensure_overlay()
	call_deferred("_apply_safe_margins_centered")
	if _depth_run != null and _depth_run.has_method("bind_panel"):
		_depth_run.call("bind_panel", self)
	left_col.add_theme_constant_override("separation", 12)
	right_col.add_theme_constant_override("separation", 12)

	left_col.custom_minimum_size.x = 780
	right_col.custom_minimum_size.x = 780

	_ensure_overlay()
	if _depth_run != null and _depth_run.has_method("bind_panel"):
		_depth_run.call("bind_panel", self)

# ---- FIX: move bars DOWN so they don't overlap top HUD ----
	var root := $BarsRoot
	if root != null:
		root.offset_top += bars_margin_top
		root.offset_right -= bars_margin_right
		
func _refresh_all_rows() -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return
	
	for i in range(1, 16):
		var local_upgs = drc.get("local_upgrades")
		if local_upgs is Dictionary and local_upgs.has(i):
			set_active_local_upgrades(i, local_upgs[i])
			
func _ensure_overlay() -> void:
	if _overlay != null:
		return

	# Always above HUD
	var cl := CanvasLayer.new()
	cl.name = "ExpandOverlayLayer"
	cl.layer = 200
	add_child(cl)

	_overlay = Control.new()
	_overlay.name = "ExpandOverlay"
	_overlay.visible = false
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	cl.add_child(_overlay)

	# IMPORTANT: CanvasLayer is not a Control, so anchors don't size children.
	# We must size the overlay manually to the viewport.
	_overlay.top_level = true
	_overlay.position = Vector2.ZERO
	_overlay.size = get_viewport().get_visible_rect().size

	# Keep overlay sized when window changes
	if not get_viewport().size_changed.is_connected(Callable(self, "_on_viewport_resized")):
		get_viewport().size_changed.connect(Callable(self, "_on_viewport_resized"))

	_overlay_dimmer = ColorRect.new()
	_overlay_dimmer.name = "Dimmer"
	_overlay_dimmer.color = Color(0.02, 0.04, 0.08, 0.18)
	_overlay_dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(_overlay_dimmer)
	_overlay_dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)

	_overlay_dimmer.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_overlay()
	)

	var center := CenterContainer.new()
	center.name = "Center"
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(center)

	_overlay_frame = PanelContainer.new()
	_overlay_frame.name = "Frame"
	center.add_child(_overlay_frame)

	_overlay_frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_overlay_frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_overlay_frame.custom_minimum_size = Vector2(1200, 340)

	_style_overlay_frame()

	var pad := MarginContainer.new()
	pad.name = "Pad"
	pad.add_theme_constant_override("margin_left", 0)
	pad.add_theme_constant_override("margin_right", 0)
	pad.add_theme_constant_override("margin_top", 0)
	pad.add_theme_constant_override("margin_bottom", 0)
	_overlay_frame.add_child(pad)

	_overlay_slot = VBoxContainer.new()
	_overlay_slot.name = "Slot"
	_overlay_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_overlay_slot.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(_overlay_slot)



func _build_rows() -> void:
		# Check if containers are ready
	if left_col == null or right_col == null or depth15_slot == null:
		push_warning("DepthBarsPanel: Containers not ready, deferring _build_rows")
		call_deferred("_build_rows")
		return

	_clear_container(left_col)
	_clear_container(right_col)
	_clear_container(depth15_slot)
	_rows.clear()
	_expanded_depth = -1

	if depth_row_scene == null:
		push_warning("DepthBarsPanel: depth_row_scene not set (assign DepthBarRow.tscn in inspector).")
		return

	for d in range(1, 16):
		var row := depth_row_scene.instantiate()
		row.name = "DepthBarRow_%d" % d
		_rows[d] = row
		_wire_row(row, d)

		if d == big_depth_index:
			depth15_slot.add_child(row)
		elif d <= 7:
			left_col.add_child(row)
		else:
			right_col.add_child(row)

	_apply_row_states()

func _wire_row(row: Node, depth_index: int) -> void:
	if row.has_method("set_depth_index"):
		row.call_deferred("set_depth_index", depth_index)

	if row.has_signal("clicked_depth") and not row.clicked_depth.is_connected(_on_row_clicked_depth):
		row.clicked_depth.connect(_on_row_clicked_depth)

	if row.has_signal("request_dive") and not row.request_dive.is_connected(_on_row_request_dive):
		row.request_dive.connect(_on_row_request_dive)

	if row.has_signal("request_close") and not row.request_close.is_connected(_on_row_request_close):
		row.request_close.connect(_on_row_request_close)

func _apply_row_states() -> void:
	for depth_index in range(1, 16):
		var row: Node = _rows.get(depth_index, null)
		if row == null:
			continue

		var locked: bool = depth_index > max_unlocked_depth
		var frozen: bool = depth_index < active_depth
		var is_active: bool = depth_index == active_depth

		if row.has_method("set_locked"):
			row.call("set_locked", locked)
		if row.has_method("set_frozen"):
			row.call("set_frozen", frozen)
		if row.has_method("set_active"):
			row.call("set_active", is_active)

# -------------------------
# Row callbacks
# -------------------------
func _on_row_clicked_depth(depth_index: int) -> void:
	# Debounce to prevent instant re-open after closing
	if Time.get_ticks_msec() < _ignore_row_clicks_until_msec:
		return

	if depth_index != active_depth:
		return

	if _expanded_depth == depth_index:
		_close_overlay()
	else:
		_open_overlay(depth_index)


func _on_row_request_close(_depth_index: int) -> void:
	_close_overlay()

func _on_row_request_dive(_depth_index: int) -> void:
	if _depth_run != null and _depth_run.has_method("dive"):
		_depth_run.call("dive")
	_close_overlay()

# -------------------------
# Center overlay logic
# -------------------------
func _open_overlay(depth_index: int) -> void:
	_close_overlay()

	if depth_row_scene == null:
		return

	_expanded_depth = depth_index

	# Create a CLONE row for the overlay (do NOT move the real row)
	var overlay_row := depth_row_scene.instantiate()
	overlay_row.name = "OverlayDepthRow_%d" % depth_index
	_overlay_slot.add_child(overlay_row)
	_overlay_row = overlay_row

	# Get FRESH data from controller, not cache
	var drc := get_node_or_null("/root/DepthRunController")
	var fresh_data: Dictionary = {"progress": 0.0, "memories": 0.0, "crystals": 0.0}
	if drc != null:
		var run_data: Array = drc.get("run") as Array
		if run_data != null and depth_index >= 1 and depth_index <= run_data.size():
			fresh_data = run_data[depth_index - 1].duplicate(true)

	# Apply index + state
	var locked: bool = depth_index > max_unlocked_depth
	var frozen: bool = depth_index < active_depth
	var is_active: bool = depth_index == active_depth

	if overlay_row.has_method("set_depth_index"):
		overlay_row.call("set_depth_index", depth_index)
	if overlay_row.has_method("set_locked"):
		overlay_row.call("set_locked", locked)
	if overlay_row.has_method("set_frozen"):
		overlay_row.call("set_frozen", frozen)
	if overlay_row.has_method("set_active"):
		overlay_row.call("set_active", is_active)

	# Use FRESH data, not cached
	if overlay_row.has_method("set_data"):
		overlay_row.call("set_data", fresh_data)

	# Copy cached upgrades (these don't change as often)
	if _row_local_upgrades_cache.has(depth_index) and overlay_row.has_method("set_local_upgrades"):
		overlay_row.call("set_local_upgrades", _row_local_upgrades_cache[depth_index])
	if _row_frozen_upgrades_cache.has(depth_index) and overlay_row.has_method("set_frozen_upgrades"):
		overlay_row.call("set_frozen_upgrades", _row_frozen_upgrades_cache[depth_index])

	# Overlay presentation
	if overlay_row.has_method("set_overlay_mode"):
		overlay_row.call("set_overlay_mode", true)
	if overlay_row.has_method("set_details_open"):
		overlay_row.call("set_details_open", true)

	# Wire overlay buttons
	if overlay_row.has_signal("request_close") and not overlay_row.request_close.is_connected(_on_row_request_close):
		overlay_row.request_close.connect(_on_row_request_close)
	if overlay_row.has_signal("request_dive") and not overlay_row.request_dive.is_connected(_on_row_request_dive):
		overlay_row.request_dive.connect(_on_row_request_dive)

	_overlay.visible = true


func _close_overlay() -> void:
	if _overlay == null:
		return

	_overlay.visible = false
	_expanded_depth = -1

	if _overlay_row != null and is_instance_valid(_overlay_row):
		_overlay_row.queue_free()
	_overlay_row = null



func _clear_placeholder() -> void:
	if _overlay_placeholder != null and is_instance_valid(_overlay_placeholder):
		var p := _overlay_placeholder.get_parent()
		if p != null:
			p.remove_child(_overlay_placeholder)
		_overlay_placeholder.queue_free()
	_overlay_placeholder = null

# -------------------------
# Public API (called by controller)
# -------------------------
func set_active_depth(d: int) -> void:
	# Use a local constant or get from controller
	var max_depth_val: int = 15
	var drc := get_node_or_null("/root/DepthRunController")
	if drc != null and drc.get("max_depth") != null:
		max_depth_val = int(drc.get("max_depth"))
	
	active_depth = clampi(d, 1, max_depth_val)
	
	# If you need to emit a signal, declare it at the top of the script:
	# signal active_depth_changed(new_depth: int)
	# Then: active_depth_changed.emit(active_depth)
	
	_apply_row_states()

func set_max_unlocked_depth(depth_index: int) -> void:
	max_unlocked_depth = clamp(depth_index, 1, 15)
	_apply_row_states()

func set_row_data(depth_index: int, data: Dictionary) -> void:
	# Always update cache with latest data
	_row_data_cache[depth_index] = data.duplicate(true)
	
	var row: Node = _rows.get(depth_index, null)
	if row == null:
		return
	if row.has_method("set_data"):
		row.call("set_data", data)


func request_refresh_details(depth_index: int) -> void:
	var row: Node = _rows.get(depth_index, null)
	if row != null and row.has_method("refresh_details"):
		row.call("refresh_details")

func set_row_frozen_upgrades(depth_index: int, upgrades: Dictionary) -> void:
	_row_frozen_upgrades_cache[depth_index] = upgrades

	var row: Node = _rows.get(depth_index, null)
	if row != null and row.has_method("set_frozen_upgrades"):
		row.call("set_frozen_upgrades", upgrades)

	if _overlay_row != null and _expanded_depth == depth_index and _overlay_row.has_method("set_frozen_upgrades"):
		_overlay_row.call("set_frozen_upgrades", upgrades)

func set_active_local_upgrades(depth_index: int, upgrades: Dictionary) -> void:
	_row_local_upgrades_cache[depth_index] = upgrades

	var row: Node = _rows.get(depth_index, null)
	if row != null and row.has_method("set_local_upgrades"):
		row.call("set_local_upgrades", upgrades)

	if _overlay_row != null and _expanded_depth == depth_index and _overlay_row.has_method("set_local_upgrades"):
		_overlay_row.call("set_local_upgrades", upgrades)


# -------------------------
# Utils
# -------------------------
func _clear_container(n: Node) -> void:
	if n == null:
		return
	for c in n.get_children():
		c.queue_free()

# -------------------------
# Wake + Dive (FINAL, Godot 4 safe)
# -------------------------

func _get_run_active_depth() -> int:
	var run := get_node_or_null("/root/DepthRunController")
	if run == null:
		return 1
	var v = run.get("active_depth") # Godot 4: get() takes 1 arg only
	return int(v) if v != null else 1


func _open_meta_to_depth(depth_index: int) -> void:
	# IMPORTANT: your meta overlay node should be named "MetaPanel" in the scene
	var meta := get_tree().current_scene.find_child("MetaPanel", true, false)
	if meta == null:
		push_warning("DepthBarsPanel: Could not find node named 'MetaPanel' in current scene.")
		return

	if meta.has_method("open_to_depth"):
		meta.call("open_to_depth", depth_index)
	elif meta.has_method("open"):
		meta.call("open")
	else:
		meta.visible = true


# -------------------------
# Utils (FIXED)
# -------------------------

func on_wake_pressed() -> void:
	# Always use the PrestigePanel confirmation flow via GameManager.
	var gm := get_tree().current_scene.find_child("GameManager", true, false)
	if gm != null and gm.has_method("_on_wake_pressed"):
		gm.call("_on_wake_pressed")
	else:
		push_warning("DepthBarsPanel: GameManager not found or missing _on_wake_pressed().")


func on_dive_pressed() -> void:
	var run := get_node_or_null("/root/DepthRunController")
	if run == null:
		push_warning("DepthBarsPanel: /root/DepthRunController not found.")
		return

	# Godot 4: get() has NO default param, and avoid Variant inference warnings-as-errors.
	var v_depth: Variant = run.get("active_depth")
	var d: int = 1
	if typeof(v_depth) == TYPE_INT:
		d = int(v_depth)

	# Gate: next depth requires unlock_next_bought[d] in DepthMetaSystem
	var meta: Node = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if meta != null:
		var v_unlocks: Variant = meta.get("unlock_next_bought")
		if typeof(v_unlocks) == TYPE_DICTIONARY:
			var unlocks: Dictionary = v_unlocks
			var bought: bool = false
			if unlocks.has(d):
				bought = int(unlocks[d]) != 0

			if not bought:
				var meta_ui := get_tree().current_scene.find_child("MetaPanel", true, false)
				if meta_ui != null and meta_ui.has_method("open_to_depth"):
					meta_ui.call("open_to_depth", d)
				elif meta_ui != null and meta_ui.has_method("open"):
					meta_ui.call("open")
				return

	# Perform dive in the DepthRunController
	if run.has_method("dive_next_depth"):
		run.call("dive_next_depth")
	else:
		run.set("active_depth", d + 1)

	# Read new depth safely
	var v_new_depth: Variant = run.get("active_depth")
	var new_d: int = d + 1
	if typeof(v_new_depth) == TYPE_INT:
		new_d = int(v_new_depth)

	# Camera snap (optional)
	var cam := get_tree().current_scene.find_child("Camera3D", true, false)
	if cam != null and cam.has_method("snap_to_depth"):
		cam.call("snap_to_depth", new_d)

	# Sound (optional)
	var gm := get_tree().current_scene.find_child("GameManager", true, false)
	if gm != null and gm.get("sound_system") != null:
		gm.sound_system.play_dive()

func _style_overlay_frame() -> void:
	if _overlay_frame == null:
		return

	var sb := StyleBoxFlat.new()
	# No extra frame border (this was the "outside pointless border")
	sb.bg_color = Color(0, 0, 0, 0.0)
	sb.border_width_left = 0
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0

	# Keep rounded corners so clicks feel nice, but no visible frame
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14

	_overlay_frame.add_theme_stylebox_override("panel", sb)



func _style_overlay_dimmer() -> void:
	if _overlay_dimmer == null:
		return
	# Almost opaque dark navy (blocks the underlying 0% ghosts without going pure black)
	_overlay_dimmer.color = Color(0.02, 0.03, 0.05, 0.94)


func _apply_bars_root_rect() -> void:
	var root := $BarsRoot as Control
	if root == null:
		return

	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = bars_margin_left
	root.offset_right = -bars_margin_right
	root.offset_top = bars_margin_top
	root.offset_bottom = -bars_margin_bottom

func _apply_safe_margins_centered() -> void:
	var bars_root := $BarsRoot as Control
	if bars_root == null:
		push_warning("DepthBarsPanel: BarsRoot not found.")
		return

	# Let containers finish their layout first
	await get_tree().process_frame

	# If already wrapped, just update margins
	var parent := bars_root.get_parent()
	if parent is MarginContainer:
		var mc := parent as MarginContainer
		mc.add_theme_constant_override("margin_top", safe_top)
		mc.add_theme_constant_override("margin_bottom", safe_bottom)
		mc.add_theme_constant_override("margin_left", safe_left)
		mc.add_theme_constant_override("margin_right", safe_right)
		return

	# Wrap BarsRoot so margins can't be overridden by Containers
	var p := parent
	var idx := -1
	if p != null:
		idx = p.get_children().find(bars_root)

	var bars_wrap := MarginContainer.new()
	bars_wrap.name = "BarsRootWrap"
	bars_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	p.remove_child(bars_root)
	p.add_child(bars_wrap)
	if idx >= 0:
		p.move_child(bars_wrap, idx)

	bars_wrap.add_child(bars_root)

	# apply margins on bars_wrap (not bars_root!)
	bars_wrap.add_theme_constant_override("margin_top", safe_top)
	bars_wrap.add_theme_constant_override("margin_bottom", safe_bottom)
	bars_wrap.add_theme_constant_override("margin_left", safe_left)
	bars_wrap.add_theme_constant_override("margin_right", safe_right)


	# BarsRoot fills the wrapper
	bars_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	bars_root.offset_left = 0
	bars_root.offset_right = 0
	bars_root.offset_top = 0
	bars_root.offset_bottom = 0

func _on_viewport_resized() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.position = Vector2.ZERO
		_overlay.size = get_viewport().get_visible_rect().size

func _restore_row_after_overlay(row: Node) -> void:
	if _overlay_slot != null and is_instance_valid(_overlay_slot) and row.get_parent() == _overlay_slot:
		_overlay_slot.remove_child(row)

	if _overlay_prev_parent != null and is_instance_valid(_overlay_prev_parent):
		_overlay_prev_parent.add_child(row)
		if _overlay_prev_index >= 0:
			_overlay_prev_parent.move_child(row, _overlay_prev_index)

	_clear_placeholder()
	_overlay_prev_parent = null
	_overlay_prev_index = -1

func clear_all_row_data() -> void:
	_row_data_cache.clear()
	_row_local_upgrades_cache.clear()
	_row_frozen_upgrades_cache.clear()
	
	# Reset all row displays to 0
	for depth_index in range(1, 16):
		var empty_data: Dictionary = {"progress": 0.0, "memories": 0.0, "crystals": 0.0}
		_row_data_cache[depth_index] = empty_data
		
		var row: Node = _rows.get(depth_index, null)
		if row == null:
			continue
		
		# After wake: depth 1 is active, all others are locked (not visited this run)
		if depth_index == 1:
			if row.has_method("set_active"):
				row.call("set_active", true)
			if row.has_method("set_frozen"):
				row.call("set_frozen", false)
			if row.has_method("set_locked"):
				row.call("set_locked", false)
		else:
			# NOT visited this run - locked, not frozen
			if row.has_method("set_active"):
				row.call("set_active", false)
			if row.has_method("set_frozen"):
				row.call("set_frozen", false)  # IMPORTANT: locked, not frozen
			if row.has_method("set_locked"):
				row.call("set_locked", true)
		
		# Force data update with zeros
		if row.has_method("set_data"):
			row.call("set_data", empty_data)

func _process(_delta: float) -> void:
	# Update overlay if open
	if _overlay != null and _overlay.visible and _expanded_depth > 0 and _overlay_row != null:
		# Get fresh data from controller
		var drc := get_node_or_null("/root/DepthRunController")
		if drc != null:
			var run_data: Array = drc.get("run") as Array
			if run_data != null and _expanded_depth >= 1 and _expanded_depth <= run_data.size():
				var fresh_data: Dictionary = run_data[_expanded_depth - 1]
				if _overlay_row.has_method("set_data"):
					_overlay_row.call("set_data", fresh_data)
