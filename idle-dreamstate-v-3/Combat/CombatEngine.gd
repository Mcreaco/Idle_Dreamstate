extends Node
class_name CombatEngine

signal combat_started(enemy_name: String)
signal turn_started(turn_num: int, max_turns: int)
signal intent_revealed(intent: Dictionary)
signal player_turn(options: Array)
signal combat_ended(result: Dictionary)
signal hp_changed(p_hp: float, e_hp: float)
signal damage_dealt(amount: float, target_type: String)

var active: bool = false
var current_turn: int = 0
var max_turns: int = 99
var player_turn_active: bool = false

var player_stats: Dictionary
var enemy_stats: Dictionary
var current_depth: int = 0

var player_hp: float = 0.0
var enemy_hp: float = 0.0

var last_player_attack: String = ""
var enemy_intent: Dictionary = {}

var player_statuses: Array[Dictionary] = [] # {id, duration, strength}
var enemy_statuses: Array[Dictionary] = []

# Cache references to avoid repeated get_node calls
var _game_manager: Node = null
var _equipment_manager: Node = null

func _ready() -> void:
	_game_manager = get_node_or_null("/root/Main/GameManager")
	if _game_manager:
		_equipment_manager = _game_manager.get("equipment_manager")
		if _equipment_manager == null:
			push_warning("CombatEngine: EquipmentManager not found on GameManager")
	else:
		push_warning("CombatEngine: GameManager not found")

func _get_player_attack_options() -> Array:
	var options: Array = []
	
	# If no equipment manager, return basic options
	if _equipment_manager == null:
		options.append({"id": "slash", "name": "Slash", "type": "weapon", "desc": "100% dmg"})
		options.append({"id": "pierce", "name": "Pierce", "type": "weapon", "desc": "80% dmg"})
		options.append({"id": "block", "name": "Block", "type": "armor", "desc": "-60% dmg"})
		return options
	
	# Standard options
	options.append({"id": "slash", "name": "Slash", "type": "weapon", "desc": "100% dmg + Bleed"})
	options.append({"id": "pierce", "name": "Pierce", "type": "weapon", "desc": "80% dmg, ignore 30% DEF"})
	options.append({"id": "bludgeon", "name": "Bludgeon", "type": "weapon", "desc": "120% dmg + Stun"})
	options.append({"id": "block", "name": "Block", "type": "armor", "desc": "-60% damage"})
	options.append({"id": "dodge", "name": "Dodge", "type": "armor", "desc": "Avoid 100% (if predicted)"})
	options.append({"id": "brace", "name": "Brace", "type": "armor", "desc": "-30% dmg + reflect"})
	
	# Check equipment abilities safely
	if _equipment_manager.has_method("has_ring_ability") and _equipment_manager.has_ring_ability():
		options.append({"id": "interrupt", "name": "Interrupt", "type": "ring", "desc": "Cancel intent + 40% dmg"})
		options.append({"id": "feint", "name": "Feint", "type": "ring", "desc": "Force miss + counter"})
	
	if _equipment_manager.has_method("has_amulet_charge") and _equipment_manager.has_amulet_charge():
		if _equipment_manager.has_method("get_amulet_special_name"):
			options.append({"id": "special", "name": _equipment_manager.get_amulet_special_name(), "type": "amulet", "desc": "Special"})
		else:
			options.append({"id": "special", "name": "Amulet", "type": "amulet", "desc": "Special"})
	
	if current_turn == max_turns:
		if _equipment_manager.has_method("talisman_used"):
			if not _equipment_manager.talisman_used:
				options.append({"id": "ultimate", "name": "ULTIMATE", "type": "talisman", "desc": "300% damage"})
		else:
			options.append({"id": "ultimate", "name": "ULTIMATE", "type": "talisman", "desc": "300% damage"})
	
	return options

