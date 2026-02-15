extends HBoxContainer
class_name PermPerkRow

@export var perk_id: String = "memory_engine"

@onready var btn: Button = $BuyButton
@onready var bar: Range = $Bar
@onready var cost_label: Label = $CostLabel

var gm: GameManager
var perm: PermPerkSystem
var desc_label: Label
var _t := 0.0

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false)
	perm = get_tree().current_scene.find_child("PermPerkSystem", true, false)
	
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 16)
	
	# Clear existing children and rebuild in correct order: Button | Desc | Cost | Bar
	# This avoids the need for move_child gymnastics
	for child in get_children():
		if child != btn and child != bar and child != cost_label:
			child.queue_free()
	
	# Button (left, fixed 500px)
	if btn:
		btn.custom_minimum_size = Vector2(500, 44)
		btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
		if gm and gm.has_method("_style_button"):
			gm._style_button(btn)
		if not btn.pressed.is_connected(_on_buy):
			btn.pressed.connect(_on_buy)
	
	# Description (middle, expands to fill available space)
	desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	desc_label.size_flags_horizontal = SIZE_EXPAND_FILL  # This pushes Cost and Bar right
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(desc_label)
	
	# Cost (middle-right, fixed 70px, centered in its slot)
	if cost_label:
		if cost_label.get_parent():
			cost_label.get_parent().remove_child(cost_label)
		cost_label.custom_minimum_size = Vector2(70, 0)
		cost_label.size_flags_horizontal = SIZE_SHRINK_CENTER  # CHANGED: Don't fight for 'end'
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(cost_label)
	
	# Bar (far right, fixed 500px, anchored to right edge)
	if bar:
		if bar.get_parent():
			bar.get_parent().remove_child(bar)
		bar.custom_minimum_size = Vector2(500, 20)
		bar.size_flags_horizontal = SIZE_SHRINK_END  # Keeps it anchored right
		bar.mouse_filter = MOUSE_FILTER_IGNORE
		
		var bg = StyleBoxFlat.new()
		bg.bg_color = Color(0.15, 0.17, 0.20, 0.8)
		bg.corner_radius_top_left = 6
		bg.corner_radius_top_right = 6
		bg.corner_radius_bottom_left = 6
		bg.corner_radius_bottom_right = 6
		
		var fg = StyleBoxFlat.new()
		fg.bg_color = Color(0.35, 0.8, 0.95, 0.95)
		fg.corner_radius_top_left = 6
		fg.corner_radius_top_right = 6
		fg.corner_radius_bottom_left = 6
		fg.corner_radius_bottom_right = 6
		
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		add_child(bar)
		print("Child order: ", get_children().map(func(c): return c.name))
	
	# Force layout update after reparenting
	queue_sort()
	
	refresh()

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
	
	print("DEBUG: ", perk_id, " bought=", bought, " cost=", cost, " memories=", gm.memories, " res=", res)
	
	if bought:
		gm.memories = maxf(gm.memories - cost, 0.0)
		gm.save_game()
		refresh()

func refresh() -> void:
	if not gm or not perm:
		return
	
	var title = ""
	var lvl = 0
	var max_lvl = perm.max_level
	var cost = 0.0
	var tip = ""
	
	match perk_id:
		"memory_engine":
			title = "Memory Engine"
			lvl = perm.memory_engine_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+5% Thoughts per level"
		"calm_mind":
			title = "Calm Mind"
			lvl = perm.calm_mind_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "-4% Instability gain per level"
		"focused_will":
			title = "Focused Will"
			lvl = perm.focused_will_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+6% Control per level"
		"starting_insight":
			title = "Starting Insight"
			lvl = perm.starting_insight_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Start each run with +25 Thoughts per level"
		"stability_buffer":
			title = "Stability Buffer"
			lvl = perm.stability_buffer_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "Start each run with -2 Instability per level"
		"offline_echo":
			title = "Offline Echo"
			lvl = perm.offline_echo_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+8% Offline gains per level"
		"recursive_memory":
			title = "Recursive Memory"
			lvl = perm.recursive_memory_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+5% Memories gain per level"
		"lucid_dreaming":
			title = "Lucid Dreaming"
			lvl = perm.lucid_dreaming_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+10% Overclock duration per level"
		"deep_sleeper":
			title = "Deep Sleeper"
			lvl = perm.deep_sleeper_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+2% Thoughts per depth level per level"
		"night_owl":
			title = "Night Owl"
			lvl = perm.night_owl_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+8% Idle Thoughts per level"
		"dream_catcher":
			title = "Dream Catcher"
			lvl = perm.dream_catcher_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+3% chance to not consume Control on Overclock"
		"subconscious_miner":
			title = "Subconscious Miner"
			lvl = perm.subconscious_miner_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+0.5 passive Thoughts/sec even while offline"
		"void_walker":
			title = "Void Walker"
			lvl = perm.void_walker_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+5 Instability cap per level (can exceed 100%)"
		"rapid_eye":
			title = "Rapid Eye"
			lvl = perm.rapid_eye_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "-3% Dive cooldown per level"
		"sleep_paralysis":
			title = "Sleep Paralysis"
			lvl = perm.sleep_paralysis_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+1s frozen Instability after Wake/Fail per level"
		"oneiromancy":
			title = "Oneiromancy"
			lvl = perm.oneiromancy_level
			cost = perm.get_cost_by_id(perk_id)
			tip = "+1 depth preview per level"
	
	if btn:
		btn.text = "%s (Lv %d/%d)" % [title, lvl, max_lvl]
		btn.disabled = (lvl >= max_lvl) or (gm.memories < cost)
		btn.tooltip_text = "%s\n%s\nCost: %d Memories\nYou have: %d" % [
			title, tip, int(round(cost)), int(round(gm.memories))
		]
	
	if desc_label:
		desc_label.text = tip
		if lvl >= max_lvl:
			desc_label.modulate = Color(0.5, 0.5, 0.5, 0.5)
		else:
			desc_label.modulate = Color(1, 1, 1, 1.0)
	
	if cost_label:
		cost_label.text = "—" if lvl >= max_lvl else "%d" % int(round(cost))
		if lvl < max_lvl and gm.memories < cost:
			cost_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		else:
			cost_label.remove_theme_color_override("font_color")
	
	if bar:
		bar.min_value = 0
		bar.max_value = max_lvl
		bar.value = lvl

	 # Debug check
	var is_maxed: bool = lvl >= max_lvl
	var can_afford: bool = gm.memories >= cost
	var should_disable := is_maxed or not can_afford
	
	#print("PermPerk %s: lvl=%d, cost=%d, memories=%d, disabled=%s" % [
	#	perk_id, lvl, cost, gm.memories, should_disable
	#])
	
	if btn:
		btn.disabled = should_disable
		# Force mouse filter to ensure clicks go through
		btn.mouse_filter = MOUSE_FILTER_STOP
	
	
