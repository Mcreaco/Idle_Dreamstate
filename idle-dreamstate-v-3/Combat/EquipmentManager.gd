extends Node
class_name EquipmentManager

const MAX_LEVELS := {
	"common": 10,
	"uncommon": 20,
	"rare": 30,
	"epic": 40,
	"legendary": 40,
	"mythic": 60,
	"transcendent": 80,
	"god_tier": 100
}

const LEVEL_BONUSES := {
	"common": 0.05,
	"uncommon": 0.05,
	"rare": 0.05,
	"epic": 0.05,
	"legendary": 0.05,
	"mythic": 0.05,
	"transcendent": 0.05,
	"god_tier": 0.05
}

const BASE_SCORES := {
	"common": 250,
	"uncommon": 1000,
	"rare": 6000,
	"epic": 27000,
	"legendary": 100000,
	"mythic": 350000,
	"transcendent": 600000,
	"god_tier": 1000000
}

var equipped: Dictionary = {
	"weapon": null,
	"armor": null,
	"amulet": null,
	"ring1": null,
	"helmet": null,
	"talisman": null
}

var inventory: Array[Dictionary] = []
var active_set_bonuses: Dictionary = {}

func generate_item(rarity: String, slot: String, wave: int) -> Dictionary:
	var base_score: int = BASE_SCORES[rarity]
	var stats_roll = _roll_stats(rarity, slot)
	
	# Determine if this is an S-Tier drop (Wave 20+, Rare+ only)
	var is_s_tier = false
	if wave >= 20 and ["epic", "legendary", "mythic", "transcendent", "god_tier"].has(rarity):
		if randf() < 0.1: # 10% chance for S-tier if in correct pool
			is_s_tier = true
			
	var item_name = _generate_item_name_v2(rarity, slot, wave, is_s_tier)
	
	var item: Dictionary = {
		"id": _generate_item_id(),
		"name": item_name,
		"rarity": rarity,
		"slot": slot,
		"is_s_tier": is_s_tier,
		"level": 1,
		"max_level": MAX_LEVELS[rarity],
		"base_score": base_score * (2.5 if is_s_tier else 1.0),
		"stats": stats_roll.main,
		"secondary_stats": stats_roll.secondary,
		"sub_stats": _roll_sub_stats(rarity),
		"set_id": _roll_set_id(),
		"special_attack": _get_special_for_slot(slot)
	}
	
	if is_s_tier:
		# S-Tier gets a primary stat boost
		for k in item.stats.keys():
			item.stats[k] *= 1.5

	return item

func calculate_item_score(item: Dictionary) -> float:
	var base: int = item.base_score
	var level_bonus: float = 1.0 + (item.level * LEVEL_BONUSES[item.rarity])
	var roll_quality: float = _calculate_roll_quality(item.stats)
	var set_bonus: float = 1.2 if _is_set_equipped(item.set_id) else 1.0
	
	return base * level_bonus * roll_quality * set_bonus

func calculate_total_gear_score() -> float:
	var total: float = 0.0
	for slot in equipped.keys():
		if equipped[slot] != null:
			total += calculate_item_score(equipped[slot])
	return total

func get_player_combat_stats() -> Dictionary:
	var stats: Dictionary = {
		"attack": 10.0,
		"max_hp": 100.0,
		"defense": 5.0
	}
	
	for slot in equipped.keys():
		var item = equipped[slot]
		if item == null: continue
		
		# Base Scaling based on level and rarity (Level bonus from constants or fixed 5% per lv)
		var lv_mult = 1.0 + (item.get("level", 1) * 0.05)
		var item_stats: Dictionary = item.get("stats", {})
		
		if item_stats.has("attack"):
			stats.attack += item_stats.attack * lv_mult
		if item_stats.has("hp"):
			stats.max_hp += item_stats.hp * lv_mult
		if item_stats.has("defense"):
			stats.defense += item_stats.defense * lv_mult
	
	_apply_set_bonuses(stats)
	return stats

