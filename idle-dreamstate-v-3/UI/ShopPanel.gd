# ShopPanel.gd
# Non-P2W shop with time boosters, convenience, and cosmetics
extends PanelContainer
class_name ShopPanel

@export var panel_min_size: Vector2 = Vector2(800, 600)

@export var panel_bg: Color = Color(0.04, 0.07, 0.12, 0.92)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 1.0)
@export var panel_border_width: int = 2
@export var panel_radius: int = 12

@export var settings_panel_node_name: String = "SettingsPanel"
@export var prestige_panel_node_name: String = "PrestigePanel"

var equipped_theme: String = ""

# Shop item definitions
var shop_items: Array[Dictionary] = [
	# TIME BOOSTERS
	{
		"id": "boost_2x_4h",
		"name": "Lucid Dream",
		"desc": "2x Thoughts for 4 hours",
		"price_usd": 0.99,
		"price_display": "$0.99",
		"type": "booster",
		"icon": "⏱️",
		"effect": {"thoughts_mult": 2.0, "duration_hours": 4}
	},
	{
		"id": "boost_2x_24h",
		"name": "Deep Trance",
		"desc": "2x Thoughts for 24 hours",
		"price_usd": 2.99,
		"price_display": "$2.99",
		"type": "booster",
		"icon": "⏱️",
		"effect": {"thoughts_mult": 2.0, "duration_hours": 24}
	},
	{
		"id": "boost_3x_4h",
		"name": "Void Rush",
		"desc": "3x Thoughts for 4 hours",
		"price_usd": 1.99,
		"price_display": "$1.99",
		"type": "booster",
		"icon": "⚡",
		"effect": {"thoughts_mult": 3.0, "duration_hours": 4}
	},
	
	# CONVENIENCE
		{
		"id": "early_auto_buy",
		"name": "Automated Mind (Early)",
		"desc": "Unlock auto-buy for ALL depths immediately",
		"price_usd": 4.99,  # Or include in £9.99 supporter pack
		"type": "permanent",
		"icon": "🤖",
		"effect": "early_auto_buy"
	},
	{
		"id": "fast_mode",
		"name": "Hyper Speed",
		"desc": "2x game speed (animations, progress)",
		"price_usd": 2.99,
		"price_display": "$2.99",
		"type": "permanent",
		"icon": "🚀",
		"effect": "game_speed_2x",
		"owned": false
	},
	
	# STARTER PACK (One-time)
	{
		"id": "starter_pack",
		"name": "Dreamer's Starter",
		"desc": "500 Memories + 50 of each crystal + 24h 2x boost",
		"price_usd": 4.99,
		"price_display": "$4.99",
		"type": "one_time",
		"icon": "🎁",
		"effect": {"memories": 500, "crystals_each": 50, "boost_hours": 24},
		"can_repurchase": false,
		"owned": false
	},
	
	# COSMETICS
	{
		"id": "theme_abyss",
		"name": "Abyss Theme",
		"desc": "Dark purple UI with void particles",
		"price_usd": 1.99,
		"price_display": "$1.99",
		"type": "cosmetic",
		"icon": "🎨",
		"effect": "theme_abyss",
		"owned": false
	},
	{
		"id": "theme_golden",
		"name": "Lucid Gold",
		"desc": "Premium gold UI theme",
		"price_usd": 2.99,
		"price_display": "$2.99",
		"type": "cosmetic",
		"icon": "✨",
		"effect": "theme_golden",
		"owned": false
	},
	
	# SUPPORTER PACK
	{
		"id": "supporter_pack",
		"name": "Void Walker Supporter",
		"desc": "All cosmetics + 1.1x Thoughts permanent + badge",
		"price_usd": 9.99,
		"price_display": "$9.99",
		"type": "premium",
		"icon": "👑",
		"effect": {"all_cosmetics": true, "thoughts_mult": 1.1, "badge": true},
		"owned": false
	}
]

var _root: VBoxContainer
var _items_container: VBoxContainer
var _close_btn: Button

