extends Node
class_name OverclockSystem

@export var base_control_cost: float = 12.0
@export var base_duration: float = 8.0

@export var base_thoughts_mult: float = 2.0
@export var base_instability_mult: float = 1.6

var active: bool = false
var timer: float = 0.0

# Effective values (computed on activate)
var control_cost: float = 12.0
var duration: float = 8.0
var thoughts_mult: float = 2.0
var instability_mult: float = 1.6


func can_activate(control: float) -> bool:
	return (not active) and control >= control_cost


# Params order:
# 0 thoughts_mult_add
# 1 thoughts_mult_mul
# 2 instability_mult_mul
# 3 duration_mul
# 4 cost_mul
func activate(
	thoughts_mult_add: float = 0.0,
	thoughts_mult_mul: float = 1.0,
	instability_mult_mul: float = 1.0,
	duration_mul: float = 1.0,
	cost_mul: float = 1.0
) -> void:
	control_cost = base_control_cost * cost_mul
	duration = base_duration * duration_mul

	thoughts_mult = (base_thoughts_mult + thoughts_mult_add) * thoughts_mult_mul
	instability_mult = base_instability_mult * instability_mult_mul

	active = true
	timer = duration


func update(delta: float) -> void:
	if not active:
		return
	timer -= delta
	if timer <= 0.0:
		timer = 0.0
		active = false

		# reset effective values
		control_cost = base_control_cost
		duration = base_duration
		thoughts_mult = base_thoughts_mult
		instability_mult = base_instability_mult
