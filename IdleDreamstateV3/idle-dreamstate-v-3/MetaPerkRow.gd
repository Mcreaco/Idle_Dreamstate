extends HBoxContainer
class_name MetaPerkRow

@export var perk_id: String = "echoed_descent" # echoed_descent | abyssal_focus | dark_insight | abyss_veil
var gm: GameManager
var abyss: AbyssPerkSystem

@onready var btn: Button = $BuyButton
@onready var bar: Range = $Bar
@onready var cost_label: Label = $CostLabel

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	abyss = get_tree().current_scene.find_child("AbyssPerkSystem", true, false) as AbyssPerkSystem
	btn.pressed.connect(_on_buy)
	_refresh()
	set_process(true)

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
	if gm == null or abyss == null:
		return

	var title := ""
	var lvl := 0
	var max_lvl := 1
	var cost := 0.0
	var desc := ""

	match perk_id:
		"echoed_descent":
			title = "Echoed Descent"
			lvl = abyss.echoed_descent_level
			max_lvl = abyss.echoed_descent_max
			cost = abyss.get_echoed_descent_cost()
			desc = "Start each run deeper.\n+%d start depth per level." % abyss.start_depth_per_level
		"abyssal_focus":
			title = "Abyssal Focus"
			lvl = abyss.abyssal_focus_level
			max_lvl = abyss.abyssal_focus_max
			cost = abyss.get_abyssal_focus_cost()
			desc = "More Control gain.\n+%d%% per level." % int(round(abyss.control_mult_step * 100.0))
		"dark_insight":
			title = "Dark Insight"
			lvl = abyss.dark_insight_level
			max_lvl = abyss.dark_insight_max
			cost = abyss.get_dark_insight_cost()
			desc = "More Thoughts gain.\n+%d%% per level." % int(round(abyss.thoughts_mult_step * 100.0))
		"abyss_veil":
			title = "Abyss Veil"
			lvl = abyss.abyss_veil_level
			max_lvl = abyss.abyss_veil_max
			cost = abyss.get_abyss_veil_cost()
			desc = "Reduce Instability gain at depth %d+.\n-%d%% per level (min 10%%)." % [
				abyss.abyss_veil_starts_at_depth,
				int(round(abyss.abyss_veil_step * 100.0))
			]

	btn.text = "%s (Lv %d/%d)" % [title, lvl, max_lvl]
	btn.disabled = (gm.memories < cost) or (lvl >= max_lvl)

	cost_label.text = "%d" % int(round(cost))

	bar.min_value = 0
	bar.max_value = max_lvl
	bar.value = lvl

	btn.tooltip_text = "%s\n\n%s\n\nCost: %d Memories" % [title, desc, int(round(cost))]
