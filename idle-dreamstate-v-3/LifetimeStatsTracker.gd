# LifetimeStatsTracker.gd
# Attach: GameManager -> add child Node named "LifetimeStatsTracker" -> attach this script
extends Node
class_name LifetimeStatsTracker

@export var game_manager_name: String = "GameManager"
@export var prestige_panel_name: String = "PrestigePanel"
@export var flush_interval_sec: float = 1.0

const LT_THOUGHTS := "lifetime_thoughts"
const LT_CONTROL := "lifetime_control"
const LT_DIVES := "total_dives"
const LT_DEEPEST := "deepest_depth"
const LT_PLAYTIME := "total_playtime"

var _gm: Node = null
var _prev_thoughts: float = 0.0
var _prev_control: float = 0.0
var _sec_accum: float = 0.0
var _flush_accum: float = 0.0

var _pending_add: Dictionary = {}    # key -> float
var _pending_setmax: Dictionary = {} # key -> int

func _ready() -> void:
	_gm = get_tree().current_scene.find_child(game_manager_name, true, false)
	if _gm == null:
		push_error("LifetimeStatsTracker: GameManager not found (looking for '%s')." % game_manager_name)
		set_process(false)
		return

	_prev_thoughts = _gm_float("thoughts")
	_prev_control = _gm_float("control")

	var pp := get_tree().current_scene.find_child(prestige_panel_name, true, false)
	if pp != null and pp.has_signal("confirm_wake"):
		if not pp.confirm_wake.is_connected(Callable(self, "_on_confirm_wake")):
			pp.confirm_wake.connect(Callable(self, "_on_confirm_wake"))

	set_process(true)

func _process(delta: float) -> void:
	if _gm == null:
		return

	# playtime
	_sec_accum += delta
	while _sec_accum >= 1.0:
		_sec_accum -= 1.0
		_queue_add(LT_PLAYTIME, 1.0)

	# thoughts/control (positive deltas only)
	var t := _gm_float("thoughts")
	var c := _gm_float("control")

	var dt := t - _prev_thoughts
	if dt > 0.0:
		_queue_add(LT_THOUGHTS, dt)

	var dc := c - _prev_control
	if dc > 0.0:
		_queue_add(LT_CONTROL, dc)

	_prev_thoughts = t
	_prev_control = c

	# deepest depth (max)
	_queue_setmax(LT_DEEPEST, _gm_int("depth"))

	# flush
	_flush_accum += delta
	if _flush_accum >= maxf(flush_interval_sec, 0.1):
		_flush_accum = 0.0
		_flush_now()

func _on_confirm_wake() -> void:
	_queue_add_int(LT_DIVES, 1)
	_flush_now()

func _queue_add(key: String, delta: float) -> void:
	if delta <= 0.0:
		return
	_pending_add[key] = float(_pending_add.get(key, 0.0)) + delta

func _queue_add_int(key: String, delta: int) -> void:
	if delta == 0:
		return
	_pending_add[key] = float(_pending_add.get(key, 0.0)) + float(delta)

func _queue_setmax(key: String, value: int) -> void:
	var cur := int(_pending_setmax.get(key, value))
	if value > cur:
		_pending_setmax[key] = value

func _flush_now() -> void:
	if _pending_add.is_empty() and _pending_setmax.is_empty():
		return

	var data: Dictionary = SaveSystem.load_game()

	for k in _pending_add.keys():
		var addv := float(_pending_add[k])
		data[k] = float(data.get(k, 0.0)) + addv

	for k in _pending_setmax.keys():
		var want := int(_pending_setmax[k])
		var curi := int(data.get(k, 0))
		if want > curi:
			data[k] = want

	SaveSystem.save_game(data)
	_pending_add.clear()
	_pending_setmax.clear()

func _gm_float(prop: String) -> float:
	var v: Variant = _gm.get(prop)
	if typeof(v) == TYPE_FLOAT:
		return float(v)
	if typeof(v) == TYPE_INT:
		return float(v)
	return 0.0

func _gm_int(prop: String) -> int:
	var v: Variant = _gm.get(prop)
	if typeof(v) == TYPE_INT:
		return int(v)
	if typeof(v) == TYPE_FLOAT:
		return int(v)
	return 0
