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
	"common": 0.02,
	"uncommon": 0.02,
	"rare": 0.02,
	"epic": 0.02,
	"legendary": 0.02,
	"mythic": 0.03,
	"transcendent": 0.04,
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
	"ring2": null,
	"talisman": null
}

var inventory: Array[Dictionary] = []
var active_set_bonuses: Dictionary = {}

func generate_item(rarity: String, slot: String, depth: int) -> Dictionary:
	var base_score: int = BASE_SCORES[rarity]
	var item: Dictionary = {
		"id": _generate_item_id(),
		"name": _generate_item_name(rarity, slot, depth),
		"rarity": rarity,
		"slot": slot,
		"level": 1,
		"max_level": MAX_LEVELS[rarity],
		"base_score": base_score,
		"stats": _roll_stats(rarity, slot),
		"sub_stats": _roll_sub_stats(rarity),
		"set_id": _roll_set_id(),
		"special_attack": _get_special_for_slot(slot)
	}
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
	
	if equipped.weapon:
		stats.attack += equipped.weapon.stats.attack * (1.0 + equipped.weapon.level * 0.02)
	if equipped.armor:
		stats.max_hp += equipped.armor.stats.hp * (1.0 + equipped.armor.level * 0.02)
		stats.defense += equipped.armor.stats.defense * (1.0 + equipped.armor.level * 0.02)
	
	_apply_set_bonuses(stats)
	return stats

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

func get_save_data() -> Dictionary:
	return {"equipped": equipped, "inventory": inventory}

func load_save_data(data: Dictionary) -> void:
	if data.has("equipped"):
		equipped = data.equipped
	if data.has("inventory"):
		# Clear current inventory
		inventory.clear()
		# Convert untyped Array to Array[Dictionary] item by item
		var loaded_items: Array = data.inventory
		for item in loaded_items:
			inventory.append(item as Dictionary)

# MISSING HELPERS - Implement or stub
func _generate_item_id() -> String:
	return str(randi())

func _generate_item_name(rarity: String, slot: String, depth: int) -> String:
	return rarity.capitalize() + " " + slot.capitalize()

func _roll_stats(rarity: String, slot: String) -> Dictionary:
	return {"attack": 10.0, "hp": 50.0, "defense": 5.0}

func _roll_sub_stats(rarity: String) -> Dictionary:
	return {}

func _roll_set_id() -> String:
	return ""

func _get_special_for_slot(slot: String) -> String:
	return ""

func _calculate_roll_quality(stats: Dictionary) -> float:
	return 1.0

func _is_set_equipped(set_id: String) -> bool:
	return false

func _apply_set_bonuses(stats: Dictionary) -> void:
	pass

func _calculate_level_cost(item: Dictionary, levels: int) -> int:
	return item.level * 100 * levels

# Ring/Amulet/Talisman helpers
func has_ring_ability() -> bool:
	return equipped.ring1 != null or equipped.ring2 != null

func has_amulet_charge() -> bool:
	return equipped.amulet != null

func get_amulet_special_name() -> String:
	return "Special Attack"

func use_talisman() -> void:
	pass
