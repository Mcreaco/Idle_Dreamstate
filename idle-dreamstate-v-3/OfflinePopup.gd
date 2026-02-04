extends CanvasLayer
class_name OfflinePopup

@export var show_seconds: float = 4.0

var panel: Panel = null
var label: Label = null

func _ready() -> void:
	# Find any Panel under this node
	panel = find_child("Panel", true, false) as Panel

	# Find a Label named TextLabel anywhere under this node
	label = find_child("TextLabel", true, false) as Label

	if panel == null:
		push_error("OfflinePopup: Could not find a Panel node named 'Panel' under OfflinePopup.")
		return

	# Hide by default
	panel.visible = false
	panel.modulate = Color(1, 1, 1, 1)

	if label == null:
		push_error("OfflinePopup: Could not find a Label node named 'TextLabel' under OfflinePopup. Popup will not show text.")
		return


func show_popup(text: String) -> void:
	if panel == null or label == null:
		# Fail safely instead of crashing.
		push_error("OfflinePopup: show_popup called but Panel/TextLabel is missing.")
		return

	label.text = text
	panel.visible = true
	panel.modulate = Color(1, 1, 1, 1)

	await get_tree().create_timer(show_seconds).timeout

	# In case the node got freed or hidden during scene changes
	if is_instance_valid(panel):
		panel.visible = false
