extends VBoxContainer
class_name NormalVBoxInfo

@export var refresh_interval: float = 0.2
@export var title_prefix: String = "RUN"

var _gm: GameManager
var _risk: RiskSystem
var _perks: PerkSystem

var _title: Label
var _tier: Label
var _depth_label: Label
var _bonuses: Label # optional

var _t: float = 0.0


func _ready() -> void:
	_title = find_child("Title", true, false) as Label
	_tier = find_child("TierRow", true, false) as Label
	_depth_label = find_child("DepthRow", true, false) as Label
	_bonuses = find_child("BonusesRow", true, false) as Label # may be null

	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	if _gm != null:
		_risk = _gm.risk_system

	_perks = get_tree().current_scene.find_child("PerkSystem", true, false) as PerkSystem

	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _title == null or _tier == null or _depth_label == null:
		return
	if _gm == null or _risk == null:
		return

	var tier_name: String = str(_risk.get_state(_gm.instability))
	var depth_tier: String = _gm.get_depth_tier_name()

	_title.text = "%s — %s" % [title_prefix, tier_name]
	_tier.text = "Tier: %s   |   Instability: %d%%" % [tier_name, int(round(_gm.instability))]
	_depth_label.text = "Depth %d — %s" % [_gm.depth, depth_tier]

	# BonusesRow is optional
	if _bonuses != null and _perks != null:
		var thoughts_mult := _perks.get_thoughts_mult()
		var control_mult := _perks.get_control_mult()
		var instab_mult := _perks.get_instability_mult()
		_bonuses.text = "Bonuses: Thoughts x%.2f  |  Control x%.2f  |  Instab x%.2f" % [
			thoughts_mult, control_mult, instab_mult
		]
