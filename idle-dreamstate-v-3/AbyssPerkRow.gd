extends PanelContainer
class_name AbyssPerkRow

@export var mode: String = "echoed_descent"
@export var refresh_interval: float = 0.2
@export var level_display_cap: int = 10

var _gm: GameManager
var _abyss: AbyssPerkSystem

# UI References
var _title_lbl: Label
var _desc_lbl: Label
var _stat_lbl: Label
var _cost_lbl: Label
var _buy_btn: Button
var _bar: ProgressBar
var _bar_lbl: Label

var _t: float = 0.0
var _is_hovered: bool = false

func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_abyss = get_tree().current_scene.find_child("AbyssPerkSystem", true, false) as AbyssPerkSystem
	
	_setup_ui_structure()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	set_process(true)
	_refresh()

func _setup_ui_structure() -> void:
	# Clear existing if any (procedural safety)
	for c in get_children(): c.queue_free()
	
	_style_card_base()
	
	var main_hbox := HBoxContainer.new()
	main_hbox.add_theme_constant_override("separation", 20)
	add_child(main_hbox)
	
	# Column 1: Buy Action (120px)
	var col_buy := VBoxContainer.new()
	col_buy.custom_minimum_size = Vector2(120, 0)
	col_buy.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(col_buy)
	
	_buy_btn = Button.new()
	_buy_btn.text = "UPGRADE"
	_buy_btn.custom_minimum_size = Vector2(110, 42)
	_buy_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_buy_btn.pressed.connect(_on_pressed)
	col_buy.add_child(_buy_btn)
	
	_cost_lbl = Label.new()
	_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_lbl.add_theme_font_size_override("font_size", 13)
	_cost_lbl.add_theme_color_override("font_color", Color(0.8, 0.4, 0.9)) # Purple-ish
	col_buy.add_child(_cost_lbl)
	
	# Column 2: Info & Stats (Flexible)
	var col_info := VBoxContainer.new()
	col_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_info.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(col_info)
	
	_title_lbl = Label.new()
	_title_lbl.add_theme_font_size_override("font_size", 18)
	_title_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	col_info.add_child(_title_lbl)
	
	_stat_lbl = Label.new()
	_stat_lbl.add_theme_font_size_override("font_size", 14)
	_stat_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	col_info.add_child(_stat_lbl)
	
	_desc_lbl = Label.new()
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc_lbl.add_theme_font_size_override("font_size", 12)
	_desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	col_info.add_child(_desc_lbl)
	
	# Column 3: Mastery (180px)
	var col_mastery := VBoxContainer.new()
	col_mastery.custom_minimum_size = Vector2(180, 0)
	col_mastery.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(col_mastery)
	
	var mastery_title := Label.new()
	mastery_title.text = "ABYSS MASTERY"
	mastery_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mastery_title.add_theme_font_size_override("font_size", 10)
	mastery_title.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	col_mastery.add_child(mastery_title)
	
	var bar_container := PanelContainer.new()
	col_mastery.add_child(bar_container)
	
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 24)
	_bar.show_percentage = false
	bar_container.add_child(_bar)
	
	_bar_lbl = Label.new()
	_bar_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_lbl.add_theme_font_size_override("font_size", 11)
	_bar_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	_bar_lbl.add_theme_constant_override("outline_size", 4)
	bar_container.add_child(_bar_lbl)

func _style_card_base() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.12, 0.18, 0.7)
	sb.border_width_bottom = 2
	sb.border_color = Color(0.3, 0.4, 0.6, 0.3)
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 15
	sb.content_margin_right = 15
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)

func _process(delta: float) -> void:
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()

