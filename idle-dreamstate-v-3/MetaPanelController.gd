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

var _current_abyss_sub: String = "perks"
var _abyss_sub_tabs_hbox: HBoxContainer = null
var _abyss_perks_page: Control = null
var _abyss_shop_page: Control = null

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
		if not close_btn.pressed.is_connected(Callable(self, "_on_close_button_pressed")):
			close_btn.pressed.connect(Callable(self, "_on_close_button_pressed"))

	_fix_stacking()
	
	# CRITICAL: Replace the scene label with our own private one
	_replace_memories_label()
	
	_find_and_setup_upgrade_rows()
	_wrap_upgrade_rows_in_scroll()
	_setup_abyss_consolidation()
	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)
	_style_top_tabs()
	_style_perm_panel()
	_style_main_window()
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
			
func _make_tab_style(bg: Color, border: Color, border_w: int = 2, radius: int = 8, shadow_color: Color = Color(0, 0, 0, 0.4), shadow_size: int = 4) -> StyleBoxFlat:
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
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
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
		if b == null: continue
		_style_tab_button(b)
		# Active state colors
		var is_active = (b == tab_perm and _current_meta == "perm") or \
						(b == tab_depth and _current_meta == "depth") or \
						(b == tab_abyss and _current_meta == "abyss")
		if is_active:
			b.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
			var active_sb = _make_tab_style(Color(0.15, 0.18, 0.25, 0.98), Color(0.4, 0.8, 1.0, 0.9), 2, 9)
			b.add_theme_stylebox_override("normal", active_sb)
		else:
			b.remove_theme_color_override("font_color")

func _style_depth_tabs_bar() -> void:
	if depth_tabs == null:
		return
	if not _styled_depth_tabs:
		_styled_depth_tabs = true
		var panel := depth_tabs.get_parent()
		while panel != null and not (panel is Panel or panel is PanelContainer):
			panel = panel.get_parent()
		if panel != null:
			var sb := _make_tab_style(Color(0.08, 0.1, 0.15, 0.6), Color(0.4, 0.6, 1.0, 0.2), 1, 12, Color(0, 0, 0, 0.4), 6)
			sb.content_margin_left = 12
			sb.content_margin_right = 12
			sb.content_margin_top = 8
			sb.content_margin_bottom = 8
			panel.add_theme_stylebox_override("panel", sb)

		if depth_tabs is BoxContainer:
			depth_tabs.add_theme_constant_override("separation", 8)
			depth_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _style_depth_header(depth_idx: int) -> void:
	if page_depth == null: return
	var scroll = page_depth.find_child("DepthScroll", true, false)
	if scroll == null: return
	var parent = scroll.get_parent()
	
	var header_id = "DepthHeader"
	var header = parent.get_node_or_null(header_id)
	if header == null:
		header = PanelContainer.new()
		header.name = header_id
		parent.add_child(header)
		parent.move_child(header, scroll.get_index())
		
		# Spacing
		var margin = MarginContainer.new()
		margin.add_theme_constant_override("margin_bottom", 16)
		header.add_child(margin)
		
		var hbox = HBoxContainer.new()
		hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		margin.add_child(hbox)
		
		var title = Label.new()
		title.name = "DepthTitle"
		title.add_theme_font_size_override("font_size", 28)
		title.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		title.add_theme_constant_override("outline_size", 4)
		title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.5))
		hbox.add_child(title)
		
		var spacer = Control.new()
		spacer.custom_minimum_size.x = 40
		hbox.add_child(spacer)
		
		var curr_hbox = HBoxContainer.new()
		curr_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		hbox.add_child(curr_hbox)
		
		var curr_val = Label.new()
		curr_val.name = "CurrencyValue"
		curr_val.add_theme_font_size_override("font_size", 24)
		curr_val.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
		curr_hbox.add_child(curr_val)
		
		var curr_name = Label.new()
		curr_name.name = "CurrencyName"
		curr_name.add_theme_font_size_override("font_size", 18)
		curr_name.modulate = Color(1, 1, 1, 0.6)
		curr_hbox.add_child(curr_name)
	
	# Update content
	var depth_name = DepthMetaSystem.get_depth_name(depth_idx)
	var currency_name = DepthMetaSystem.get_depth_currency_name(depth_idx)
	var amount = depth_meta_system.currency[depth_idx] if depth_meta_system else 0.0
	
	header.find_child("DepthTitle").text = depth_name.to_upper()
	header.find_child("CurrencyValue").text = _fmt_num(amount)
	header.find_child("CurrencyName").text = " " + currency_name
	
	# Style the header panel
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.2, 0.4)
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.6, 1.0, 0.3)
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	header.add_theme_stylebox_override("panel", sb)

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
	var sb := _make_tab_style(Color(0.08, 0.1, 0.13, 0.4), Color(0.4, 0.5, 0.8, 0.2), 1, 12, Color(0, 0, 0, 0.45), 8)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", sb)

	var container := rows[0].get_parent()
	if container is BoxContainer:
		container.add_theme_constant_override("separation", 12)

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
	var tm = get_node_or_null("/root/TutorialManage")
	if tm and tm.has_method("on_ui_element_clicked"):
		if which == "perm": tm.on_ui_element_clicked("TabPerm")
		elif which == "depth": tm.on_ui_element_clicked("TabDepth")
		elif which == "abyss": tm.on_ui_element_clicked("TabAbyss")

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

	_style_main_window()
	_style_depth_tabs_bar()
	_apply_tab_styles()

