extends PanelContainer

@onready var enemy_name: Label = $VBox/EnemyName
@onready var intent_display: Control = $VBox/IntentDisplay
@onready var attack_grid: GridContainer = $VBox/AttackGrid
@onready var player_hp_bar: ProgressBar = $VBox/PlayerHP
@onready var enemy_hp_bar: ProgressBar = $VBox/EnemyHP
@onready var turn_counter: Label = $VBox/TurnCounter

var _ce: Node = null

func show_combat(encounter: Dictionary) -> void:
	visible = true
	enemy_name.text = encounter.enemy.name
	
	_ce = get_node("/root/Main/GameManager").combat_engine
	var ce: Node = _ce  # Local typed reference
	
	player_hp_bar.max_value = ce.player_stats.max_hp
	enemy_hp_bar.max_value = ce.enemy_stats.hp
	
	ce.intent_revealed.connect(_show_intent)
	ce.player_turn.connect(_show_attack_options)
	ce.combat_ended.connect(_combat_finished)

func _show_intent(intent: Dictionary) -> void:
	if intent.size() == 0:
		intent_display.text = "TOO UNSTABLE - AUTO-COMBAT"
		return
	
	var text: String = "ENEMY INTENT: "
	if intent.type == "dual":
		text += "???" if intent.options.size() == 1 else " or ".join(intent.options)
	else:
		text += intent.selected.to_upper()
	
	intent_display.text = text

func _show_attack_options(options: Array) -> void:
	for child in attack_grid.get_children():
		child.queue_free()
	
	for option in options:
		var btn := Button.new()
		btn.text = "%s\n%s" % [option.name, option.desc]
		btn.pressed.connect(_on_attack_selected.bind(option.id))
		attack_grid.add_child(btn)

func _on_attack_selected(attack_id: String) -> void:
	var ce: Node = _ce
	ce.execute_player_attack(attack_id)
	
	for btn in attack_grid.get_children():
		btn.disabled = true

func _combat_finished(result: Dictionary) -> void:
	visible = false
	
	var msg: String = "VICTORY!" if result.won else "DEFEAT..."
	if result.perfect:
		msg += "\nPERFECT!"
	
	_show_result_popup(msg, result)

func _show_result_popup(msg: String, result: Dictionary) -> void:
	# TODO: Implement result popup
	print(msg, result)
