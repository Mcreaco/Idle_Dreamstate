extends Control
class_name MetaPanelController

@export var max_depth_reached: int = 1
@export var abyss_unlocked: bool = false

var tab_perm: Button
var tab_depth: Button
var tab_abyss: Button


var page_perm: Control
var page_depth: Control
var page_abyss: Control

var depth_tabs: Control
var depth_pages: Control

var dim: Control
var close_btn: Button

var depth_meta_system: DepthMetaSystem
var currency_summary: Node # optional, if you have one

var _current_meta: String = "perm"
var _current_depth: int = 1
var _styled_top_tabs := false
var _styled_depth_tabs := false

var currency_labels: Array[Label] = []  # Store references to update later
var depth_upgrade_rows: Array = []  # Store row references

func _ready() -> void:
	visible = false
	call_deferred("_late_bind")
	
	# Connect close button
	close_btn = find_child("CloseButton", true, false)
	if close_btn and not close_btn.pressed.is_connected(_on_close_button_pressed):
		close_btn.pressed.connect(_on_close_button_pressed)

func _on_close_button_pressed() -> void:
	# Notify tutorial that close button was clicked
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("CloseButton")
	
	# ... your existing close panel code ...
	visible = false  # or however you normally close it
	
func _late_bind() -> void:
	depth_meta_system = get_tree().current_scene.find_child("DepthMetaSystem", true, false) as DepthMetaSystem

	tab_perm = find_child("TabPerm", true, false) as Button
	tab_depth = find_child("TabDepth", true, false) as Button
	tab_abyss = find_child("TabAbyss", true, false) as Button

	page_perm = find_child("PermPage", true, false) as Control
	page_depth = find_child("DepthPage", true, false) as Control
	page_abyss = find_child("AbyssPage", true, false) as Control

	dim = find_child("Dim", true, false) as Control
	close_btn = find_child("CloseButton", true, false) as Button

	depth_tabs = null
	depth_pages = null
	if page_depth != null:
		depth_tabs = page_depth.find_child("DepthTabs", true, false) as Control
		depth_pages = page_depth.find_child("DepthPages", true, false) as Control
		currency_summary = page_depth.find_child("CurrencySummaryVBox", true, false)

	_connect_top_tab(tab_perm, "perm")
	_connect_top_tab(tab_depth, "depth")
	_connect_top_tab(tab_abyss, "abyss")

	if dim != null:
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		if not dim.gui_input.is_connected(Callable(self, "_on_dim_gui_input")):
			dim.gui_input.connect(Callable(self, "_on_dim_gui_input"))

	if close_btn != null:
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if not close_btn.pressed.is_connected(Callable(self, "close")):
			close_btn.pressed.connect(Callable(self, "close"))

	_fix_stacking()
	
	# CRITICAL: Find and setup all upgrade rows FIRST
	_find_and_setup_upgrade_rows()
	_wrap_upgrade_rows_in_scroll()
	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)
	_style_top_tabs()
	_style_perm_panel()
	_style_close_button()
	_style_currency_summary()
	_update_currency_display()
	_refresh_all_rows()

func _style_currency_summary() -> void:
	if currency_summary == null:
		return
	
	# Clear old
	currency_labels.clear()
	for child in currency_summary.get_children():
		child.queue_free()
	
	# Ensure it's a PanelContainer with border
	if not currency_summary is PanelContainer:
		var wrapper := PanelContainer.new()
		wrapper.name = "CurrencySummaryPanel"
		var parent = currency_summary.get_parent()
		parent.remove_child(currency_summary)
		wrapper.add_child(currency_summary)
		parent.add_child(wrapper)
		currency_summary = wrapper
	
	# Add border style
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	sb.border_color = Color(0.5, 0.6, 0.9, 0.6)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	currency_summary.add_theme_stylebox_override("panel", sb)
	
	# Position at bottom-left (or adjust as needed)
	currency_summary.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	currency_summary.custom_minimum_size = Vector2(800, 140)
	
	# Create grid
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	currency_summary.add_child(grid)
	
	# Create labels and store references
	for i in range(1, 16):
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 4)
		
		var name_lbl := Label.new()
		name_lbl.text = DepthMetaSystem.get_depth_currency_name(i) + ":"
		name_lbl.add_theme_font_size_override("font_size", 16)
		hbox.add_child(name_lbl)
		
		var val_lbl := Label.new()
		val_lbl.add_theme_font_size_override("font_size", 16)
		val_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		hbox.add_child(val_lbl)
		currency_labels.append(val_lbl)  # Store reference!
		
		grid.add_child(hbox)
	
	# Update values immediately
	_update_currency_display()

