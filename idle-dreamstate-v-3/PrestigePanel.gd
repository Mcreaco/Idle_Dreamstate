# PrestigePanel.gd
extends PanelContainer
class_name PrestigePanel

signal confirm_wake
signal cancel

@export var debug_print: bool = false

# Panel styling
@export var panel_bg: Color = Color(0.04, 0.07, 0.12, 0.92)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 1.0)
@export var panel_border_width: int = 2
@export var panel_radius: int = 12

# Close these overlays when prestige opens (prevents overlap)
@export var settings_panel_node_name: String = "SettingsPanel"
@export var shop_panel_node_name: String = "ShopPanel"

# IMPORTANT:
# - On PC, ads are hidden by default.
# - Turn this ON in the inspector to test the Ad button on PC.
@export var show_ads_on_pc_for_testing: bool = false

# Your tree (note: Vbox casing)
@onready var title: Label = $"Vbox/Title"
@onready var summary: Label = $"Vbox/Summary"
@onready var keep_label: Label = $"Vbox/Details/You Keep"
@onready var reset_label: Label = $"Vbox/Details/You Reset"
@onready var cancel_btn: Button = $"Vbox/Buttons/CancelButton"
@onready var confirm_btn: Button = $"Vbox/Buttons/ConfirmWakeButton"
@onready var ad_btn: Button = $"Vbox/Buttons/AdWakeButton"

# Uses existing Backdrop node in your scene (transparent input blocker)
@onready var backdrop: ColorRect = get_node_or_null("Backdrop") as ColorRect

var _pending_gain: float = 0.0
var _pending_depth_gain: float = 0.0
var _pending_depth_index: int = 1
var _pending_preview: Dictionary = {} # stores DepthRunController.preview_wake(...)

# Ad bonus for this wake (e.g. 1.0 means +100% extra memories)
var _ad_bonus: float = 0.0
var _ad_used: bool = false

var _ad_service: Node = null

func _process(_delta: float) -> void:
	if not visible:
		return
	_refresh_live_preview()

func _ready() -> void:
	_apply_panel_frame()
	visible = false
	z_index = 220
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true) # <-- add this
	set_process_unhandled_input(true)

	_setup_backdrop()

	_apply_action_button_style(confirm_btn)
	_apply_action_button_style(cancel_btn)
	_apply_action_button_style(ad_btn)

	if confirm_btn != null and not confirm_btn.pressed.is_connected(Callable(self, "_on_confirm")):
		confirm_btn.pressed.connect(Callable(self, "_on_confirm"))

	if cancel_btn != null and not cancel_btn.pressed.is_connected(Callable(self, "_on_cancel")):
		cancel_btn.pressed.connect(Callable(self, "_on_cancel"))

	if ad_btn != null and not ad_btn.pressed.is_connected(Callable(self, "_on_ad_pressed")):
		ad_btn.pressed.connect(Callable(self, "_on_ad_pressed"))

	# Autoload detection (THIS is the correct way)
	_ad_service = get_node_or_null("/root/AdService")

	# Listen for rewarded ad completion
	if _ad_service != null and _ad_service.has_signal("reward_wake_bonus"):
		if not _ad_service.reward_wake_bonus.is_connected(Callable(self, "_on_ad_reward_wake_bonus")):
			_ad_service.reward_wake_bonus.connect(Callable(self, "_on_ad_reward_wake_bonus"))

	_update_ad_button_visibility()
	_update_ad_button_state()

func open_with_depth(mem: float, crystals_dict: Dictionary, wake_depth: int) -> void:
	"""
	Opens the prestige panel with wake rewards
	
	Args:
		mem: Total memories to be gained
		crystals_dict: Dictionary of currency_name -> amount (e.g., {"Amethyst": 45.0, "Ruby": 23.0})
		wake_depth: The depth being woken from
	"""
	visible = true
	
	# Display memories
	if has_node("MemoriesLabel"):
		var mem_label = get_node("MemoriesLabel")
		mem_label.text = "Memories: +%.1f" % mem
	
	# Display all depth currencies
	# Option A: Dynamic container approach
	var currency_container = get_node_or_null("CurrencyContainer")
	if currency_container:
		# Clear old currency labels
		for child in currency_container.get_children():
			child.queue_free()
		
		# Sort currencies by depth order (1->15)
		var sorted_currencies := []
		for i in range(1, 16):
			var currency_name = DepthMetaSystem.get_depth_currency_name(i)
			if crystals_dict.has(currency_name):
				var amount = crystals_dict[currency_name]
				if amount > 0.0:
					sorted_currencies.append({"name": currency_name, "amount": amount, "depth": i})
		
		# Create labels for each currency
		for entry in sorted_currencies:
			var label = Label.new()
			label.text = "%s: +%.1f" % [entry.name, entry.amount]
			label.add_theme_font_size_override("font_size", 14)
			currency_container.add_child(label)
		
		# If no currencies, show a message
		if sorted_currencies.is_empty():
			var label = Label.new()
			label.text = "No depth currencies earned"
			label.modulate = Color(0.7, 0.7, 0.7)
			currency_container.add_child(label)
	
	# Option B: Pre-made labels approach (if you have Depth1Label, Depth2Label, etc.)
	# Uncomment this section if you use pre-made labels instead of a dynamic container
	"""
	for i in range(1, 16):
		var label_name = "Depth%dLabel" % i
		if has_node(label_name):
			var label = get_node(label_name)
			var currency_name = DepthMetaSystem.get_depth_currency_name(i)
			var amount = crystals_dict.get(currency_name, 0.0)
			
			if amount > 0.0:
				label.text = "%s: +%.1f" % [currency_name, amount]
				label.visible = true
			else:
				label.visible = false
	"""
	
	# Display wake depth info
	if has_node("WakeDepthLabel"):
		var depth_label = get_node("WakeDepthLabel")
		depth_label.text = "Waking from %s" % DepthMetaSystem.get_depth_name(wake_depth)

