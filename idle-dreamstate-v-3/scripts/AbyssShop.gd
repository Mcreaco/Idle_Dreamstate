extends Control

var items: Array = [
	{"id": "auto_dive", "name": "Auto-Dive Module", "cost": 499, "type": "convenience", "desc": "Auto-dive at 100% progress"},
	{"id": "void_theme", "name": "Void Theme", "cost": 1000, "type": "cosmetic", "desc": "Dark purple UI"},
	{"id": "title_1", "name": "Title: Abyss Walker", "cost": 2000, "type": "cosmetic", "desc": "Show transcendence", "req_tier": 1},
	{"id": "title_2", "name": "Title: Void Touched", "cost": 5000, "type": "cosmetic", "desc": "5x transcended", "req_tier": 5},
	{"id": "pet", "name": "Voidling Pet", "cost": 3000, "type": "cosmetic", "desc": "Cosmetic companion"},
	{"id": "aura", "name": "Abyssal Aura", "cost": 8000, "type": "cosmetic", "desc": "Purple particles"},
	{"id": "smart_oc", "name": "Smart Overclock", "cost": 2500, "type": "convenience", "desc": "Auto-OC when safe"}
]

var unlocked: Array[String] = []
var list_container: VBoxContainer
var ap_label: Label
var last_ap_value: float = -1.0
var active_items: Dictionary = {}  # item_id -> bool (enabled/disabled)

func _ready():
	_create_ui()
	
	# Load from GameManager (which already loaded from save)
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm and gm.has_method("get_abyss_shop_data"):
		var shop_data = gm.get_abyss_shop_data()
		unlocked = shop_data.unlocked
		active_items = shop_data.active
	
	refresh()

func _create_ui() -> void:
	# Clear existing
	for child in get_children():
		child.queue_free()
	
	# Set this control to fill parent
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	# Main container fills everything
	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_vbox)
	
	# Header
	ap_label = Label.new()
	ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap_label.add_theme_font_size_override("font_size", 20)
	ap_label.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
	main_vbox.add_child(ap_label)
	
	main_vbox.add_child(HSeparator.new())
	
	# Scroll fills remaining space
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
	# List container
	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(list_container)

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible and list_container != null:
			print("Tab became visible, refreshing...")
			refresh()
			
func refresh() -> void:
	print("Refresh called")
	
	if list_container == null:
		return
	
	# Clear
	for child in list_container.get_children():
		child.queue_free()
	
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null:
		ap_label.text = "GameManager not found"
		return
	
	var tier: int = gm.abyss_tier if "abyss_tier" in gm else 0
	var points: float = gm.abyss_points if "abyss_points" in gm else 0.0
	
	ap_label.text = "✦ ABYSS SHOP ✦\nPoints: %d | Tier: %d" % [int(points), tier]
	
	for item in items:
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # Expand to fill width
		row.custom_minimum_size = Vector2(550, 90)  # Wide enough for content
		
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_top", 15)
		margin.add_theme_constant_override("margin_bottom", 15)
		row.add_child(margin)
		
		var hbox := HBoxContainer.new()
		margin.add_child(hbox)
		
		# Info
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl := Label.new()
		name_lbl.text = item.name
		name_lbl.add_theme_font_size_override("font_size", 18)  # Bigger
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		info.add_child(name_lbl)
		
		var desc_lbl := Label.new()
		desc_lbl.text = item.desc
		desc_lbl.add_theme_font_size_override("font_size", 14)  # Bigger
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
		info.add_child(desc_lbl)
		
		var cost_lbl := Label.new()
		cost_lbl.text = "Cost: %d AP" % item.cost
		cost_lbl.add_theme_font_size_override("font_size", 14)
		cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
		info.add_child(cost_lbl)
		
		hbox.add_child(info)
		
		# Button - FIXED LOGIC
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 45)
		
		var owned: bool = item.id in unlocked
		var item_cost: float = float(item.cost)
		var can_afford: bool = points >= item_cost
		
		# Store item data in button for dynamic updates
		btn.set_meta("item_id", item.id)
		btn.set_meta("item_cost", item_cost)

		if owned:
			btn.text = "Owned"
			btn.disabled = true
			btn.modulate = Color(0.5, 0.8, 0.5)
		elif item.has("req_tier") and tier < int(item.req_tier):
			btn.text = "Tier %d" % int(item.req_tier)
			btn.disabled = true
			btn.modulate = Color(0.5, 0.5, 0.5)
		elif can_afford:
			btn.text = "Buy"
			btn.disabled = false
			btn.modulate = Color(1.0, 1.0, 1.0)
			# FIX: Capture item properly using intermediate variable
			var current_item = item  
			btn.pressed.connect(func(): buy(current_item))
		else:
			btn.text = "Need AP"
			btn.disabled = true
			btn.modulate = Color(0.8, 0.5, 0.5)
		
		# Store reference for dynamic updates
		btn.set_meta("needs_check", true)
		
		hbox.add_child(btn)
		list_container.add_child(row)
		
		# Spacer
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		list_container.add_child(spacer)

