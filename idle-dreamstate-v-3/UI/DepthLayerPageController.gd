extends Control
class_name DepthLayerPageController

@export var depth_index: int = 1

@onready var currency_label: Label = get_node_or_null("Margin/VBox/CurrencyLabel") as Label
@onready var afk_label: Label = get_node_or_null("Margin/VBox/AfkLabel") as Label
@onready var upgrades_vbox: VBoxContainer = get_node_or_null("Margin/VBox/UpgradesVBox") as VBoxContainer
@onready var bg: ColorRect = get_node_or_null("Margin/Bg") as ColorRect # optional

var gm: GameManager
var depth_meta: DepthMetaSystem

var _refresh_t := 0.0

func _ready() -> void:
	gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	depth_meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false) as DepthMetaSystem

	# Optional: darken panel so text behind doesn't show through visually
	if bg != null:
		bg.color = Color(0, 0, 0, 0.72) # tweak alpha to taste
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_rebuild_rows()
	_refresh()
	set_process(true)

func _process(delta: float) -> void:
	_refresh_t += delta
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		_refresh()
	else:
		_refresh_afk_only()

func _rebuild_rows() -> void:
	if upgrades_vbox == null or depth_meta == null:
		return

	for c in upgrades_vbox.get_children():
		c.queue_free()

	var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)
	var defs := depth_meta.get_depth_upgrade_defs(d)

	for def in defs:
		var row := DepthUpgradeRow.new()
		row.depth_index = d
		row.upgrade_id = String(def.get("id", ""))
		row.upgrade_name = String(def.get("name", ""))
		row.upgrade_desc = String(def.get("desc", ""))
		row.max_level = int(def.get("max", 1))
		row.depth_meta = depth_meta
		row.gm = gm
		upgrades_vbox.add_child(row)

func _refresh() -> void:
	if depth_meta == null:
		return
	var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)

	if currency_label != null:
		var cname := DepthMetaSystem.get_depth_currency_name(d)
		currency_label.text = "%s: %.2f" % [cname, depth_meta.currency[d]]

	_refresh_afk_only()

func _refresh_afk_only() -> void:
	if gm == null or afk_label == null:
		return
	if gm.get_current_depth() != depth_index:
		afk_label.text = "AFK: (enter this depth to estimate)"
		return
	var s := gm.get_seconds_until_fail()
	if s >= 999999.0:
		afk_label.text = "AFK: safe (no risk gain)"
	else:
		afk_label.text = "AFK until reset: %s" % _fmt_time(s)

func _fmt_time(sec: float) -> String:
	var t := int(maxf(sec, 0.0))
	var m := int(t / 60.0)
	var r := t % 60
	return "%02d:%02d" % [m, r]
