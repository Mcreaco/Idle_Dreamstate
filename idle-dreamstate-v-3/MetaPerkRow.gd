extends PanelContainer
class_name MetaPerkRow

@export var perk_id: String = "echoed_descent" # echoed_descent | abyssal_focus | dark_insight | abyss_veil
var gm: GameManager
var abyss: AbyssPerkSystem
var depth_meta_system: DepthMetaSystem # Added based on instruction's _ready and _refresh usage

var title_label: Label
var desc_label: Label
var stat_label: Label
var cost_label: Label
var bar_label: Label
var _t := 0.0

@onready var btn: Button
@onready var bar: Range

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	abyss = get_tree().current_scene.find_child("AbyssPerkSystem", true, false) as AbyssPerkSystem
	depth_meta_system = get_tree().current_scene.find_child("DepthMetaSystem", true, false) as DepthMetaSystem
	
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
	
	# --- COLUMN 1: Action ---
	var action_vbox := VBoxContainer.new()
	action_vbox.custom_minimum_size = Vector2(240, 0)
	action_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	hbox.add_child(action_vbox)
	
	btn = Button.new()
	btn.name = "BuyButton"
	btn.custom_minimum_size = Vector2(240, 54)
	btn.size_flags_horizontal = SIZE_SHRINK_CENTER
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not btn.pressed.is_connected(_on_buy):
		btn.pressed.connect(_on_buy)
	action_vbox.add_child(btn)
	
	cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 16)
	cost_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	action_vbox.add_child(cost_label)
	
	# --- COLUMN 2: Info ---
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	info_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	hbox.add_child(info_vbox)
	
	title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	info_vbox.add_child(title_label)
	
	desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_label)
	
	stat_label = Label.new()
	stat_label.name = "StatLabel"
	stat_label.add_theme_font_size_override("font_size", 15)
	stat_label.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0)) # Purple tint for Abyss
	info_vbox.add_child(stat_label)
	
	# --- COLUMN 3: Mastery ---
	var mastery_vbox := VBoxContainer.new()
	mastery_vbox.custom_minimum_size = Vector2(300, 0)
	mastery_vbox.alignment = VBoxContainer.ALIGNMENT_CENTER
	hbox.add_child(mastery_vbox)
	
	var bar_container = PanelContainer.new()
	bar_container.mouse_filter = MOUSE_FILTER_IGNORE
	mastery_vbox.add_child(bar_container)
	
	bar = ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(300, 24)
	bar.show_percentage = false
	bar_container.add_child(bar)
	
	bar_label = Label.new()
	bar_label.name = "BarLabel"
	bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bar_label.add_theme_font_size_override("font_size", 13)
	bar_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	bar_label.add_theme_constant_override("outline_size", 4)
	bar_container.add_child(bar_label)
	
	var mastery_lbl = Label.new()
	mastery_lbl.text = "Depth Mastery"
	mastery_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mastery_lbl.add_theme_font_size_override("font_size", 11)
	mastery_lbl.modulate = Color(1, 1, 1, 0.5)
	mastery_vbox.add_child(mastery_lbl)
	
	_style_bar()
	
	if gm and gm.has_method("_style_button"):
		gm._style_button(btn)
	
	_refresh()
	set_process(true)

func _style_card_base() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.12, 0.18, 0.5) # Deeper purple-black base
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.6, 0.4, 0.8, 0.15)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	add_theme_stylebox_override("panel", sb)

func _style_bar() -> void:
	if not bar: return
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.02, 0.06, 0.9)
	bg.corner_radius_top_left = 12
	bg.corner_radius_top_right = 12
	bg.corner_radius_bottom_left = 12
	bg.corner_radius_bottom_right = 12
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.5, 0.3, 0.7, 0.3)
	
	var fg = StyleBoxFlat.new()
	fg.bg_color = Color(0.7, 0.4, 1.0, 1.0) # Abyss Purple
	fg.corner_radius_top_left = 12
	fg.corner_radius_top_right = 12
	fg.corner_radius_bottom_left = 12
	fg.corner_radius_bottom_right = 12
	
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)

func _on_mouse_entered() -> void:
	var sb := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.bg_color = Color(0.18, 0.16, 0.28, 0.7)
	sb.border_color = Color(0.8, 0.5, 1.0, 0.5)
	sb.shadow_color = Color(0.6, 0.3, 1.0, 0.2)
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

func _process(_d: float) -> void:
	_refresh()

