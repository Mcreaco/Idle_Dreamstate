extends PanelContainer
class_name ClickUpgradeRow

var _name_lbl: Label
var _desc_lbl: Label
var _lvl_lbl: Label
var _cost_lbl: Label
var _buy_btn: Button
var _bar: ProgressBar
var evolve_btn: Button = null
var main_hbox: HBoxContainer

@export var upgrade_type: String = "power"
var gm: Node
var _is_blinded: bool = false
var _inner_eye_lvl: int = 0

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false)
	
	size_flags_horizontal = SIZE_EXPAND_FILL
	custom_minimum_size.y = 60
	
	# Blue border style matching Reset tab
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.10, 0.14, 0.88)
	panel_style.border_color = Color(0.24, 0.67, 0.94, 0.8)
	panel_style.border_width_left = 2
	panel_style.border_width_top = 2
	panel_style.border_width_right = 2
	panel_style.border_width_bottom = 2
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", panel_style)
	
	# Main horizontal container
	main_hbox = HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 12)
	add_child(main_hbox)
	
	# LEFT: Name + Description
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.custom_minimum_size.x = 300
	main_hbox.add_child(left_vbox)
	
	_name_lbl = Label.new()
	_name_lbl.add_theme_font_size_override("font_size", 17)
	_name_lbl.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	left_vbox.add_child(_name_lbl)
	
	_desc_lbl = Label.new()
	_desc_lbl.add_theme_font_size_override("font_size", 13)
	_desc_lbl.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(_desc_lbl)
	
	# MIDDLE: Progress bar (to next milestone)
	var bar_vbox := VBoxContainer.new()
	bar_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_vbox.custom_minimum_size.x = 150
	main_hbox.add_child(bar_vbox)
	
	_lvl_lbl = Label.new()
	_lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lvl_lbl.add_theme_font_size_override("font_size", 15)
	bar_vbox.add_child(_lvl_lbl)
	
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(120, 20)
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.show_percentage = false
	
	# Style the progress bar with blue theme
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.07, 0.10, 0.9)
	bar_bg.corner_radius_top_left = 8
	bar_bg.corner_radius_top_right = 8
	bar_bg.corner_radius_bottom_left = 8
	bar_bg.corner_radius_bottom_right = 8
	
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.24, 0.67, 0.94, 1.0)
	bar_fill.corner_radius_top_left = 8
	bar_fill.corner_radius_top_right = 8
	bar_fill.corner_radius_bottom_left = 8
	bar_fill.corner_radius_bottom_right = 8
	
	_bar.add_theme_stylebox_override("background", bar_bg)
	_bar.add_theme_stylebox_override("fill", bar_fill)
	_bar.custom_minimum_size.y = 20
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_vbox.add_child(_bar)
	
	# Milestone label
	var milestone_lbl := Label.new()
	milestone_lbl.name = "MilestoneLabel"
	milestone_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	milestone_lbl.add_theme_font_size_override("font_size", 11)
	milestone_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	bar_vbox.add_child(milestone_lbl)
	
	# RIGHT: Cost and Buy button
	var right_hbox := HBoxContainer.new()
	right_hbox.add_theme_constant_override("separation", 8)
	main_hbox.add_child(right_hbox)
	
	_cost_lbl = Label.new()
	_cost_lbl.custom_minimum_size.x = 100
	_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost_lbl.add_theme_font_size_override("font_size", 15)
	right_hbox.add_child(_cost_lbl)
	
	_buy_btn = Button.new()
	_buy_btn.custom_minimum_size = Vector2(80, 36)
	_buy_btn.pressed.connect(_on_buy)
	
	# Style buy button
	var btn_style := StyleBoxFlat.new()
	btn_style.bg_color = Color(0.12, 0.20, 0.35, 1.0)
	btn_style.border_color = Color(0.35, 0.65, 0.95, 1.0)
	btn_style.border_width_left = 2
	btn_style.border_width_top = 2
	btn_style.border_width_right = 2
	btn_style.border_width_bottom = 2
	btn_style.corner_radius_top_left = 6
	btn_style.corner_radius_top_right = 6
	btn_style.corner_radius_bottom_left = 6
	btn_style.corner_radius_bottom_right = 6
	_buy_btn.add_theme_stylebox_override("normal", btn_style)
	
	var btn_hover := btn_style.duplicate()
	btn_hover.bg_color = Color(0.18, 0.30, 0.50, 1.0)
	_buy_btn.add_theme_stylebox_override("hover", btn_hover)
	
	var btn_disabled := btn_style.duplicate()
	btn_disabled.bg_color = Color(0.08, 0.10, 0.12, 0.6)
	btn_disabled.border_color = Color(0.3, 0.35, 0.4, 0.5)
	_buy_btn.add_theme_stylebox_override("disabled", btn_disabled)
	
	right_hbox.add_child(_buy_btn)
	
	# Evolution button
	evolve_btn = Button.new()
	evolve_btn.text = "Evolve ★"
	evolve_btn.visible = false
	evolve_btn.custom_minimum_size = Vector2(90, 36)
	evolve_btn.pressed.connect(_on_evolve_pressed)
	
	# Style evolve button (gold)
	var evo_style := StyleBoxFlat.new()
	evo_style.bg_color = Color(0.35, 0.30, 0.12, 1.0)
	evo_style.border_color = Color(0.95, 0.85, 0.35, 1.0)
	evo_style.border_width_left = 2
	evo_style.border_width_top = 2
	evo_style.border_width_right = 2
	evo_style.border_width_bottom = 2
	evo_style.corner_radius_top_left = 6
	evo_style.corner_radius_top_right = 6
	evo_style.corner_radius_bottom_left = 6
	evo_style.corner_radius_bottom_right = 6
	evolve_btn.add_theme_stylebox_override("normal", evo_style)
	
	var evo_hover := evo_style.duplicate()
	evo_hover.bg_color = Color(0.50, 0.45, 0.18, 1.0)
	evolve_btn.add_theme_stylebox_override("hover", evo_hover)
	
	right_hbox.add_child(evolve_btn)
	
	refresh()