func _apply_tab_styles() -> void:
	if depth_tabs == null: return
	
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
		
		var is_active = (i == _current_depth)
		if is_active:
			tab.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
			tab.add_theme_stylebox_override("normal", _make_tab_style(Color(0.15, 0.2, 0.3, 0.9), Color(0.4, 0.8, 1.0, 0.8), 2, 9))
			tab.modulate = Color(1.1, 1.1, 1.2, 1.0)
		else:
			tab.remove_theme_color_override("font_color")
			tab.modulate = Color(1, 1, 1, 0.55) if tab.disabled else Color(1, 1, 1, 1)

		tab.visible = true
		tab.disabled = (max_depth_reached < i)
		tab.mouse_filter = Control.MOUSE_FILTER_IGNORE if tab.disabled else Control.MOUSE_FILTER_STOP

		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.size_flags_stretch_ratio = 1
		tab.custom_minimum_size = Vector2.ZERO

		var depth_title := DepthMetaSystem.get_depth_name(i)
		var total_upgs := 0
		var bought_upgs := 0
		var defs: Array = depth_meta_system.get_depth_upgrade_defs(i)
		for def in defs:
			total_upgs += int(def.get("max", 1))
			bought_upgs += depth_meta_system.get_level(i, def.get("id", ""))
		var completion := 0.0
		if total_upgs > 0:
			completion = float(bought_upgs) / float(total_upgs)
		
		# Show completion percentage in tab
		tab.text = "%s (%.0f%%)" % [depth_title, completion * 100.0]
		if completion >= 1.0:
			tab.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))  # Green for complete

		if not tab.pressed.is_connected(Callable(self, "_on_depth_tab_pressed")):
			tab.pressed.connect(Callable(self, "_on_depth_tab_pressed").bind(i))


	# Clamping logic removed to prevent recursion.
	# Callers of _apply_unlocks should handle depth switching if needed.
	
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

