extends CanvasLayer
class_name AbyssUnlockFX

@export var flash_path: NodePath
@export var flash_in: float = 0.10
@export var flash_hold: float = 0.10
@export var flash_out: float = 0.45
@export var max_alpha: float = 0.65

# If you later add a sound method like SoundSystem.play_abyss_unlock()
@export var play_sound: bool = false

var _gm: GameManager
var _flash: ColorRect
var _tw: Tween
var _done_once: bool = false


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_flash = get_node_or_null(flash_path) as ColorRect

	if _flash != null:
		_flash.visible = true
		_flash.modulate.a = 0.0

	if _gm != null and not _gm.abyss_unlocked.is_connected(Callable(self, "_on_abyss_unlocked")):
		_gm.abyss_unlocked.connect(Callable(self, "_on_abyss_unlocked"))

	# If loading a save where abyss already unlocked, do nothing (keep mystery)


func _on_abyss_unlocked() -> void:
	if _done_once:
		return
	_done_once = true

	# optional sound hook
	if play_sound and _gm != null and _gm.sound_system != null:
		if _gm.sound_system.has_method("play_abyss_unlock"):
			_gm.sound_system.call("play_abyss_unlock")

	_flash_pulse()


func _flash_pulse() -> void:
	if _flash == null:
		return

	if _tw != null:
		_tw.kill()

	_tw = create_tween()
	_tw.set_trans(Tween.TRANS_SINE)
	_tw.set_ease(Tween.EASE_OUT)

	_flash.modulate.a = 0.0
	_tw.tween_property(_flash, "modulate:a", max_alpha, flash_in)
	_tw.tween_interval(flash_hold)
	_tw.tween_property(_flash, "modulate:a", 0.0, flash_out)
