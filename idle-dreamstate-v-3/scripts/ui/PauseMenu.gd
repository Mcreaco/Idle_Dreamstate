extends CanvasLayer

@onready var center: Control = $CenterContainer
@onready var panel: Control = $CenterContainer/Panel

var is_open: bool = false
var save_panel: Control = null

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	
	# Style the main panel
	_apply_panel_style(panel)
	
	var vbox = panel.find_child("VBox", true, false)
	if vbox:
		vbox.add_theme_constant_override("separation", 12)
		# Remove any remaining blank buttons
		_remove_blank_buttons(vbox)
	
	# CRITICAL: Style Resume with delay to override any editor theme
	var resume_btn = vbox.find_child("ResumeButton", false, false) as Button
	if resume_btn:
		resume_btn.text = "Resume"
		# Clear any existing theme resource
		resume_btn.theme = null
		# Force style immediately and after a frame
		_force_button_style(resume_btn)
		if not resume_btn.pressed.is_connected(_on_resume):
			resume_btn.pressed.connect(_on_resume)
		# Double-check styling after frame render
		call_deferred("_force_button_style", resume_btn)
	
	var quit_btn = vbox.find_child("QuitButton", false, false) as Button
	if quit_btn:
		quit_btn.text = "Quit"
		quit_btn.theme = null
		_force_button_style(quit_btn)
		if not quit_btn.pressed.is_connected(_on_quit):
			quit_btn.pressed.connect(_on_quit)
	
	# Add Save/Load between Resume and Quit
	_add_save_load_buttons(vbox)
	
	# Start hidden
	center.visible = false
	call_deferred("_create_save_panel")

func _remove_blank_buttons(vbox: VBoxContainer):
	"""Remove any buttons with no text or no name"""
	for child in vbox.get_children():
		if child is Button and child.name != "ResumeButton" and child.name != "QuitButton":
			if child.text == "" or child.name == "":
				child.queue_free()

func _add_save_load_buttons(vbox: VBoxContainer):
	# Remove any existing Save/Load first to prevent duplicates
	for child in vbox.get_children():
		if child.name in ["SaveButton", "LoadButton"]:
			child.queue_free()
	
	var resume_btn = vbox.find_child("ResumeButton", false, false)
	var insert_index = 1
	if resume_btn:
		insert_index = resume_btn.get_index() + 1
	
	# Save Button
	var save_btn = Button.new()
	save_btn.name = "SaveButton"
	save_btn.text = "Save Game"
	save_btn.custom_minimum_size = Vector2(200, 50)
	_force_button_style(save_btn)
	save_btn.pressed.connect(_show_save_panel.bind(true))
	vbox.add_child(save_btn)
	vbox.move_child(save_btn, insert_index)
	
	# Load Button
	var load_btn = Button.new()
	load_btn.name = "LoadButton"
	load_btn.text = "Load Game"
	load_btn.custom_minimum_size = Vector2(200, 50)
	_force_button_style(load_btn)
	load_btn.pressed.connect(_show_save_panel.bind(false))
	vbox.add_child(load_btn)
	vbox.move_child(load_btn, insert_index + 1)

func _create_save_panel():
	save_panel = PanelContainer.new()
	save_panel.name = "SaveLoadPanel"
	save_panel.visible = false
	save_panel.z_index = 200
	save_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_panel_style(save_panel)
	save_panel.custom_minimum_size = Vector2(350, 400)
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	save_panel.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)
	
	var title = Label.new()
	title.name = "TitleLabel"
	title.text = "Save Game"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	vbox.add_child(title)
	
	var slots = VBoxContainer.new()
	slots.name = "Slots"
	slots.add_theme_constant_override("separation", 8)
	vbox.add_child(slots)
	
	get_tree().current_scene.add_child(save_panel)
	save_panel.set_meta("title", title)
	save_panel.set_meta("slots", slots)

func _show_save_panel(is_save: bool):
	print("Opening panel, is_save: ", is_save)
	
	if not save_panel:
		return
	
	# Get references
	var title = save_panel.get_meta("title")
	var slots = save_panel.get_meta("slots")
	
	# Set mode using meta (create if doesn't exist)
	save_panel.set_meta("is_save_mode", is_save)
	
	title.text = "Save Game" if is_save else "Load Game"
	
	# Always show panel when called
	save_panel.visible = true
	
	# Clear existing slots
	while slots.get_child_count() > 0:
		var child = slots.get_child(0)
		slots.remove_child(child)
		child.queue_free()
	
	# Create slots
	for i in range(1, 4):
		var btn = Button.new()
		var has_data = SaveSystem.has_slot(i)
		
		if has_data:
			var preview = SaveSystem.get_slot_preview(i)
			var depth = preview.get("depth", 1) if preview is Dictionary else 1
			btn.text = "Slot %d - Depth %d" % [i, depth]
		else:
			btn.text = "Slot %d [Empty]" % i
		
		btn.custom_minimum_size = Vector2(300, 60)
		_force_button_style(btn)
		
		# Connect based on mode
		if is_save:
			btn.pressed.connect(_on_save_slot_pressed.bind(i))
		else:
			if has_data:
				btn.pressed.connect(_on_load_slot_pressed.bind(i))
			else:
				btn.disabled = true
		
		slots.add_child(btn)
	
	# Cancel button
	var cancel = Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(300, 50)
	cancel.pressed.connect(_on_cancel_pressed)
	_force_button_style(cancel)
	slots.add_child(cancel)

