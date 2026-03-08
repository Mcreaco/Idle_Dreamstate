extends Node

const SAVE_PATH: String = "user://savegame.json"
const MAX_SLOTS = 3

func save_to_slot(slot: int, data: Dictionary) -> void:
	if slot < 1 or slot > MAX_SLOTS:
		return
	var path = "user://save_slot_%d.json" % slot
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()

func load_from_slot(slot: int) -> Dictionary:
	var path = "user://save_slot_%d.json" % slot
	if not FileAccess.file_exists(path):
		return {}
	var file = FileAccess.open(path, FileAccess.READ)
	if file:
		var text = file.get_as_text()
		file.close()
		var parsed = JSON.parse_string(text)
		if parsed is Dictionary:
			return parsed
	return {}

func has_slot(slot: int) -> bool:
	return FileAccess.file_exists("user://save_slot_%d.json" % slot)

func get_slot_preview(slot: int) -> Dictionary:
	var data = load_from_slot(slot)
	if data.is_empty():
		return {"empty": true}
	return {
		"empty": false,
		"depth": data.get("depth", 1),
		"thoughts": data.get("thoughts", 0),
		"time_played": data.get("time_in_run", 0)
	}

func _debug_check_save_file():
	var file_path = "user://savegame.json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var text = file.get_as_text()
		file.close()
		
		# Check if it contains meta data
		if text.find("depth_currency_") != -1:
			print("SAVE FILE CONTAINS META CURRENCY DATA")
		else:
			print("WARNING: Save file missing meta currency data!")
			
		if text.find("depth_1_upg") != -1:
			print("SAVE FILE CONTAINS UPGRADE DATA")
		else:
			print("WARNING: Save file missing upgrade data!")
	else:
		print("No save file found")
		
func save_game(data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

# ADD THIS: Helper to collect all game state
func gather_save_data() -> Dictionary:
	var data := {}
	
	# GameManager data
	var gm = get_node_or_null("/root/Main/GameManager")
	if gm:
		data["thoughts"] = gm.thoughts
		data["dreamcloud"] = gm.dreamcloud
		data["gems"] = gm.gems if "gems" in gm else 0
		data["memories"] = gm.memories if "memories" in gm else 0
		# ... other GM data
	
	# DepthRunController data - THIS IS THE KEY
	var drc = get_node_or_null("/root/DepthRunController")
	if drc:
		data["depth_run_controller"] = {
			"active_depth": int(drc.active_depth),
			"max_unlocked_depth": int(drc.max_unlocked_depth),
			"run": drc._run_internal.duplicate(true),
			"local_upgrades": drc.local_upgrades.duplicate(true),
			"frozen_upgrades": drc.frozen_upgrades.duplicate(true),
			"thoughts": drc.thoughts,
			"dreamcloud": drc.dreamcloud,
			"instability": drc.instability
		}
	
	data["last_play_time"] = Time.get_unix_time_from_system()
	return data

# Convenience method to save everything
func save_all() -> void:
	save_game(gather_save_data())

func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var text: String = file.get_as_text()
	file.close()
	
	if text.is_empty():
		return {}
	
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) == TYPE_DICTIONARY:
		var data = parsed as Dictionary
		# Ensure new keys exist with defaults
		if not data.has("dream_current"):
			data["dream_current"] = 1.0
		return data
	
	# If parsing failed or returned wrong type, delete corrupted save
	delete_save()
	return {}

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))

# ---- Lifetime stat helpers ----
func add_stat(key: String, delta: float) -> void:
	var data: Dictionary = load_game()
	data[key] = float(data.get(key, 0.0)) + delta
	save_game(data)

func add_stat_int(key: String, delta: int) -> void:
	var data: Dictionary = load_game()
	data[key] = int(data.get(key, 0)) + delta
	save_game(data)

func set_max_stat(key: String, value: int) -> void:
	var data: Dictionary = load_game()
	var cur := int(data.get(key, 0))
	if value > cur:
		data[key] = value
		save_game(data)

var owned_items: Array[String] = []
var active_boost: Dictionary = {"mult": 1.0, "expires": 0}

func _save_shop_data() -> void:
	var data: Dictionary = SaveSystem.load_game()
	data["shop_owned_items"] = owned_items
	data["shop_active_boost"] = active_boost
	SaveSystem.save_game(data)

func _load_shop_data() -> void:
	var data: Dictionary = SaveSystem.load_game()
	owned_items = data.get("shop_owned_items", [])
	active_boost = data.get("shop_active_boost", {"mult": 1.0, "expires": 0})

func migrate_old_save(data: Dictionary) -> Dictionary:
	# Convert old dreamcloud to Dream Cloud (at 1:1 rate)
	if data.has("dreamcloud") and not data.has("dreamcloud"):
		data["dreamcloud"] = data["dreamcloud"]
		data.erase("dreamcloud")
	
	# Initialize empty equipment if missing
	if not data.has("equipment"):
		data["equipment"] = {
			"equipped": {},
			"inventory": []
		}
	
	return data