func _generate_equipment_drop() -> Dictionary:
	# Check if equipment manager exists
	if _equipment_manager == null:
		push_warning("CombatEngine: EquipmentManager is null, cannot generate drop")
		return {"rarity": "common", "slot": "weapon", "depth": current_depth, "name": "Broken Sword"}
	
	# Check if method exists
	if not _equipment_manager.has_method("generate_item"):
		push_warning("CombatEngine: EquipmentManager missing generate_item method")
		return {"rarity": "common", "slot": "weapon", "depth": current_depth, "name": "Rusty Dagger"}
	
	# Generate drop normally...
	var rarity_roll: float = randf()
	var rarity: String
	
	if current_depth >= 90:
		rarity = "legendary" if rarity_roll < 0.6 else "mythic"
	elif current_depth >= 70:
		rarity = "epic" if rarity_roll < 0.7 else "legendary"
	elif current_depth >= 40:
		rarity = "rare" if rarity_roll < 0.7 else "epic"
	elif current_depth >= 20:
		rarity = "uncommon" if rarity_roll < 0.6 else "rare"
	elif current_depth >= 10:
		rarity = "common" if rarity_roll < 0.5 else "uncommon"
	else:
		rarity = "common"
	
	var slots: Array[String] = ["weapon", "armor", "amulet", "ring1", "helmet", "talisman"]
	var slot: String = slots[randi() % slots.size()]
	
	return _equipment_manager.generate_item(rarity, slot, current_depth)

func start_combat(p_stats: Dictionary, e_data: Dictionary, depth: int) -> void:
	active = true
	current_turn = 1
	current_depth = depth
	
	max_turns = 99
	
	player_stats = p_stats
	enemy_stats = e_data.duplicate()
	
	player_hp = p_stats.max_hp
	enemy_hp = e_data.hp
	
	hp_changed.emit(player_hp, enemy_hp)
	combat_started.emit(enemy_stats.name)
	
	player_statuses.clear()
	enemy_statuses.clear()
	
	await get_tree().create_timer(0.5).timeout
	_start_turn()

func _start_turn() -> void:
	if not active:
		return
	
	# 1. PROCESS TURN-START STATUSES (Bleed, etc)
	_process_status_dots()
	
	if player_hp <= 0: _end_combat(false); return
	if enemy_hp <= 0: _end_combat(true); return
	
	# 2. CHECK STUN
	if _has_status(player_statuses, "stun"):
		_decrement_status(player_statuses, "stun")
		current_turn += 1
		await get_tree().create_timer(1.2).timeout
		_start_turn()
		return

	turn_started.emit(current_turn, max_turns)
	_generate_enemy_intent()
	
	var intent_info: Dictionary = _process_instability_effects(enemy_intent)
	intent_revealed.emit(intent_info)
	
	await get_tree().create_timer(1.0).timeout
	
	var options: Array = _get_player_attack_options()
	player_turn_active = true
	player_turn.emit(options)

func _process_status_dots() -> void:
	for i in range(player_statuses.size() - 1, -1, -1):
		var s = player_statuses[i]
		if s.id == "bleed":
			player_hp -= s.strength
			s.duration -= 1
			if s.duration <= 0: player_statuses.remove_at(i)
	
	for i in range(enemy_statuses.size() - 1, -1, -1):
		var s = enemy_statuses[i]
		if s.id == "bleed":
			enemy_hp -= s.strength
			s.duration -= 1
			if s.duration <= 0: enemy_statuses.remove_at(i)
	hp_changed.emit(player_hp, enemy_hp)

func _has_status(statuses: Array, id: String) -> bool:
	for s in statuses:
		if s.get("id") == id: return true
	return false

func _decrement_status(statuses: Array, id: String) -> void:
	for i in range(statuses.size() - 1, -1, -1):
		if statuses[i].get("id") == id:
			statuses[i].duration -= 1
			if statuses[i].duration <= 0: statuses.remove_at(i)

func _generate_enemy_intent() -> void:
	var possible_intents: Array[String] = ["strike", "crush", "flurry", "lunge", "charge", "weave", "drain"]
	
	if current_depth >= 5:
		var intent1: String = possible_intents[randi() % possible_intents.size()]
		var intent2: String = possible_intents[randi() % possible_intents.size()]
		enemy_intent = {
			"type": "dual",
			"options": [intent1, intent2],
			"selected": intent1 if randf() < 0.5 else intent2
		}
	else:
		var intent: String = possible_intents[randi() % possible_intents.size()]
		enemy_intent = {
			"type": "single", 
			"selected": intent
		}

