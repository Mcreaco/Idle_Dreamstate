extends Node

const SERVER_ENABLED := false

var daily_purchased: float = 0.0
var daily_ads: int = 0
var last_reset: int = 0

func _ready() -> void:
	load_data()

func check_new_day() -> bool:
	var now := Time.get_unix_time_from_system()
	var curr_day := int(now / 86400)
	var last_day := int(last_reset / 86400)
	
	if curr_day > last_day:
		daily_purchased = 0.0
		daily_ads = 0
		last_reset = now
		save_data()
		return true
	return false

func can_purchase_time(hours: float) -> bool:
	check_new_day()
	return (daily_purchased + hours) <= 4.0

func record_purchase(hours: float) -> bool:
	if not can_purchase_time(hours):
		return false
	daily_purchased += hours
	save_data()
	return true

func can_watch_ad() -> bool:
	check_new_day()
	return daily_ads < 10

func record_ad() -> bool:
	if not can_watch_ad():
		return false
	daily_ads += 1
	save_data()
	return true

func get_stats() -> Dictionary:
	check_new_day()
	return {
		"purchased": daily_purchased,
		"purchased_left": 4.0 - daily_purchased,
		"ads": daily_ads,
		"ads_left": 10 - daily_ads
	}

func save_data() -> void:
	var data := SaveSystem.load_game()
	data["eth_purchased"] = daily_purchased
	data["eth_ads"] = daily_ads
	data["eth_reset"] = last_reset
	SaveSystem.save_game(data)

func load_data() -> void:
	var data := SaveSystem.load_game()
	daily_purchased = float(data.get("eth_purchased", 0.0))
	daily_ads = int(data.get("eth_ads", 0))
	last_reset = int(data.get("eth_reset", 0))
	check_new_day()
