# TimedBoostController.gd  (AUTOLOAD RECOMMENDED)
extends Node

# Boost spec
@export var multiplier: float = 2.0

# If true, boost button can be used on PC for testing (otherwise you hide the UI on PC)
@export var allow_on_pc_for_testing: bool = false

# Names to find
@export var game_manager_name: String = "GameManager"

# Internal
var _gm: Node = null
var _ad: Node = null

var _active: bool = false
var _boost_end_unix: float = 0.0

# Original values we override (so we can restore perfectly)
var _orig_idle_thoughts_rate: float = 0.0
var _orig_idle_control_rate: float = 0.0
var _orig_dive_thoughts_gain: float = 0.0
var _orig_dive_control_gain: float = 0.0
var _have_orig: bool = false

func _ready() -> void:
	# Keep ticking even when paused (your choice "2")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	_ad = get_node_or_null("/root/AdService")
	if _ad != null and _ad.has_signal("reward_timed_boost"):
		if not _ad.reward_timed_boost.is_connected(Callable(self, "_on_reward_timed_boost")):
			_ad.reward_timed_boost.connect(Callable(self, "_on_reward_timed_boost"))

	_gm = get_tree().current_scene.find_child(game_manager_name, true, false)

func request_timed_boost() -> void:
	# Call this from your UI button.
	if not _platform_allowed():
		return

	_ad = get_node_or_null("/root/AdService")
	if _ad == null:
		return

	if _ad.has_method("show_rewarded"):
		_ad.call("show_rewarded", _ad.AD_TIMED_BOOST)

func is_active() -> bool:
	return _active and _time_left() > 0.0

func time_left_seconds() -> float:
	return _time_left()

func current_multiplier() -> float:
	return multiplier if is_active() else 1.0

func _process(_delta: float) -> void:
	# Use real time so it keeps ticking during pause/off-focus
	if _active and _time_left() <= 0.0:
		_end_boost()

func _on_reward_timed_boost(seconds: float) -> void:
	if seconds <= 0.0:
		return
	_start_boost(seconds)

func _start_boost(seconds: float) -> void:
	_gm = get_tree().current_scene.find_child(game_manager_name, true, false)
	if _gm == null:
		return

	# First time we boost, capture original values.
	if not _have_orig:
		_orig_idle_thoughts_rate = float(_gm.get("idle_thoughts_rate"))
		_orig_idle_control_rate = float(_gm.get("idle_control_rate"))
		_orig_dive_thoughts_gain = float(_gm.get("dive_thoughts_gain"))
		_orig_dive_control_gain = float(_gm.get("dive_control_gain"))
		_have_orig = true

	# Apply boosted values
	_gm.set("idle_thoughts_rate", _orig_idle_thoughts_rate * multiplier)
	_gm.set("idle_control_rate", _orig_idle_control_rate * multiplier)
	_gm.set("dive_thoughts_gain", _orig_dive_thoughts_gain * multiplier)
	_gm.set("dive_control_gain", _orig_dive_control_gain * multiplier)

	_active = true
	_boost_end_unix = Time.get_unix_time_from_system() + seconds

func _end_boost() -> void:
	if _gm == null:
		_gm = get_tree().current_scene.find_child(game_manager_name, true, false)

	if _gm != null and _have_orig:
		_gm.set("idle_thoughts_rate", _orig_idle_thoughts_rate)
		_gm.set("idle_control_rate", _orig_idle_control_rate)
		_gm.set("dive_thoughts_gain", _orig_dive_thoughts_gain)
		_gm.set("dive_control_gain", _orig_dive_control_gain)

	_active = false
	_boost_end_unix = 0.0

func _time_left() -> float:
	if not _active:
		return 0.0
	return maxf(0.0, _boost_end_unix - Time.get_unix_time_from_system())

func _platform_allowed() -> bool:
	if allow_on_pc_for_testing:
		return true
	var os := OS.get_name()
	return os == "Android" or os == "iOS"