func _fix_stacking() -> void:
	# Godot 4: ColorRect doesn't have move_to_back().
	# Ensure dim is the FIRST child (behind), and everything else is above.
	if dim == null:
		return
	var p := dim.get_parent()
	if p != null:
		p.move_child(dim, 0)

	# Also prevent hidden pages from blocking input (this was causing “perm buttons don’t work”)
	if page_perm != null and not page_perm.visible:
		page_perm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page_depth != null and not page_depth.visible:
		page_depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page_abyss != null and not page_abyss.visible:
		page_abyss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
func _find_and_setup_upgrade_rows() -> void:
	# Find ALL DepthUpgradeRow nodes in the entire panel
	depth_upgrade_rows = find_children("*", "DepthUpgradeRow", true, false)
	print("Found ", depth_upgrade_rows.size(), " upgrade rows")
	
	for row in depth_upgrade_rows:
		row.depth_meta = depth_meta_system
		row.gm = get_tree().current_scene.find_child("GameManager", true, false)
		
		# CONNECT the buy signal if it exists
		if row.has_signal("upgrade_bought"):
			if not row.is_connected("upgrade_bought", Callable(self, "_on_upgrade_bought")):
				row.connect("upgrade_bought", Callable(self, "_on_upgrade_bought"))
		
		# Force refresh so buttons update
		if row.has_method("_refresh"):
			row.call_deferred("_refresh")
			
func _wrap_upgrade_rows_in_scroll() -> void:
	for i in range(1, 16):
		var page := depth_pages.get_node_or_null("DepthPage%d" % i) as Control
		if page == null:
			continue
		
		var upgrades_vbox := page.find_child("UpgradesVBox", true, false) as VBoxContainer
		if upgrades_vbox == null:
			continue
		
		if upgrades_vbox.get_parent() is ScrollContainer:
			continue
		
		var parent := upgrades_vbox.get_parent()
		
		# Create ScrollContainer
		var scroll := ScrollContainer.new()
		scroll.name = "UpgradesScroll"
		scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# INCREASED HEIGHT - almost to currency
		scroll.custom_minimum_size = Vector2(0, 600)
		
		# ADD BORDER
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.08, 0.7)
		sb.border_color = Color(0.4, 0.5, 0.8, 0.5)
		sb.border_width_left = 2
		sb.border_width_top = 2
		sb.border_width_right = 2
		sb.border_width_bottom = 2
		sb.corner_radius_top_left = 8
		sb.corner_radius_top_right = 8
		sb.corner_radius_bottom_left = 8
		sb.corner_radius_bottom_right = 8
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		scroll.add_theme_stylebox_override("panel", sb)
		
		var idx := upgrades_vbox.get_index()
		parent.remove_child(upgrades_vbox)
		parent.add_child(scroll)
		parent.move_child(scroll, idx)
		
		scroll.add_child(upgrades_vbox)
		upgrades_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		upgrades_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
			
func _on_upgrade_bought(depth: int, upgrade_id: String) -> void:
	# Refresh this specific row
	for row in depth_upgrade_rows:
		if row.depth_index == depth and row.upgrade_id == upgrade_id:
			if row.has_method("_refresh"):
				row._refresh()
			break
	
	# Update currency display at bottom
	_update_currency_display()
	
	# Update the depth tab text to show new currency amount
	_refresh_depth_tabs()
	
func _refresh_depth_tabs() -> void:
	if depth_tabs == null:
		return
	for i in range(1, 16):
		var tab := depth_tabs.get_node_or_null("DepthTab%d" % i) as Button
		if tab == null:
			continue
		var depth_title := DepthMetaSystem.get_depth_name(i)
		var amount := depth_meta_system.currency[i] if depth_meta_system != null else 0.0
		tab.text = "%s (%.0f)" % [depth_title, amount]
			
