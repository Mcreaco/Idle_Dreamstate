extends Button

func _ready() -> void:
	# Use gui_input signal so Button internals still run
	if not gui_input.is_connected(Callable(self, "_on_gui_input")):
		gui_input.connect(Callable(self, "_on_gui_input"))

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index != MOUSE_BUTTON_LEFT:
			return

		# fire on mouse release
		if e.pressed:
			return

		var gm := get_tree().current_scene.find_child("GameManager", true, false)
		if gm == null:
			push_error("WakeButton: GameManager not found.")
			return

		if gm.has_method("_on_wake_pressed"):
			gm.call("_on_wake_pressed")
			return

		if gm.has_method("do_wake"):
			gm.call("do_wake")
			return

		push_error("WakeButton: GameManager missing _on_wake_pressed/do_wake.")