# Owned items (save/load this)
var owned_items: Array[String] = []
var active_boost: Dictionary = {"mult": 1.0, "expires": 0}


func equip_theme(theme_id: String) -> void:
	equipped_theme = theme_id
	_apply_theme(theme_id)
	_save_shop_data()

func _apply_theme(theme_id: String) -> void:
	equipped_theme = theme_id
	var gm = _get_game_manager()
	if not gm:
		return
	
	match theme_id:
		"theme_abyss":
			gm.set_ui_colors(Color(0.4, 0.2, 0.6), Color(0.2, 0.1, 0.3))
		"theme_golden":
			gm.set_ui_colors(Color(1.0, 0.8, 0.2), Color(0.5, 0.4, 0.1))
		"theme_crimson":
			gm.set_ui_colors(Color(0.8, 0.2, 0.2), Color(0.4, 0.1, 0.1))

func get_equipped_theme() -> String:
	return equipped_theme
	
func _ready() -> void:
	_load_shop_data()
	_apply_center_layout(panel_min_size)
	_apply_panel_frame()
	_build_ui()
	visible = false
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)

func _process(_delta: float) -> void:
	# Check if boost expired
	if active_boost.expires > 0 and Time.get_unix_time_from_system() > active_boost.expires:
		active_boost = {"mult": 1.0, "expires": 0}
		_save_shop_data()
	

func _shop_has_auto_buy() -> bool:
	var shop = get_tree().current_scene.find_child("ShopPanel", true, false)
	if shop and shop.has_method("has_auto_buy"):
		return shop.has_auto_buy()
	return false
	
func open() -> void:
	_force_close_overlay(settings_panel_node_name)
	_force_close_overlay(prestige_panel_node_name)
	_apply_center_layout(panel_min_size)
	_apply_panel_frame()
	_refresh_shop_ui()
	visible = true
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	grab_focus()

func close() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if not get_global_rect().has_point(mb.position):
				close()
				get_viewport().set_input_as_handled()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	_root = VBoxContainer.new()
	_root.name = "Root"
	_root.add_theme_constant_override("separation", 12)
	add_child(_root)

	# Header
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_root.add_child(header)

	var title := Label.new()
	title.text = "Dream Shop"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# Active boost indicator
	var boost_label := Label.new()
	boost_label.name = "BoostLabel"
	boost_label.add_theme_font_size_override("font_size", 14)
	boost_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3))
	header.add_child(boost_label)

	_close_btn = Button.new()
	_close_btn.text = "✕"
	_close_btn.custom_minimum_size = Vector2(40, 40)
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)
	_style_button(_close_btn)

	_root.add_child(HSeparator.new())

	# Scrollable items container
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 400
	_root.add_child(scroll)

	_items_container = VBoxContainer.new()
	_items_container.add_theme_constant_override("separation", 8)
	scroll.add_child(_items_container)

	# Disclaimer
	var disclaimer := Label.new()
	disclaimer.text = "All content achievable for free. Purchases are optional and provide convenience only."
	disclaimer.add_theme_font_size_override("font_size", 12)
	disclaimer.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	disclaimer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	disclaimer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(disclaimer)

func _refresh_shop_ui() -> void:
	# Update boost label
	var boost_label: Label = _root.get_node_or_null("BoostLabel")
	if boost_label:
		if active_boost.mult > 1.0 and active_boost.expires > Time.get_unix_time_from_system():
			var hours_left: float = (active_boost.expires - Time.get_unix_time_from_system()) / 3600.0
			boost_label.text = "⚡ %.1fx boost (%.1fh left)" % [active_boost.mult, hours_left]
		else:
			boost_label.text = ""

	# Clear and rebuild items
	for c in _items_container.get_children():
		c.queue_free()

	# Group items by category
	var categories: Dictionary = {
		"booster": "⏱️ Time Boosters",
		"permanent": "🤖 Convenience",
		"one_time": "🎁 Special Offers",
		"cosmetic": "🎨 Cosmetics",
		"premium": "👑 Premium"
	}

	for cat_type in categories.keys():
		var cat_items: Array = shop_items.filter(func(item: Dictionary) -> bool: return item.type == cat_type)
		if cat_items.is_empty():
			continue

		# Category header
		var cat_label := Label.new()
		cat_label.text = categories[cat_type]
		cat_label.add_theme_font_size_override("font_size", 18)
		cat_label.add_theme_color_override("font_color", Color(0.8, 0.85, 0.9))
		cat_label.add_theme_constant_override("margin_top", 10)
		_items_container.add_child(cat_label)

		for item: Dictionary in cat_items:
			_items_container.add_child(_create_item_row(item))

