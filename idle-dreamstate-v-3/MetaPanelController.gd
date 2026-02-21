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
var currency_summary: Node

var _current_meta: String = "perm"
var _current_depth: int = 1
var _styled_top_tabs := false
var _styled_depth_tabs := false

var currency_labels: Array[Label] = []
var depth_upgrade_rows: Array = []
var _update_timer: float = 0.0
const UPDATE_INTERVAL: float = 0.5

# NEW: Store reference to our private label that no other script can find
var _memories_label: Label = null
var _header_hbox: HBoxContainer = null

func _process(delta: float) -> void:
	if not visible:
		return
	
	# Update our private label every frame (no flickering possible now)
	_update_memories_label_text()
	
	# Throttled update for bottom currencies
	_update_timer += delta
	if _update_timer >= UPDATE_INTERVAL:
		_update_timer = 0.0
		_update_bottom_currencies()

func _ready() -> void:
	visible = false
	call_deferred("_late_bind")

func _on_close_button_pressed() -> void:
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_ui_element_clicked"):
		tm.on_ui_element_clicked("CloseButton")
	visible = false

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
	
	# CRITICAL: Replace the scene label with our own private one
	_replace_memories_label()
	
	_find_and_setup_upgrade_rows()
	_wrap_upgrade_rows_in_scroll()
	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)
	_style_top_tabs()
	_style_perm_panel()
	_style_close_button()
	_style_currency_summary()
	_refresh_all_rows()

func _replace_memories_label() -> void:
	# Find the existing label (that other scripts are fighting over)
	var old_label := get_node_or_null("Window/RootVBox/HeaderHBox/MemoriesLabel") as Label
	if old_label == null:
		old_label = find_child("MemoriesLabel", true, false) as Label
	
	# Store reference to parent
	if old_label != null:
		_header_hbox = old_label.get_parent() as HBoxContainer
		# Delete the old label so no other script can update it
		old_label.queue_free()
	
	# If we can't find the parent, try to find HeaderHBox directly
	if _header_hbox == null:
		_header_hbox = get_node_or_null("Window/RootVBox/HeaderHBox") as HBoxContainer
		if _header_hbox == null:
			_header_hbox = find_child("HeaderHBox", true, false) as HBoxContainer
	
	if _header_hbox == null:
		push_error("MetaPanelController: Cannot find HeaderHBox to add memories label")
		return
	
	# Find the CloseButton and TitleLabel first (before we mess with ordering)
	var close_btn_node := _header_hbox.find_child("CloseButton", true, false)
	var title_node := _header_hbox.find_child("TitleLabel", true, false)
	
	# Create our own label that no other script knows about
	_memories_label = Label.new()
	_memories_label.name = "_MetaPanelPrivate_MemoriesLabel"  # Underscore makes it "private"
	_memories_label.add_theme_font_size_override("font_size", 18)
	_memories_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_memories_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_memories_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Take up available space
	
	# Add it to the HBox
	_header_hbox.add_child(_memories_label)
	
	# Move TitleLabel to index 0 if it exists
	if title_node != null:
		_header_hbox.move_child(title_node, 0)
	
	# Move our label to index 1 (right after title)
	_header_hbox.move_child(_memories_label, 1)
	
	# CRITICAL: Move CloseButton to the end (far right)
	if close_btn_node != null:
		var btn_count := _header_hbox.get_child_count()
		_header_hbox.move_child(close_btn_node, btn_count - 1)
	
	# Set initial text
	_update_memories_label_text()

func _update_memories_label_text() -> void:
	if _memories_label == null:
		return
		
	var gm = get_tree().current_scene.find_child("GameManager", true, false)
	if gm != null:
		var mem: float = float(gm.memories)
		var mem_str: String = _fmt_num(mem)
		var new_text := "Meta Memories: %s" % mem_str
		if _memories_label.text != new_text:
			_memories_label.text = new_text

func _style_currency_summary() -> void:
	if currency_summary == null:
		return
	
	currency_labels.clear()
	for child in currency_summary.get_children():
		child.queue_free()
	
	if not currency_summary is PanelContainer:
		var wrapper := PanelContainer.new()
		wrapper.name = "CurrencySummaryPanel"
		var parent = currency_summary.get_parent()
		parent.remove_child(currency_summary)
		wrapper.add_child(currency_summary)
		parent.add_child(wrapper)
		currency_summary = wrapper
	
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
	
	currency_summary.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	currency_summary.custom_minimum_size = Vector2(800, 140)
	
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 8)
	currency_summary.add_child(grid)
	
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
		currency_labels.append(val_lbl)
		
		grid.add_child(hbox)
	
	_update_bottom_currencies()

func _fix_stacking() -> void:
	if dim == null:
		return
	var p := dim.get_parent()
	if p != null:
		p.move_child(dim, 0)

	if page_perm != null and not page_perm.visible:
		page_perm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page_depth != null and not page_depth.visible:
		page_depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page_abyss != null and not page_abyss.visible:
		page_abyss.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
func _find_and_setup_upgrade_rows() -> void:
	depth_upgrade_rows = find_children("*", "DepthUpgradeRow", true, false)
	print("Found ", depth_upgrade_rows.size(), " upgrade rows")
	
	for row in depth_upgrade_rows:
		row.depth_meta = depth_meta_system
		row.gm = get_tree().current_scene.find_child("GameManager", true, false)
		
		if row.has_signal("upgrade_bought"):
			if not row.is_connected("upgrade_bought", Callable(self, "_on_upgrade_bought")):
				row.connect("upgrade_bought", Callable(self, "_on_upgrade_bought"))
		
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
		
		var scroll := ScrollContainer.new()
		scroll.name = "UpgradesScroll"
		scroll.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size = Vector2(0, 600)
		
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
	for row in depth_upgrade_rows:
		if row.depth_index == depth and row.upgrade_id == upgrade_id:
			if row.has_method("_refresh"):
				row._refresh()
			break
	
	_update_memories_label_text()
	_update_bottom_currencies()
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
	btn.add_theme_stylebox_override("disabled", _make_tab_style(Color(0.06, 0.07, 0.09, 0.7),  Color(0.35, 0.45, 0.65, 0.6), 2, 9))
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

