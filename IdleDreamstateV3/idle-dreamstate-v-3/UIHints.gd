extends Node
class_name UIHints

@export var automation_system_node_name: String = "AutomationSystem"

@export var dive_slider_name: String = "DiveSlider"
@export var wake_slider_name: String = "WakeSlider"
@export var overclock_slider_name: String = "OverclockSlider"

@export var debug_print: bool = true

var _automation: AutomationSystem = null
var _dive_slider: HSlider = null
var _wake_slider: HSlider = null
var _overclock_slider: HSlider = null


func _ready() -> void:
	_automation = _find_automation_system()
	if _automation == null:
		push_error("UIHints: Could not find AutomationSystem in current scene.")
		return

	var scene := get_tree().current_scene
	_dive_slider = scene.find_child(dive_slider_name, true, false) as HSlider
	_wake_slider = scene.find_child(wake_slider_name, true, false) as HSlider
	_overclock_slider = scene.find_child(overclock_slider_name, true, false) as HSlider

	_wire_slider(_dive_slider, Callable(self, "_on_dive_changed"))
	_wire_slider(_wake_slider, Callable(self, "_on_wake_changed"))
	_wire_slider(_overclock_slider, Callable(self, "_on_overclock_changed"))

	# Apply once so system matches current UI
	if _dive_slider != null: _on_dive_changed(_dive_slider.value)
	if _wake_slider != null: _on_wake_changed(_wake_slider.value)
	if _overclock_slider != null: _on_overclock_changed(_overclock_slider.value)

	if debug_print:
		print("UIHints OK | AutomationSystem=", _automation.name,
			" dive=", _automation.dive_strength,
			" wake=", _automation.wake_strength,
			" overclock=", _automation.overclock_strength)


func _find_automation_system() -> AutomationSystem:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	return scene.find_child(automation_system_node_name, true, false) as AutomationSystem


func _wire_slider(slider: HSlider, cb: Callable) -> void:
	if slider == null:
		return
	if not slider.value_changed.is_connected(cb):
		slider.value_changed.connect(cb)


func _to_01(slider: HSlider, v: float) -> float:
	var minv := float(slider.min_value)
	var maxv := float(slider.max_value)
	if maxv <= minv:
		return 0.0
	return clampf((v - minv) / (maxv - minv), 0.0, 1.0)


func _on_dive_changed(v: float) -> void:
	if _dive_slider == null or _automation == null:
		return
	_automation.set_dive_strength(_to_01(_dive_slider, v))
	if debug_print:
		print("DiveSlider -> dive_strength=", _automation.dive_strength)


func _on_wake_changed(v: float) -> void:
	if _wake_slider == null or _automation == null:
		return
	_automation.set_wake_strength(_to_01(_wake_slider, v))
	if debug_print:
		print("WakeSlider -> wake_strength=", _automation.wake_strength)


func _on_overclock_changed(v: float) -> void:
	if _overclock_slider == null or _automation == null:
		return
	_automation.set_overclock_strength(_to_01(_overclock_slider, v))
	if debug_print:
		print("OverclockSlider -> overclock_strength=", _automation.overclock_strength)