func get_total_secondary_bonuses() -> Dictionary:
	var totals: Dictionary = {
		"thoughts_mult": 0.0,
		"crystals_mult": 0.0,
		"memories_mult": 0.0
	}
	for slot in equipped.keys():
		var item = equipped[slot]
		if item == null: continue
		var lv_mult = 1.0 + (item.get("level", 1) * 0.05)
		var s_stats = item.get("secondary_stats", {})
		for key in totals.keys():
			if s_stats.has(key):
				totals[key] += s_stats[key] * lv_mult
	
	return totals

func level_up_item(slot: String, levels: int = 1) -> bool:
	var item: Dictionary = equipped[slot]
	if item == null:
		return false
	
	if item.level >= item.max_level:
		return false
	
	var gm: Node = get_node("/root/Main/GameManager")
	var cost: int = _calculate_level_cost(item, levels)
	
	if gm.dreamcloud < cost:
		return false
	
	gm.dreamcloud -= cost
	item.level = min(item.level + levels, item.max_level)
	gm.save_game()
	return true

func fuse_items(item1: Dictionary, item2: Dictionary, item3: Dictionary) -> Dictionary:
	if item1.rarity != item2.rarity or item2.rarity != item3.rarity:
		return {}
	
	if item1.level < item1.max_level or item2.level < item2.max_level or item3.level < item3.max_level:
		return {}
	
	var next_tier: String = ""
	match item1.rarity:
		"common": next_tier = "uncommon"
		"uncommon": next_tier = "rare"
		"rare": next_tier = "epic"
		"epic": next_tier = "legendary"
		"legendary": next_tier = "mythic"
		"mythic": next_tier = "transcendent"
		"transcendent": next_tier = "god_tier"
		_: return {}
	
	var gm: Node = get_node("/root/Main/GameManager")
	var fusion_cost: int = _get_fusion_cost(item1.rarity)
	
	if gm.dreamcloud < fusion_cost:
		return {}
	
	gm.dreamcloud -= fusion_cost
	var new_item: Dictionary = generate_item(next_tier, item1.slot, 1)
	new_item.level = 1
	gm.save_game()
	return new_item

func _get_fusion_cost(rarity: String) -> int:
	match rarity:
		"common": return 500
		"uncommon": return 2500
		"rare": return 10000
		"epic": return 50000
		"legendary": return 200000
		"mythic": return 500000
		"transcendent": return 1000000
	return 9999999

func salvage_item(item: Dictionary) -> int:
	return int(calculate_item_score(item) * 0.3)

func dismantle_item(idx: int) -> int:
	if idx < 0 or idx >= inventory.size():
		return 0
	var item = inventory[idx]
	var reward = salvage_item(item)
	inventory.remove_at(idx)
	
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm:
		gm.dreamcloud += reward
		gm.save_game()
	return reward

func get_save_data() -> Dictionary:
	# Explicitly deep-duplicate to break references and ensure perfect JSON snapshots
	var data = {
		"equipped": equipped.duplicate(true), 
		"inventory": inventory.duplicate(true)
	}
	print("[DEBUG] EquipmentManager (ID: %d): Serializing save data (ROBUST)..." % get_instance_id())
	print("        - Equipped slots count: ", equipped.values().filter(func(v): return v != null).size())
	print("        - Inventory count: ", inventory.size())
	return data

func load_save_data(data: Dictionary) -> void:
	print("[DEBUG] EquipmentManager: Loading save data...")
	if data.has("equipped") and data["equipped"] is Dictionary:
		var d_equipped: Dictionary = data["equipped"]
		# Only clear/restore if the dict isn't totally empty, or if specifically intended
		if d_equipped.size() > 0 or inventory.size() == 0:
			for slot in equipped.keys():
				var key_to_check = slot
				# Migration: search for ring2 and convert to helmet
				if slot == "helmet" and not d_equipped.has("helmet") and d_equipped.has("ring2"):
					key_to_check = "ring2"
					print("MIGRATION: Found legacy 'ring2', converting to 'helmet'")
					
				if d_equipped.has(key_to_check):
					var item = d_equipped[key_to_check]
					if item is Dictionary:
						if key_to_check == "ring2": item["slot"] = "helmet"
						equipped[slot] = item

	print("LOAD: Restored equipped slots: ", equipped.keys().filter(func(k): return equipped[k] != null))
	
	if data.has("inventory") and data["inventory"] is Array:
		inventory.clear()
		for item in data["inventory"]:
			if item is Dictionary:
				var it: Dictionary = item
				if it.get("slot") == "ring2": 
					it["slot"] = "helmet"
					print("MIGRATION: Converted inventory ring2 to helmet")
				inventory.append(it)
	
	print("LOAD: Restored inventory items: ", inventory.size())

