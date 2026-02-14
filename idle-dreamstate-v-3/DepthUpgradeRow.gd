extends PanelContainer  # Changed from HBoxContainer to get borders
class_name DepthUpgradeRow

var depth_index: int = 1
var upgrade_id: String = ""
var upgrade_name: String = ""
var upgrade_desc: String = ""
var max_level: int = 1

var depth_meta: DepthMetaSystem
var gm: GameManager

var _name_lbl: Label
var _desc_lbl: Label
var _lvl_lbl: Label
var _cost_lbl: Label
var _buy_btn: Button
var _bar: ProgressBar

func _ready() -> void:
	# SETUP THE BORDER (Blue border like other panels)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.9)
	sb.border_color = Color(0.5, 0.6, 0.9, 0.6)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)
	
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	# Create main HBox for layout
	var main_hbox := HBoxContainer.new()
	main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_hbox.add_theme_constant_override("separation", 12)
	add_child(main_hbox)
	
	# LEFT SIDE: Name + Description (takes up left 60%)
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vbox.custom_minimum_size.x = 400
	main_hbox.add_child(left_vbox)
	
	_name_lbl = Label.new()
	_name_lbl.text = upgrade_name
	_name_lbl.add_theme_font_size_override("font_size", 16)
	left_vbox.add_child(_name_lbl)
	
	_desc_lbl = Label.new()
	_desc_lbl.text = upgrade_desc
	_desc_lbl.add_theme_font_size_override("font_size", 12)
	_desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left_vbox.add_child(_desc_lbl)
	
	# CENTER: Level + Cost (fixed width, centered)
	var center_vbox := VBoxContainer.new()
	center_vbox.custom_minimum_size.x = 200
	center_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.add_child(center_vbox)
	
	_lvl_lbl = Label.new()
	_lvl_lbl.text = "Lv 0/%d" % max_level
	_lvl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center_vbox.add_child(_lvl_lbl)
	
	_cost_lbl = Label.new()
	_cost_lbl.text = "Cost: ?"
	_cost_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cost_lbl.add_theme_font_size_override("font_size", 12)
	center_vbox.add_child(_cost_lbl)
	
	# Affordability bar below cost
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(150, 8)
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.show_percentage = true
	center_vbox.add_child(_bar)
	
	# RIGHT SIDE: Buy button
	_buy_btn = Button.new()
	_buy_btn.text = "Buy"
	_buy_btn.custom_minimum_size = Vector2(100, 40)
	_buy_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	main_hbox.add_child(_buy_btn)
	
	_buy_btn.pressed.connect(_on_buy)
	
	if gm != null and gm.has_method("_style_button"):
		gm._style_button(_buy_btn)
	
	if depth_meta == null:
		depth_meta = get_tree().current_scene.find_child("DepthMetaSystem", true, false)
	if gm == null:
		gm = get_tree().current_scene.find_child("GameManager", true, false)
	
	set_process(true)
	call_deferred("_refresh")  # Refresh after everything is ready

func _format_costs(d: int, def: Dictionary) -> Dictionary:
	var base := depth_meta.cost_for(d, def)
	var costs: Dictionary = def.get("costs", { d: 1.0 })
	
	var parts: Array[String] = []
	var ok := true
	
	for k in costs.keys():
		var idx := int(k)
		var need_f := base * float(costs[k])
		var need := int(round(need_f))
		var cname := DepthMetaSystem.get_depth_currency_name(idx)
		
		parts.append("%d %s" % [need, cname])
		
		if depth_meta.currency[idx] < need_f:
			ok = false
	
	return {
		"text": " + ".join(parts),
		"ok": ok,
		"base": base,
		"costs": costs
	}