func _make_tab_style(bg: Color, border: Color, border_w: int = 2, radius: int = 8, shadow_color: Color = Color(0, 0, 0, 0.35), shadow_size: int = 3) -> StyleBoxFlat:
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
	sb.shadow_color = shadow_color
	sb.shadow_size = shadow_size
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _style_tab_button(btn: Button) -> void:
	if btn == null:
		return
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_stretch_ratio = 1
	btn.custom_minimum_size.x = 0
	btn.add_theme_constant_override("content_margin_left", 10)
	btn.add_theme_constant_override("content_margin_right", 10)
	btn.add_theme_constant_override("h_separation", 6)
	btn.clip_text = false
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	btn.add_theme_stylebox_override("normal",   _make_tab_style(Color(0.12, 0.12, 0.14, 0.95), Color(0.55, 0.65, 0.9, 0.8), 2, 9))
	btn.add_theme_stylebox_override("hover",    _make_tab_style(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 9))
	btn.add_theme_stylebox_override("pressed",  _make_tab_style(Color(0.09, 0.09, 0.11, 0.95), Color(0.50, 0.60, 0.85, 0.8), 2, 9))
	btn.add_theme_stylebox_override("disabled", _make_tab_style(Color(0.06, 0.07, 0.09, 0.7),  Color(0.35, 0.45, 0.65, 0.6), 2, 9)) # darker blue
	btn.add_theme_stylebox_override("focus",    _make_tab_style(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 9))

func _style_top_tabs() -> void:
	if _styled_top_tabs:
		return
	_styled_top_tabs = true
	var root_btn := tab_perm
	if root_btn == null:
		root_btn = tab_depth
	if root_btn == null:
		root_btn = tab_abyss
	if root_btn == null:
		return

	# Frame the tab bar
	var panel := root_btn.get_parent()
	while panel != null and not (panel is Panel or panel is PanelContainer):
		panel = panel.get_parent()
	if panel != null:
		var sb := _make_tab_style(Color(0.05, 0.06, 0.08, 0.85), Color(0.5, 0.6, 0.9, 0.6), 2, 10, Color(0, 0, 0, 0.35), 3)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		panel.add_theme_stylebox_override("panel", sb)

	# Spacing between perm/depth/abyss tabs
	var container := root_btn.get_parent()
	if container is BoxContainer:
		container.add_theme_constant_override("separation", 10)
		container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	for b in [tab_perm, tab_depth, tab_abyss]:
		_style_tab_button(b)

func _style_depth_tabs_bar() -> void:
	if depth_tabs == null:
		return
	if not _styled_depth_tabs:
		_styled_depth_tabs = true
		# Frame around the depth tabs row
		var panel := depth_tabs.get_parent()
		while panel != null and not (panel is Panel or panel is PanelContainer):
			panel = panel.get_parent()
		if panel != null:
			var sb := _make_tab_style(Color(0.05, 0.06, 0.08, 0.85), Color(0.5, 0.6, 0.9, 0.6), 2, 10, Color(0, 0, 0, 0.35), 3)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
			panel.add_theme_stylebox_override("panel", sb)

		if depth_tabs is BoxContainer:
			depth_tabs.add_theme_constant_override("separation", 6)
			depth_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	

func _update_currency_display() -> void:
	if depth_meta_system == null:
		return
	
	for i in range(1, 16):
		if i <= currency_labels.size():
			var amount = depth_meta_system.currency[i]
			currency_labels[i-1].text = "%.1f" % amount

func _refresh_all_rows() -> void:
	for row in depth_upgrade_rows:
		if is_instance_valid(row) and row.has_method("_refresh"):
			row._refresh()
			
func toggle_open() -> void:
	visible = not visible
	if visible:
		_apply_unlocks()
		_show_meta(_current_meta)
		_show_depth(_current_depth)
		_update_currency_display()
		_refresh_all_rows()

func open() -> void:
	visible = true
	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)
	_update_currency_display()
	_refresh_all_rows()
	
func _refresh_depth_upgrades() -> void:
	# Force all upgrade rows to refresh (so Buy buttons update)
	var rows = find_children("*", "DepthUpgradeRow", true, false)
	for row in rows:
		if row.has_method("_refresh"):
			row._refresh()
	
func _style_close_button() -> void:
	if close_btn == null:
		return
	close_btn.custom_minimum_size = Vector2(40, 28)
	close_btn.add_theme_constant_override("content_margin_left", 8)
	close_btn.add_theme_constant_override("content_margin_right", 8)
	close_btn.add_theme_constant_override("h_separation", 4)

	close_btn.add_theme_stylebox_override("normal", _make_tab_style(Color(0.12, 0.12, 0.14, 0.95), Color(0.55, 0.65, 0.9, 0.8), 2, 6))
	close_btn.add_theme_stylebox_override("hover",  _make_tab_style(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 6))
	close_btn.add_theme_stylebox_override("pressed", _make_tab_style(Color(0.09, 0.09, 0.11, 0.95), Color(0.50, 0.60, 0.85, 0.8), 2, 6))
	close_btn.add_theme_stylebox_override("disabled", _make_tab_style(Color(0.08, 0.08, 0.10, 0.60), Color(0.40, 0.45, 0.55, 0.5), 2, 6))
	close_btn.add_theme_stylebox_override("focus", _make_tab_style(Color(0.16, 0.16, 0.20, 0.98), Color(0.60, 0.70, 0.95, 0.9), 2, 6))