func set_blinded(enabled: bool, inner_eye_level: int) -> void:
	_is_blinded = enabled
	_inner_eye_lvl = inner_eye_level
	refresh()

func _on_buy() -> void:
	if gm == null:
		print("ERROR: No GameManager")
		return
		
	# Debug which upgrade type
	print("BUY CLICK: type=", upgrade_type)
	
	var success := false
	match upgrade_type:
		"power": 
			success = gm.try_buy_click_power_upgrade()
			print("Bought Mental Strike, new level=", gm.click_power_level)
		"stability": 
			success = gm.try_buy_click_stability_upgrade()
		"flow": 
			success = gm.try_buy_click_flow_upgrade()
		"resonance": 
			success = gm.try_buy_click_resonance_upgrade()
		"combat_focus": 
			success = gm.try_buy_click_combat_focus_upgrade()
	
	if success:
		refresh()

func _on_evolve_pressed() -> void:
	if gm == null:
		return
	_show_sacrifice_dialog()

func _show_sacrifice_dialog() -> void:
	var dialog := PanelContainer.new()
	dialog.set_anchors_preset(Control.PRESET_CENTER)
	dialog.custom_minimum_size = Vector2(400, 300)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	dialog.add_child(vbox)
	
	var title := Label.new()
	title.text = "Choose Sacrifice for Evolution"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	
	var desc := Label.new()
	desc.text = "Select one upgrade to weaken by 50% (permanent this run)"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc)
	
	# Updated options (removed dreamcloud, added combat_focus)
	var options := ["power", "stability", "flow", "resonance", "combat_focus"]
	for opt in options:
		if opt == upgrade_type:
			continue
		
		var sac_btn := Button.new()
		var penalty_str := "50%"
		if gm.perm_perk_system != null:
			var mastery: float = gm.perm_perk_system.get_evolution_mastery_reduction()
			penalty_str = str(int((0.5 - mastery) * 100)) + "%"
		
		sac_btn.text = "Weaken %s by %s" % [opt.capitalize().replace("_", " "), penalty_str]
		sac_btn.pressed.connect(func():
			if gm.evolve_upgrade(upgrade_type, opt):
				dialog.queue_free()
				refresh()
		)
		vbox.add_child(sac_btn)
	
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(func(): dialog.queue_free())
	vbox.add_child(cancel_btn)
	
	add_child(dialog)

func _get_next_milestone(current: int) -> int:
	var milestones := [10, 25, 50, 100, 200, 300, 400, 500, 750, 1000]
	for m in milestones:
		if current < m:
			return m
	return 1000

