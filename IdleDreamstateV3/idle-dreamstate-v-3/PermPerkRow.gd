extends HBoxContainer
class_name PermPerkRow

@export var perk_id: String = "memory_engine"
@export var debug_print: bool = false

@onready var btn: Button = $BuyButton
@onready var bar: Range = $Bar
@onready var cost_label: Label = $CostLabel

var gm: GameManager
var perm: PermPerkSystem
var _t := 0.0

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	perm = get_tree().current_scene.find_child("PermPerkSystem", true, false) as PermPerkSystem

	if debug_print:
		print("[PermPerkRow] ready id=", perk_id,
			" gm=", gm, " gm_path=", (str(gm.get_path()) if gm else "<null>"),
			" perm=", perm, " perm_path=", (str(perm.get_path()) if perm else "<null>"))

	if btn != null:
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if not btn.pressed.is_connected(Callable(self, "_on_buy")):
			btn.pressed.connect(Callable(self, "_on_buy"))

	set_process(true)
	refresh()

func _process(delta: float) -> void:
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()

func _on_buy() -> void:
	if gm == null or perm == null:
		if debug_print:
			print("[PermPerkRow] buy blocked: gm or perm null")
		return

	var res: Dictionary
	match perk_id:
		"memory_engine":      res = perm.try_buy_memory_engine(gm.memories)
		"calm_mind":          res = perm.try_buy_calm_mind(gm.memories)
		"focused_will":       res = perm.try_buy_focused_will(gm.memories)
		"starting_insight":   res = perm.try_buy_starting_insight(gm.memories)
		"stability_buffer":   res = perm.try_buy_stability_buffer(gm.memories)
		"offline_echo":       res = perm.try_buy_offline_echo(gm.memories)
		_:
			return

	var bought := bool(res.get("bought", false))
	var cost := float(res.get("cost", 0.0))

	if bought:
		# PermPerkSystem only increments level + returns cost, it does NOT spend.
		gm.memories = maxf(gm.memories - cost, 0.0)
		gm.save_game()

	refresh()

func refresh() -> void:
	if gm == null or perm == null:
		return

	var title := ""
	var lvl := 0
	var max_lvl := perm.max_level
	var cost := 0.0
	var tip := ""

	match perk_id:
		"memory_engine":
			title = "Memory Engine"
			lvl = perm.memory_engine_level
			cost = perm.cost_memory_engine()
			tip = "+5% Thoughts per level"
		"calm_mind":
			title = "Calm Mind"
			lvl = perm.calm_mind_level
			cost = perm.cost_calm_mind()
			tip = "-4% Instability gain per level"
		"focused_will":
			title = "Focused Will"
			lvl = perm.focused_will_level
			cost = perm.cost_focused_will()
			tip = "+6% Control per level"
		"starting_insight":
			title = "Starting Insight"
			lvl = perm.starting_insight_level
			cost = perm.cost_starting_insight()
			tip = "Start each run with +25 Thoughts per level"
		"stability_buffer":
			title = "Stability Buffer"
			lvl = perm.stability_buffer_level
			cost = perm.cost_stability_buffer()
			tip = "Start each run with -2 Instability per level"
		"offline_echo":
			title = "Offline Echo"
			lvl = perm.offline_echo_level
			cost = perm.cost_offline_echo()
			tip = "+8% Offline gains per level"

	if btn != null:
		btn.text = "%s (Lv %d/%d)" % [title, lvl, max_lvl]
		btn.disabled = (lvl >= max_lvl) or (gm.memories < cost)
		btn.tooltip_text = "%s\n%s\nCost: %d Memories\nYou have: %d" % [
			title, tip, int(round(cost)), int(round(gm.memories))
		]

	if cost_label != null:
		cost_label.text = "%d" % int(round(cost))

	if bar != null:
		bar.min_value = 0
		bar.max_value = max_lvl
		bar.value = lvl