func _style_perm_panel() -> void:
	# Find a parent panel that wraps the perm upgrades (PermPerkRow)
	var rows := find_children("*", "PermPerkRow", true, false)
	if rows.is_empty():
		return
	var panel := rows[0].get_parent()
	while panel != null and not (panel is Panel or panel is PanelContainer):
		panel = panel.get_parent()
	if panel == null:
		return
	var sb := _make_tab_style(Color(0.05, 0.06, 0.08, 0.85), Color(0.5, 0.6, 0.9, 0.6), 2, 10, Color(0, 0, 0, 0.35), 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)

	# Add spacing in the VBox that holds the rows (if any)
	var container := rows[0].get_parent()
	if container is BoxContainer:
		container.add_theme_constant_override("separation", 10)

func close() -> void:
	visible = false

func set_progress(new_max_depth: int, is_abyss_unlocked: bool) -> void:
	max_depth_reached = maxi(1, new_max_depth)
	abyss_unlocked = is_abyss_unlocked
	_apply_unlocks()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ----------------------------
# Top tabs
# ----------------------------
func _connect_top_tab(btn: Button, which: String) -> void:
	if btn == null:
		return
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if not btn.pressed.is_connected(Callable(self, "_on_top_tab_pressed")):
		btn.pressed.connect(Callable(self, "_on_top_tab_pressed").bind(which))

func _on_top_tab_pressed(which: String) -> void:
	_show_meta(which)

func _show_meta(which: String) -> void:
	_current_meta = which

	# IMPORTANT: hidden pages must not block clicks
	if page_perm != null:
		page_perm.visible = (which == "perm")
		page_perm.mouse_filter = Control.MOUSE_FILTER_STOP if page_perm.visible else Control.MOUSE_FILTER_IGNORE

	if page_depth != null:
		page_depth.visible = (which == "depth")
		page_depth.mouse_filter = Control.MOUSE_FILTER_STOP if page_depth.visible else Control.MOUSE_FILTER_IGNORE

	if page_abyss != null:
		page_abyss.visible = (which == "abyss")
		page_abyss.mouse_filter = Control.MOUSE_FILTER_STOP if page_abyss.visible else Control.MOUSE_FILTER_IGNORE

	# snap back if abyss locked
	if which == "abyss" and (tab_abyss == null or tab_abyss.disabled):
		_current_meta = "depth"
		if page_perm != null:
			page_perm.visible = false
			page_perm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if page_depth != null:
			page_depth.visible = true
			page_depth.mouse_filter = Control.MOUSE_FILTER_STOP
		if page_abyss != null:
			page_abyss.visible = false
			page_abyss.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ----------------------------
# Unlocks / Depth tabs
# ----------------------------
func _apply_unlocks() -> void:
	if page_depth == null:
		page_depth = find_child("DepthPage", true, false) as Control
	if page_depth != null and (depth_tabs == null or depth_pages == null):
		depth_tabs = page_depth.find_child("DepthTabs", true, false) as Control
		depth_pages = page_depth.find_child("DepthPages", true, false) as Control

	if depth_tabs == null or depth_pages == null:
		push_warning("MetaPanelController: DepthTabs or DepthPages not found. Check node names.")
		return

	_style_depth_tabs_bar()

	# Abyss tab visibility
	var abyss_ok := abyss_unlocked or (max_depth_reached >= 15)
	if tab_abyss != null:
		tab_abyss.visible = abyss_ok
		tab_abyss.disabled = not abyss_ok

	# Depth tab setup
	for i in range(1, 16):
		var tab := depth_tabs.get_node_or_null("DepthTab%d" % i) as Button
		if tab == null:
			continue
		# ... existing visibility/disabled logic ...
		tab.add_theme_constant_override("h_separation", 4)
		tab.add_theme_constant_override("content_margin_left", 6)
		tab.add_theme_constant_override("content_margin_right", 6)
		tab.add_theme_font_size_override("font_size", 11)  # was default; shrink to fit
		_style_tab_button(tab)

		tab.visible = true  # keep width consistent
		tab.disabled = (max_depth_reached < i)
		tab.modulate = Color(1, 1, 1, 0.55) if tab.disabled else Color(1, 1, 1, 1)
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE if tab.disabled else Control.MOUSE_FILTER_STOP

		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.size_flags_stretch_ratio = 1
		tab.custom_minimum_size = Vector2.ZERO

		var depth_title := DepthMetaSystem.get_depth_name(i)
		var amount := depth_meta_system.currency[i] if depth_meta_system != null else 0.0
		tab.text = "%s (%.0f)" % [depth_title, amount]

		# pad a bit for fit
		tab.add_theme_constant_override("h_separation", 4)
		tab.add_theme_constant_override("content_margin_left", 6)
		tab.add_theme_constant_override("content_margin_right", 6)

		_style_tab_button(tab)

		if not tab.pressed.is_connected(Callable(self, "_on_depth_tab_pressed")):
			tab.pressed.connect(Callable(self, "_on_depth_tab_pressed").bind(i))

	if _current_depth > max_depth_reached:
		_current_depth = max_depth_reached
	_show_depth(_current_depth)
	
