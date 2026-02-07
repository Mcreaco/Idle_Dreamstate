extends Node
class_name LifetimeStatsTracker

@export var game_manager_name: String = "GameManager"
@export var prestige_panel_name: String = "PrestigePanel"

# Save keys
const LT_THOUGHTS := "lifetime_thoughts"
const LT_CONTROL := "lifetime_control"
const LT_DIVES := "total_dives"
const LT_DEEPEST := "deepest_depth"
const LT_PLAYTIME := "total_playtime"

var _gm: Node = null
var _prev_thoughts: float = 0.0
var _prev_control: float = 0.0
var _sec_accum: float = 0.0

func _ready() -> void:
	_gm = get_tree().current_scene.find_child(game_manager_name, true, false)
	if _gm == null:
		push_error("LifetimeStatsTracker: GameManager not found.")
		return

	_prev_thoughts = _get_float("thoughts")
	_prev_control = _get_float("control")

	# Hook prestige confirm (counts as a dive/wake)
	var pp := get_tree().current_scene.find_child(prestige_panel_name, true, false)
	if pp != null and pp.has_signal("confirm_wake"):
		if not pp.confirm_wake.is_connected(_on_confirm_wake):
			pp.confirm_wake.connect(_on_confirm_wake)

	set_process(true)

func _process(delta: float) -> void:
	if _gm == null:
		return

	# Track lifetime totals by observing increases
	var t := _get_float("thoughts")
	var c := _get_float("control")

	var dt := t - _prev_thoughts
	if dt > 0.0:
		SaveSystem.add_stat(LT_THOUGHTS, dt)

	var dc := c - _prev_control
	if dc > 0.0:
		SaveSystem.add_stat(LT_CONTROL, dc)

	_prev_thoughts = t
	_prev_control = c

	# Deepest depth
	var depth := _get_int("depth")
	SaveSystem.set_max_stat(LT_DEEPEST, depth)

	# Playtime seconds
	_sec_accum += delta
	if _sec_accum >= 1.0:
		_sec_accum -= 1.0
		SaveSystem.add_stat(LT_PLAYTIME, 1.0)

func _on_confirm_wake() -> void:
	SaveSystem.add_stat_int(LT_DIVES, 1)

func _get_float(prop: String) -> float:
	var v: Variant = _gm.get(prop)
	if typeof(v) == TYPE_FLOAT:
		return float(v)
	if typeof(v) == TYPE_INT:
		return float(v)
	return 0.0

func _get_int(prop: String) -> int:
	var v: Variant = _gm.get(prop)
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return 0
