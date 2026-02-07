extends Button

@export var settings_panel_name: String = "SettingsPanel"
@export var shop_panel_name: String = "ShopPanel"

func _ready() -> void:
	# Use gui_input so Button internals still run
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

		# --- CLOSE PANELS FIRST (prevents underlap/overlap issues) ---
		_close_panel_by_name(settings_panel_name)
		_close_panel_by_name(shop_panel_name)

		# --- Then do wake ---
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

func _close_panel_by_name(panel_name: String) -> void:
	if panel_name.strip_edges() == "":
		return

	var p := get_tree().current_scene.find_child(panel_name, true, false) as Control
	if p == null:
		return

	# Prefer a close() method if your panel has one
	if p.has_method("close"):
		p.call("close")
	else:
		p.visible = false
