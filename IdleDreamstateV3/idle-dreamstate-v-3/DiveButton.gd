extends Button

var gm: Node = null
var perks: PerkSystem = null

@export var dive_cd_base: float = 10.0
@export var dive_cd_min: float = 3.0
@export var perk2_cd_reduction_per_level: float = 0.5

var _cd_left: float = 0.0
var _base_text: String = "Dive"
var _just_ready: bool = false
var _ready_flash_time: float = 0.5
var _ready_timer: float = 0.0

func _ready() -> void:
	_base_text = text if text != "" else "Dive"

	var scene := get_tree().get_current_scene()
	gm = scene.get_node_or_null("GameManager")
	perks = scene.get_node_or_null("Systems/PerkSystem") as PerkSystem

	if gm == null:
		push_error("DiveButton: GameManager not found.")
		return

	pressed.connect(_on_pressed)
	set_process(true)
	_update_ui()

func _process(delta: float) -> void:
	if _cd_left > 0.0:
		_cd_left = max(0.0, _cd_left - delta)
		if _cd_left == 0.0:
			_just_ready = true
			_ready_timer = _ready_flash_time

	if _just_ready:
		_ready_timer -= delta
		if _ready_timer <= 0.0:
			_just_ready = false

	_update_ui()

func _current_cooldown() -> float:
	var cd: float = dive_cd_base
	if perks != null:
		cd -= perk2_cd_reduction_per_level * float(perks.perk2_level)
	return max(dive_cd_min, cd)

func _on_pressed() -> void:
	if _cd_left > 0.0:
		return

	if gm.has_method("do_dive"):
		gm.call("do_dive")
	else:
		push_error("DiveButton: GameManager has no do_dive()")
		return

	_cd_left = _current_cooldown()
	_update_ui()

func _update_ui() -> void:
	if _cd_left > 0.0:
		disabled = true
		text = "%s (%.1fs)" % [_base_text, _cd_left]
	elif _just_ready:
		disabled = false
		text = "%s ✓" % _base_text
	else:
		disabled = false
		text = _base_text
