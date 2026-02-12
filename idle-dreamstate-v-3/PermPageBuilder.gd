extends Control
class_name PermPageBuilder

@export var row_scene: PackedScene
@onready var vbox: VBoxContainer = $PermScroll/PermVBox

func _ready() -> void:
	if row_scene == null:
		push_error("PermPageBuilder: row_scene not assigned.")
		return
	call_deferred("_build")

func _build() -> void:
	# clear old rows (hard clear avoids overlap / ghost input in weird cases)
	for c in vbox.get_children():
		c.free()

	var perk_ids := [
		"memory_engine",
		"calm_mind",
		"focused_will",
		"starting_insight",
		"stability_buffer",
		"offline_echo",
		"recursive_memory",
		"lucid_dreaming",
		"deep_sleeper",
		"night_owl",
		"dream_catcher",
		"subconscious_miner",
		"void_walker",
		"rapid_eye",
		"sleep_paralysis",
		"oneiromancy",
	]

	for id in perk_ids:
		var row = row_scene.instantiate()
		row.perk_id = id
		vbox.add_child(row)