func _create_item_row(item: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Icon
	var icon_label := Label.new()
	icon_label.text = item.get("icon", "📦")
	icon_label.add_theme_font_size_override("font_size", 24)
	icon_label.custom_minimum_size.x = 32
	row.add_child(icon_label)

	# Name + desc
	var info_vbox := VBoxContainer.new()
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 2)
	row.add_child(info_vbox)

	var name_label := Label.new()
	name_label.text = item.get("name", "???")
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	info_vbox.add_child(name_label)

	var desc_label := Label.new()
	desc_label.text = item.get("desc", "")
	desc_label.add_theme_font_size_override("font_size", 12)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.75, 0.8))
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_vbox.add_child(desc_label)

	# Price / Owned button
	var id: String = item.get("id", "")
	var is_owned: bool = id in owned_items
	var item_type: String = item.get("type", "")
	var is_one_time_owned: bool = item_type == "one_time" and is_owned

	var btn := Button.new()
	btn.custom_minimum_size = Vector2(100, 36)

	if is_one_time_owned:
		btn.text = "Owned"
		btn.disabled = true
	elif is_owned and item_type == "permanent":
		btn.text = "Owned"
		btn.disabled = true
	elif is_owned and item_type == "cosmetic":
		btn.text = "Equip"
	else:
		btn.text = item.get("price_display", "$?")

	_style_button(btn)

	# Button action
	if not btn.disabled:
		btn.pressed.connect(func(): _on_buy_pressed(item))

	row.add_child(btn)

	return row

func _on_buy_pressed(item: Dictionary) -> void:
	var item_id: String = item.get("id", "")
	
	# Platform-specific purchase
	if OS.has_feature("mobile"):
		_purchase_mobile(item_id, item)
	else:
		_purchase_steam(item_id, item)

func _purchase_steam(item_id: String, item: Dictionary) -> void:
	# Steam integration would go here
	# For now, simulate purchase
	print("Steam purchase: ", item_id)
	_grant_item(item)

func _purchase_mobile(item_id: String, item: Dictionary) -> void:
	# iOS/Android IAP would go here
	# For now, simulate purchase
	print("Mobile purchase: ", item_id)
	_grant_item(item)

func _grant_item(item: Dictionary) -> void:
	var id: String = item.get("id", "")
	var type: String = item.get("type", "")
	var effect: Variant = item.get("effect", {})

	# Grant the item
	if not id in owned_items:
		owned_items.append(id)

	match type:
		"booster":
			var mult: float = effect.get("thoughts_mult", 2.0)
			var hours: int = effect.get("duration_hours", 4)
			active_boost = {
				"mult": mult,
				"expires": Time.get_unix_time_from_system() + (hours * 3600)
			}
			print("Boost activated: ", mult, "x for ", hours, " hours")

		"one_time":
			var gm: Node = _get_game_manager()
			if gm:
				var mem: int = effect.get("memories", 0)
				var crystals: int = effect.get("crystals_each", 0)
				var boost_hours: int = effect.get("boost_hours", 0)
				
				if gm.has_method("add_memories"):
					gm.call("add_memories", mem)
				
				if boost_hours > 0:
					active_boost = {
						"mult": 2.0,
						"expires": Time.get_unix_time_from_system() + (boost_hours * 3600)
					}
				print("Starter pack granted: ", mem, " memories, ", crystals, " crystals each")

		"permanent":
			print("Permanent unlock: ", effect)

		"cosmetic":
			equipped_theme = id
			_apply_theme(id)
			equip_theme(id)
			print("Cosmetic unlocked: ", effect)

		"premium":
			# Grant all cosmetics
			for shop_item: Dictionary in shop_items:
				if shop_item.get("type", "") == "cosmetic":
					var cosmetic_id: String = shop_item.get("id", "")
					if not cosmetic_id in owned_items:
						owned_items.append(cosmetic_id)
			# Set permanent boost
			active_boost = {"mult": 1.1, "expires": -1} # -1 = permanent
			print("Premium pack granted")

	_save_shop_data()
	_refresh_shop_ui()

