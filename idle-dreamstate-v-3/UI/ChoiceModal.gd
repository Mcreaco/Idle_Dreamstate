extends PanelContainer
class_name ChoiceModal

signal choice_made(choice_id: String, effects: Dictionary)

@export var title_font_size: int = 22
@export var desc_font_size: int = 16
@export var button_font_size: int = 18

var _gm: GameManager
var _drc: Node
var _pending_effects: Dictionary = {}

func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_drc = get_node_or_null("/root/DepthRunController")
	visible = false
	z_index = 300
	mouse_filter = Control.MOUSE_FILTER_STOP

func show_event(event_data: Dictionary, depth_def: Dictionary) -> void:
	"""Show a choice event from _depth_defs"""
	visible = true
	
	# Pause the run
	if _drc != null:
		_drc.set_process(false)
	
	# Build UI
	for child in get_children():
		child.queue_free()
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = depth_def.get("new_title", "Event")
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Description
	var desc := Label.new()
	desc.text = event_data.get("warning", "Choose carefully...")
	desc.add_theme_font_size_override("font_size", desc_font_size)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(400, 0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)
	
	# Separator
	vbox.add_child(HSeparator.new())
	
	# Choice buttons
	var choices: Array = event_data.get("choices", [])
	for choice in choices:
		var btn := Button.new()
		btn.text = choice.get("text", "???")
		btn.add_theme_font_size_override("font_size", button_font_size)
		btn.custom_minimum_size = Vector2(0, 50)
		
		var effects: Dictionary = choice.get("effect", {})
		var id: String = choice.get("id", "unknown")
		
		btn.pressed.connect(func(): _on_choice_selected(id, effects))
		
		# Style based on risk
		if _is_risky_choice(effects):
			_style_risk_button(btn)
		else:
			_style_safe_button(btn)
			
		vbox.add_child(btn)
	
	# Center on screen
	set_anchors_preset(Control.PRESET_CENTER)
	_fade_in()

func _on_choice_selected(id: String, effects: Dictionary) -> void:
	_pending_effects = effects
	
	# Apply immediate effects
	if effects.has("instability_bonus"):
		var amt := float(effects["instability_bonus"]) * 100.0
		if _gm != null:
			_gm.instability = clampf(_gm.instability + amt, 0.0, 100.0)
	
	if effects.has("cost_control"):
		var cost := float(effects["cost_control"])
		if _gm != null:
			_gm.control = maxf(0.0, _gm.control - cost)
	
	if effects.has("cost_thoughts"):
		var cost := float(effects["cost_thoughts"])
		if _gm != null:
			_gm.thoughts = maxf(0.0, _gm.thoughts - cost)
	
	# Duration effects (handled by DepthRunController)
	choice_made.emit(id, effects)
	
	# Resume
	visible = false
	if _drc != null:
		_drc.set_process(true)

func _is_risky_choice(effects: Dictionary) -> bool:
	if effects.has("instability_bonus") and float(effects["instability_bonus"]) > 0.1:
		return true
	if effects.has("cost_control") or effects.has("cost_thoughts"):
		return true
	return false

func _style_safe_button(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.25, 0.4, 0.9)
	sb.border_color = Color(0.3, 0.7, 0.9, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", sb)

func _style_risk_button(btn: Button) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.3, 0.1, 0.1, 0.9)
	sb.border_color = Color(0.9, 0.3, 0.3, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", sb)

func _fade_in() -> void:
	modulate = Color(1, 1, 1, 0)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color(1, 1, 1, 1), 0.2)
