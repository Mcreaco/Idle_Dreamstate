extends Node
class_name DiveCooldownDebug

@export var game_manager_node_name: String = "GameManager"

var _gm: Node = null
var _t: float = 0.0

func _ready() -> void:
	var scene := get_tree().current_scene
	_gm = scene.find_child(game_manager_node_name, true, false)
	if _gm == null:
		push_error("DiveCooldownDebug: Could not find GameManager named '%s'." % game_manager_node_name)
	set_process(true)

func _process(delta: float) -> void:
	if _gm == null:
		return

	_t += delta
	if _t >= 1.0:
		_t = 0.0
		var cd := float(_gm.get("dive_cooldown"))
		var timer := float(_gm.get("dive_cooldown_timer"))
		print("DiveCooldownDebug | dive_cooldown=", cd, "  timer=", timer)
