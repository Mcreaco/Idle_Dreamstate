extends Panel
class_name UpgradeInfoPanel

# Button node names in your UI
@export var thoughts_upgrade_button_name: String = "BuyThoughtsUpgradeButton"
@export var stability_upgrade_button_name: String = "BuyStabilityUpgradeButton"

# UpgradeManager node name
@export var upgrade_manager_node_name: String = "UpgradeManager"

# Tier brackets for the “milestone bar”
@export var tiers: Array = [
	{"start": 1, "end": 10, "label": "Tier 1 (Lv 1–10)"},
	{"start": 11, "end": 25, "label": "Tier 2 (Lv 11–25)"},
	{"start": 26, "end": 50, "label": "Tier 3 (Lv 26–50)"},
	{"start": 51, "end": 100, "label": "Tier 4 (Lv 51–100)"}
]

@onready var title_label: Label = $VBox/TitleLabel
@onready var desc_label: Label = $VBox/DescLabel
@onready var current_label: Label = $VBox/CurrentLabel
@onready var next_label: Label = $VBox/NextLabel
@onready var tier_label: Label = $VBox/TierLabel
@onready var tier_bar: ProgressBar = $VBox/TierBar

var _upgrade_manager: Node = null
var _btn_thoughts: Button = null
var _btn_stability: Button = null
var _selected: String = "thoughts"


func _ready() -> void:
	var scene := get_tree().current_scene

	_upgrade_manager = scene.find_child(upgrade_manager_node_name, true, false)
	if _upgrade_manager == null:
		push_error("UpgradeInfoPanel: could not find UpgradeManager.")

	_btn_thoughts = scene.find_child(thoughts_upgrade_button_name, true, false) as Button
	_btn_stability = scene.find_child(stability_upgrade_button_name, true, false) as Button

	if _btn_thoughts != null:
		_btn_thoughts.mouse_entered.connect(func(): _selected = "thoughts"; _refresh())
		_btn_thoughts.focus_entered.connect(func(): _selected = "thoughts"; _refresh())

	if _btn_stability != null:
		_btn_stability.mouse_entered.connect(func(): _selected = "stability"; _refresh())
		_btn_stability.focus_entered.connect(func(): _selected = "stability"; _refresh())

	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tier_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	_refresh()
	set_process(true)


func _process(_delta: float) -> void:
	_refresh()


func _refresh() -> void:
	if _upgrade_manager == null:
		title_label.text = "UPGRADES"
		desc_label.text = "UpgradeManager not found."
		current_label.text = ""
		next_label.text = ""
		tier_label.text = ""
		tier_bar.value = 0
		return

	if _selected == "thoughts":
		_render_thoughts_upgrade()
	else:
		_render_stability_upgrade()


func _render_thoughts_upgrade() -> void:
	var lvl: int = int(_upgrade_manager.get("thoughts_level"))
	var cost: float = float(_upgrade_manager.call("get_thoughts_cost"))
	var mult_now: float = float(_upgrade_manager.call("get_thoughts_mult"))
	var mult_next: float = _predict_next_mult(mult_now, lvl)

	title_label.text = "Thoughts Up"
	desc_label.text = "Increases your Thoughts gain multiplier (idle + Dive)."

	current_label.text = "Current: Lv %d → x%.2f Thoughts gain" % [lvl, mult_now]
	next_label.text = "Next:    Lv %d → x%.2f (Cost: %d Thoughts)" % [lvl + 1, mult_next, int(round(cost))]

	_render_tier(lvl)


func _render_stability_upgrade() -> void:
	var lvl: int = int(_upgrade_manager.get("stability_level"))
	var cost: float = float(_upgrade_manager.call("get_stability_cost"))
	var mult_now: float = float(_upgrade_manager.call("get_instability_mult"))
	var mult_next: float = _predict_next_mult(mult_now, lvl)

	title_label.text = "Stability Up"
	desc_label.text = "Reduces Instability gain multiplier (survive longer)."

	current_label.text = "Current: Lv %d → x%.2f Instability gain" % [lvl, mult_now]
	next_label.text = "Next:    Lv %d → x%.2f (Cost: %d Thoughts)" % [lvl + 1, mult_next, int(round(cost))]

	_render_tier(lvl)


func _render_tier(level: int) -> void:
	var t: Dictionary = _get_tier(level)
	var start: int = int(t["start"])
	var end: int = int(t["end"])

	tier_label.text = "%s — milestone at Lv %d" % [String(t["label"]), end]

	var denom := maxf(float(end - start), 1.0)
	var prog := clampf(float(level - start) / denom, 0.0, 1.0)

	tier_bar.min_value = 0
	tier_bar.max_value = 1
	tier_bar.value = prog


func _get_tier(level: int) -> Dictionary:
	for t in tiers:
		var s: int = int(t["start"])
		var e: int = int(t["end"])
		if level <= e:
			return {"start": s, "end": e, "label": String(t["label"])}

	# beyond last tier
	var last: Dictionary = tiers[tiers.size() - 1]
	return {"start": int(last["start"]), "end": int(last["end"]), "label": String(last["label"])}


func _predict_next_mult(current_mult: float, level: int) -> float:
	var t: Dictionary = _get_tier(level)
	var end: int = int(t["end"])

	var normal_step: float = 1.03
	var milestone_step: float = 1.10

	if level + 1 == end:
		return current_mult * milestone_step
	return current_mult * normal_step