func _process(_delta: float) -> void:
	# Update label and buttons when AP changes
	if Engine.get_process_frames() % 30 == 0:  # Check twice per second
		var gm := get_node_or_null("/root/Main/GameManager")
		if gm == null or not ("abyss_points" in gm):
			return
		
		var current_ap: float = float(gm.abyss_points)
		
		# Only refresh if AP changed
		if current_ap != last_ap_value:
			last_ap_value = current_ap
			_update_ap_label()
			_update_buttons(current_ap)

func _update_buttons(current_ap: float) -> void:
	# Update button states without full rebuild
	if list_container == null:
		return
	
	for row in list_container.get_children():
		if row is PanelContainer:
			var hbox = row.get_child(0).get_child(0)  # margin -> hbox
			var btn = hbox.get_child(1)  # info -> btn
			
			if btn.has_meta("needs_check") and btn.has_meta("item_cost"):
				var cost: float = btn.get_meta("item_cost")
				var is_owned: bool = btn.get_meta("item_id") in unlocked
				
				if is_owned:
					continue  # Skip owned items
				
				# Update state based on current AP
				if current_ap >= cost and btn.text == "Need AP":
					btn.text = "Buy"
					btn.disabled = false
					btn.modulate = Color(1.0, 1.0, 1.0)
					# Reconnect if needed
					if not btn.pressed.is_connected(func(): pass):
						var current_id = btn.get_meta("item_id")
						# Find the item data again for the callback
						for it in items:
							if it.id == current_id:
								var current_item = it
								btn.pressed.connect(func(): buy(current_item))
								break
				elif current_ap < cost and btn.text == "Buy":
					btn.text = "Need AP"
					btn.disabled = true
					btn.modulate = Color(0.8, 0.5, 0.5)
					
func _update_ap_label() -> void:
	if ap_label == null:
		return
	
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null:
		return
	
	var tier: int = gm.abyss_tier if "abyss_tier" in gm else 0
	var points: float = gm.abyss_points if "abyss_points" in gm else 0.0
	
	ap_label.text = "✦ ABYSS SHOP ✦\nPoints: %d | Tier: %d" % [int(points), tier]
	
func buy(item: Dictionary) -> void:
	print("Buying: ", item.name)
	var gm := get_node_or_null("/root/Main/GameManager")
	if gm == null:
		return
	
	if not ("abyss_points" in gm):
		print("ERROR: No abyss_points in GM")
		return
	
	if gm.abyss_points >= item.cost:
		gm.abyss_points -= item.cost
		unlocked.append(str(item.id))
		save_data()
		refresh()
		print("Bought! New AP: ", gm.abyss_points)
	else:
		print("Not enough AP! Have: ", gm.abyss_points, " Need: ", item.cost)
	# For convenience items, auto-enable on purchase
	if item.type == "convenience":
		active_items[item.id] = true
		save_data()
		print(item.name, " activated!")

func get_shop_data() -> Dictionary:
	return {
		"unlocked": unlocked,
		"active": active_items
	}
	
func is_item_active(item_id: String) -> bool:
	return active_items.get(item_id, false)

func toggle_item(item_id: String, active: bool):
	active_items[item_id] = active
	save_data()
	
func save_data() -> void:
	var data = SaveSystem.load_game()
	data["abyss_shop_unlocked"] = unlocked
	data["abyss_shop_active"] = active_items
	SaveSystem.save_game(data)
	
	print("ABYSS SHOP SAVED:", unlocked.size(), "items")
	print("Unlocked:", unlocked)

func load_data() -> void:
	var data = SaveSystem.load_game()
	var loaded = data.get("abyss_shop_unlocked", [])
	
	print("ABYSS SHOP LOADED:", loaded.size(), "items")
	print("Loaded data:", loaded)
	
	unlocked.clear()
	for item in loaded:
		unlocked.append(str(item))
	
	# Load active states (for convenience items)
	var loaded_active = data.get("abyss_shop_active", {})
	active_items.clear()
	for key in loaded_active.keys():
		active_items[key] = bool(loaded_active[key])

func has_item(id: String) -> bool:
	return id in unlocked
