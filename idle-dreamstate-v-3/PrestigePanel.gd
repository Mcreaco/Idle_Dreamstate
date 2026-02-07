extends PanelContainer
class_name PrestigePanel

signal confirm_wake
signal cancel

@export var debug_print: bool = false

# Blue frame styling (match Settings/Shop)
@export var panel_bg: Color = Color(0.06, 0.08, 0.12, 0.70)
@export var panel_border: Color = Color(0.24, 0.67, 0.94, 0.95)
@export var panel_border_width: int = 2
@export var panel_radius: int = 10

# Close these overlays when prestige opens (prevents overlap)
@export var settings_panel_node_name: String = "SettingsPanel"
@export var shop_panel_node_name: String = "ShopPanel"

# Your tree uses "Vbox" (NOT VBox)
@onready var vbox: Node = $"Vbox"

@onready var title: Label = $"Vbox/Title"
@onready var summary: Label = $"Vbox/Summary"
@onready var keep_label: Label = $"Vbox/Details/You Keep"
@onready var reset_label: Label = $"Vbox/Details/You Reset"
@onready var cancel_btn: Button = $"Vbox/Buttons/CancelButton"
@onready var confirm_btn: Button = $"Vbox/Buttons/ConfirmWakeButton"

var _pending_gain: float = 0.0
var _backdrop: ColorRect = null

func _ready() -> void:
	_apply_panel_frame()
	_setup_backdrop()

	# Connect buttons safely
	if confirm_btn != null and not confirm_btn.pressed.is_connected(_on_confirm):
		confirm_btn.pressed.connect(_on_confirm)
	if cancel_btn != null and not cancel_btn.pressed.is_connected(_on_cancel):
		cancel_btn.pressed.connect(_on_cancel)

	visible = false
	if _backdrop: _backdrop.visible = false

	if debug_print:
		print("PrestigePanel ready. vbox=", vbox, " title=", title, " summary=", summary)

# -------------------------------------------------
# OPEN / CLOSE
# -------------------------------------------------
func open_with_depth(memories_gain: float, depth_gain: float, depth_index: int) -> void:
	# Close other overlays so they can't overlap
	_force_close_overlay(settings_panel_node_name)
	_force_close_overlay(shop_panel_node_name)

	_apply_panel_frame()

	_pending_gain = maxf(memories_gain, 0.0)

	if title != null:
		title.text = "Wake / Prestige"

	var depth_name := DepthMetaSystem.get_depth_currency_name(depth_index)

	if summary != null:
		summary.text = "If you wake now:\n" + \
			"• +" + str(int(round(_pending_gain))) + " Memories\n" + \
			"• +" + str(int(round(maxf(depth_gain, 0.0)))) + " " + depth_name

	if keep_label != null:
		keep_label.text = "You KEEP:\n" + \
			"• Memories\n" + \
			"• Perks (permanent upgrades)\n" + \
			"• Unlocks & difficulty\n" + \
			"• Settings"

	if reset_label != null:
		reset_label.text = "You RESET:\n" + \
			"• Thoughts, Control, Instability\n" + \
			"• Run time & stats\n" + \
			"• Run upgrades\n" + \
			"• Overclock state & cooldowns"

	if confirm_btn != null:
		if _pending_gain <= 0.0:
			confirm_btn.text = "Not worth waking yet"
			confirm_btn.disabled = true
		else:
			confirm_btn.text = "Wake (+" + str(int(round(_pending_gain))) + ")"
			confirm_btn.disabled = false

	if cancel_btn != null:
		cancel_btn.text = "Cancel"

	visible = true
	z_index = 210
	mouse_filter = Control.MOUSE_FILTER_STOP

	if _backdrop:
		_backdrop.visible = true
		_backdrop.z_index = 209

func close() -> void:
	visible = false
	if _backdrop:
		_backdrop.visible = false

# -------------------------------------------------
# BUTTONS
# -------------------------------------------------
func _on_confirm() -> void:
	if _pending_gain <= 0.0:
		return
	confirm_wake.emit()

func _on_cancel() -> void:
	cancel.emit()
	close()

# -------------------------------------------------
# PANEL FRAME (blue border)
# -------------------------------------------------
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

	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14

	add_theme_stylebox_override("panel", sb)

# -------------------------------------------------
# MODAL BACKDROP (click outside closes + blocks input)
# -------------------------------------------------
func _setup_backdrop() -> void:
	# If you didn't add a Backdrop node in the editor, we create it here.
	_backdrop = get_node_or_null("Backdrop") as ColorRect
	if _backdrop == null:
		_backdrop = ColorRect.new()
		_backdrop.name = "Backdrop"
		add_child(_backdrop)
		# Make sure backdrop is behind the panel contents
		move_child(_backdrop, 0)

	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.color = Color(0, 0, 0, 0.35)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.visible = false

	if not _backdrop.gui_input.is_connected(_on_backdrop_input):
		_backdrop.gui_input.connect(_on_backdrop_input)

func _on_backdrop_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		close()

# -------------------------------------------------
# Close other overlays (rename param to avoid shadowing Node.name)
# -------------------------------------------------
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
