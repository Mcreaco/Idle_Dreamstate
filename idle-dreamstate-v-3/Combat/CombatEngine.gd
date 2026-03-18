extends Node
class_name CombatEngine

signal combat_started(enemy_name: String)
signal turn_started(turn_num: int, max_turns: int)
signal intent_revealed(intent: Dictionary)
signal player_turn(options: Array)
signal combat_ended(result: Dictionary)
signal hp_changed(p_hp: float, e_hp: float)
signal damage_dealt(amount: float, target_type: String)
signal message_logged(text: String)
signal vfx_triggered(type: String)

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

var _game_manager: Node = null
var _equipment_manager: Node = null
var _sound_system: Node = null

func _ready() -> void:
	_game_manager = get_node_or_null("/root/Main/GameManager")
	_sound_system = get_node_or_null("/root/Main/SoundSystem")
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
	
	# 1. Base Attack tied to Weapon name
	var weapon_item = _equipment_manager.equipped.get("weapon")
	if weapon_item:
		var w_name = weapon_item.get("name", "").to_lower()
		if "mace" in w_name or "hammer" in w_name or "club" in w_name:
			options.append({"id": "bludgeon", "name": "Bludgeon", "type": "weapon", "desc": "120% dmg + Stun"})
		elif "dagger" in w_name or "rapier" in w_name or "stinger" in w_name:
			options.append({"id": "pierce", "name": "Pierce", "type": "weapon", "desc": "80% dmg, ignore 30% DEF"})
		else:
			# Default is Sword/Slash
			options.append({"id": "slash", "name": "Slash", "type": "weapon", "desc": "100% dmg + Bleed"})
		
		# S-Tier / Awakened Action (Legendary or higher)
		var rarity = weapon_item.get("rarity", "common")
		if rarity in ["legendary", "mythic", "transcendent", "god_tier"]:
			options.insert(0, {"id": "awakened_strike", "name": "AWAKENED", "type": "weapon", "desc": "300% DMG Dimensional Strike"})
	else:
		# Bare fists/Generic
		options.append({"id": "slash", "name": "Strike", "type": "weapon", "desc": "80% dmg"})

	# Filtered advanced actions (Universal/Tactical)
	var advanced_actions = [
		{"id": "block", "name": "Block", "type": "armor", "desc": "-60% damage"},
		{"id": "dodge", "name": "Dodge", "type": "armor", "desc": "Avoid 100% (if predicted)"},
		{"id": "brace", "name": "Brace", "type": "armor", "desc": "-30% dmg + reflect"},
		{"id": "meditate", "name": "Meditate", "type": "amulet", "desc": "+10% HP, gain Focus"},
		{"id": "overclock", "name": "Overclock", "type": "talisman", "desc": "+50% ATK, take 10% HP"}
	]
	
	for action in advanced_actions:
		if _game_manager.has_method("is_skill_unlocked") and _game_manager.is_skill_unlocked(action.id):
			options.append(action)
	
	# Special ring abilities (also locked by skill tree if we want, but keeping them tied to equipment for now)
	if _game_manager.has_method("is_skill_unlocked") and _game_manager.is_skill_unlocked("interrupt"):
		if _equipment_manager.has_method("has_ring_ability") and _equipment_manager.has_ring_ability():
			options.append({"id": "interrupt", "name": "Interrupt", "type": "ring", "desc": "Cancel intent + 40% dmg"})
	
	if _game_manager.has_method("is_skill_unlocked") and _game_manager.is_skill_unlocked("feint"):
		if _equipment_manager.has_method("has_ring_ability") and _equipment_manager.has_ring_ability():
			options.append({"id": "feint", "name": "Feint", "type": "ring", "desc": "Force miss + counter"})
	
	if _game_manager.has_method("is_skill_unlocked") and _game_manager.is_skill_unlocked("special"):
		if _equipment_manager.has_method("has_amulet_charge") and _equipment_manager.has_amulet_charge():
			if _equipment_manager.has_method("get_amulet_special_name"):
				options.append({"id": "special", "name": _equipment_manager.get_amulet_special_name(), "type": "amulet", "desc": "Special"})
			else:
				options.append({"id": "special", "name": "Amulet", "type": "amulet", "desc": "Special"})

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
	message_logged.emit("[color=#ffffff]Combat started against [b]%s[/b]![/color]" % enemy_stats.name)
	
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
	
	# Process Overclocked status duration
	_decrement_status(player_statuses, "overclocked")
	
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
	
	# v13: Skill Tree Passives (Conditional Multipliers)
	var atk_mult = 1.0
	
	# v17: Depth Run Upgrades (Combat Reflexes, Shadow Binding)
	var drc = _game_manager.get_node_or_null("DepthRunController")
	if drc:
		atk_mult *= drc.call("get_combat_damage_mult")
	
	if _game_manager.is_skill_unlocked("god_slayer") and enemy_stats.get("is_boss", false):
		atk_mult *= 4.0 # +300% vs Bosses
	
	var crit_chance = _game_manager.get_skill_level("lethal_precision") * 0.05
	var is_crit = randf() < crit_chance
	if is_crit: atk_mult *= 2.0
	
	var heal_on_hit_pct = _game_manager.get_skill_level("bloodlust") * 0.02
	
	# Initial action logic
	match attack_id:
		"slash":
			damage = player_stats.attack * 1.0
			enemy_statuses.append({"id": "bleed", "duration": 3, "strength": player_stats.attack * 0.1})
		"awakened_strike":
			damage = player_stats.attack * 3.0
			enemy_statuses.append({"id": "bleed", "duration": 5, "strength": player_stats.attack * 0.2})
			damage *= (1.0 + _game_manager.get_skill_level("s_tier_res") * 0.50)
		"pierce":
			damage = player_stats.attack * 0.8
			enemy_stats.defense *= 0.7
		"bludgeon":
			damage = player_stats.attack * 1.2
			if randf() < 0.35:
				enemy_statuses.append({"id": "stun", "duration": 1})
		"block":
			player_def_mult = 0.4
			var retal_chance = _game_manager.get_skill_level("counter_strike") * 0.20
			if randf() < retal_chance: _execute_retaliation()
		"dodge":
			if _predicted_correctly("dodge"): player_def_mult = 0.0
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
		"meditate":
			var heal = player_stats.max_hp * 0.1
			player_hp = min(player_hp + heal, player_stats.max_hp)
			player_statuses.append({"id": "focus", "duration": 1})
		"overclock":
			player_hp -= player_stats.max_hp * 0.1
			player_statuses.append({"id": "overclocked", "duration": 2})
			if _game_manager: _game_manager.instability += 1.0
	
	# Final Damage Processing
	if damage > 0 and attack_id != "bludgeon":
		_execute_damage_calc(damage, atk_mult, is_crit, heal_on_hit_pct, attack_id)

	# Turn Sequence Logic (v8 Adjustment: Delayed turns and Bludgeon order)
	if attack_id == "bludgeon":
		# Enemy attacks FIRST for 120% dmg tradeoff
		if not _has_status(enemy_statuses, "stun") and not enemy_intent.selected in ["interrupted", "missed"]:
			_process_enemy_attack(player_def_mult)
		
		# 0.8s pause before player counter
		await get_tree().create_timer(0.8).timeout
		_execute_damage_calc(damage, atk_mult, is_crit, heal_on_hit_pct, attack_id)
	else:
		# Player attacked, now wait 0.8s then enemy response
		await get_tree().create_timer(0.8).timeout
		if not _has_status(enemy_statuses, "stun") and not enemy_intent.selected in ["interrupted", "missed"]:
			_process_enemy_attack(player_def_mult)
	
	_decrement_status(enemy_statuses, "stun")
	hp_changed.emit(player_hp, enemy_hp)
	
	if enemy_hp <= 0: _end_combat(true)
	elif player_hp <= 0: _end_combat(false)
	else:
		current_turn += 1
		await get_tree().create_timer(0.7).timeout
		_start_turn()

