extends PanelContainer  # Changed from HBoxContainer to get borders
class_name DepthUpgradeRow

var depth_index: int = 1
var upgrade_id: String = ""
var upgrade_name: String = ""
var upgrade_desc: String = ""
var max_level: int = 1

var depth_meta: DepthMetaSystem
var gm: GameManager

var _title_lbl: Label
var _desc_lbl: Label
var _stat_lbl: Label
var _bar_lbl: Label
var _cost_lbl: Label
var _buy_btn: Button
var _bar: ProgressBar
var _t := 0.0

func _ready() -> void:
	depth_meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	gm = get_tree().current_scene.find_child("GameManager", true, false)
	
	size_flags_horizontal = SIZE_EXPAND_FILL
	mouse_filter = MOUSE_FILTER_STOP
	
	pivot_offset = size / 2.0
	item_rect_changed.connect(func(): pivot_offset = size / 2.0)
	
	_style_card_base()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	for child in get_children():
		child.queue_free()
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	margin.add_child(hbox)
	
	# --- COLUMN 1: Action (Left) ---
	var action_vbox := VBoxContainer.new()
	action_vbox.custom_minimum_size = Vector2(240, 0)
	action_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	hbox.add_child(action_vbox)
	
	_buy_btn = Button.new()
	_buy_btn.name = "BuyButton"
	_buy_btn.custom_minimum_size = Vector2(240, 54)
	_buy_btn.size_flags_horizontal = SIZE_SHRINK_CENTER
	_buy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not _buy_btn.pressed.is_connected(_on_buy):
		_buy_btn.pressed.connect(_on_buy)
	action_vbox.add_child(_buy_btn)
	
	_cost_lbl = Label.new()
	_cost_lbl.name = "CostLabel"
	_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_lbl.add_theme_font_size_override("font_size", 13)
	_cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	_cost_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	action_vbox.add_child(_cost_lbl)
	
	# --- COLUMN 2: Info (Middle) ---
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	info_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	hbox.add_child(info_vbox)
	
	_title_lbl = Label.new()
	_title_lbl.name = "TitleLabel"
	_title_lbl.add_theme_font_size_override("font_size", 20)
	_title_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	_title_lbl.text = upgrade_name
	info_vbox.add_child(_title_lbl)
	
	_desc_lbl = Label.new()
	_desc_lbl.name = "DescLabel"
	_desc_lbl.add_theme_font_size_override("font_size", 14)
	_desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.text = upgrade_desc
	info_vbox.add_child(_desc_lbl)
	
	_stat_lbl = Label.new()
	_stat_lbl.name = "StatLabel"
	_stat_lbl.add_theme_font_size_override("font_size", 15)
	_stat_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	info_vbox.add_child(_stat_lbl)
	
	# --- COLUMN 3: Mastery (Right) ---
	var mastery_vbox := VBoxContainer.new()
	mastery_vbox.custom_minimum_size = Vector2(300, 0)
	mastery_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	hbox.add_child(mastery_vbox)
	
	var bar_container = PanelContainer.new()
	bar_container.mouse_filter = MOUSE_FILTER_IGNORE
	mastery_vbox.add_child(bar_container)
	
	_bar = ProgressBar.new()
	_bar.name = "Bar"
	_bar.custom_minimum_size = Vector2(300, 24)
	_bar.show_percentage = false
	bar_container.add_child(_bar)
	
	_bar_lbl = Label.new()
	_bar_lbl.name = "BarLabel"
	_bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_lbl.add_theme_font_size_override("font_size", 13)
	_bar_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_bar_lbl.add_theme_constant_override("outline_size", 4)
	bar_container.add_child(_bar_lbl)
	
	var mastery_lbl = Label.new()
	mastery_lbl.text = "Depth Mastery"
	mastery_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mastery_lbl.add_theme_font_size_override("font_size", 11)
	mastery_lbl.modulate = Color(1, 1, 1, 0.4)
	mastery_vbox.add_child(mastery_lbl)
	
	_style_bar()
	
	if gm and gm.has_method("_style_button"):
		gm._style_button(_buy_btn)
	
	set_process(true)
	call_deferred("_refresh")

func _style_card_base() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.16, 0.45)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.4, 0.6, 1.0, 0.15)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	add_theme_stylebox_override("panel", sb)

