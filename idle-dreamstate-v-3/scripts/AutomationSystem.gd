extends Node
class_name AutomationSystem

var auto_dive: bool = false
var auto_wake: bool = false
var auto_overclock: bool = false

# 0..1 (sliders)
var dive_strength: float = 1.0
var wake_strength: float = 1.0
var overclock_strength: float = 1.0

@export var dive_attempt_min_interval: float = 0.05
@export var dive_attempt_max_interval: float = 2.0

@export var wake_instability_min: float = 70.0
@export var wake_instability_max: float = 97.0

@export var overclock_instability_safe_min: float = 40.0
@export var overclock_instability_safe_max: float = 90.0

var _dive_timer: float = 0.0


func set_dive_strength(v: float) -> void:
	dive_strength = clampf(v, 0.0, 1.0)

func set_wake_strength(v: float) -> void:
	wake_strength = clampf(v, 0.0, 1.0)

func set_overclock_strength(v: float) -> void:
	overclock_strength = clampf(v, 0.0, 1.0)


# Return 1 when we should TRY a dive click this frame
func update(delta: float) -> int:
	if not auto_dive:
		_dive_timer = 0.0
		return 0

	_dive_timer += delta
	var interval := lerpf(dive_attempt_max_interval, dive_attempt_min_interval, dive_strength)

	if _dive_timer >= interval:
		_dive_timer = 0.0
		return 1

	return 0


func should_wake(instability: float) -> bool:
	if not auto_wake:
		return false

	var threshold := lerpf(wake_instability_max, wake_instability_min, wake_strength)
	return instability >= threshold


func should_overclock(_control: float, instability: float, can_overclock: bool) -> bool:
	if not auto_overclock:
		return false

	if not can_overclock:
		return false

	var safe_limit := lerpf(
		overclock_instability_safe_max,
		overclock_instability_safe_min,
		overclock_strength
	)

	return instability <= safe_limit
