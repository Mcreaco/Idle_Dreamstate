extends Control

var items: Array = [
	{"id": "auto_dive", "name": "Auto-Dive Module", "cost": 499, "type": "convenience", "desc": "Auto-dive at 100% progress", "toggleable": true},
	{"id": "void_theme", "name": "Void Theme", "cost": 1000, "type": "cosmetic", "desc": "Dark purple UI"},
	{"id": "title_1", "name": "Title: Abyss Walker", "cost": 2000, "type": "cosmetic", "desc": "Show transcendence", "req_tier": 1},
	{"id": "title_2", "name": "Title: Void Touched", "cost": 5000, "type": "cosmetic", "desc": "5x transcended", "req_tier": 5},
	{"id": "pet", "name": "Voidling Pet", "cost": 3000, "type": "cosmetic", "desc": "Cosmetic companion"},
	{"id": "aura", "name": "Abyssal Aura", "cost": 8000, "type": "cosmetic", "desc": "Purple particles"},
	{"id": "smart_oc", "name": "Smart Overclock", "cost": 2500, "type": "convenience", "desc": "Auto-OC when safe", "toggleable": true}
]

var unlocked: Array[String] = []
var list_container: VBoxContainer
var ap_label: Label
var last_ap_value: float = -1.0
var active_items: Dictionary = {}
var _gm: Node = null

func _ready():
	_gm = get_node_or_null("/root/Main/GameManager")
	_create_ui()
	
	# CRITICAL: Load from GameManager instead of SaveSystem directly
	if _gm != null:
		await get_tree().process_frame
		if _gm.has_method("get_abyss_shop_data"):
			var shop_data = _gm.get_abyss_shop_data()
			# CRITICAL: Cast to proper types to avoid "Array vs Array[String]" error
			unlocked = Array(shop_data.unlocked, TYPE_STRING, &"", null)
			active_items = Dictionary(shop_data.active)
		else:
			# Fallback to direct variables
			unlocked = _gm.abyss_shop_unlocked.duplicate()
			active_items = _gm.abyss_shop_active.duplicate()
	
	refresh()

func _create_ui() -> void:
	for child in get_children():
		child.queue_free()
	
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0
	offset_right = 0
	offset_top = 0
	offset_bottom = 0
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var main_vbox := VBoxContainer.new()
	main_vbox.anchor_right = 1.0
	main_vbox.anchor_bottom = 1.0
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_vbox)
	
	ap_label = Label.new()
	ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap_label.add_theme_font_size_override("font_size", 20)
	ap_label.add_theme_color_override("font_color", Color(0.8, 0.4, 1.0))
	main_vbox.add_child(ap_label)
	
	main_vbox.add_child(HSeparator.new())
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(scroll)
	
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
	
	for child in list_container.get_children():
		child.queue_free()
	
	if _gm == null:
		ap_label.text = "GameManager not found"
		return
	
	var tier: int = _gm.abyss_tier if "abyss_tier" in _gm else 0
	var points: float = _gm.abyss_points if "abyss_points" in _gm else 0.0
	
	ap_label.text = "✦ ABYSS SHOP ✦\nPoints: %d | Tier: %d" % [int(points), tier]
	
	for item in items:
		var row := PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(550, 90)
		
		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 20)
		margin.add_theme_constant_override("margin_right", 20)
		margin.add_theme_constant_override("margin_top", 15)
		margin.add_theme_constant_override("margin_bottom", 15)
		row.add_child(margin)
		
		var hbox := HBoxContainer.new()
		margin.add_child(hbox)
		
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var name_lbl := Label.new()
		name_lbl.text = item.name
		name_lbl.add_theme_font_size_override("font_size", 18)
		name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		info.add_child(name_lbl)
		
		var desc_lbl := Label.new()
		desc_lbl.text = item.desc
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.9))
		info.add_child(desc_lbl)
		
		var cost_lbl := Label.new()
		cost_lbl.text = "Cost: %d AP" % item.cost
		cost_lbl.add_theme_font_size_override("font_size", 14)
		cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
		info.add_child(cost_lbl)
		
		hbox.add_child(info)
		
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(100, 45)
		
		var owned: bool = item.id in unlocked
		var item_cost: float = float(item.cost)
		var can_afford: bool = points >= item_cost
		
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
			var current_item = item  
			btn.pressed.connect(func(): buy(current_item))
		else:
			btn.text = "Need AP"
			btn.disabled = true
			btn.modulate = Color(0.8, 0.5, 0.5)
		
		btn.set_meta("needs_check", true)
		
		hbox.add_child(btn)
		list_container.add_child(row)
		
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 8)
		list_container.add_child(spacer)

