extends Node

func _ready() -> void:
	set_process_input(true)
	print("ButtonStyleDebugger READY")

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if not mb.pressed:
			return

		var hovered: Control = get_viewport().gui_get_hovered_control()
		if hovered == null:
			print("CLICK: hovered NONE")
			return

		print("CLICK: hovered=", hovered.name, " path=", str(hovered.get_path()), " class=", hovered.get_class())

		if hovered is Button:
			var b: Button = hovered as Button

			print("  text=", b.text)
			print("  disabled=", b.disabled, " visible=", b.visible)
			print("  modulate=", b.modulate, " self_modulate=", b.self_modulate)

			var c_normal: Color = b.get_theme_color("font_color", "Button")
			var c_disabled: Color = b.get_theme_color("font_disabled_color", "Button")
			print("  theme font_color=", c_normal, " theme font_disabled_color=", c_disabled)

			var f = b.get_theme_font("font", "Button")
			print("  theme font=", ("OK" if f != null else "NULL"))

			var fs: int = b.get_theme_font_size("font_size", "Button")
			print("  theme font_size=", fs)

			var sb_normal = b.get_theme_stylebox("normal", "Button")
			var sb_disabled = b.get_theme_stylebox("disabled", "Button")
			print("  stylebox normal=", sb_normal)
			print("  stylebox disabled=", sb_disabled)

			if sb_normal != null:
				print("  normal margins LRTB=",
					sb_normal.get_content_margin(SIDE_LEFT), ",",
					sb_normal.get_content_margin(SIDE_RIGHT), ",",
					sb_normal.get_content_margin(SIDE_TOP), ",",
					sb_normal.get_content_margin(SIDE_BOTTOM))

			if sb_disabled != null:
				print("  disabled margins LRTB=",
					sb_disabled.get_content_margin(SIDE_LEFT), ",",
					sb_disabled.get_content_margin(SIDE_RIGHT), ",",
					sb_disabled.get_content_margin(SIDE_TOP), ",",
					sb_disabled.get_content_margin(SIDE_BOTTOM))
