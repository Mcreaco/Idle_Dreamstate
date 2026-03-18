class_name EquipmentManager
extends Node

signal item_obtained(item: Dictionary)

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

func get_next_rarity(rarity: String) -> String:
	var rarities = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "transcendent", "god_tier"]
	var idx = rarities.find(rarity)
	if idx != -1 and idx < rarities.size() - 1:
		return rarities[idx + 1]
	return rarity

func get_merge_cost(rarity: String) -> int:
	match rarity:
		"common": return 5000 # 5k
		"uncommon": return 50000 # 50k
		"rare": return 250000 # 250k
		"epic": return 1500000 # 1.5M
		"legendary": return 10000000 # 10M
		"mythic": return 75000000 # 75M
		"transcendent": return 500000000 # 500M
		"god_tier": return 2500000000 # 2.5B
	return 500

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
	"god_tier": 5000000
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

func get_count_in_slot(slot: String) -> int:
	var count = 0
	for it in inventory:
		if it.get("slot", "") == slot:
			count += 1
	return count

func add_to_inventory(item: Dictionary, allow_overfill: bool = false) -> bool:
	var slot = item.get("slot", "weapon")
	if not allow_overfill and get_count_in_slot(slot) >= 32:
		return false
	inventory.append(item)
	item_obtained.emit(item)
	return true

