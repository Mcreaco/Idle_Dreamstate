extends PanelContainer
class_name PermPerkRow

@export var perk_id: String = "memory_engine"

@onready var btn: Button = $BuyButton
@onready var bar: Range = $Bar
@onready var cost_label: Label = $CostLabel

var gm: GameManager
var perm: PermPerkSystem
var title_label: Label
var desc_label: Label
var stat_label: Label
var bar_label: Label
var _t := 0.0

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false)
	perm = get_tree().current_scene.find_child("PermPerkSystem", true, false)
	
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
	stat_label.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
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
	mastery_lbl.text = "Mastery Progress"
	mastery_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mastery_lbl.add_theme_font_size_override("font_size", 11)
	mastery_lbl.modulate = Color(1, 1, 1, 0.5)
	mastery_vbox.add_child(mastery_lbl)
	
	_style_bar()
	
	if gm and gm.has_method("_style_button"):
		gm._style_button(btn)
	
	refresh()

func _style_card_base() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.45) # Darker, more glass
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(0.5, 0.6, 1.0, 0.12)
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	add_theme_stylebox_override("panel", sb)

func _style_bar() -> void:
	if not bar: return
	
	var bg = StyleBoxFlat.new()
	bg.bg_color = Color(0.02, 0.03, 0.05, 0.9)
	bg.corner_radius_top_left = 12
	bg.corner_radius_top_right = 12
	bg.corner_radius_bottom_left = 12
	bg.corner_radius_bottom_right = 12
	bg.border_width_left = 1
	bg.border_width_top = 1
	bg.border_width_right = 1
	bg.border_width_bottom = 1
	bg.border_color = Color(0.4, 0.5, 0.8, 0.25)
	
	var fg = StyleBoxFlat.new()
	fg.bg_color = Color(0.4, 0.75, 1.0, 1.0)
	fg.corner_radius_top_left = 12
	fg.corner_radius_top_right = 12
	fg.corner_radius_bottom_left = 12
	fg.corner_radius_bottom_right = 12
	
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fg)

func _on_mouse_entered() -> void:
	var sb := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	sb.bg_color = Color(0.18, 0.22, 0.28, 0.65)
	sb.border_color = Color(0.6, 0.8, 1.0, 0.5)
	sb.shadow_color = Color(0.4, 0.6, 1.0, 0.2)
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

func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()

func _on_buy() -> void:
	if not gm or not perm:
		push_error("PermPerkRow: gm or perm is null! gm=", gm, " perm=", perm)
		return
	
	var res: Dictionary
	match perk_id:
		"memory_engine":      res = perm.try_buy_memory_engine(gm.memories)
		"calm_mind":          res = perm.try_buy_calm_mind(gm.memories)
		"focused_will":       res = perm.try_buy_focused_will(gm.memories)
		"starting_insight":   res = perm.try_buy_starting_insight(gm.memories)
		"stability_buffer":   res = perm.try_buy_stability_buffer(gm.memories)
		"offline_echo":       res = perm.try_buy_offline_echo(gm.memories)
		"recursive_memory":   res = perm.try_buy_recursive_memory(gm.memories)
		"lucid_dreaming":     res = perm.try_buy_lucid_dreaming(gm.memories)
		"deep_sleeper":       res = perm.try_buy_deep_sleeper(gm.memories)
		"night_owl":          res = perm.try_buy_night_owl(gm.memories)
		"dream_catcher":      res = perm.try_buy_dream_catcher(gm.memories)
		"subconscious_miner": res = perm.try_buy_subconscious_miner(gm.memories)
		"void_walker":        res = perm.try_buy_void_walker(gm.memories)
		"rapid_eye":          res = perm.try_buy_rapid_eye(gm.memories)
		"sleep_paralysis":    res = perm.try_buy_sleep_paralysis(gm.memories)
		"oneiromancy":        res = perm.try_buy_oneiromancy(gm.memories)
		_:
			push_error("PermPerkRow: Unknown perk_id: ", perk_id)
			return
	
	var bought = bool(res.get("bought", false))
	var cost = float(res.get("cost", 0.0))
	
	
	if bought:
		gm.memories = maxf(gm.memories - cost, 0.0)
		gm.save_game()
		var meta_panel = get_tree().current_scene.find_child("MetaPanelController", true, false)
		if meta_panel != null and meta_panel.has_method("_update_currency_display"):
			meta_panel._update_currency_display()
		refresh()

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
	