func _setup_abyss_consolidation() -> void:
	if page_abyss == null: return
	
	# Prepare the Abyss Page to hold sub-tabs
	for c in page_abyss.get_children(): c.queue_free()
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 15)
	page_abyss.add_child(main_vbox)
	
	# 1. Sub-Tab Bar
	_abyss_sub_tabs_hbox = HBoxContainer.new()
	_abyss_sub_tabs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	_abyss_sub_tabs_hbox.add_theme_constant_override("separation", 20)
	main_vbox.add_child(_abyss_sub_tabs_hbox)
	
	var btn_perks := Button.new()
	btn_perks.text = "ABYSS PERKS"
	btn_perks.custom_minimum_size = Vector2(160, 32)
	btn_perks.pressed.connect(_on_abyss_sub_pressed.bind("perks"))
	_abyss_sub_tabs_hbox.add_child(btn_perks)
	
	var btn_shop := Button.new()
	btn_shop.text = "VOID SHOP"
	btn_shop.custom_minimum_size = Vector2(160, 32)
	btn_shop.pressed.connect(_on_abyss_sub_pressed.bind("shop"))
	_abyss_sub_tabs_hbox.add_child(btn_shop)
	
	# 2. Content Area
	var content_root := MarginContainer.new()
	content_root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_theme_constant_override("margin_left", 10)
	content_root.add_theme_constant_override("margin_right", 10)
	main_vbox.add_child(content_root)
	
	# Perks Page
	_abyss_perks_page = ScrollContainer.new()
	_abyss_perks_page.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_abyss_perks_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(_abyss_perks_page)
	
	var perks_vbox := VBoxContainer.new()
	perks_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	perks_vbox.add_theme_constant_override("separation", 10)
	_abyss_perks_page.add_child(perks_vbox)
	
	# Reparent rows if found
	var old_panel = get_tree().current_scene.find_child("AbyssPanel", true, false)
	if old_panel:
		var rows_container = old_panel.find_child("Rows", true, false)
		if rows_container:
			var rows = rows_container.get_children()
			for row in rows:
				row.get_parent().remove_child(row)
				perks_vbox.add_child(row)
		old_panel.queue_free()
	
	# Shop Page
	_abyss_shop_page = Control.new() # AbyssShop script will target this
	_abyss_shop_page.name = "ShopPage"
	_abyss_shop_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_root.add_child(_abyss_shop_page)
	
	# Re-init AbyssShop script if it's on page_abyss
	if page_abyss.has_method("_create_ui_in"):
		page_abyss.call("_create_ui_in", _abyss_shop_page)
	
	_show_abyss_sub("perks")

func _on_abyss_sub_pressed(sub: String) -> void:
	_show_abyss_sub(sub)

func _show_abyss_sub(sub: String) -> void:
	_current_abyss_sub = sub
	if _abyss_perks_page: _abyss_perks_page.visible = (sub == "perks")
	if _abyss_shop_page: _abyss_shop_page.visible = (sub == "shop")
	
	if _abyss_sub_tabs_hbox:
		for btn in _abyss_sub_tabs_hbox.get_children():
			if btn is Button:
				var active = (sub == "perks" and btn.text.contains("PERKS")) or (sub == "shop" and btn.text.contains("SHOP"))
				_style_sub_tab_button(btn, active)

func _style_sub_tab_button(btn: Button, active: bool) -> void:
	var color_bg = Color(0.12, 0.15, 0.25, 0.9) if active else Color(0.08, 0.08, 0.1, 0.4)
	var color_border = Color(0.4, 0.7, 1.0, 0.8) if active else Color(0.3, 0.3, 0.35, 0.3)
	btn.add_theme_stylebox_override("normal", _make_tab_style(color_bg, color_border, 2, 8))
	btn.modulate = Color(1.1, 1.1, 1.25) if active else Color(0.8, 0.8, 0.85)

func _on_depth_tab_pressed(depth_index: int) -> void:
	_show_depth(depth_index)
	
func _show_depth(depth_index: int) -> void:
	if depth_pages == null:
		return
	_current_depth = clampi(depth_index, 1, maxi(1, max_depth_reached))

	for i in range(1, 16):
		var page := depth_pages.get_node_or_null("DepthPage%d" % i) as Control
		if page != null:
			page.visible = (i == _current_depth)
			page.mouse_filter = Control.MOUSE_FILTER_STOP if page.visible else Control.MOUSE_FILTER_IGNORE
	
	_style_depth_header(_current_depth)
	# Breaking the cycle: just styling the tabs, not re-calling _show_depth
	_apply_tab_styles() 
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

func _style_main_window() -> void:
	var window := get_node_or_null("Window") as Control
	if window == null:
		window = find_child("Window", true, false) as Control
	if window == null: return
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.94)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.4, 0.5, 0.8, 0.3)
	sb.corner_radius_top_left = 16
	sb.corner_radius_top_right = 16
	sb.corner_radius_bottom_left = 16
	sb.corner_radius_bottom_right = 16
	sb.shadow_color = Color(0, 0, 0, 0.6)
	sb.shadow_size = 20
	
	# If parent is a PanelContainer, style it
	if window is PanelContainer:
		window.add_theme_stylebox_override("panel", sb)
	elif window is Panel:
		window.add_theme_stylebox_override("panel", sb)
	else:
		# Search for a background panel inside window
		var bg := window.get_node_or_null("BG") as Panel
		if bg: bg.add_theme_stylebox_override("panel", sb)
