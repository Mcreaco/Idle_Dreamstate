extends Node
class_name AutomationUIBinder

# ---- Set these to match your scene node names ----
@export var automation_system_node_name: String = "AutomationSystem"

@export var auto_dive_toggle_name: String = "AutoDiveToggle"
@export var auto_wake_toggle_name: String = "AutoWakeToggle"

# Optional sliders (if you have them). Leave blank if not used.
@export var dive_slider_name: String = "DiveSlider"
@export var wake_slider_name: String = "WakeSlider"

# Slider ranges (set to match your sliders)
@export var slider_min: float = 0.0
@export var slider_max: float = 100.0

var _auto_sys: Node = null
var _dive_toggle: CheckButton = null
var _wake_toggle: CheckButton = null
var _dive_slider: Range = null
var _wake_slider: Range = null

func _ready() -> void:
	var scene := get_tree().current_scene
	_auto_sys = scene.find_child(automation_system_node_name, true, false)
	if _auto_sys == null:
		push_error("AutomationUIBinder: Could not find AutomationSystem named '%s'." % automation_system_node_name)

	_dive_toggle = scene.find_child(auto_dive_toggle_name, true, false) as CheckButton
	_wake_toggle = scene.find_child(auto_wake_toggle_name, true, false) as CheckButton

	if dive_slider_name != "":
		_dive_slider = scene.find_child(dive_slider_name, true, false) as Range
	if wake_slider_name != "":
		_wake_slider = scene.find_child(wake_slider_name, true, false) as Range

	set_process(true)

func _process(_delta: float) -> void:
	if _auto_sys == null:
		return

	# ---- Auto Dive toggle ----
	if _dive_toggle != null:
		_auto_sys.auto_dive = _dive_toggle.button_pressed

	# ---- Auto Wake toggle ----
	if _wake_toggle != null:
		_auto_sys.auto_wake = _wake_toggle.button_pressed

	# ---- Dive strength from slider (0..1) ----
	if _dive_slider != null:
		var v01 := _norm01(_dive_slider.value)
		if _auto_sys.has_method("set_dive_strength"):
			_auto_sys.call("set_dive_strength", v01)
		else:
			_auto_sys.dive_strength = v01

	# ---- Wake strength from slider (0..1) ----
	if _wake_slider != null:
		var v01 := _norm01(_wake_slider.value)
		if _auto_sys.has_method("set_wake_strength"):
			_auto_sys.call("set_wake_strength", v01)
		else:
			_auto_sys.wake_strength = v01

func _norm01(v: float) -> float:
	if slider_max <= slider_min:
		return 1.0
	return clampf((v - slider_min) / (slider_max - slider_min), 0.0, 1.0)
