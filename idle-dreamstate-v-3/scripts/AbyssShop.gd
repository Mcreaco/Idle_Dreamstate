extends Control

var items: Array = [
	{"id": "auto_dive", "name": "Auto-Dive Module", "cost": 499, "type": "convenience", "desc": "Auto-dive at 100% progress", "toggleable": true},
	{"id": "void_theme", "name": "Void Theme", "cost": 1000, "type": "cosmetic", "desc": "Dark purple UI Theme"},
	{"id": "title_1", "name": "Title: Abyss Walker", "cost": 2000, "type": "cosmetic", "desc": "Shows your transcendence status", "req_tier": 1},
	{"id": "title_2", "name": "Title: Void Touched", "cost": 5000, "type": "cosmetic", "desc": "Reached transcendence 5+ times", "req_tier": 5},
	{"id": "pet", "name": "Voidling Pet", "cost": 3000, "type": "cosmetic", "desc": "A small floating companion"},
	{"id": "aura", "name": "Abyssal Aura", "cost": 8000, "type": "cosmetic", "desc": "Visual purple particle effect"},
	{"id": "smart_oc", "name": "Smart Overclock", "cost": 2500, "type": "convenience", "desc": "Auto-Overclock when safe", "toggleable": true}
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
	
	if _gm != null:
		await get_tree().process_frame
		if _gm.has_method("get_abyss_shop_data"):
			var shop_data = _gm.get_abyss_shop_data()
			unlocked = Array(shop_data.unlocked, TYPE_STRING, &"", null)
			active_items = Dictionary(shop_data.active)
		else:
			unlocked = _gm.abyss_shop_unlocked.duplicate()
			active_items = _gm.abyss_shop_active.duplicate()
	refresh()

func _create_ui() -> void:
	_create_ui_in(self)

func _create_ui_in(container: Control) -> void:
	for child in container.get_children():
		child.queue_free()
	
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_theme_constant_override("separation", 10)
	container.add_child(main_vbox)
	
	ap_label = Label.new()
	ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ap_label.add_theme_font_size_override("font_size", 18)
	ap_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
	main_vbox.add_child(ap_label)
	
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(scroll)
	
	list_container = VBoxContainer.new()
	list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_theme_constant_override("separation", 12)
	scroll.add_child(list_container)
	
	refresh()

func refresh() -> void:
	if list_container == null: return
	for child in list_container.get_children(): child.queue_free()
	
	if _gm == null:
		ap_label.text = "GameManager not found"
		return
	
	_update_ap_label()
	
	for item in items:
		var card := _create_item_card(item)
		list_container.add_child(card)

func _create_item_card(item: Dictionary) -> PanelContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 96)
	
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.2, 0.75)
	sb.border_width_bottom = 2
	sb.border_color = Color(0.35, 0.45, 0.7, 0.35)
	sb.corner_radius_top_left = 10
	sb.corner_radius_top_right = 10
	sb.corner_radius_bottom_left = 10
	sb.corner_radius_bottom_right = 10
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", sb)
	
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 20)
	card.add_child(hbox)
	
	# Col 1: Action (120px)
	var col_buy := VBoxContainer.new()
	col_buy.custom_minimum_size = Vector2(120, 0)
	col_buy.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(col_buy)
	
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(110, 42)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	col_buy.add_child(btn)
	
	var cost_lbl := Label.new()
	cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_lbl.add_theme_font_size_override("font_size", 13)
	cost_lbl.add_theme_color_override("font_color", Color(0.9, 0.6, 1.0))
	col_buy.add_child(cost_lbl)
	
	# Col 2: Info (Expand)
	var col_info := VBoxContainer.new()
	col_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_info.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(col_info)
	
	var name_lbl := Label.new()
	name_lbl.text = item.name
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	col_info.add_child(name_lbl)
	
	var desc_lbl := Label.new()
	desc_lbl.text = item.desc
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	col_info.add_child(desc_lbl)
	
	# Col 3: Status (80px)
	var col_status := VBoxContainer.new()
	col_status.custom_minimum_size = Vector2(80, 0)
	col_status.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(col_status)
	
	var type_lbl := Label.new()
	type_lbl.text = item.type.to_upper()
	type_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	type_lbl.add_theme_font_size_override("font_size", 10)
	type_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	col_status.add_child(type_lbl)
	
	# Logic for Button/Cost
	var points: float = _gm.abyss_points if "abyss_points" in _gm else 0.0
	var tier: int = _gm.abyss_tier if "abyss_tier" in _gm else 0
	var owned: bool = item.id in unlocked
	var item_cost: float = float(item.cost)
	var can_afford: bool = points >= item_cost
	var tier_locked: bool = item.has("req_tier") and tier < int(item.req_tier)
	
	btn.set_meta("item_id", item.id)
	btn.set_meta("item_cost", item_cost)
	btn.set_meta("needs_check", true)
	
	if owned:
		btn.text = "OWNED"
		btn.disabled = true
		btn.modulate = Color(0.6, 1.0, 0.7)
		cost_lbl.text = "—"
	elif tier_locked:
		btn.text = "LOCKED"
		btn.disabled = true
		btn.modulate = Color(0.5, 0.5, 0.5)
		cost_lbl.text = "Requires Tier %d" % int(item.req_tier)
		cost_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	elif can_afford:
		btn.text = "BUY"
		btn.disabled = false
		btn.modulate = Color(1, 1, 1)
		btn.pressed.connect(func(): buy(item))
		cost_lbl.text = "[ %d AP ]" % int(item_cost)
	else:
		btn.text = "NEED AP"
		btn.disabled = true
		btn.modulate = Color(0.8, 0.5, 0.5)
		cost_lbl.text = "[ %d AP ]" % int(item_cost)

	return card

func _process(_delta: float) -> void:
	if Engine.get_process_frames() % 30 == 0:
		if _gm == null or not ("abyss_points" in _gm): return
		var current_ap: float = float(_gm.abyss_points)
		if current_ap != last_ap_value:
			last_ap_value = current_ap
			_update_ap_label()
			refresh()

func _update_ap_label() -> void:
	if ap_label == null or _gm == null: return
	var tier: int = _gm.abyss_tier if "abyss_tier" in _gm else 0
	var points: float = _gm.abyss_points if "abyss_points" in _gm else 0.0
	ap_label.text = "✦ VOID SHOP ✦\nAbyss Points: %d | Current Tier: %d" % [int(points), tier]

func buy(item: Dictionary) -> void:
	if _gm == null or not ("abyss_points" in _gm): return
	if _gm.abyss_points >= item.cost:
		_gm.abyss_points -= item.cost
		if not item.id in unlocked: unlocked.append(str(item.id))
		if item.get("toggleable", false): active_items[item.id] = true
		if _gm.has_method("update_abyss_shop_data"):
			_gm.update_abyss_shop_data(unlocked, active_items)
		refresh()

func has_item(id: String) -> bool: return id in unlocked
func is_item_active(id: String) -> bool: return active_items.get(id, false)
func set_active(id: String, active: bool):
	if id in unlocked:
		active_items[id] = active
		if _gm != null and _gm.has_method("update_abyss_shop_data"):
			_gm.update_abyss_shop_data(unlocked, active_items)

func get_shop_data() -> Dictionary:
	return {"unlocked": unlocked.duplicate(), "active": active_items.duplicate()}

func load_from_gamemanager(p_unlocked: Array[String], p_active: Dictionary):
	unlocked = p_unlocked.duplicate()
	active_items = p_active.duplicate()
	refresh()

func save_data(): pass
func load_data(): pass
