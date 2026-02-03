extends Button

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if not gui_input.is_connected(Callable(self, "_on_gui_input")):
		gui_input.connect(Callable(self, "_on_gui_input"))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			return

		var meta := get_tree().current_scene.find_child("MetaPanel", true, false)
		if meta == null:
			push_error("PerksButton: MetaPanel not found.")
			return

		# if MetaPanelController is attached, use it
		if meta.has_method("toggle_open"):
			meta.call("toggle_open")
		elif meta is CanvasItem:
			(meta as CanvasItem).visible = not (meta as CanvasItem).visible
