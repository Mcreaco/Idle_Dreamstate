extends PanelContainer

var _ce: Node = null

var _enemy_name_lbl: Label = null
var _intent_display: Label = null
var _attack_grid: GridContainer = null
var _player_hp_bar: ProgressBar = null
var _enemy_hp_bar: ProgressBar = null
var _turn_counter: Label = null

func _ready() -> void:
	_enemy_name_lbl = find_child("EnemyName", true, false) as Label
	_intent_display = find_child("IntentDisplay", true, false) as Label
	_attack_grid = find_child("AttackGrid", true, false) as GridContainer
	_player_hp_bar = find_child("PlayerHP", true, false) as ProgressBar
	_enemy_hp_bar = find_child("EnemyHP", true, false) as ProgressBar
	_turn_counter = find_child("TurnCounter", true, false) as Label
	visible = false

func show_combat(encounter: Dictionary) -> void:
	visible = true
	if _enemy_name_lbl:
		_enemy_name_lbl.text = encounter.enemy.name
	
	var gm: Node = get_tree().current_scene.find_child("GameManager", true, false)
	if gm == null or not "combat_engine" in gm:
		return
	_ce = gm.combat_engine
	
	if _player_hp_bar:
		_player_hp_bar.max_value = _ce.player_stats.max_hp
		_player_hp_bar.value = _ce.player_stats.max_hp
	if _enemy_hp_bar:
		_enemy_hp_bar.max_value = _ce.enemy_stats.hp
		_enemy_hp_bar.value = _ce.enemy_stats.hp
	
	_ce.turn_started.connect(_on_turn_started)
	_ce.intent_revealed.connect(_show_intent)
	_ce.player_turn.connect(_show_attack_options)
	_ce.combat_ended.connect(_combat_finished)

func _on_turn_started(turn_num: int, max_turns: int) -> void:
	if _turn_counter:
		_turn_counter.text = "Turn %d / %d" % [turn_num, max_turns]
	if _player_hp_bar and _ce:
		_player_hp_bar.value = _ce.player_hp
	if _enemy_hp_bar and _ce:
		_enemy_hp_bar.value = _ce.enemy_hp

func _show_intent(intent: Dictionary) -> void:
	if _intent_display == null:
		return
	if intent.size() == 0:
		_intent_display.text = "TOO UNSTABLE — AUTO-RESOLVE"
		return
	var text := "Enemy: "
	if intent.get("type", "single") == "dual":
		var opts: Array = intent.get("options", [])
		text += "???" if opts.size() == 1 else " or ".join(opts)
	else:
		text += str(intent.get("selected", "?")).to_upper()
	_intent_display.text = text

func _show_attack_options(options: Array) -> void:
	if _attack_grid == null:
		return
	for child in _attack_grid.get_children():
		child.queue_free()
	for option in options:
		var btn := Button.new()
		btn.text = "%s\n%s" % [option.name, option.desc]
		btn.custom_minimum_size = Vector2(100, 50)
		btn.pressed.connect(_on_attack_selected.bind(option.id))
		_attack_grid.add_child(btn)

func _on_attack_selected(attack_id: String) -> void:
	if _ce == null:
		return
	_ce.execute_player_attack(attack_id)
	if _attack_grid:
		for btn in _attack_grid.get_children():
			btn.disabled = true
	if _player_hp_bar and _ce:
		_player_hp_bar.value = _ce.player_hp
	if _enemy_hp_bar and _ce:
		_enemy_hp_bar.value = _ce.enemy_hp

func _combat_finished(result: Dictionary) -> void:
	for child in get_children():
		child.visible = false
	_show_result_popup(result)

func _show_result_popup(result: Dictionary) -> void:
	var won: bool = result.get("won", false)
	var perfect: bool = result.get("perfect", false)
	var depth: int = result.get("depth", 1)
	var drop: Dictionary = result.get("drop", {})
	
	var overlay := PanelContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	
	var ov_style := StyleBoxFlat.new()
	ov_style.bg_color = Color(0.03, 0.04, 0.08, 0.97)
	ov_style.border_color = Color(0.3, 0.55, 0.9, 0.85) if won else Color(0.8, 0.25, 0.25, 0.85)
	ov_style.border_width_left = 3
	ov_style.border_width_top = 3
	ov_style.border_width_right = 3
	ov_style.border_width_bottom = 3
	ov_style.corner_radius_top_left = 10
	ov_style.corner_radius_top_right = 10
	ov_style.corner_radius_bottom_left = 10
	ov_style.corner_radius_bottom_right = 10
	ov_style.content_margin_left = 24.0
	ov_style.content_margin_right = 24.0
	ov_style.content_margin_top = 20.0
	ov_style.content_margin_bottom = 20.0
	overlay.add_theme_stylebox_override("panel", ov_style)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	overlay.add_child(vbox)
	
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	if perfect:
		title.text = "✦ PERFECT VICTORY ✦"
		title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	elif won:
		title.text = "VICTORY!"
		title.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
	else:
		title.text = "DEFEATED..."
		title.add_theme_color_override("font_color", Color(0.9, 0.35, 0.35))
	vbox.add_child(title)
	
	var dc_label := Label.new()
	dc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dc_label.add_theme_font_size_override("font_size", 16)
	if won:
		var reward := float(depth) * 50.0 * (2.0 if perfect else 1.0)
		dc_label.text = "+%.0f Dreamcloud" % reward
		dc_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	else:
		dc_label.text = "+5 Instability"
		dc_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
	vbox.add_child(dc_label)
	
	if not drop.is_empty():
		var drop_lbl := Label.new()
		drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		drop_lbl.add_theme_font_size_override("font_size", 14)
		drop_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
		drop_lbl.text = "Drop: %s [%s]" % [drop.get("name", "Item"), drop.get("rarity", "?").capitalize()]
		drop_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(drop_lbl)
	
	var btn := Button.new()
	btn.text = "Continue"
	btn.custom_minimum_size = Vector2(140, 44)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.pressed.connect(func():
		visible = false
		overlay.queue_free()
		for child in get_children():
			child.visible = true
	)
	vbox.add_child(btn)
