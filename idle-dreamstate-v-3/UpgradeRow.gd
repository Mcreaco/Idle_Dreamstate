extends HBoxContainer
class_name UpgradeRow

@export var mode: String = "thoughts"
@export var refresh_interval: float = 0.25
@export var debug_print: bool = false

# "level" = bar shows THIS upgrade's level (simple cap)
# "cost"  = bar shows affordability toward next cost
# "tier"  = bar shows tier progress (1-10, 11-25, 26-50, 51-100) and resets each tier
@export var bar_mode: String = "tier"

# If bar_mode == "level", this level fills the bar to 100%
@export var level_display_cap: int = 10

var _gm: GameManager
var _up: UpgradeManager
var _button: Button
var _mini: Label
var _bar: Range
var _t: float = 0.0

func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_up = get_tree().current_scene.find_child("UpgradeManager", true, false) as UpgradeManager
	_button = _find_first_button(self)
	_mini = find_child("Mini", true, false) as Label
	_bar = find_child("Bar", true, false) as Range
	
	if _button != null:
		var cb := Callable(self, "_on_pressed")
		if not _button.pressed.is_connected(cb):
			_button.pressed.connect(cb)
		_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button.size_flags_stretch_ratio = 1
		_button.custom_minimum_size.x = 0

	if _bar != null:
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar.size_flags_stretch_ratio = 1
		_bar.custom_minimum_size.x = 0

	add_theme_constant_override("separation", 12)

	if _button != null:
		var cb := Callable(self, "_on_pressed")
		if not _button.pressed.is_connected(cb):
			_button.pressed.connect(cb)
	
	if _button != null:
		var cb := Callable(self, "_on_pressed")
		if not _button.pressed.is_connected(cb):
			_button.pressed.connect(cb)
		_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button.size_flags_stretch_ratio = 3  # ~60%
		_button.custom_minimum_size.x = 0
		_button.add_theme_constant_override("content_margin_left", 8)
		_button.add_theme_constant_override("content_margin_right", 8)
		_button.add_theme_constant_override("h_separation", 4)
		_button.clip_text = false
		_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS  # only trims if it truly can’t fit

	if _bar != null:
		_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_bar.size_flags_stretch_ratio = 2  # ~40%
		_bar.custom_minimum_size.x = 0

	add_theme_constant_override("separation", 12)

	set_process(true)
	_refresh()

	if debug_print:
		print("[UpgradeRow] ready mode=", mode, " btn=", _button, " gm=", _gm, " up=", _up)

func _process(delta: float) -> void:
	_t += delta
	if _t >= refresh_interval:
		_t = 0.0
		_refresh()

func _on_pressed() -> void:
	if _gm == null:
		push_error("[UpgradeRow] GameManager not found (node named GameManager must have GameManager.gd attached).")
		return

	match mode.to_lower():
		"thoughts":
			_gm.do_buy_thoughts_upgrade()
		"stability":
			_gm.do_buy_stability_upgrade()
		"deepdives":
			_gm.do_buy_deep_dives_upgrade()
		"mentalbuffer":
			_gm.do_buy_mental_buffer_upgrade()
		"overclockmastery":
			_gm.do_buy_overclock_mastery_upgrade()
		"overclocksafety":
			_gm.do_buy_overclock_safety_upgrade()
		_:
			push_error("[UpgradeRow] Unknown mode: %s" % mode)

	_refresh()