func _on_buy() -> void:
	if gm == null or abyss == null:
		return
	var res := {}
	match perk_id:
		"echoed_descent": res = abyss.try_buy_echoed_descent(gm.memories)
		"abyssal_focus": res = abyss.try_buy_abyssal_focus(gm.memories)
		"dark_insight": res = abyss.try_buy_dark_insight(gm.memories)
		"abyss_veil": res = abyss.try_buy_abyss_veil(gm.memories)
	if bool(res.get("bought", false)):
		gm.memories -= float(res.get("cost", 0.0))
		gm.save_game()
	_refresh()

func _refresh() -> void:
	if gm == null or abyss == null or depth_meta_system == null:
		return

	var title := ""
	var lvl := 0
	var max_lvl := 1
	var cost := 0.0
	var desc := ""
	var stat_text := "" # New variable for stat tracking

	match perk_id:
		"echoed_descent":
			title = "Echoed Descent"
			lvl = abyss.echoed_descent_level
			max_lvl = abyss.echoed_descent_max
			cost = abyss.get_echoed_descent_cost()
			desc = "Start each run deeper."
			stat_text = "+%d start depth per level." % abyss.start_depth_per_level
		"abyssal_focus":
			title = "Abyssal Focus"
			lvl = abyss.abyssal_focus_level
			max_lvl = abyss.abyssal_focus_max
			cost = abyss.get_abyssal_focus_cost()
			desc = "More dreamcloud gain."
			stat_text = "+%d%% per level." % int(round(abyss.dreamcloud_mult_step * 100.0))
		"dark_insight":
			title = "Dark Insight"
			lvl = abyss.dark_insight_level
			max_lvl = abyss.dark_insight_max
			cost = abyss.get_dark_insight_cost()
			desc = "More Thoughts gain."
			stat_text = "+%d%% per level." % int(round(abyss.thoughts_mult_step * 100.0))
		"abyss_veil":
			title = "Abyss Veil"
			lvl = abyss.abyss_veil_level
			max_lvl = abyss.abyss_veil_max
			cost = abyss.get_abyss_veil_cost()
			desc = "Reduce Instability gain at depth %d+." % abyss.abyss_veil_starts_at_depth
			stat_text = "-%d%% per level (min 10%%)." % int(round(abyss.abyss_veil_step * 100.0))

	# The instruction provided a partial _refresh for a different system (DepthMetaSystem)
	# I will integrate the new label assignments based on the original AbyssPerkSystem logic
	# and the new label variables.

	if title_label: title_label.text = title
	if desc_label: desc_label.text = desc
	if stat_label: stat_label.text = stat_text
	
	if btn:
		btn.text = "%s (Lv %d/%d)" % [title, lvl, max_lvl] if lvl < max_lvl else "MAXED"
		btn.disabled = (gm.memories < cost) or (lvl >= max_lvl)
		btn.add_theme_font_size_override("font_size", 18) # Added from instruction
	
	if cost_label:
		cost_label.text = "—" if lvl >= max_lvl else "[ %s %s ]" % [str(int(round(cost))), "Memories"] # Assuming currency is Memories
		if lvl < max_lvl and gm.memories < cost:
			cost_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
		else:
			cost_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.5))
	
	if bar:
		bar.min_value = 0
		bar.max_value = max_lvl
		bar.value = lvl
		if bar_label:
			bar_label.text = "LEVEL %d / %d" % [lvl, max_lvl]
			if lvl >= max_lvl:
				bar_label.text = "ABYSS MASTERED" # Changed from DEPTH MASTERED to ABYSS MASTERED
				bar_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.4))

	btn.tooltip_text = "%s\n\n%s\n\nCost: %d Memories" % [title, desc, int(round(cost))]

# Helper function for formatting numbers, assumed from instruction's _refresh
func _fmt_num(num: float) -> String:
	if num >= 1_000_000_000_000_000_000.0: return "%.2fQ" % (num / 1e18)
	if num >= 1_000_000_000_000_000.0: return "%.2fP" % (num / 1e15)
	if num >= 1_000_000_000_000.0: return "%.2fT" % (num / 1e12)
	if num >= 1_000_000_000.0: return "%.2fB" % (num / 1e9)
	if num >= 1_000_000.0: return "%.2fM" % (num / 1e6)
	if num >= 1_000.0: return "%.2fK" % (num / 1e3)
	return str(int(round(num)))