func close() -> void:
	visible = false
	if backdrop != null:
		backdrop.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()

func _on_confirm() -> void:
	if _pending_gain <= 0.0:
		return

	close()
	confirm_wake.emit()

	# Apply extra ad memories after wake completes (so we don't refactor GameManager yet)
	if _ad_bonus > 0.0:
		call_deferred("_apply_post_wake_ad_bonus")

func _apply_post_wake_ad_bonus() -> void:
	var gm := get_tree().current_scene.find_child("GameManager", true, false)
	if gm == null:
		return

	var extra := maxf(_pending_gain * _ad_bonus, 0.0)

	# Godot 4 safe property access (no has_variable)
	var mem_var: Variant = gm.get("memories")
	if mem_var != null:
		gm.set("memories", float(mem_var) + extra)

	if gm.has_method("save_game"):
		gm.call("save_game")


func _on_cancel() -> void:
	close()
	cancel.emit()

func _on_ad_pressed() -> void:
	if _ad_used:
		return
	if not _ads_supported():
		return
	if _ad_service == null:
		_ad_service = get_node_or_null("/root/AdService")
	if _ad_service == null:
		return

	# Ask AdService to show a rewarded ad (mock succeeds instantly right now)
	if _ad_service.has_method("show_rewarded"):
		_ad_service.call("show_rewarded", _ad_service.AD_WAKE_BONUS)

func _on_ad_reward_wake_bonus(multiplier: float) -> void:
	if _ad_used:
		return

	_ad_used = true
	_ad_bonus = maxf(multiplier, 0.0)

	_update_summary_text()
	_update_confirm_button()
	_update_ad_button_state()

func _update_summary_text() -> void:
	var lines: Array[String] = []
	lines.append("If you wake now:")

	# NEW path: show full preview (memories + thoughts + all gems)
	if _pending_preview.size() > 0:
		var mem := float(_pending_preview.get("memories", 0.0))
		var th := float(_pending_preview.get("thoughts", 0.0))
		var gems: Dictionary = _pending_preview.get("crystals_by_name", {})

		# Apply ad bonus ONLY to memories (your current design)
		if _ad_bonus > 0.0:
			mem = mem * (1.0 + _ad_bonus)
			lines.append("• +" + str(int(round(mem))) + " Memories (Ad)")
		else:
			lines.append("• +" + str(int(round(mem))) + " Memories")

		# Thoughts (optional display — remove if you don’t want it shown)
		if th > 0.0:
			lines.append("• +" + str(int(round(th))) + " Thoughts")

		# All depth currencies (sorted for stable UI)
		var names := gems.keys()
		names.sort()
		for gem_name in names:
			var amt := float(gems[gem_name])
			if amt > 0.0:
				lines.append("• +" + str(int(round(amt))) + " " + str(gem_name))


		if summary != null:
			summary.text = "\n".join(lines)
		return

	# FALLBACK (old single-depth display)
	var depth_name := DepthMetaSystem.get_depth_currency_name(_pending_depth_index)
	var mem_line := "• +" + str(int(round(_pending_gain))) + " Memories"
	if _ad_bonus > 0.0:
		var boosted := _pending_gain * (1.0 + _ad_bonus)
		mem_line = "• +" + str(int(round(boosted))) + " Memories (Ad)"

	if summary != null:
		summary.text = "If you wake now:\n" + \
			mem_line + "\n" + \
			"• +" + str(int(round(_pending_depth_gain))) + " " + depth_name


