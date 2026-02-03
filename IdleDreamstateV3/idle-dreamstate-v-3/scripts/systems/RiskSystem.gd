class_name RiskSystem
extends Node

const STABLE_MAX := 30.0
const DEEP_MAX := 70.0
const CRITICAL_MAX := 100.0
const CORRUPTION_START := 90.0

func add_risk(current: float, amount: float) -> float:
	return clamp(current + amount, 0.0, 100.0)

func reduce_risk(current: float, amount: float) -> float:
	return clamp(current - amount, 0.0, 100.0)

func get_state(instability: float) -> String:
	if instability < STABLE_MAX:
		return "Stable"
	elif instability < DEEP_MAX:
		return "Deep"
	else:
		return "Critical"

func is_corruption(instability: float) -> bool:
	return instability >= CORRUPTION_START