# MISSING HELPERS - Implement or stub
func _generate_item_id() -> String:
	return str(randi())

func _generate_item_name_v2(_rarity: String, slot: String, _wave: int, is_s_tier: bool) -> String:
	if is_s_tier:
		match slot:
			"weapon": return "Voidreaver"
			"armor": return "Abyssal Garb"
			"ring1": return "Eternal Loop"
			"amulet": return "Soul Eye"
			"talisman": return "Heart of Dreams"
	
	var pool := {
		"weapon": ["Long Sword", "Heavy Mace", "Sharp Dagger"],
		"armor": ["Steel Plate", "Leather Tunic"],
		"helmet": ["Iron Helm", "Great Helm"],
		"ring1": ["Silver Band", "Gold Ring"],
		"amulet": ["Crystal Neck"],
		"talisman": ["Ancient Idol"]
	}
	
	var names: Array = pool.get(slot, ["Mystery Item"])
	return names[randi() % names.size()]

func _roll_stats(rarity: String, slot: String) -> Dictionary:
	var stats := {}
	var budget := 1.0
	match rarity:
		"common": budget = 1.0
		"uncommon": budget = 2.5
		"rare": budget = 6.0
		"epic": budget = 15.0
		"legendary": budget = 40.0
		"mythic": budget = 100.0
	# Slot specializations
	match slot:
		"weapon":
			stats["attack"] = 12.0 * budget * (0.9 + randf() * 0.2)
		"armor":
			stats["hp"] = 60.0 * budget * (0.9 + randf() * 0.2)
			stats["defense"] = 8.0 * budget * (0.9 + randf() * 0.2)
		"ring1":
			if randf() > 0.5: stats["attack"] = 6.0 * budget * (0.8 + randf() * 0.4)
			else: stats["hp"] = 30.0 * budget * (0.8 + randf() * 0.4)
		"helmet":
			stats["defense"] = 5.0 * budget * (0.9 + randf() * 0.2)
			stats["hp"] = 25.0 * budget * (0.9 + randf() * 0.2)
		"amulet":
			stats["attack"] = 4.0 * budget * randf()
			stats["defense"] = 4.0 * budget * randf()
		"talisman":
			stats["hp"] = 40.0 * budget * randf()
			stats["attack"] = 10.0 * budget * randf()
			
	# Roll Secondary Stats (Thoughts, Crystals, Memories)
	var secondary := {}
	var sec_chance = 0.3 + (0.1 * ["common","uncommon","rare","epic","legendary","mythic"].find(rarity))
	if randf() < sec_chance:
		# More variety: Add specific "Farm" stats vs "Combat" stats
		var farmer_keys = ["thoughts_mult", "crystals_mult", "memories_mult"]
		var combat_keys = ["crit_chance", "crit_damage", "instability_reduction"]
		
		var pool = farmer_keys if randf() < 0.6 else combat_keys
		var key = pool[randi() % pool.size()]
		
		# Boosts: 2-8% base, scales with budget (Mythic budget 100 -> ~20-80%)
		secondary[key] = (0.02 + randf() * 0.06) * sqrt(budget)
	
	return {"main": stats, "secondary": secondary}

func _roll_sub_stats(_rarity: String) -> Dictionary:
	return {}

func _roll_set_id() -> String:
	return ""

func _get_special_for_slot(_slot: String) -> String:
	return ""

func _calculate_roll_quality(_stats: Dictionary) -> float:
	return 1.0

func _is_set_equipped(_set_id: String) -> bool:
	return false

func _apply_set_bonuses(_stats: Dictionary) -> void:
	pass

func _calculate_level_cost(item: Dictionary, levels: int) -> int:
	return item.level * 100 * levels

# Ring/Amulet/Talisman helpers
func has_ring_ability() -> bool:
	return equipped.ring1 != null

func has_amulet_charge() -> bool:
	return equipped.amulet != null

func get_amulet_special_name() -> String:
	return "Special Attack"

func use_talisman() -> void:
	pass