func _refresh() -> void:
	# DEBUG
	if depth_meta == null:
		push_warning("DepthUpgradeRow: depth_meta is NULL for " + upgrade_id)
		_buy_btn.disabled = true
		return
	
	# Check if currency array is valid
	if depth_meta.currency.size() <= depth_index:
		push_warning("DepthUpgradeRow: currency array size " + str(depth_meta.currency.size()) + " <= index " + str(depth_index))
		_buy_btn.disabled = true
		return
	
	var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)
	var lvl := depth_meta.get_level(d, upgrade_id)
	
	_name_lbl.text = upgrade_name
	_desc_lbl.text = upgrade_desc
	_lvl_lbl.text = "Lv %d/%d" % [lvl, max_level]
	
	# Find def
	var defs := depth_meta.get_depth_upgrade_defs(d)
	var def: Dictionary = {}
	for item in defs:
		if String(item.get("id", "")) == upgrade_id:
			def = item
			break
	
	var can_buy := true
	var cost_text := "???"
	var affordability := 0.0
	
	if def.is_empty():
		can_buy = false
	else:
		var info := _format_costs(d, def)
		cost_text = String(info["text"])
		can_buy = bool(info["ok"])
		
		var base := float(info["base"])
		var costs: Dictionary = info["costs"]
		var primary_mult := float(costs.get(d, 1.0))
		var primary_cost := base * primary_mult
		if primary_cost > 0.0:
			affordability = clampf((depth_meta.currency[d] / primary_cost) * 100.0, 0.0, 100.0)
	
	_cost_lbl.text = cost_text
	_bar.value = affordability
	
	if lvl >= max_level:
		can_buy = false
		_cost_lbl.text = "MAXED"
		_bar.visible = false
	
	# Hide unlock row until it should appear
	if upgrade_id == "unlock":
		visible = depth_meta.can_show_unlock_upgrade(d) and (d < DepthMetaSystem.MAX_DEPTH)
	else:
		visible = true
	
	_buy_btn.disabled = not can_buy

func _on_buy() -> void:
	if depth_meta == null:
		return
	
	# Get level BEFORE buying
	var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)
	
	# Try to buy
	var res := depth_meta.try_buy(depth_index, upgrade_id)
	
	if bool(res.get("bought", false)):
		# Get level AFTER buying
		var new_level := depth_meta.get_level(d, upgrade_id)
		
		# IMMEDIATELY update the display
		_lvl_lbl.text = "Lv %d/%d" % [new_level, max_level]
		
		# Handle maxed case
		if new_level >= max_level:
			_cost_lbl.text = "MAXED"
			_bar.visible = false
			_buy_btn.disabled = true
			_buy_btn.text = "MAXED"
		else:
			# Update cost for next level
			var defs := depth_meta.get_depth_upgrade_defs(d)
			var def: Dictionary = {}
			for item in defs:
				if String(item.get("id", "")) == upgrade_id:
					def = item
					break
			
			if not def.is_empty():
				var info := _format_costs(d, def)
				_cost_lbl.text = String(info["text"])
				
				# Check if can afford next level
				var can_afford = bool(info["ok"])
				_buy_btn.disabled = not can_afford
		
		# Update meta panel currency display
		var meta_panel := get_tree().current_scene.find_child("MetaPanelController", true, false)
		if meta_panel != null:
			if meta_panel.has_method("_update_currency_display"):
				meta_panel._update_currency_display()
			if meta_panel.has_method("_refresh_depth_tabs"):
				meta_panel._refresh_depth_tabs()
		
		# Save and unlock logic
		if gm != null:
			if upgrade_id == "unlock":
				gm.force_unlock_depth_tab(depth_index + 1)
			gm.save_game()

func _process(_delta: float) -> void:
	# Only refresh periodically to catch currency changes
	if Engine.get_process_frames() % 10 == 0:
		if _buy_btn != null and not _buy_btn.disabled:
			var d := clampi(depth_index, 1, DepthMetaSystem.MAX_DEPTH)
			var lvl := depth_meta.get_level(d, upgrade_id)
			_lvl_lbl.text = "Lv %d/%d" % [lvl, max_level]
