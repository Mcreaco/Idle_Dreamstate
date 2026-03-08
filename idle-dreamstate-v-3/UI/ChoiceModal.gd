extends PanelContainer
class_name ChoiceModal

signal choice_made(choice_id: String, effects: Dictionary)

@export var title_font_size: int = 22
@export var desc_font_size: int = 16
@export var button_font_size: int = 18

var _gm: GameManager
var _drc: Node
var _pending_effects: Dictionary = {}

func show_choice(title_text: String, choices_array: Array) -> void:
	visible = true
	
	# Clear existing
	for child in get_children():
		child.queue_free()
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	add_child(vbox)
	
	# Title
	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", title_font_size)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	vbox.add_child(HSeparator.new())
	
	# Choice buttons
	for choice in choices_array:
		var btn := Button.new()
		btn.text = choice.get("text", "???")
		btn.custom_minimum_size = Vector2(300, 60)
		
		var choice_id = choice.get("id", "")
		var effects = choice.get("effect", {})
		
		btn.pressed.connect(func(): 
			choice_made.emit(choice_id, effects)
			visible = false
		)
		
		_style_button(btn, choice_id == "overclock")  # true if risky
		vbox.add_child(btn)
	
	# Center it
	set_anchors_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(500, 300)

func _style_button(btn: Button, is_risky: bool) -> void:
	var sb := StyleBoxFlat.new()
	if is_risky:
		sb.bg_color = Color(0.3, 0.1, 0.1, 0.9)
		sb.border_color = Color(0.9, 0.3, 0.3, 1.0)
	else:
		sb.bg_color = Color(0.1, 0.25, 0.4, 0.9)
		sb.border_color = Color(0.3, 0.7, 0.9, 1.0)
	
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	btn.add_theme_stylebox_override("normal", sb)
	
func _ready() -> void:
	_gm = get_tree().current_scene.find_child("GameManager", true, false) as GameManager
	_drc = get_node_or_null("/root/DepthRunController")
	visible = false
	
	# CRITICAL: Make sure it's on top of everything including depth bars
	z_index = 400  # Higher than depth bars (usually 100-300)
	z_as_relative = false  # Use absolute z-index
	
	# Stop mouse events from passing through
	mouse_filter = Control.MOUSE_FILTER_STOP
	
	# Instead, set anchor to center
	set_anchors_preset(Control.PRESET_CENTER)

# Modify show_event signature to accept risk_assessment_unlocked
func show_event(event_data: Dictionary, depth_def: Dictionary, risk_assessment_unlocked: bool = false) -> void:
	# Remove the full_rect anchor preset - it's conflicting!
	# Keep only the z-index and mouse filter settings from _ready
	
	visible = true
	
	# Pause the run
	if _drc != null:
		_drc.set_meta("progress_paused", true)
	
	# Clear existing children
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
	
	# Description with risk assessment hint
	var desc := Label.new()
	if risk_assessment_unlocked:
		desc.text = "Reality fractures. One path is revealed to you..."
	else:
		desc.text = event_data.get("warning", "Choose carefully...")
	desc.add_theme_font_size_override("font_size", desc_font_size)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	desc.custom_minimum_size = Vector2(400, 0)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)
	
	vbox.add_child(HSeparator.new())
	
	# Choice buttons
	var choices: Array = event_data.get("choices", [])
	
	# Risk Assessment logic: pick one random outcome to reveal if upgrade owned
	var revealed_index = -1
	if risk_assessment_unlocked and choices.size() > 0:
		revealed_index = randi() % choices.size()
	
	for i in range(choices.size()):
		var choice = choices[i]
		var btn := Button.new()
		var is_revealed = (i == revealed_index)
		
		# Build button text
		var btn_text = choice.get("text", "???")
		if is_revealed:
			var eff = choice.get("effect", {})
			var details = []
			if eff.has("progress_bonus"):
				details.append("Progress %+d%%" % int(eff.progress_bonus * 100))
			if eff.has("instability_bonus"):
				details.append("Instability %+d%%" % int(eff.instability_bonus * 100))
			if eff.has("mem_mul"):
				details.append("Memories x%.1f for %ds" % [eff.mem_mul, eff.get("duration", 0)])
			if details.size() > 0:
				btn_text += "\n[ " + " | ".join(details) + " ]"
			btn.add_theme_color_override("font_color", Color(0.8, 1.0, 0.8))  # Green tint for revealed
		
		btn.text = btn_text
		btn.add_theme_font_size_override("font_size", button_font_size)
		btn.custom_minimum_size = Vector2(0, 60)
		
		var effects: Dictionary = choice.get("effect", {})
		var id: String = choice.get("id", "unknown")
		
		btn.pressed.connect(func(): _on_choice_selected(id, effects))
		
		if _is_risky_choice(effects):
			_style_risk_button(btn)
		else:
			_style_safe_button(btn)
			
		vbox.add_child(btn)
	
	# CRITICAL FIX: Center properly
	set_anchors_preset(Control.PRESET_CENTER)
	set_size(Vector2(500, 300))  # Force size first
	custom_minimum_size = Vector2(500, 300)
	
	# Center on screen
	if get_viewport_rect().size.x > 0:
		position = (get_viewport_rect().size - custom_minimum_size) / 2
	
	visible = true
	_fade_in()

func _on_choice_selected(id: String, effects: Dictionary) -> void:
	_pending_effects = effects
	
	if effects.has("cost_dreamcloud"):
		var cost := float(effects["cost_dreamcloud"])
		if _gm != null:
			_gm.dreamcloud = maxf(0.0, _gm.dreamcloud - cost)
	
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
	if effects.has("cost_dreamcloud") or effects.has("cost_thoughts"):
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
