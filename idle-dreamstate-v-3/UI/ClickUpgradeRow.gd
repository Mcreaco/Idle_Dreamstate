extends HBoxContainer
class_name ClickUpgradeRow

@export var upgrade_type: String = "power"

var btn: Button  # Created dynamically
var bar: ProgressBar  # Created dynamically
var cost_label: Label  # Created dynamically
var desc_label: Label

var gm: Node

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false)
	
	size_flags_horizontal = SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	
	# Create BuyButton
	btn = Button.new()
	btn.name = "BuyButton"
	btn.custom_minimum_size = Vector2(120, 36)
	btn.size_flags_horizontal = SIZE_SHRINK_BEGIN
	btn.pressed.connect(_on_buy)
	add_child(btn)
	
	# Create Description Label
	desc_label = Label.new()
	desc_label.name = "DescLabel"
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	desc_label.size_flags_horizontal = SIZE_EXPAND_FILL
	desc_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(desc_label)
	
	# Create Cost Label
	cost_label = Label.new()
	cost_label.name = "CostLabel"
	cost_label.custom_minimum_size = Vector2(80, 0)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(cost_label)
	
	# Create Progress Bar
	bar = ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(100, 16)
	bar.size_flags_horizontal = SIZE_SHRINK_END
	bar.size_flags_vertical = SIZE_SHRINK_CENTER
	add_child(bar)
	
	refresh()

func _process(_delta: float) -> void:
	refresh()

func _on_buy() -> void:
	if gm == null:
		return
	var success := false
	match upgrade_type:
		"power": success = gm.try_buy_click_power_upgrade()
		"control": success = gm.try_buy_click_control_upgrade()
		"stability": success = gm.try_buy_click_stability_upgrade()
		"flow": success = gm.try_buy_click_flow_upgrade()
		"resonance": success = gm.try_buy_click_resonance_upgrade()
	if success:
		refresh()

func refresh() -> void:
	if gm == null:
		return
	
	@warning_ignore("unused_variable")
	var title: String = ""
	var level: int = 0
	var max_level: int = 10
	var cost: float = 0.0
	var desc: String = ""
	
	match upgrade_type:
		"power":
			title = "Mental Strike"
			level = gm.click_power_level
			cost = gm.get_click_power_cost()
			var power: float = gm.get_click_power()
			desc = "+%s thoughts per manual click" % gm._fmt_num(power)
		"control":
			title = "Controlled Breathing"
			level = gm.click_control_level
			cost = gm.get_click_control_cost()
			var control_amt: float = gm.click_control_gain * (1.0 + float(level) * 0.1)
			desc = "+%.1f Control per click" % control_amt
		"stability":
			title = "Pressure Release"
			level = gm.click_stability_level
			cost = gm.get_click_stability_cost()
			var reduction: float = gm.click_instability_reduction
			desc = "-%.1f%% Instability per click" % reduction
		"flow":
			title = "Flow State"
			level = gm.click_flow_level
			cost = gm.get_click_flow_cost()
			var window: float = 2.0 + (float(level) * 0.15)
			var bonus: float = (0.15 + float(level) * 0.02) * 100.0
			desc = "Combo: +%.0f%% per click (%.1fs)" % [bonus, window]
		"resonance":
			title = "Deep Resonance"
			level = gm.click_resonance_level
			cost = gm.get_click_resonance_cost()
			var bonus_pct: float = float(level) * 2.5
			desc = "+%.1f%% of idle production" % bonus_pct
	
	if btn:
		btn.text = "Lv %d/%d" % [level, max_level] if level < max_level else "MAXED"
		btn.disabled = (level >= max_level) or (gm.thoughts < cost)
	
	if desc_label:
		desc_label.text = desc
	
	if cost_label:
		if level >= max_level:
			cost_label.text = "—"
			cost_label.remove_theme_color_override("font_color")
		else:
			cost_label.text = gm._fmt_num(cost)
			if gm.thoughts < cost:
				cost_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
			else:
				cost_label.remove_theme_color_override("font_color")
	
	if bar:
		bar.min_value = 0
		bar.max_value = max_level
		bar.value = level
