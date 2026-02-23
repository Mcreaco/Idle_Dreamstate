extends Node

const DAILY_CAP := 500.0
const ACCUMULATION_RATE := 0.1
const BREAK_THRESHOLD := 100.0
const USD_RATE := 0.01

var current_amount: float = 0.0
var last_reset_date: String = ""
var times_broken: int = 0

func _ready() -> void:
	load_state()
	check_daily_reset()

func add_thoughts(amount: float) -> void:
	var to_add := amount * ACCUMULATION_RATE
	var old := current_amount
	current_amount = minf(current_amount + to_add, DAILY_CAP)
	if current_amount - old > 1.0:
		save_state()

func can_break() -> bool:
	return current_amount >= BREAK_THRESHOLD

func get_usd_value() -> float:
	return current_amount * USD_RATE

func break_bank() -> Dictionary:
	if not can_break():
		return {"success": false}
	
	var amount := current_amount
	current_amount = 0.0
	times_broken += 1
	save_state()
	
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		if "thoughts" in gm:
			gm.thoughts += amount
		if "total_thoughts_earned" in gm:
			gm.total_thoughts_earned += amount
	
	return {"success": true, "amount": amount, "usd": amount * USD_RATE}

func check_daily_reset() -> void:
	var today := Time.get_date_string_from_system()
	if last_reset_date != today:
		last_reset_date = today
		save_state()

func save_state() -> void:
	var data := SaveSystem.load_game()
	data["piggy_bank"] = current_amount
	data["piggy_date"] = last_reset_date
	data["piggy_breaks"] = times_broken
	SaveSystem.save_game(data)

func load_state() -> void:
	var data := SaveSystem.load_game()
	current_amount = float(data.get("piggy_bank", 0.0))
	last_reset_date = str(data.get("piggy_date", ""))
	times_broken = int(data.get("piggy_breaks", 0))

func get_display() -> String:
	return "%d thoughts ($%.2f)" % [int(current_amount), get_usd_value()]
