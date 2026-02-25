extends Control

@onready var hours_display = $Hours      # Can be Label or Button
@onready var buy_control = $DailyWarp     # Can be Label or Button  
@onready var ad_control = $"Watch Ad"     # Can be Label or Button

func _ready():
	_refresh_ui()
	
	# Connect signals only if they're buttons
	if buy_control is Button:
		buy_control.pressed.connect(_on_buy)
	if ad_control is Button:
		ad_control.pressed.connect(_on_watch_ad)

func _refresh_ui():
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm == null:
		return
	
	var stats = gm.get_daily_stats()
	var purchased = stats.purchased_hours
	var remaining = stats.purchased_remaining
	
	# Set text (works for both Label and Button)
	var hours_text = "Purchased: %.1fh / 4h" % purchased
	if hours_display is Label:
		hours_display.text = hours_text
	elif hours_display is Button:
		hours_display.text = hours_text
		hours_display.disabled = true
	
	var buy_text = "Buy 1h (%.1fh left)" % remaining if remaining > 0 else "Daily Cap Reached"
	if buy_control is Label:
		buy_control.text = buy_text
	elif buy_control is Button:
		buy_control.text = buy_text
		buy_control.disabled = remaining <= 0
	
	var ads_text = "Watch Ad [%d left]" % stats.ads_remaining
	if ad_control is Label:
		ad_control.text = ads_text
	elif ad_control is Button:
		ad_control.text = ads_text
		ad_control.disabled = stats.ads_remaining <= 0

func _on_buy():
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm and gm.purchase_time_warp(1.0):
		_refresh_ui()

func _on_watch_ad():
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm and gm.watch_ad_for_time_warp(1.0):
		_refresh_ui()
