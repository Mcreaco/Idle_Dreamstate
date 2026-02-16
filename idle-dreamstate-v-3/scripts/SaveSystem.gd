extends Node

const SAVE_PATH: String = "user://savegame.json"

func save_game(data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

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
		return parsed as Dictionary
	
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
