extends Control
class_name PanelStyleClone

# If you set this, it will use it. If you leave it empty, it will auto-find.
@export var reference_control_path: NodePath

# If auto-find is used, it will look for this node name anywhere in the scene.
@export var reference_node_name: String = "UpgradesPanel"

@export var style_key: String = "panel" # Panel/PanelContainer usually use "panel"

func _ready() -> void:
	var ref: Control = null

	# 1) Prefer explicit path
	if reference_control_path != NodePath("") and reference_control_path != null:
		ref = get_node_or_null(reference_control_path) as Control

	# 2) Fallback: auto-find by name
	if ref == null and reference_node_name.strip_edges() != "":
		ref = get_tree().current_scene.find_child(reference_node_name, true, false) as Control

	# 3) If still not found, do nothing (no spam errors)
	if ref == null:
		push_warning("PanelStyleClone: couldn't find reference. Set reference_control_path or reference_node_name.")
		return

	var sb := ref.get_theme_stylebox(style_key)
	if sb:
		add_theme_stylebox_override(style_key, sb)
