extends HBoxContainer
class_name DepthUpgradeRow

var depth_index: int = 1
var upgrade_id: String = ""
var upgrade_name: String = ""
var upgrade_desc: String = ""
var max_level: int = 1

var depth_meta: DepthMetaSystem
var gm: GameManager

var _name_lbl: Label
var _desc_lbl: Label
var _lvl_lbl: Label
var _cost_lbl: Label
var _buy_btn: Button
var _bar: ProgressBar

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_name_lbl = Label.new()
	_name_lbl.custom_minimum_size.x = 220
	add_child(_name_lbl)

	_desc_lbl = Label.new()
	_desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_desc_lbl.custom_minimum_size.x = 520
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_desc_lbl)

	_lvl_lbl = Label.new()
	_lvl_lbl.custom_minimum_size.x = 90
	add_child(_lvl_lbl)

	_cost_lbl = Label.new()
	_cost_lbl.custom_minimum_size.x = 260
	add_child(_cost_lbl)

	_bar = ProgressBar.new()
	_bar.custom_minimum_size.x = 160
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = true
	add_child(_bar)

	_buy_btn = Button.new()
	_buy_btn.text = "Buy"
	_buy_btn.custom_minimum_size.x = 70
	add_child(_buy_btn)

	_buy_btn.pressed.connect(_on_buy)

	# Match blue border buttons
	_buy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buy_btn.custom_minimum_size.x = 0
	if gm != null and gm.has_method("_style_button"):
		gm._style_button(_buy_btn)

	set_process(true)
	_refresh()

func _process(_delta: float) -> void:
	_refresh()

func _format_costs(d: int, def: Dictionary) -> Dictionary:
	var base := depth_meta.cost_for(d, def)
	var costs: Dictionary = def.get("costs", { d: 1.0 }) # default = only this depth currency

	var parts: Array[String] = []
	var ok := true

	for k in costs.keys():
		var idx := int(k)
		var need_f := base * float(costs[k])
		var need := int(round(need_f))
		var cname := DepthMetaSystem.get_depth_currency_name(idx)

		parts.append("%d %s" % [need, cname])

		if depth_meta.currency[idx] < need_f:
			ok = false

	return {
		"text": "Cost: " + " + ".join(parts),
		"ok": ok,
		"base": base,
		"costs": costs
	}

func _refresh() -> void:
	if depth_meta == null:
		return

	var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)
	var lvl := depth_meta.get_level(d, upgrade_id)

	_name_lbl.text = upgrade_name
	_desc_lbl.text = upgrade_desc
	_lvl_lbl.text = "Lv %d/%d" % [lvl, max_level]

	# find def
	var defs := depth_meta.get_depth_upgrade_defs(d)
	var def: Dictionary = {}
	for item in defs:
		if String(item.get("id", "")) == upgrade_id:
			def = item
			break

	var can_buy := true
	var cost_text := "Cost: ?"
	var affordability := 0.0

	if def.is_empty():
		can_buy = false
	else:
		var info := _format_costs(d, def)
		cost_text = String(info["text"])
		can_buy = bool(info["ok"])

		# affordability bar based on the “primary” cost in THIS depth currency
		var base := float(info["base"])
		var costs: Dictionary = info["costs"]
		var primary_mult := float(costs.get(d, 1.0))
		var primary_cost := base * primary_mult
		if primary_cost > 0.0:
			affordability = clampf((depth_meta.currency[d] / primary_cost) * 100.0, 0.0, 100.0)

	_cost_lbl.text = cost_text
	_bar.value = affordability

	if lvl >= max_level:
		can_buy = false

	# Hide unlock row until it should appear
	if upgrade_id == "unlock":
		visible = depth_meta.can_show_unlock_upgrade(d) and (d < DepthMetaSystem.MAX_DEPTH)
	else:
		visible = true

	_buy_btn.disabled = not can_buy

func _on_buy() -> void:
	if depth_meta == null:
		return

	var res := depth_meta.try_buy(depth_index, upgrade_id)
	if bool(res.get("bought", false)):
		if gm != null:
			if upgrade_id == "unlock":
				gm.force_unlock_depth_tab(depth_index + 1)
			gm.save_game()
