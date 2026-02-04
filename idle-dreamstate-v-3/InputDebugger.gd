extends Node

func _ready() -> void:
	set_process_input(true)
	print("InputDebugger READY")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return

		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered == null:
			print("CLICK hovered=NONE")
			return

		print("CLICK hovered=", hovered.name, " path=", str(hovered.get_path()), " class=", hovered.get_class())

		if hovered is Button:
			var b: Button = hovered as Button
			print("  text=", b.text)
			print("  disabled=", b.disabled, " visible=", b.visible)
			print("  modulate=", b.modulate, " self_modulate=", b.self_modulate)

			# Effective theme colors used for text
			var c_normal: Color = b.get_theme_color("font_color", "Button")
			var c_disabled: Color = b.get_theme_color("font_disabled_color", "Button")
			print("  theme font_color=", c_normal, " font_disabled_color=", c_disabled)

			# Font + size (theme)
			var f = b.get_theme_font("font", "Button")
			if f == null:
				print("  theme font=NULL")
			else:
				print("  theme font=OK")

			var fs: int = b.get_theme_font_size("font_size", "Button")
			print("  theme font_size=", fs)
