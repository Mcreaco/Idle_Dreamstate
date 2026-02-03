extends VBoxContainer
class_name CurrencySummaryPanel

@export var show_only_unlocked: bool = true

var depth_meta: DepthMetaSystem
var gm: GameManager

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	depth_meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false) as DepthMetaSystem
	_build_rows()
	set_process(true)

func _build_rows() -> void:
	for c in get_children():
		c.queue_free()

	if depth_meta == null:
		return

	for d in range(1, DepthMetaSystem.MAX_DEPTH + 1):
		var row := HBoxContainer.new()
		row.name = "Row%d" % d
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var name_lbl := Label.new()
		name_lbl.name = "Name"
		name_lbl.custom_minimum_size.x = 180
		row.add_child(name_lbl)

		var amount_lbl := Label.new()
		amount_lbl.name = "Amount"
		amount_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(amount_lbl)

		add_child(row)

func _process(_delta: float) -> void:
	_refresh()

func _refresh() -> void:
	if depth_meta == null:
		return

	var max_depth := 1
	if gm != null:
		max_depth = maxi(1, gm.max_depth_reached)

	for d in range(1, DepthMetaSystem.MAX_DEPTH + 1):
		var row := get_node_or_null("Row%d" % d) as HBoxContainer
		if row == null:
			continue

		row.visible = (not show_only_unlocked) or (d <= max_depth)

		var name_lbl := row.get_node("Name") as Label
		var amount_lbl := row.get_node("Amount") as Label

		var cname := DepthMetaSystem.get_depth_currency_name(d)
		var amt := depth_meta.currency[d]

		name_lbl.text = "%s:" % cname
		amount_lbl.text = "%.2f" % amt