func _ensure_depth_tab_spacer() -> void:
	if depth_tabs == null:
		return
	var spacer := depth_tabs.get_node_or_null("DepthTabsSpacer") as Control
	if spacer == null:
		spacer = Control.new()
		spacer.name = "DepthTabsSpacer"
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		depth_tabs.add_child(spacer)
	# Keep the spacer as the first child so it pushes tabs to the right
	depth_tabs.move_child(spacer, 0)

func _on_depth_tab_pressed(depth_index: int) -> void:
	_show_depth(depth_index)
	
func _show_depth(depth_index: int) -> void:
	if depth_pages == null:
		return
	_current_depth = clampi(depth_index, 1, 15)

	for i in range(1, 16):
		var page := depth_pages.get_node_or_null("DepthPage%d" % i) as Control
		if page != null:
			page.visible = (i == _current_depth)
			page.mouse_filter = Control.MOUSE_FILTER_STOP if page.visible else Control.MOUSE_FILTER_IGNORE
	
	# Refresh rows after showing new depth
	_refresh_all_rows()

func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()

func open_to_depth(depth_index: int) -> void:
	open()
	_show_meta("depth")
	_show_depth(depth_index)

func _on_buy_upgrade_pressed(depth: int, upgrade_id: String) -> void:
	var result = depth_meta_system.buy_upgrade(depth, upgrade_id)
	if result == false:
		return
	
	var new_level = depth_meta_system.get_level(depth, upgrade_id)
	var max_level = depth_meta_system.get_max_level(depth, upgrade_id)
	
	var row = _find_upgrade_row(depth, upgrade_id)
	if row == null:
		return
	
	var level_label = row.get_node_or_null("LevelLabel")
	if level_label == null:
		for child in row.get_children():
			if child is Label and ("Lv" in child.text or "/" in child.text or "0/" in child.text):
				level_label = child
				break
	
	if level_label != null:
		if new_level >= max_level:
			level_label.text = "MAXED"
		else:
			level_label.text = "Lv %d/%d" % [new_level, max_level]
	
	var cost_label = row.get_node_or_null("CostLabel")
	if cost_label:
		if new_level >= max_level:
			cost_label.text = ""
		else:
			var cost = depth_meta_system.get_upgrade_cost(depth, upgrade_id, new_level)
			cost_label.text = _format_cost(cost)
	
	var buy_btn = row.get_node_or_null("BuyButton")
	if buy_btn:
		if new_level >= max_level:
			buy_btn.disabled = true
			buy_btn.text = "MAXED"
		else:
			var can_afford = depth_meta_system.can_afford_upgrade(depth, upgrade_id)
			buy_btn.disabled = not can_afford
	
	_refresh_currency_display()
	_refresh_depth_tabs()

func _find_upgrade_row(depth: int, upgrade_id: String) -> Node:
	for row in depth_upgrade_rows:
		if row.has_method("get_depth") and row.has_method("get_upgrade_id"):
			if row.get_depth() == depth and row.get_upgrade_id() == upgrade_id:
				return row
		# Alternative: check metadata if the row stores it
		if "depth_index" in row and "upgrade_id" in row:
			if row.depth_index == depth and row.upgrade_id == upgrade_id:
				return row
	return null

func _format_cost(cost_dict: Dictionary) -> String:
	if cost_dict.is_empty():
		return ""
	
	var parts: Array[String] = []
	for currency_name in cost_dict.keys():
		var amount = float(cost_dict[currency_name])
		parts.append("%.0f %s" % [amount, currency_name])
	
	return " + ".join(parts)

func _refresh_currency_display() -> void:
	_update_currency_display()