func _style_bar() -> void:
	if not _bar: return
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.01, 0.02, 0.04, 0.9)
	bg.corner_radius_top_left = 12
	bg.corner_radius_top_right = 12
	bg.corner_radius_bottom_left = 12
	bg.corner_radius_bottom_right = 12
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.4, 0.6, 1.0, 0.2)
	
	var fg = StyleBoxFlat.new()
	fg.bg_color = Color(0.3, 0.7, 1.0, 1.0)
	fg.corner_radius_top_left = 12
	fg.corner_radius_top_right = 12
	fg.corner_radius_bottom_left = 12
	fg.corner_radius_bottom_right = 12
	
	_bar.add_theme_stylebox_override("background", bg)
	_bar.add_theme_stylebox_override("fill", fg)

func _on_mouse_entered() -> void:
	var sb := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.bg_color = Color(0.15, 0.18, 0.25, 0.65)
	sb.border_color = Color(0.5, 0.8, 1.0, 0.5)
	sb.shadow_color = Color(0.3, 0.6, 1.0, 0.2)
	sb.shadow_size = 12
	add_theme_stylebox_override("panel", sb)
	
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.008, 1.008), 0.1).set_trans(Tween.TRANS_SINE)
	z_index = 10

func _on_mouse_exited() -> void:
	_style_card_base()
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE)
	z_index = 0

func _format_costs(d: int, def: Dictionary) -> Dictionary:
	var base := depth_meta.cost_for(d, def)
	var costs: Dictionary = def.get("costs", { d: 1.0 })
	
	var parts: Array[String] = []
	var ok := true
	
	for k in costs.keys():
		var idx := int(k)
		var need_f := base * float(costs[k])
		var _need := int(round(need_f))  # If you don't use it, prefix with _
		var cname := DepthMetaSystem.get_depth_currency_name(idx)
		
		# FIX: Format large numbers nicely
		parts.append("%s %s" % [_fmt_num(need_f), cname])
		
		if depth_meta.currency[idx] < need_f:
			ok = false
	
	return {
		"text": " + ".join(parts),
		"ok": ok,
		"base": base,
		"costs": costs
	}

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
	
func _refresh() -> void:
	var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)
	var lvl := depth_meta.get_level(d, upgrade_id)
	
	if _title_lbl: _title_lbl.text = upgrade_name
	if _desc_lbl: _desc_lbl.text = upgrade_desc
	if _bar_lbl:
		_bar_lbl.text = "LEVEL %d / %d" % [lvl, max_level]
		if lvl >= max_level:
			_bar_lbl.text = "MASTERY COMPLETE"
			_bar_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
		else:
			_bar_lbl.remove_theme_color_override("font_color")
	
	if _stat_lbl:
		_stat_lbl.text = depth_meta.get_upgrade_stat_text(d, upgrade_id, lvl)
	
	var defs := depth_meta.get_depth_upgrade_defs(d)
	var def: Dictionary = {}
	for item in defs:
		if String(item.get("id", "")) == upgrade_id:
			def = item
			break
	
	var can_buy := true
	var cost_text := "???"
	
	if def.is_empty():
		can_buy = false
	else:
		var info := _format_costs(d, def)
		cost_text = String(info["text"])
		can_buy = bool(info["ok"])
		# Removed unused cost calculations
	
	if _cost_lbl:
		_cost_lbl.text = "[ %s ]" % cost_text if lvl < max_level else "—"
		if can_buy or lvl >= max_level:
			_cost_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
		else:
			_cost_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
	
	if _bar:
		_bar.min_value = 0
		_bar.max_value = max_level
		_bar.value = lvl
		_bar.visible = true
	
	if _buy_btn:
		_buy_btn.text = "BUY UPGRADE" if lvl < max_level else "MAXED"
		_buy_btn.disabled = not can_buy or lvl >= max_level
		_buy_btn.add_theme_font_size_override("font_size", 18)
	
	if upgrade_id == "unlock":
		visible = depth_meta.can_show_unlock_upgrade(d) and (d < DepthMetaSystem.MAX_DEPTH)
	else:
		visible = true

func _on_buy() -> void:
	if depth_meta == null:
		return
	
	# Try to buy
	var res := depth_meta.try_buy(depth_index, upgrade_id)
	
	if bool(res.get("bought", false)):
		_refresh()
		
		# Update meta panel currency display
		var meta_panel := get_tree().current_scene.find_child("MetaPanelController", true, false)
		if meta_panel != null:
			if meta_panel.has_method("_update_currency_display"):
				meta_panel._update_currency_display()
			if meta_panel.has_method("_refresh_depth_tabs"):
				meta_panel._refresh_depth_tabs()
		
		# Save and unlock logic
		if gm != null:
			if upgrade_id == "unlock":
				gm.force_unlock_depth_tab(depth_index + 1)
			gm.save_game()

func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		_refresh()