func _update_bottom_currencies() -> void:
	if depth_meta_system == null:
		return
		
	for i in range(currency_labels.size()):
		var label := currency_labels[i] as Label
		if label != null and is_instance_valid(label):
			var amount: float = depth_meta_system.currency[i + 1]
			var new_text := _fmt_num(amount)
			if label.text != new_text:
				label.text = new_text

func _fmt_num(v: float) -> String:
	if v == INF or v == -INF:
		return "∞"
	if v != v:
		return "NaN"
	v = float(v)
	if v >= 1e15:
		var exponent := int(floor(log(v) / log(10)))
		var mantissa := snappedf(v / pow(10, exponent), 0.01)
		return str(mantissa) + "e+" + str(exponent)
	if v >= 1e12:
		return "%.2fT" % (v / 1e12)
	if v >= 1e9:
		return "%.2fB" % (v / 1e9)
	if v >= 1e6:
		return "%.2fM" % (v / 1e6)
	if v >= 1e3:
		return "%.2fk" % (v / 1e3)
	return str(int(v))
	
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
		_update_memories_label_text()
		_update_bottom_currencies()
		_refresh_all_rows()

func open() -> void:
	visible = true
	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)
	_update_memories_label_text()
	_update_bottom_currencies()
	_refresh_all_rows()
	
func _refresh_depth_upgrades() -> void:
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

	if page_perm != null:
		page_perm.visible = (which == "perm")
		page_perm.mouse_filter = Control.MOUSE_FILTER_STOP if page_perm.visible else Control.MOUSE_FILTER_IGNORE

	if page_depth != null:
		page_depth.visible = (which == "depth")
		page_depth.mouse_filter = Control.MOUSE_FILTER_STOP if page_depth.visible else Control.MOUSE_FILTER_IGNORE

	if page_abyss != null:
		page_abyss.visible = (which == "abyss")
		page_abyss.mouse_filter = Control.MOUSE_FILTER_STOP if page_abyss.visible else Control.MOUSE_FILTER_IGNORE

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

	var abyss_ok := abyss_unlocked or (max_depth_reached >= 15)
	if tab_abyss != null:
		tab_abyss.visible = abyss_ok
		tab_abyss.disabled = not abyss_ok

	for i in range(1, 16):
		var tab := depth_tabs.get_node_or_null("DepthTab%d" % i) as Button
		if tab == null:
			continue
			
		tab.add_theme_constant_override("h_separation", 4)
		tab.add_theme_constant_override("content_margin_left", 6)
		tab.add_theme_constant_override("content_margin_right", 6)
		tab.add_theme_font_size_override("font_size", 11)
		_style_tab_button(tab)

		tab.visible = true
		tab.disabled = (max_depth_reached < i)
		tab.modulate = Color(1, 1, 1, 0.55) if tab.disabled else Color(1, 1, 1, 1)
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE if tab.disabled else Control.MOUSE_FILTER_STOP

		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.size_flags_stretch_ratio = 1
		tab.custom_minimum_size = Vector2.ZERO

		var depth_title := DepthMetaSystem.get_depth_name(i)
		var amount := depth_meta_system.currency[i] if depth_meta_system != null else 0.0
		tab.text = "%s (%.0f)" % [depth_title, amount]

		tab.add_theme_constant_override("h_separation", 4)
		tab.add_theme_constant_override("content_margin_left", 6)
		tab.add_theme_constant_override("content_margin_right", 6)

		_style_tab_button(tab)

		if not tab.pressed.is_connected(Callable(self, "_on_depth_tab_pressed")):
			tab.pressed.connect(Callable(self, "_on_depth_tab_pressed").bind(i))
		
		var completion := 0.0
		var total_upgs := 0
		var bought_upgs := 0
		var defs: Array = depth_meta_system.get_depth_upgrade_defs(i)
		for def in defs:
			total_upgs += int(def.get("max", 1))
			bought_upgs += depth_meta_system.get_level(i, def.get("id", ""))
		if total_upgs > 0:
			completion = float(bought_upgs) / float(total_upgs)
		
		# Show completion percentage in tab
		tab.text = "%s (%.0f%%)" % [depth_title, completion * 100.0]
		if completion >= 1.0:
			tab.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))  # Green for complete


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
	
	_refresh_all_rows()

func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()

func open_to_depth(depth_index: int) -> void:
	open()
	_show_meta("depth")
	_show_depth(depth_index)
	
	# CRITICAL: Force refresh of upgrade rows for this depth
	var rows = find_children("*", "DepthUpgradeRow", true, false)
	for row in rows:
		if row.has_method("set_depth"):
			row.set_depth(depth_index)
		if row.has_method("_refresh"):
			row._refresh()
	
	_update_memories_label_text()
	_update_bottom_currencies()

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
	
	_update_memories_label_text()
	_refresh_depth_tabs()

func _find_upgrade_row(depth: int, upgrade_id: String) -> Node:
	for row in depth_upgrade_rows:
		if row.has_method("get_depth") and row.has_method("get_upgrade_id"):
			if row.get_depth() == depth and row.get_upgrade_id() == upgrade_id:
				return row
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
