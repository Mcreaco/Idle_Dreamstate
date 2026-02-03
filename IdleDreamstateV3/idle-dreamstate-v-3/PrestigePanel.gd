extends PanelContainer
class_name PrestigePanel

signal confirm_wake
signal cancel

@export var debug_print: bool = false

var _title: Label
var _summary: Label
var _keep_label: Label
var _reset_label: Label
var _confirm_btn: Button
var _cancel_btn: Button

var _pending_gain: float = 0.0

func _ready() -> void:
	_title = find_child("Title", true, false) as Label
	_summary = find_child("Summary", true, false) as Label
	_keep_label = find_child("You Keep", true, false) as Label
	_reset_label = find_child("You Reset", true, false) as Label
	_confirm_btn = find_child("ConfirmWakeButton", true, false) as Button
	_cancel_btn = find_child("CancelButton", true, false) as Button

	if _confirm_btn != null:
		if _confirm_btn.pressed.is_connected(Callable(self, "_on_confirm")):
			_confirm_btn.pressed.disconnect(Callable(self, "_on_confirm"))
		_confirm_btn.pressed.connect(Callable(self, "_on_confirm"))

	if _cancel_btn != null:
		if _cancel_btn.pressed.is_connected(Callable(self, "_on_cancel")):
			_cancel_btn.pressed.disconnect(Callable(self, "_on_cancel"))
		_cancel_btn.pressed.connect(Callable(self, "_on_cancel"))

	if _cancel_btn != null and _cancel_btn.text.strip_edges() == "":
		_cancel_btn.text = "Cancel"

	visible = false

	if debug_print:
		print("PrestigePanel ready:",
			"title=", _title,
			" summary=", _summary,
			" keep=", _keep_label,
			" reset=", _reset_label,
			" confirm=", _confirm_btn,
			" cancel=", _cancel_btn
		)

func open_with_depth(memories_gain: float, depth_gain: float, depth_index: int) -> void:
	_pending_gain = maxf(memories_gain, 0.0)

	if _title != null:
		_title.text = "Wake / Prestige"

	var depth_name := DepthMetaSystem.get_depth_currency_name(depth_index)

	if _summary != null:
		_summary.text = "If you wake now:\n" + \
			"• +" + str(int(round(_pending_gain))) + " Memories\n" + \
			"• +" + str(int(round(maxf(depth_gain, 0.0)))) + " " + depth_name

	if _keep_label != null:
		_keep_label.text = "You KEEP:\n" + \
			"• Memories\n" + \
			"• Perks (permanent upgrades)\n" + \
			"• Unlocks & difficulty\n" + \
			"• Settings"

	if _reset_label != null:
		_reset_label.text = "You RESET:\n" + \
			"• Thoughts, Control, Instability\n" + \
			"• Run time & stats\n" + \
			"• Run upgrades\n" + \
			"• Overclock state & cooldowns"

	if _confirm_btn != null:
		if _pending_gain <= 0.0:
			_confirm_btn.text = "Not worth waking yet"
			_confirm_btn.disabled = true
		else:
			_confirm_btn.text = "Wake (+" + str(int(round(_pending_gain))) + ")"
			_confirm_btn.disabled = false

	if _cancel_btn != null:
		_cancel_btn.text = "Cancel"

	visible = true

	if debug_print:
		print("PrestigePanel OPEN mem_gain=", _pending_gain, " depth_gain=", depth_gain, " depth=", depth_index)


func close() -> void:
	visible = false
	if debug_print:
		print("PrestigePanel CLOSE")

func _on_confirm() -> void:
	if _pending_gain <= 0.0:
		return
	if debug_print:
		print("PrestigePanel CONFIRM")
	confirm_wake.emit()

func _on_cancel() -> void:
	if debug_print:
		print("PrestigePanel CANCEL")
	cancel.emit()