func generate_item(rarity: String, slot: String, wave: int, forced_name: String = "") -> Dictionary:
	var base_score: int = BASE_SCORES[rarity]
	var stats_roll = _roll_stats(rarity, slot)
	
	# Determine if this is an S-Tier drop 
	var is_s_tier = false
	if ["epic", "legendary", "mythic", "transcendent", "god_tier"].has(rarity):
		# Wave Gating
		# Strictly gated by wave milestones
		if rarity == "god_tier" and wave < 141:
			rarity = "transcendent"
			base_score = BASE_SCORES[rarity]
		elif rarity == "transcendent" and wave < 121:
			rarity = "mythic"
			base_score = BASE_SCORES[rarity]
		elif rarity == "mythic" and wave < 101:
			rarity = "legendary"
			base_score = BASE_SCORES[rarity]
		elif rarity == "legendary" and wave < 81:
			rarity = "epic"
			base_score = BASE_SCORES[rarity]
		elif rarity == "epic" and wave < 61:
			rarity = "rare"
			base_score = BASE_SCORES[rarity]
			
		if wave >= 20 and randf() < 0.1: # 10% chance for S-tier if in correct pool
			is_s_tier = true
			
	var item_name = forced_name if forced_name != "" else _generate_item_name_v2(rarity, slot, wave, is_s_tier)
	
	var item: Dictionary = {
		"id": _generate_item_id(),
		"name": item_name,
		"rarity": rarity,
		"slot": slot,
		"is_s_tier": is_s_tier,
		"level": 1,
		"max_level": MAX_LEVELS[rarity],
		"plus_tier": 0,
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

		# Increase base stats for god tier
		if rarity == "god_tier":
			for k in item.stats.keys():
				item.stats[k] *= 2.0  # Extra multiplier for god tier stats

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
	
	# v13: Apply Skill Tree Passives
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm:
		var atk_mult = 1.0 + (gm.get_skill_level("strike_mastery") * 0.10)
		var hp_mult = 1.0 + (gm.get_skill_level("vitality_core") * 0.10)
		var def_mult = 1.0 + (gm.get_skill_level("iron_will") * 0.10)
		
		# Keystone: Resonance (+5% all per level)
		var res_lvl = gm.get_skill_level("resonance")
		if res_lvl > 0:
			var res_mult = 1.0 + (res_lvl * 0.05)
			atk_mult *= res_mult
			hp_mult *= res_mult
			def_mult *= res_mult
			
		stats.attack *= atk_mult
		stats.max_hp *= hp_mult
		stats.defense *= def_mult
		
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

func fuse_items(target_item: Dictionary, fodder_items: Array[Dictionary]) -> Dictionary:
	var rarity = target_item.get("rarity", "common")
	var slot = target_item.get("slot", "weapon")
	var plus_tier = target_item.get("plus_tier", 0)
	
	# Determine next tier
	var next_tier: String = ""
	match rarity:
		"common": next_tier = "uncommon"
		"uncommon": next_tier = "rare"
		"rare": next_tier = "epic"
		"epic": next_tier = "legendary"
		"legendary": next_tier = "mythic"
		"mythic": next_tier = "transcendent"
		"transcendent": next_tier = "god_tier"
	
	# SIMPLE LOGIC (Common to Rare)
	if ["common", "uncommon", "rare"].has(rarity):
		if fodder_items.size() < 2: return {} # Now requires 3 total (Target + 2 Fodder)
		for fodder in fodder_items:
			if fodder.rarity != rarity or fodder.slot != slot or fodder.name != target_item.name:
				return {}
		
		# Common doesn't need max level; Uncommon/Rare do
		if rarity != "common" and target_item.level < target_item.max_level:
			return {}
		
		# Upgrade to next tier
		var gm = get_node("/root/Main/GameManager")
		var cost = _get_fusion_cost(rarity)
		if gm.dreamcloud < cost: return {}
		gm.dreamcloud -= cost
		
		# v8 Fix: Pass target_item.name to preserve item type during fusion
		var new_item = generate_item(next_tier, slot, 1, target_item.name)
		new_item.level = 1
		gm.save_game()
		return new_item

	# TIERED LOGIC (Epic+)
	# 1. Base (Max) + Base -> Base+1
	if plus_tier == 0:
		if fodder_items.size() < 1: return {}
		var fodder = fodder_items[0]
		if fodder.rarity != rarity or fodder.slot != slot or fodder.plus_tier != 0 or fodder.name != target_item.name: 
			return {}
		if target_item.level < target_item.max_level: return {}
		
		var gm = get_node("/root/Main/GameManager")
		var cost = _get_fusion_cost(rarity)
		if gm.dreamcloud < cost: return {}
		gm.dreamcloud -= cost
		
		target_item.plus_tier = 1
		target_item.level = 1 # ENSURE RESET
		var new_item = target_item.duplicate(true)
		new_item.plus_tier = 1
		new_item.level = 1 # ENSURE RESET
		new_item["id"] = _generate_item_id() # Important: Unique ID for fusion
		for k in new_item.stats.keys(): new_item.stats[k] *= 1.2
		
		gm.save_game()
		return new_item
	
	# 2. Base+1 (Max) + 2x Base -> Base+2
	elif plus_tier == 1:
		if fodder_items.size() < 2: return {}
		for f in fodder_items:
			if f.rarity != rarity or f.slot != slot or f.plus_tier != 0 or f.name != target_item.name: 
				return {}
		if target_item.level < target_item.max_level: return {}
		
		var gm = get_node("/root/Main/GameManager")
		var cost = _get_fusion_cost(rarity) * 2
		if gm.dreamcloud < cost: return {}
		gm.dreamcloud -= cost
		
		var new_item = target_item.duplicate(true)
		new_item.plus_tier = 2
		new_item.level = 1
		new_item["id"] = _generate_item_id() # Important: Unique ID for fusion
		for k in new_item.stats.keys(): new_item.stats[k] *= 1.3
		
		gm.save_game()
		return new_item
		
	# 3. Base+2 + Base+2 -> NextTier
	elif plus_tier == 2:
		if fodder_items.size() < 1: return {}
		var fodder = fodder_items[0]
		if fodder.rarity != rarity or fodder.slot != slot or fodder.plus_tier != 2 or fodder.name != target_item.name: 
			return {}
		if target_item.level < target_item.max_level: return {}
		
		var gm = get_node("/root/Main/GameManager")
		var cost = _get_fusion_cost(rarity) * 4
		if gm.dreamcloud < cost: return {}
		gm.dreamcloud -= cost
		
		var new_item = generate_item(next_tier, slot, 1, target_item.name)
		new_item.level = 1
		gm.save_game()
		return new_item

	return {}

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

func sort_inventory() -> void:
	var slot_order = ["weapon", "armor", "helmet", "amulet", "ring1", "talisman"]
	var rarity_order = ["common", "uncommon", "rare", "epic", "legendary", "mythic", "transcendent", "god_tier"]
	
	inventory.sort_custom(func(a, b):
		# 1. Slot
		var s_a = slot_order.find(a.get("slot", "weapon"))
		var s_b = slot_order.find(b.get("slot", "weapon"))
		if s_a != s_b: return s_a < s_b
		
		# 2. Rarity (Higher first)
		var r_a = rarity_order.find(a.get("rarity", "common"))
		var r_b = rarity_order.find(b.get("rarity", "common"))
		if r_a != r_b: return r_a > r_b
		
		# 3. Level (Higher first)
		var l_a = a.get("level", 1)
		var l_b = b.get("level", 1)
		if l_a != l_b: return l_a > l_b
		
		# 4. Name
		return a.get("name", "") < b.get("name", "")
	)

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
	# print("[DEBUG] EquipmentManager (ID: %d): Serializing save data (ROBUST)..." % get_instance_id())
	# print("        - Equipped slots count: ", equipped.values().filter(func(v): return v != null).size())
	# print("        - Inventory count: ", inventory.size())
	return data

func load_save_data(data: Dictionary) -> void:
	# print("[DEBUG] EquipmentManager: Loading save data...")
	if data.has("equipped") and data["equipped"] is Dictionary:
		var eq = data["equipped"]
		for slot in equipped.keys():
			if eq.has(slot) and eq[slot] != null:
				equipped[slot] = eq[slot]
				if slot == "ring2": # Migration
					equipped["helmet"] = eq["ring2"]
					equipped["ring2"] = null
					# print("MIGRATION: Found legacy 'ring2', converting to 'helmet'")
	
	# print("LOAD: Restored equipped slots: ", equipped.keys().filter(func(k): return equipped[k] != null))
	
	if data.has("inventory") and data["inventory"] is Array:
		inventory.clear()
		for item in data["inventory"]:
			if item is Dictionary:
				var it: Dictionary = item
				if it.has("slot") and it["slot"] == "ring2":
					it["slot"] = "helmet"
					# print("MIGRATION: Converted inventory ring2 to helmet")
				inventory.append(it)
		enforce_inventory_cap()
	
func enforce_inventory_cap() -> void:
	var slots = ["weapon", "armor", "amulet", "ring1", "helmet", "talisman"]
	var new_inv: Array[Dictionary] = []
	for s in slots:
		var items_in_slot = []
		for it in inventory:
			if it.get("slot") == s:
				items_in_slot.append(it)
		# Keep only the first 32
		for i in range(min(32, items_in_slot.size())):
			new_inv.append(items_in_slot[i])
	inventory = new_inv
	
	# print("LOAD: Restored inventory items: ", inventory.size())
	
	# Standardize existing items (Remove old randomization)
	for item in equipped.values():
		if item: 
			if not item.has("id"): item["id"] = _generate_item_id()
			_standardize_item(item)
	for item in inventory:
		if not item.has("id"): item["id"] = _generate_item_id()
		_standardize_item(item)

func _standardize_item(item: Dictionary) -> void:
	var rarity = item.get("rarity", "common")
	var slot = item.get("slot", "weapon")
	var budget = 1.0
	match rarity:
		"common": budget = 1.0
		"uncommon": budget = 2.5
		"rare": budget = 6.0
		"epic": budget = 15.0
		"legendary": budget = 40.0
		"mythic": budget = 100.0
		"transcendent": budget = 300.0
		"god_tier": budget = 1500.0
	
	var stats = item.get("stats", {})
	match slot:
		"weapon": stats["attack"] = 12.0 * budget
		"armor":
			stats["hp"] = 60.0 * budget
			stats["defense"] = 8.0 * budget
		"ring1":
			stats["attack"] = 6.0 * budget
			stats["hp"] = 30.0 * budget
		"helmet":
			stats["defense"] = 5.0 * budget
			stats["hp"] = 25.0 * budget
		"amulet":
			stats["attack"] = 4.0 * budget
			stats["defense"] = 4.0 * budget
		"talisman":
			stats["hp"] = 40.0 * budget
			stats["attack"] = 10.0 * budget
	
	var s_stats = item.get("secondary_stats", {})
	for k in s_stats.keys():
		s_stats[k] = 0.05 * sqrt(budget)

# MISSING HELPERS - Implement or stub
func _generate_item_id() -> String:
	return str(Time.get_ticks_usec()) + "_" + str(randi_range(1000, 9999))

func _generate_item_name_v2(_rarity: String, slot: String, _wave: int, is_s_tier: bool) -> String:
	if is_s_tier:
		match slot:
			"weapon": return "Voidreever"
			"armor": return "Abyssal Garb"
			"ring1": return "Eternal Loop"
			"amulet": return "Soul Eye"
			"talisman": return "Heart of Dreams"
			"helmet": return "Void Gaze"
	
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
		"transcendent": budget = 300.0
		"god_tier": budget = 1500.0
	# Slot specializations
	match slot:
		"weapon":
			stats["attack"] = 12.0 * budget
		"armor":
			stats["hp"] = 60.0 * budget
			stats["defense"] = 8.0 * budget
		"ring1":
			stats["attack"] = 6.0 * budget
			stats["hp"] = 30.0 * budget
		"helmet":
			stats["defense"] = 5.0 * budget
			stats["hp"] = 25.0 * budget
		"amulet":
			stats["attack"] = 4.0 * budget
			stats["defense"] = 4.0 * budget
		"talisman":
			stats["hp"] = 40.0 * budget
			stats["attack"] = 10.0 * budget
			
	# Roll Secondary Stats (Thoughts, Crystals, Memories)
	var secondary := {}
	var rarity_list = ["common","uncommon","rare","epic","legendary","mythic","transcendent","god_tier"]
	var sec_chance = 0.3 + (0.1 * rarity_list.find(rarity))
	if randf() < sec_chance:
		# More variety: Add specific "Farm" stats vs "Combat" stats
		var farmer_keys = ["thoughts_mult", "crystals_mult", "memories_mult"]
		var combat_keys = ["crit_chance", "crit_damage", "instability_reduction"]
		
		var pool = farmer_keys if randf() < 0.6 else combat_keys
		var key = pool[randi() % pool.size()]
		
		# Boosts: fixed 5% base, scales with budget
		secondary[key] = 0.05 * sqrt(budget)
	
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
	var base_cost = 100
	var rarity_mult = ["common","uncommon","rare","epic","legendary","mythic","transcendent","god_tier"].find(item.rarity) + 1
	var plus_mult = 1.0 + (item.get("plus_tier", 0) * 1.5)
	
	var total = 0
	for i in range(levels):
		total += int(base_cost * (item.level + i) * rarity_mult * plus_mult)
	return total

# Ring/Amulet/Talisman helpers
func has_ring_ability() -> bool:
	return equipped.ring1 != null

func has_amulet_charge() -> bool:
	return equipped.amulet != null

func get_amulet_special_name() -> String:
	return "Special Attack"

func use_talisman() -> void:
	pass
