extends HBoxContainer
class_name AbyssPerkRow

@export var mode: String = "echoed_descent"
@export var refresh_interval: float = 0.25

# Bar fills based on perk level (visual cap)
@export var level_display_cap: int = 10

var _gm: GameManager
var _abyss: AbyssPerkSystem

var _button: Button
var _mini: Label
var _bar: ProgressBar

var _t: float = 0.0


func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_abyss = get_tree().current_scene.find_child("AbyssPerkSystem", true, false) as AbyssPerkSystem

	_button = _find_first_button(self)
	_mini = find_child("Mini", true, false) as Label
	_bar = find_child("Bar", true, false) as ProgressBar

	if _button != null and not _button.pressed.is_connected(Callable(self, "_on_pressed")):
		_button.pressed.connect(Callable(self, "_on_pressed"))

	set_process(true)
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()


func _refresh() -> void:
	if _gm == null or _abyss == null or _button == null:
		return

	# Don’t show anything if Abyss not unlocked yet (keeps mystery)
	if not _gm.abyss_unlocked_flag:
		visible = false
		return
	visible = true

	var lvl: int = _get_level()
	var max_lvl: int = _get_max_level()
	var cost: float = _get_cost()

	_button.text = "%s (Lv %d) - %d" % [_get_title(), lvl, int(round(cost))]
	_button.disabled = (_gm.memories < cost) or (lvl >= max_lvl)

	if _mini != null:
		_mini.text = _get_mini_text()

	if _bar != null:
		var cap: int = maxi(level_display_cap, 1)
		_bar.min_value = 0.0
		_bar.max_value = float(cap)
		_bar.value = float(clampi(lvl, 0, cap))
		_bar.show_percentage = false


func _on_pressed() -> void:
	if _gm == null or _abyss == null:
		return

	var res: Dictionary
	match mode.to_lower():
		"echoed_descent":
			res = _abyss.try_buy_echoed_descent(_gm.memories)
		"abyssal_focus":
			res = _abyss.try_buy_abyssal_focus(_gm.memories)
		"dark_insight":
			res = _abyss.try_buy_dark_insight(_gm.memories)
		"abyss_veil":
			res = _abyss.try_buy_abyss_veil(_gm.memories)
		_:
			return

	if bool(res.get("bought", false)):
		_gm.memories -= float(res.get("cost", 0.0))
		_gm.save_game()

	_refresh()


func _get_title() -> String:
	match mode.to_lower():
		"echoed_descent": return "Echoed Descent"
		"abyssal_focus": return "Abyssal Focus"
		"dark_insight": return "Dark Insight"
		"abyss_veil": return "Veil of the Abyss"
	return "Abyss Perk"


func _get_mini_text() -> String:
	match mode.to_lower():
		"echoed_descent":
			return "Start runs deeper. (Abyss clear still requires starting at 0.)"
		"abyssal_focus":
			return "Permanent Control gain boost."
		"dark_insight":
			return "Permanent Thoughts gain boost."
		"abyss_veil":
			return "Instability grows slower at high depth."
	return ""


func _get_level() -> int:
	match mode.to_lower():
		"echoed_descent": return _abyss.echoed_descent_level
		"abyssal_focus": return _abyss.abyssal_focus_level
		"dark_insight": return _abyss.dark_insight_level
		"abyss_veil": return _abyss.abyss_veil_level
	return 0


func _get_max_level() -> int:
	match mode.to_lower():
		"echoed_descent": return _abyss.echoed_descent_max
		"abyssal_focus": return _abyss.abyssal_focus_max
		"dark_insight": return _abyss.dark_insight_max
		"abyss_veil": return _abyss.abyss_veil_max
	return 0


func _get_cost() -> float:
	match mode.to_lower():
		"echoed_descent": return _abyss.get_echoed_descent_cost()
		"abyssal_focus": return _abyss.get_abyssal_focus_cost()
		"dark_insight": return _abyss.get_dark_insight_cost()
		"abyss_veil": return _abyss.get_abyss_veil_cost()
	return 999999.0


func _find_first_button(n: Node) -> Button:
	if n is Button:
		return n as Button
	for c in n.get_children():
		var b := _find_first_button(c)
		if b != null:
			return b
	return null
