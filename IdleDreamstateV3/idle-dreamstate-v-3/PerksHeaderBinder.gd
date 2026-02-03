extends Node
class_name PerksHeaderBinder

@export var title_path: NodePath
@export var subtitle_path: NodePath

@export var debug_print: bool = false

var _title: CanvasItem = null
var _subtitle: CanvasItem = null
var _warned: bool = false

func _ready() -> void:
	_title = _resolve_canvas_item(title_path, "Title")
	_subtitle = _resolve_canvas_item(subtitle_path, "Subtitle")

func _resolve_canvas_item(path: NodePath, fallback_name: String) -> CanvasItem:
	var n: Node = null

	# 1) Use assigned path if valid
	if path != NodePath():
		n = get_node_or_null(path)

	# 2) Fallback: find by common names to avoid breaking when UI structure changes
	if n == null:
		n = find_child(fallback_name, true, false)

	if n == null and not _warned:
		_warned = true
		push_warning("%s: %s node NOT FOUND (set %s_path in Inspector or rename node)."
			% [name, fallback_name, fallback_name.to_lower()])
	return n as CanvasItem

# Example API you might already be calling:
func set_title(text: String) -> void:
	if _title != null and _title.has_method("set_text"):
		_title.call("set_text", text)
	elif _title is Label:
		(_title as Label).text = text
	elif debug_print:
		print("PerksHeaderBinder: title missing; cannot set title")

func set_subtitle(text: String) -> void:
	if _subtitle != null and _subtitle.has_method("set_text"):
		_subtitle.call("set_text", text)
	elif _subtitle is Label:
		(_subtitle as Label).text = text
	elif debug_print:
		print("PerksHeaderBinder: subtitle missing; cannot set subtitle")
