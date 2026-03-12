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
		
func save_game(data: Dictionary) -> bool:
	var json_str = JSON.stringify(data)
	if json_str == null or json_str.is_empty() or json_str == "{}":
		print("CRITICAL: JSON serialization failed or empty!")
		return false
	
	# ATOMIC SAVE: Write to temp first
	var temp_path = SAVE_PATH + ".tmp"
	var bak_path = SAVE_PATH + ".bak"
	
	var file: FileAccess = FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		print("CRITICAL: Failed to open temp save file!")
		return false
		
	file.store_string(json_str)
	file.close()
	
	# Rotate backups: existing save becomes .bak
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(bak_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(bak_path))
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(bak_path))
	
	# Move temp to final
	var err = DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		print("CRITICAL: Failed to finalize atomic save! Error: ", err)
		return false

	print("SAVE SUCCESS: %d bytes written via atomic swap to %s" % [json_str.length(), SAVE_PATH])
	return true

# Removed gather_save_data and save_all as they were bypasses 
# that didn't include all necessary game state (like equipment).
# Always use GameManager.save_game().

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
	if data.has("dreamcloud") and not data.has("dream_cloud"):
		data["dream_cloud"] = data["dreamcloud"]
		data.erase("dreamcloud")
	
	# Initialize empty equipment if missing
	if not data.has("equipment"):
		data["equipment"] = {
			"equipped": {},
			"inventory": []
		}
	
	return data