func _on_save_slot_pressed(slot: int):
	print("DEBUG: _on_save_slot_pressed called with slot: ", slot)  # Add this
	var gm = get_tree().get_first_node_in_group("game_manager")
	print("DEBUG: GameManager found: ", gm != null)  # Add this
	if gm and gm.has_method("get_save_data"):
		var data = gm.get_save_data()
		print("DEBUG: Save data retrieved, calling SaveSystem")  # Add this
		SaveSystem.save_to_slot(slot, data)
		print("Saved to slot %d!" % slot)
	else:
		push_error("GameManager not found or missing get_save_data method")
	save_panel.visible = false

func _on_load_slot_pressed(slot: int):
	print("LOADING FROM SLOT ", slot)
	var data = SaveSystem.load_from_slot(slot)
	
	if data.is_empty():
		push_error("No data in slot %d" % slot)
		return
	
	print("Data loaded, keys: ", data.keys())
	
	# Try multiple ways to find GameManager
	var gm = null
	
	# Method 1: By group
	var managers = get_tree().get_nodes_in_group("game_manager")
	if managers.size() > 0:
		gm = managers[0]
		print("Found GameManager via group")
	
	# Method 2: By path
	if gm == null:
		gm = get_node_or_null("/root/Main/GameManager")
		if gm:
			print("Found GameManager via path")
	
	# Method 3: Current scene
	if gm == null:
		var current = get_tree().current_scene
		if current:
			gm = current.find_child("GameManager", true, false)
			if gm:
				print("Found GameManager via current_scene")
	
	if gm == null:
		push_error("GameManager not found!")
		return
	
	print("GameManager found, checking for load_game_data...")
	
	# Check for method
	if gm.has_method("load_game_data"):
		print("Calling load_game_data...")
		gm.load_game_data(data)
		print("Loaded successfully!")
	elif gm.has_method("load_game"):
		print("Calling load_game (alternative)...")
		gm.load_game()
	else:
		push_error("GameManager missing load_game_data method! Available methods: ", gm.get_method_list())
		return
	
	save_panel.visible = false
	get_tree().paused = false

func _on_cancel_pressed():
	if save_panel:
		save_panel.visible = false
		
func _force_button_style(btn: Button):
	# CRITICAL: Clear theme resource if any
	btn.theme = null
	
	# Remove all existing style overrides
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		btn.remove_theme_stylebox_override(state)
		btn.remove_theme_color_override("font_color")
		btn.remove_theme_color_override("font_hover_color")
		btn.remove_theme_color_override("font_pressed_color")
		btn.remove_theme_color_override("font_disabled_color")
	
	# Apply fresh style
	var normal = StyleBoxFlat.new()
	normal.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	normal.border_color = Color(0.24, 0.67, 0.94, 1.0)
	normal.border_width_left = 2
	normal.border_width_top = 2
	normal.border_width_right = 2
	normal.border_width_bottom = 2
	normal.corner_radius_top_left = 10
	normal.corner_radius_top_right = 10
	normal.corner_radius_bottom_left = 10
	normal.corner_radius_bottom_right = 10
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 10
	normal.content_margin_bottom = 10
	btn.add_theme_stylebox_override("normal", normal)
	
	var hover = normal.duplicate()
	hover.bg_color = Color(0.15, 0.18, 0.25, 0.98)
	hover.border_color = Color(0.40, 0.80, 1.00, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	
	var pressed = normal.duplicate()
	pressed.bg_color = Color(0.05, 0.07, 0.10, 0.95)
	btn.add_theme_stylebox_override("pressed", pressed)
	
	btn.add_theme_color_override("font_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 1.0, 1.0, 1.0))
	btn.add_theme_color_override("font_pressed_color", Color(0.92, 0.96, 1.0, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.50, 0.55, 0.60, 0.80))

func _apply_panel_style(p: Control):
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.95)
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	sb.corner_radius_bottom_left = 12
	sb.corner_radius_bottom_right = 12
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	p.add_theme_stylebox_override("panel", sb)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if save_panel and save_panel.visible:
			save_panel.visible = false
			return
		toggle_pause()
		get_viewport().set_input_as_handled()

func toggle_pause():
	is_open = !is_open
	center.visible = is_open
	get_tree().paused = is_open
	if is_open:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_resume():
	toggle_pause()

func _on_quit():
	get_tree().quit()
