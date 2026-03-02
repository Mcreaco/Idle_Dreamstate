extends PanelContainer

signal slot_selected(slot: int, is_save: bool)

@onready var slot_container: VBoxContainer = $MarginContainer/VBox/SlotContainer
@onready var title_label: Label = $MarginContainer/VBox/TitleLabel

var is_save_mode: bool = true

func _ready() -> void:
	visible = false
	_refresh_slots()

func show_panel(save_mode: bool) -> void:
	is_save_mode = save_mode
	title_label.text = "Save Game" if save_mode else "Load Game"
	visible = true
	_refresh_slots()

func _refresh_slots() -> void:
	# Clear existing
	for child in slot_container.get_children():
		child.queue_free()
	
	for i in range(1, 4):  # Slots 1-3
		var btn = Button.new()
		var has_data = SaveSystem.has_slot(i)
		var preview = SaveSystem.get_slot_preview(i)
		
		if preview.empty:
			btn.text = "Slot %d\n[Empty]" % i
		else:
			btn.text = "Slot %d\nDepth: %d | %s" % [i, preview.depth, _fmt_time(preview.time_played)]
		
		btn.custom_minimum_size = Vector2(300, 60)
		_apply_button_style(btn)
		
		if is_save_mode:
			btn.pressed.connect(_on_save_slot.bind(i))
		else:
			btn.disabled = preview.empty
			btn.pressed.connect(_on_load_slot.bind(i))
		
		slot_container.add_child(btn)
	
	# Cancel button
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(300, 40)
	cancel_btn.pressed.connect(_on_cancel)
	slot_container.add_child(cancel_btn)

func _on_save_slot(slot: int) -> void:
	var data = SaveSystem.load_game()
	SaveSystem.save_to_slot(slot, data)
	slot_selected.emit(slot, true)
	visible = false

func _on_load_slot(slot: int) -> void:
	if not SaveSystem.has_slot(slot):
		return
	var data = SaveSystem.load_from_slot(slot)
	SaveSystem.save_game(data)
	slot_selected.emit(slot, false)
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_cancel() -> void:
	visible = false

func _apply_button_style(btn: Button) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.95)
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", sb)

func _fmt_time(seconds: float) -> String:
	if seconds < 60:
		return "%ds" % int(seconds)
	elif seconds < 3600:
		return "%dm" % (int(seconds) / 60.0)
	else:
		return "%dh" % (int(seconds) / 3600.0)
