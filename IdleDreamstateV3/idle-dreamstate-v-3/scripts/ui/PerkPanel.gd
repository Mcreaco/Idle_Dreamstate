extends PanelContainer
class_name PerksPanel

@export var refresh_interval: float = 0.25
@export var debug_print: bool = true
@export var start_hidden: bool = true

# Optional parent header UI (above the panel)
@export var parent_title_name: String = "Title"
@export var parent_info_name: String = "Info"

var _gm: GameManager
var _perks: PerkSystem

var _p1_btn: Button
var _p2_btn: Button
var _p3_btn: Button

var _p1_label: Label
var _p2_label: Label
var _p3_label: Label

var _close_btn: Button

# Parent header nodes
var _header_title: Label
var _header_info: RichTextLabel

var _t: float = 0.0


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_perks = get_tree().current_scene.find_child("PerkSystem", true, false) as PerkSystem

	_p1_btn = find_child("Perk1BuyButton", true, false) as Button
	_p2_btn = find_child("Perk2BuyButton", true, false) as Button
	_p3_btn = find_child("Perk3BuyButton", true, false) as Button

	_p1_label = find_child("Perk1Label", true, false) as Label
	_p2_label = find_child("Perk2Label", true, false) as Label
	_p3_label = find_child("Perk3Label", true, false) as Label

	_close_btn = find_child("CloseButton", true, false) as Button
	if _close_btn != null and not _close_btn.pressed.is_connected(Callable(self, "_on_close")):
		_close_btn.pressed.connect(Callable(self, "_on_close"))

	if _p1_btn != null and not _p1_btn.pressed.is_connected(Callable(self, "_buy1")):
		_p1_btn.pressed.connect(Callable(self, "_buy1"))
	if _p2_btn != null and not _p2_btn.pressed.is_connected(Callable(self, "_buy2")):
		_p2_btn.pressed.connect(Callable(self, "_buy2"))
	if _p3_btn != null and not _p3_btn.pressed.is_connected(Callable(self, "_buy3")):
		_p3_btn.pressed.connect(Callable(self, "_buy3"))

	# Find the header nodes sitting ABOVE this panel (anywhere under the same parent container)
	var p := get_parent()
	if p != null:
		_header_title = p.find_child(parent_title_name, true, false) as Label
		_header_info = p.find_child(parent_info_name, true, false) as RichTextLabel

	if debug_print:
		print("PerksPanel header find | parent=", p, " title=", _header_title, " info=", _header_info)

	# Prep header nodes
	if _header_title != null and _header_title.text.strip_edges() == "":
		_header_title.text = "Perks"

	if _header_info != null:
		_header_info.visible = true
		_header_info.bbcode_enabled = true

	if start_hidden:
		visible = false

	set_process(true)
	_refresh()


func open() -> void:
	visible = true
	_refresh()
	if debug_print:
		print("PerksPanel OPEN")


func close() -> void:
	visible = false
	if debug_print:
		print("PerksPanel CLOSE")


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func _on_close() -> void:
	close()


func _process(delta: float) -> void:
	if not visible:
		return

	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _gm == null or _perks == null:
		return

	_set_row(1, _p1_label, _p1_btn)
	_set_row(2, _p2_label, _p2_btn)
	_set_row(3, _p3_label, _p3_btn)

	_refresh_header()


func _refresh_header() -> void:
	if _header_title != null:
		_header_title.text = "Perks"

	if _header_info == null:
		return

	var t := _perks.get_thoughts_mult()
	var c := _perks.get_control_mult()
	var i := _perks.get_instability_mult()

	var msg := "Spend [b]Memories[/b] for permanent bonuses.\nCurrent: Thoughts x%.2f  |  Control x%.2f  |  Instab x%.2f" % [t, c, i]

	# Safest way: set text directly
	_header_info.text = msg


func _set_row(perk_id: int, lbl: Label, btn: Button) -> void:
	if lbl == null or btn == null:
		return

	var lvl := _perks.get_perk_level(perk_id)
	var maxlvl := _perks.get_perk_max(perk_id)
	var maxed := _perks.is_maxed(perk_id)

	var perk_name := _perks.get_perk_name(perk_id)
	var desc := _perks.get_perk_desc(perk_id)

	if maxed:
		lbl.text = "%s (Lv %d/%d)\n%s\nMAXED" % [perk_name, lvl, maxlvl, desc]
		btn.text = "Maxed"
		btn.disabled = true
		return

	var cost := _perks.get_cost(perk_id)
	lbl.text = "%s (Lv %d/%d)\n%s\nCost: %d Memories" % [perk_name, lvl, maxlvl, desc, cost]

	btn.text = "Buy (%d)" % cost
	btn.disabled = _gm.memories < float(cost)


func _buy1() -> void:
	_buy(1)

func _buy2() -> void:
	_buy(2)

func _buy3() -> void:
	_buy(3)

func _buy(perk_id: int) -> void:
	if _gm == null or _perks == null:
		return

	var res: Dictionary = _perks.try_buy(perk_id, _gm.memories)
	if bool(res.bought):
		_gm.memories -= float(res.cost)
		_gm.save_game()
		_refresh()