func get_active_thoughts_multiplier() -> float:
	if active_boost.expires == -1: # Permanent
		return active_boost.mult
	if active_boost.expires > Time.get_unix_time_from_system():
		return active_boost.mult
	return 1.0

func has_auto_buy() -> bool:
	return "auto_buy" in owned_items

func has_fast_mode() -> bool:
	return "fast_mode" in owned_items

func _get_game_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var cs := tree.current_scene
	if cs:
		return cs.find_child("GameManager", true, false)
	return null

func _save_shop_data() -> void:
	var data: Dictionary = SaveSystem.load_game()
	data["shop_owned_items"] = owned_items
	data["shop_active_boost"] = active_boost
	data["shop_equipped_theme"] = equipped_theme
	SaveSystem.save_game(data)  # Changed from set_data to save_game

func _load_shop_data() -> void:
	var data: Dictionary = SaveSystem.load_game()
	equipped_theme = data.get("shop_equipped_theme", "")
	if equipped_theme != "":
		_apply_theme(equipped_theme)
	# Load from your save system
	# var data: Dictionary = SaveSystem.get_data("shop", {})
	# owned_items = data.get("owned_items", [])
	# active_boost = data.get("active_boost", {"mult": 1.0, "expires": 0})
	pass

func _apply_center_layout(min_sz: Vector2) -> void:
	custom_minimum_size = min_sz
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -min_sz.x * 0.5
	offset_top = -min_sz.y * 0.5
	offset_right = min_sz.x * 0.5
	offset_bottom = min_sz.y * 0.5

func _apply_panel_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = panel_bg
	sb.border_color = panel_border
	sb.border_width_left = panel_border_width
	sb.border_width_top = panel_border_width
	sb.border_width_right = panel_border_width
	sb.border_width_bottom = panel_border_width
	sb.corner_radius_top_left = panel_radius
	sb.corner_radius_top_right = panel_radius
	sb.corner_radius_bottom_left = panel_radius
	sb.corner_radius_bottom_right = panel_radius
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)

func _mk_btn_style(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = border_w
	sb.border_width_top = border_w
	sb.border_width_right = border_w
	sb.border_width_bottom = border_w
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

func _style_button(btn: Button) -> void:
	if btn == null:
		return
	var normal := _mk_btn_style(Color(0.10, 0.11, 0.14, 0.95), Color(0.24, 0.67, 0.94, 0.95), 2, 8)
	var hover := _mk_btn_style(Color(0.13, 0.14, 0.18, 0.98), Color(0.30, 0.75, 0.98, 1.0), 2, 8)
	var pressed := _mk_btn_style(Color(0.07, 0.08, 0.10, 0.95), Color(0.20, 0.60, 0.90, 0.95), 2, 8)
	var disabled := _mk_btn_style(Color(0.08, 0.08, 0.10, 0.55), Color(0.20, 0.40, 0.55, 0.45), 2, 8)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.70, 0.74, 0.80, 1.0))

func _force_close_overlay(node_name: String) -> void:
	if node_name.strip_edges() == "":
		return
	var n := get_tree().current_scene.find_child(node_name, true, false)
	if n == null:
		return
	if n.has_method("close"):
		n.call("close")
	elif n is CanvasItem:
		(n as CanvasItem).visible = false

func has_early_auto_buy() -> bool:
	return "early_auto_buy" in owned_items