func refresh() -> void:
	if not gm or not perm:
		return
	
	var title = ""
	var lvl = 0
	var max_lvl = perm.max_level
	var cost = 0.0
	var tip = ""
	var stat = ""
	
	match perk_id:
		"memory_engine":
			title = "Memory Engine"
			lvl = perm.memory_engine_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Increases passive Thoughts generation."
			stat = "Thoughts Multiplier: x%.2f" % perm.get_thoughts_mult()
		"calm_mind":
			title = "Calm Mind"
			lvl = perm.calm_mind_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Reduces Instability gain from all sources."
			stat = "Instability Gain: %.0f%%" % (perm.get_instability_mult() * 100.0)
		"focused_will":
			title = "Focused Will"
			lvl = perm.focused_will_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Improves Dreamcloud generation efficiency."
			stat = "Dreamcloud Yield: +%.0f%%" % ((perm.get_dreamcloud_mult() - 1.0) * 100.0)
		"starting_insight":
			title = "Starting Insight"
			lvl = perm.starting_insight_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Increases Thoughts starting balance."
			stat = "Starting Thoughts: %s" % _fmt_num(perm.get_starting_thoughts())
		"stability_buffer":
			title = "Stability Buffer"
			lvl = perm.stability_buffer_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Reduces starting Instability level."
			stat = "Instability Reduction: -%.0f" % perm.get_starting_instability_reduction()
		"offline_echo":
			title = "Offline Echo"
			lvl = perm.offline_echo_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Increases production while the game is closed."
			stat = "Offline Multiplier: x%.2f" % perm.get_offline_mult()
		"recursive_memory":
			title = "Recursive Memory"
			lvl = perm.recursive_memory_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "A portion of Memories earned boosts the next gain."
			stat = "Memory Bonus: +%.0f%%" % ((perm.get_recursive_memory_mult() - 1.0) * 100.0)
		"lucid_dreaming":
			title = "Lucid Dreaming"
			lvl = perm.lucid_dreaming_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Lengthens the duration of Overclock state."
			stat = "Overclock Duration: +%.0f%%" % ((perm.get_lucid_dreaming_duration_bonus() - 1.0) * 100.0)
		"deep_sleeper":
			title = "Deep Sleeper"
			lvl = perm.deep_sleeper_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Grants bonus Thoughts based on your current depth."
			stat = "Depth Bonus: +%.1f%% per depth" % (perm.get_deep_sleeper_depth_bonus() * 100.0)
		"night_owl":
			title = "Night Owl"
			lvl = perm.night_owl_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Boosts passive generation based on real-world time."
			stat = "Night Multiplier: x%.2f" % perm.get_night_owl_mult()
		"dream_catcher":
			title = "Dream Catcher"
			lvl = perm.dream_catcher_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Chance for Overclock to not consume resources."
			stat = "Save Chance: %.0f%%" % (perm.get_dream_catcher_chance() * 100.0)
		"subconscious_miner":
			title = "Subconscious Miner"
			lvl = perm.subconscious_miner_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Passively mines Thoughts at a flat rate."
			stat = "Passive Rate: +%s/sec" % _fmt_num(perm.get_subconscious_miner_rate())
		"void_walker":
			title = "Void Walker"
			lvl = perm.void_walker_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Expands the absolute cap of Instability."
			stat = "Cap Increase: +%.0f" % perm.get_void_walker_instability_cap()
		"rapid_eye":
			title = "Rapid Eye"
			lvl = perm.rapid_eye_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Reduces the cooldown between dives."
			stat = "CD Reduction: -%.0f%%" % (perm.get_rapid_eye_cooldown_reduction() * 100.0)
		"sleep_paralysis":
			title = "Sleep Paralysis"
			lvl = perm.sleep_paralysis_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Freezes instability for a short time after diving."
			stat = "Freeze Time: %.1fs" % perm.get_sleep_paralysis_seconds()
		"oneiromancy":
			title = "Oneiromancy"
			lvl = perm.oneiromancy_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Grants previews of deeper, unexplored depths."
			stat = "Preview Depth: +%d" % perm.get_oneiromancy_preview_depths()
	
	if title_label: title_label.text = title
	if desc_label: desc_label.text = tip
	if stat_label: stat_label.text = stat
	
	if btn:
		btn.text = "BUY UPGRADE" if lvl < max_lvl else "MAXED"
		btn.disabled = (lvl >= max_lvl) or (gm.memories < cost)
		btn.add_theme_font_size_override("font_size", 18)
	
	if cost_label:
		cost_label.text = "—" if lvl >= max_lvl else "[ %s Memories ]" % _fmt_num(cost)
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
				bar_label.text = "MASTERY COMPLETE"
				bar_label.add_theme_color_override("font_color", Color(0.1, 1.0, 0.4))
	
	# Debug/Logic section
	var is_maxed: bool = lvl >= max_lvl
	var can_afford: bool = gm.memories >= cost
	var should_disable := is_maxed or not can_afford
	
	if btn:
		btn.disabled = should_disable
		btn.mouse_filter = MOUSE_FILTER_STOP
	
	