func refresh() -> void:
	if gm == null:
		return
	
	var title := ""
	var level := 0
	var cost := 0.0
	var desc := ""
	var next_milestone := 0
	var prev_milestone := 0
	
	match upgrade_type:
		"power":
			title = "Mental Strike"
			level = gm.click_power_level
			cost = gm.get_click_power_cost()
			var percent: float = level * 0.1
			desc = "+%.1f%% of current Thoughts per click" % percent
		
		"stability":
			title = "Pressure Release"
			level = gm.click_stability_level
			cost = gm.get_click_stability_cost()
			var percent: float = level * 2.0
			desc = "-%.0f%% Instability per click" % percent
		
		"flow":
			title = "Flow State"
			level = gm.click_flow_level
			cost = gm.get_click_flow_cost()
			var window: float = gm.get_combo_window()
			var mult: float = gm.get_combo_multiplier()
			desc = "Combo: ×%.2f (%.1fs)" % [mult, window]
		
		"resonance":
			title = "Deep Resonance"
			level = gm.click_resonance_level
			cost = gm.get_click_resonance_cost()
			var bonus: float = level * 0.01
			desc = "+%.2f%% idle thoughts (permanent)" % bonus
		
		"combat_focus":
			title = "Combat Focus"
			level = gm.click_combat_focus_level if "click_combat_focus_level" in gm else 0
			cost = gm.get_click_combat_focus_cost() if gm.has_method("get_click_combat_focus_cost") else 50.0
			var amount: int = level
			desc = "+%d Dreamcloud per click (Combat only)" % amount
	
	# Calculate milestones
	next_milestone = _get_next_milestone(level)
	# Current tier start (prev milestone)
	var milestones := [0, 10, 25, 50, 100, 200, 300, 400, 500, 750, 1000]
	prev_milestone = 0
	for i in range(milestones.size()):
		if milestones[i] == next_milestone:
			if i > 0:
				prev_milestone = milestones[i-1]
			break
	
	# Update name
	if _name_lbl:
		var evo_count := 0
		match upgrade_type:
			"power": evo_count = gm.click_power_evolution if "click_power_evolution" in gm else 0
			"stability": evo_count = gm.click_stability_evolution if "click_stability_evolution" in gm else 0
			"flow": evo_count = gm.click_flow_evolution if "click_flow_evolution" in gm else 0
			"resonance": evo_count = gm.click_resonance_evolution if "click_resonance_evolution" in gm else 0
			"combat_focus": evo_count = gm.click_combat_focus_evolution if "click_combat_focus_evolution" in gm else 0
		
		if evo_count > 0:
			var stars := "★".repeat(evo_count)
			_name_lbl.text = title + " " + stars
			_name_lbl.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
		else:
			_name_lbl.text = title
			_name_lbl.remove_theme_color_override("font_color")
	
	if _desc_lbl:
		_desc_lbl.text = desc
	
	if _lvl_lbl:
		_lvl_lbl.text = "Level %d" % level
		_lvl_lbl.visible = not (_is_blinded and _inner_eye_lvl < 3)
	
	# Update buy button
	if _buy_btn:
		if level >= 1000:
			_buy_btn.visible = false
		else:
			_buy_btn.visible = true
			if gm.thoughts < cost:
				_buy_btn.text = "Buy"
				_buy_btn.disabled = true
			else:
				_buy_btn.text = "Buy"
				_buy_btn.disabled = false
	
	# Update cost label
	if _cost_lbl:
		if level >= 1000:
			_cost_lbl.text = "MAX"
			_cost_lbl.modulate = Color(1, 1, 1)
		else:
			_cost_lbl.text = gm._fmt_num(cost) if gm.has_method("_fmt_num") else str(cost)
			if gm.thoughts < cost:
				_cost_lbl.modulate = Color(0.9, 0.3, 0.3)
			else:
				_cost_lbl.modulate = Color(1, 1, 1)
		
		if _is_blinded and _inner_eye_lvl < 4:
			_cost_lbl.text = "???"
			_cost_lbl.modulate = Color(0.7, 0.7, 0.7)
	
	# CRITICAL FIX: Update progress bar with proper reset
	if _bar:
		if level >= 1000:
			_bar.visible = false
		else:
			_bar.visible = true
			
			# Set values as floats to ensure proper calculation
			_bar.min_value = float(prev_milestone)
			_bar.max_value = float(next_milestone)
			_bar.value = float(level)
			
			# Enforce height
			_bar.custom_minimum_size.y = 20
			_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			
			# Force update
			_bar.queue_redraw()
			
			# Update milestone text
			var milestone_lbl = _bar.get_parent().get_node_or_null("MilestoneLabel")
			if milestone_lbl:
				if next_milestone >= 1000:
					milestone_lbl.text = "Next: Evolution"
				else:
					milestone_lbl.text = "Next: Lv %d" % next_milestone
			
			_bar.visible = not (_is_blinded and _inner_eye_lvl < 3)
			if milestone_lbl: milestone_lbl.visible = _bar.visible
	
	# Evolution button
	if level >= 1000:
		evolve_btn.visible = true
	else:
		evolve_btn.visible = false