func _refresh() -> void:
	if _gm == null or _up == null or _button == null:
		return

	var lvl: int = _get_level()
	var cost: float = _get_cost()

	_button.text = "%s (Lv %d) - %d" % [_get_title(), lvl, int(round(cost))]
	_button.disabled = (_gm.thoughts < cost)

	if _mini != null:
		_mini.text = "" # keep row clean

	if _bar != null:
		var bm: String = bar_mode.to_lower()

		if bm == "tier":
			# Show progress within current tier range (resets at 10, 25, 50, 100)
			var info := _tier_info(lvl)
			var start: int = int(info["start"])
			var end: int = int(info["end"])

			var tier_len: int = max(end - start + 1, 1)
			var tier_pos: int = 0
			if lvl <= 0:
				tier_pos = 0
			else:
				tier_pos = clamp(lvl - start + 1, 0, tier_len)

			var pct: float = (float(tier_pos) / float(tier_len)) * 100.0

			_bar.min_value = 0.0
			_bar.max_value = 100.0
			_bar.value = clampf(pct, 0.0, 100.0)

			# Optional: show tier indicator in Mini label without clutter
			# (comment out if you don't want it)
			if _mini != null:
				_mini.text = ""


		elif bm == "level":
			var cap: int = maxi(level_display_cap, 1)
			_bar.min_value = 0.0
			_bar.max_value = float(cap)
			_bar.value = float(clampi(lvl, 0, cap))

		elif bm == "cost":
			_bar.min_value = 0.0
			_bar.max_value = maxf(cost, 1.0)
			_bar.value = clampf(_gm.thoughts, 0.0, _bar.max_value)

		else:
			# fallback to level
			var cap2: int = maxi(level_display_cap, 1)
			_bar.min_value = 0.0
			_bar.max_value = float(cap2)
			_bar.value = float(clampi(lvl, 0, cap2))
		
		var tooltip := ""
		tooltip += "%s\n" % _get_title()
		tooltip += "Level: %d\n" % lvl
		tooltip += "Cost: %d Thoughts\n" % int(round(cost))
		tooltip += "\n%s\n" % _get_mini_text()

		# Optional: include tier info if you’re using tier bars
		if bar_mode.to_lower() == "tier":
			var info := _tier_info(lvl)
			tooltip += "\nTier %d/4  (%d–%d)\n" % [int(info["tier"]), int(info["start"]), int(info["end"])]
			tooltip += "Milestones: 10 / 25 / 50 / 100"

		_button.tooltip_text = tooltip


func _tier_info(level: int) -> Dictionary:
	# Tier ranges:
	# 1: 1-10
	# 2: 11-25
	# 3: 26-50
	# 4: 51-100
	# If level==0 (never bought), treat as tier 1 with 0% progress.
	if level <= 10:
		return {"tier": 1, "start": 1, "end": 10}
	elif level <= 25:
		return {"tier": 2, "start": 11, "end": 25}
	elif level <= 50:
		return {"tier": 3, "start": 26, "end": 50}
	else:
		return {"tier": 4, "start": 51, "end": 100}

func _get_title() -> String:
	match mode.to_lower():
		"thoughts": return "Thoughts Up"
		"stability": return "Stability Up"
		"deepdives": return "Deep Dives"
		"mentalbuffer": return "Mental Buffer"
		"overclockmastery": return "Overclock Mastery"
		"overclocksafety": return "Overclock Safety"
	return "Upgrade"

func _get_level() -> int:
	match mode.to_lower():
		"thoughts": return _up.thoughts_level
		"stability": return _up.stability_level
		"deepdives": return _up.deep_dives_level
		"mentalbuffer": return _up.mental_buffer_level
		"overclockmastery": return _up.overclock_mastery_level
		"overclocksafety": return _up.overclock_safety_level
	return 0

func _get_cost() -> float:
	match mode.to_lower():
		"thoughts": return _up.get_thoughts_cost()
		"stability": return _up.get_stability_cost()
		"deepdives": return _up.get_deep_dives_cost()
		"mentalbuffer": return _up.get_mental_buffer_cost()
		"overclockmastery": return _up.get_overclock_mastery_cost()
		"overclocksafety":
			return _up.get_overclocksafety_cost() if _up.has_method("get_overclocksafety_cost") else _up.get_overclock_safety_cost()
	return 999999.0

func _get_mini_text() -> String:
	match mode.to_lower():
		"deepdives": return "Depth scales harder (reward + risk)."
		"mentalbuffer": return "Dive grants extra Control based on Depth."
		"overclockmastery": return "+Power +Duration, but higher Control cost."
		"overclocksafety": return "Lower Overclock Instability, slightly lower Overclock Thoughts."
		"thoughts": return "More Thoughts gain."
		"stability": return "Less Instability gain."
	return ""

func _find_first_button(n: Node) -> Button:
	if n is Button:
		return n as Button
	for c: Node in n.get_children():
		var b := _find_first_button(c)
		if b != null:
			return b
	return null