func _update_confirm_button() -> void:
	if confirm_btn == null:
		return

	var mem := _pending_gain
	if _pending_preview.size() > 0:
		mem = float(_pending_preview.get("memories", 0.0))

	if mem <= 0.0:
		confirm_btn.text = "Not worth waking yet"
		confirm_btn.disabled = true
		return

	if _ad_bonus > 0.0:
		mem = mem * (1.0 + _ad_bonus)

	confirm_btn.text = "Wake (+" + str(int(round(mem))) + ")"
	confirm_btn.disabled = false


func _update_ad_button_visibility() -> void:
	if ad_btn == null:
		return
	ad_btn.visible = _ads_supported()

func _update_ad_button_state() -> void:
	if ad_btn == null:
		return

	_update_ad_button_visibility()
	if not ad_btn.visible:
		return

	if _ad_used:
		ad_btn.text = "Ad used"
		ad_btn.disabled = true
		return

	var can := true
	_ad_service = get_node_or_null("/root/AdService")
	if _ad_service != null and _ad_service.has_method("can_show"):
		can = bool(_ad_service.call("can_show", _ad_service.AD_WAKE_BONUS))

	ad_btn.disabled = not can
	ad_btn.text = "Watch Ad (+100% Memories)" if can else "Ad unavailable"

func _ads_supported() -> bool:
	if show_ads_on_pc_for_testing:
		return true
	var os := OS.get_name()
	return os == "Android" or os == "iOS"

func _apply_panel_frame() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = panel_bg
	sb.border_color = panel_border
	sb.border_width_left = panel_border_width
	sb.border_width_top = panel_border_width
	sb.border_width_right = panel_border_width
	sb.border_width_bottom = panel_border_width
	sb.corner_radius_top_left = panel_radius
	sb.corner_radius_top_right = panel_radius
	sb.corner_radius_bottom_left = panel_radius
	sb.corner_radius_bottom_right = panel_radius
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 16
	sb.content_margin_bottom = 16
	add_theme_stylebox_override("panel", sb)

func _setup_backdrop() -> void:
	if backdrop == null:
		return
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.offset_left = 0
	backdrop.offset_top = 0
	backdrop.offset_right = 0
	backdrop.offset_bottom = 0
	backdrop.color = Color(0, 0, 0, 0.0) # transparent input blocker
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.visible = false
	if not backdrop.gui_input.is_connected(Callable(self, "_on_backdrop_input")):
		backdrop.gui_input.connect(Callable(self, "_on_backdrop_input"))

func _on_backdrop_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			close()
			get_viewport().set_input_as_handled()

func _apply_action_button_style(b: Button) -> void:
	if b == null:
		return
	var normal := _mk_btn(Color(0.08, 0.10, 0.16, 0.95), Color(0.24, 0.67, 0.94, 1.0))
	var hover := _mk_btn(Color(0.10, 0.12, 0.19, 0.98), Color(0.34, 0.77, 1.00, 1.0))
	var pressed := _mk_btn(Color(0.06, 0.08, 0.12, 0.95), Color(0.20, 0.60, 0.90, 1.0))
	var disabled := _mk_btn(Color(0.08, 0.10, 0.16, 0.45), Color(0.24, 0.67, 0.94, 0.35))
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("disabled", disabled)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	b.add_theme_color_override("font_disabled_color", Color(0.70, 0.74, 0.80, 1.0))

func _mk_btn(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

func _force_close_overlay(node_name: String) -> void:
	if node_name.strip_edges() == "":
		return
	var n := get_tree().current_scene.find_child(node_name, true, false)
	if n == null:
		return
	if n.has_method("close"):
		n.call("close")
	elif n is CanvasItem:
		(n as CanvasItem).visible = false

func _refresh_live_preview() -> void:
	var drc := get_node_or_null("/root/DepthRunController")
	if drc == null:
		return

	var d := int(drc.get("active_depth"))
	_pending_depth_index = d

	# Prefer the NEW preview dict (all currencies)
	if drc.has_method("preview_wake"):
		_pending_preview = drc.call("preview_wake", 1.0, false)
	else:
		_pending_preview = {}

	# Backwards-compatible fallback (old single-depth preview)
	var mem_gain := 0.0
	var cry_gain := 0.0
	if drc.has_method("_calc_memories_gain"):
		mem_gain = float(drc.call("_calc_memories_gain"))
	if drc.has_method("_calc_crystals_gain"):
		cry_gain = float(drc.call("_calc_crystals_gain"))

	_pending_gain = maxf(mem_gain, 0.0)
	_pending_depth_gain = maxf(cry_gain, 0.0)

	_update_summary_text()
	_update_confirm_button()
	_update_ad_button_state()