func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 == 0:
		if _gm == null or not ("abyss_points" in _gm):
			return
		
		var current_ap: float = float(_gm.abyss_points)
		
		if current_ap != last_ap_value:
			last_ap_value = current_ap
			_update_ap_label()
			_update_buttons(current_ap)

func _update_buttons(current_ap: float) -> void:
	if list_container == null:
		return
	
	for row in list_container.get_children():
		if row is PanelContainer:
			var hbox = row.get_child(0).get_child(0)
			var btn = hbox.get_child(1)
			
			if btn.has_meta("needs_check") and btn.has_meta("item_cost"):
				var cost: float = btn.get_meta("item_cost")
				var is_owned: bool = btn.get_meta("item_id") in unlocked
				
				if is_owned:
					continue
				
				if current_ap >= cost and btn.text == "Need AP":
					btn.text = "Buy"
					btn.disabled = false
					btn.modulate = Color(1.0, 1.0, 1.0)
					if not btn.pressed.is_connected(func(): pass):
						var current_id = btn.get_meta("item_id")
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
	if ap_label == null or _gm == null:
		return
	
	var tier: int = _gm.abyss_tier if "abyss_tier" in _gm else 0
	var points: float = _gm.abyss_points if "abyss_points" in _gm else 0.0
	ap_label.text = "✦ ABYSS SHOP ✦\nPoints: %d | Tier: %d" % [int(points), tier]

func buy(item: Dictionary) -> void:
	print("Buying: ", item.name)
	if _gm == null:
		return
	
	if not ("abyss_points" in _gm):
		print("ERROR: No abyss_points in GM")
		return
	
	if _gm.abyss_points >= item.cost:
		_gm.abyss_points -= item.cost
		
		if not item.id in unlocked:
			unlocked.append(str(item.id))
		
		# For convenience items, auto-enable on purchase
		if item.get("toggleable", false):
			active_items[item.id] = true
		
		# CRITICAL: Update GameManager's cache (triggers save)
		if _gm.has_method("update_abyss_shop_data"):
			_gm.update_abyss_shop_data(unlocked, active_items)
		
		refresh()
		print("Bought! New AP: ", _gm.abyss_points)
	else:
		print("Not enough AP! Have: ", _gm.abyss_points, " Need: ", item.cost)

func has_item(id: String) -> bool:
	return id in unlocked

func is_item_active(id: String) -> bool:
	return active_items.get(id, false)

func set_active(id: String, active: bool):
	if id in unlocked:
		active_items[id] = active
		if _gm != null and _gm.has_method("update_abyss_shop_data"):
			_gm.update_abyss_shop_data(unlocked, active_items)

func get_shop_data() -> Dictionary:
	return {
		"unlocked": unlocked.duplicate(),
		"active": active_items.duplicate()
	}

func load_from_gamemanager(p_unlocked: Array[String], p_active: Dictionary):
	"""Called by GameManager after load_game() completes"""
	unlocked = p_unlocked.duplicate()
	active_items = p_active.duplicate()
	refresh()

# DEPRECATED - don't use these anymore
func save_data():
	push_warning("AbyssShop.save_data() deprecated - use GameManager.update_abyss_shop_data()")

func load_data():
	push_warning("AbyssShop.load_data() deprecated - loading handled by GameManager")