func _process_instability_effects(intent: Dictionary) -> Dictionary:
	var gm: Node = _game_manager
	var inst_pct: float = gm.instability / gm.get_instability_cap(gm.get_current_depth())
	
	var result: Dictionary = intent.duplicate(true)
	
	if inst_pct > 0.51 and inst_pct <= 0.75:
		if result.type == "dual":
			result.options = [result.selected]
	
	elif inst_pct > 0.76 and inst_pct <= 0.90:
		if randf() < 0.3:
			var fake_intents: Array[String] = ["strike", "crush", "flurry"]
			result.selected = fake_intents[randi() % fake_intents.size()]
	
	elif inst_pct > 0.91:
		_auto_resolve_combat()
		return {}
	
	return result

# Also fix the unused parameter warning:
func _predicted_correctly(_action: String) -> bool:
	return randf() < 0.5

func execute_player_attack(attack_id: String) -> void:
	player_turn_active = false
	last_player_attack = attack_id
	
	var damage: float = 0.0
	var player_def_mult: float = 1.0
	
	match attack_id:
		"slash":
			damage = player_stats.attack * 1.0
			enemy_statuses.append({"id": "bleed", "duration": 3, "strength": player_stats.attack * 0.1})
		"pierce":
			damage = player_stats.attack * 0.8
			enemy_stats.defense *= 0.7
		"bludgeon":
			damage = player_stats.attack * 1.2
			if randf() < 0.35:
				enemy_statuses.append({"id": "stun", "duration": 1})
		"block":
			player_def_mult = 0.4
		"dodge":
			if _predicted_correctly("dodge"):
				player_def_mult = 0.0
		"brace":
			player_def_mult = 0.7
		"interrupt":
			damage = player_stats.attack * 0.4
			enemy_intent.selected = "interrupted"
		"feint":
			enemy_intent.selected = "missed"
		"ultimate":
			damage = player_stats.attack * 4.0
			_equipment_manager.use_talisman()
	
	if damage > 0:
		var enemy_def = enemy_stats.get("defense", 0.0)
		var actual_dmg: float = max(0.0, damage - enemy_def)
		enemy_hp -= actual_dmg
		damage_dealt.emit(actual_dmg, "enemy")
	
	# Process enemy response unless stunned or interrupted
	if not _has_status(enemy_statuses, "stun") and not enemy_intent.selected in ["interrupted", "missed"]:
		var enemy_dmg_raw: float = _calculate_enemy_damage()
		var player_def = player_stats.get("defense", 0.0)
		var actual_enemy_dmg: float = max(0.0, (enemy_dmg_raw * player_def_mult) - player_def)
		player_hp -= actual_enemy_dmg
		if actual_enemy_dmg > 0:
			damage_dealt.emit(actual_enemy_dmg, "player")
	
	# Decrement one-turn statuses (like stun) after they take effect
	_decrement_status(enemy_statuses, "stun")
	
	hp_changed.emit(player_hp, enemy_hp)
	
	if enemy_hp <= 0:
		_end_combat(true)
	elif player_hp <= 0:
		_end_combat(false)
	else:
		current_turn += 1
		await get_tree().create_timer(1.2).timeout
		_start_turn()

func _calculate_enemy_damage() -> float:
	var base_dmg: float = enemy_stats.attack
	
	match enemy_intent.selected:
		"strike":
			return base_dmg
		"crush":
			return base_dmg * 1.5
		"flurry":
			return base_dmg * 0.6 * 3
		"lunge":
			return base_dmg * (2.0 if randf() < 0.3 else 1.0)
		"charge":
			return base_dmg * 0.1
		"weave":
			return base_dmg * 0.8
		"drain":
			var dmg: float = base_dmg * 0.7
			enemy_hp = min(enemy_hp + dmg * 0.5, enemy_stats.hp)
			hp_changed.emit(player_hp, enemy_hp)
			return dmg
	
	return base_dmg

func _end_combat(won: bool) -> void:
	active = false
	player_turn_active = false
	
	var perfect: bool = won and player_hp >= player_stats.max_hp * 0.8
	
	var result: Dictionary = {
		"won": won,
		"perfect": perfect,
		"depth": current_depth,
		"turns_taken": current_turn,
		"drop": null
	}
	
	if won:
		result.drop = _generate_equipment_drop()
	
	combat_ended.emit(result)



# MISSING HELPERS - Implement these or stub them
func _auto_resolve_combat() -> void:
	# TODO: Implement auto-combat at 60% win rate
	_end_combat(randf() < 0.6)

func _apply_amulet_effect() -> void:
	# TODO: Implement amulet special effects
	pass