func _execute_damage_calc(damage: float, atk_mult: float, is_crit: bool, heal_on_hit_pct: float, attack_id: String) -> void:
	if damage <= 0: return
	
	damage *= atk_mult
	if _has_status(player_statuses, "focus"):
		damage *= 1.5
		_decrement_status(player_statuses, "focus")
	if _has_status(player_statuses, "overclocked"):
		damage *= 1.5
		
	var effective_def = enemy_stats.defense
	if _game_manager.is_skill_unlocked("ripper"): effective_def *= 0.5
	
	var hits = 2 if (attack_id in ["slash", "pierce", "bludgeon", "strike"] and _game_manager.is_skill_unlocked("omega_strike")) else 1
	for i in range(hits):
		var final_dmg = maxf(1.0, damage - effective_def)
		enemy_hp -= final_dmg
		damage_dealt.emit(final_dmg, "enemy")
		if _sound_system: _sound_system.play_combat_hit()
		if is_crit: message_logged.emit("[color=#ffcc00][b]CRITICAL![/b][/color]")
		if heal_on_hit_pct > 0:
			var h = player_stats.max_hp * heal_on_hit_pct
			player_hp = minf(player_stats.max_hp, player_hp + h)

func _execute_retaliation() -> void:
	var damage = player_stats.attack * 0.5
	enemy_hp -= damage
	damage_dealt.emit(damage, "enemy")
	message_logged.emit("[color=#ffccff]Counter-Strike![/color]")
	vfx_triggered.emit("slash")
	hp_changed.emit(player_hp, enemy_hp)

func _process_enemy_attack(p_def_mult: float) -> void:
	var raw_dmg = _calculate_enemy_damage()
	var player_def = player_stats.get("defense", 0.0)
	var final_dmg = maxf(0.0, (raw_dmg * p_def_mult) - player_def)
	
	# v17: Depth Run Upgrades (Defensive Stance)
	var drc = _game_manager.get_node_or_null("DepthRunController")
	if drc:
		final_dmg *= drc.call("get_combat_defense_mult")
	
	player_hp -= final_dmg
	if final_dmg > 0:
		damage_dealt.emit(final_dmg, "player")
		if _sound_system: _sound_system.play_combat_hit()
		message_logged.emit("[color=#ff5555]Enemy %s: %.0f dmg[/color]" % [enemy_intent.selected.capitalize(), final_dmg])
	else:
		message_logged.emit("[color=#cccccc]Enemy missed![/color]")

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
		if _sound_system: _sound_system.play_combat_kill()
		result.drop = _generate_equipment_drop()
	
	combat_ended.emit(result)



# MISSING HELPERS - Implement these or stub them
func _auto_resolve_combat() -> void:
	# TODO: Implement auto-combat at 60% win rate
	_end_combat(randf() < 0.6)

func _apply_amulet_effect() -> void:
	# TODO: Implement amulet special effects
	pass