func _refresh() -> void:
	if _gm == null or _abyss == null: return
	
	if not _gm.abyss_unlocked_flag:
		visible = false
		return
	visible = true
	
	var lvl := _get_level()
	var max_lvl := _get_max_level()
	var cost := _get_cost()
	
	if _title_lbl: _title_lbl.text = _get_title()
	if _desc_lbl: _desc_lbl.text = _get_mini_text()
	if _stat_lbl: _stat_lbl.text = _get_stat_text()
	
	if _cost_lbl:
		if lvl >= max_lvl:
			_cost_lbl.text = "MAXED"
			_cost_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		else:
			_cost_lbl.text = "[ %s ]" % _fmt_num(cost)
			_cost_lbl.add_theme_color_override("font_color", Color(0.8, 0.4, 0.9))
	
	if _buy_btn:
		_buy_btn.disabled = (_gm.memories < cost) or (lvl >= max_lvl)
		_buy_btn.text = "MAXED" if lvl >= max_lvl else "UPGRADE"
		
	if _bar:
		_bar.max_value = float(max_lvl)
		_bar.value = float(lvl)
		
	if _bar_lbl:
		_bar_lbl.text = "Lv %d / %d" % [lvl, max_lvl]

func _on_pressed() -> void:
	if _gm == null or _abyss == null: return
	
	var res: Dictionary
	match mode.to_lower():
		"echoed_descent": res = _abyss.try_buy_echoed_descent(_gm.memories)
		"abyssal_focus": res = _abyss.try_buy_abyssal_focus(_gm.memories)
		"dark_insight": res = _abyss.try_buy_dark_insight(_gm.memories)
		"abyss_veil": res = _abyss.try_buy_abyss_veil(_gm.memories)
	
	if bool(res.get("bought", false)):
		_gm.memories -= float(res.get("cost", 0.0))
		_gm.save_game()
	_refresh()

func _on_mouse_entered() -> void:
	_is_hovered = true
	pivot_offset = size / 2.0
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.02, 1.02), 0.2)
	modulate = Color(1.1, 1.1, 1.2)

func _on_mouse_exited() -> void:
	_is_hovered = false
	var tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.2)
	modulate = Color(1, 1, 1)

func _get_title() -> String:
	match mode.to_lower():
		"echoed_descent": return "Echoed Descent"
		"abyssal_focus": return "Abyssal Focus"
		"dark_insight": return "Dark Insight"
		"abyss_veil": return "Veil of the Abyss"
	return "Abyss Perk"

func _get_mini_text() -> String:
	match mode.to_lower():
		"echoed_descent": return "Start runs deeper into the dreamscape."
		"abyssal_focus": return "Intensifies permanent dreamcloud gathering."
		"dark_insight": return "Deepens understanding, boosting Thought gain."
		"abyss_veil": return "Slows instability growth at extreme depths."
	return ""

func _get_stat_text() -> String:
	var lvl := _get_level()
	match mode.to_lower():
		"echoed_descent": return "Current Start Depth: +%d" % (lvl * _abyss.start_depth_per_level)
		"abyssal_focus": return "Dreamcloud Mult: +%.0f%%" % (lvl * _abyss.dreamcloud_mult_step * 100.0)
		"dark_insight": return "Thoughts Mult: +%.0f%%" % (lvl * _abyss.thoughts_mult_step * 100.0)
		"abyss_veil": return "Instability Reduc: -%.0f%%" % (lvl * _abyss.abyss_veil_step * 100.0)
	return ""

func _get_level() -> int:
	match mode.to_lower():
		"echoed_descent": return _abyss.echoed_descent_level
		"abyssal_focus": return _abyss.abyssal_focus_level
		"dark_insight": return _abyss.dark_insight_level
		"abyss_veil": return _abyss.abyss_veil_level
	return 0

func _get_max_level() -> int:
	match mode.to_lower():
		"echoed_descent": return _abyss.echoed_descent_max
		"abyssal_focus": return _abyss.abyssal_focus_max
		"dark_insight": return _abyss.dark_insight_max
		"abyss_veil": return _abyss.abyss_veil_max
	return 0

func _get_cost() -> float:
	match mode.to_lower():
		"echoed_descent": return _abyss.get_echoed_descent_cost()
		"abyssal_focus": return _abyss.get_abyssal_focus_cost()
		"dark_insight": return _abyss.get_dark_insight_cost()
		"abyss_veil": return _abyss.get_abyss_veil_cost()
	return 1e12

func _fmt_num(v: float) -> String:
	if v >= 1e12: return "%.2fT" % (v / 1e12)
	if v >= 1e9: return "%.2fB" % (v / 1e9)
	if v >= 1e6: return "%.2fM" % (v / 1e6)
	if v >= 1e3: return "%.2fk" % (v / 1e3)
	return str(int(v))
