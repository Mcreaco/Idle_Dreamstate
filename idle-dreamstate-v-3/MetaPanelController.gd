extends Control
class_name MetaPanelController

@export var max_depth_reached: int = 1
@export var abyss_unlocked: bool = false

var tab_perm: Button
var tab_depth: Button
var tab_abyss: Button

var page_perm: Control
var page_depth: Control
var page_abyss: Control

var depth_tabs: Control
var depth_pages: Control

var dim: Control
var close_btn: Button

var depth_meta_system: DepthMetaSystem
var currency_summary: Node # optional, if you have one

var _current_meta: String = "perm"
var _current_depth: int = 1

func _ready() -> void:
	visible = false
	call_deferred("_late_bind")

func _late_bind() -> void:
	depth_meta_system = get_tree().current_scene.find_child("DepthMetaSystem", true, false) as DepthMetaSystem

	tab_perm = find_child("TabPerm", true, false) as Button
	tab_depth = find_child("TabDepth", true, false) as Button
	tab_abyss = find_child("TabAbyss", true, false) as Button

	page_perm = find_child("PermPage", true, false) as Control
	page_depth = find_child("DepthPage", true, false) as Control
	page_abyss = find_child("AbyssPage", true, false) as Control

	dim = find_child("Dim", true, false) as Control
	close_btn = find_child("CloseButton", true, false) as Button

	depth_tabs = null
	depth_pages = null
	if page_depth != null:
		depth_tabs = page_depth.find_child("DepthTabs", true, false) as Control
		depth_pages = page_depth.find_child("DepthPages", true, false) as Control
		# Optional: only if you created a summary node
		currency_summary = page_depth.find_child("CurrencySummaryVBox", true, false)

	_connect_top_tab(tab_perm, "perm")
	_connect_top_tab(tab_depth, "depth")
	_connect_top_tab(tab_abyss, "abyss")

	# Dim click closes
	if dim != null:
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		if not dim.gui_input.is_connected(Callable(self, "_on_dim_gui_input")):
			dim.gui_input.connect(Callable(self, "_on_dim_gui_input"))

	# Close button
	if close_btn != null:
		close_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		if not close_btn.pressed.is_connected(Callable(self, "close")):
			close_btn.pressed.connect(Callable(self, "close"))

	_fix_stacking()

	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)

func _fix_stacking() -> void:
	# Godot 4: ColorRect doesn't have move_to_back().
	# Ensure dim is the FIRST child (behind), and everything else is above.
	if dim == null:
		return
	var p := dim.get_parent()
	if p != null:
		p.move_child(dim, 0)

	# Also prevent hidden pages from blocking input (this was causing “perm buttons don’t work”)
	if page_perm != null and not page_perm.visible:
		page_perm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page_depth != null and not page_depth.visible:
		page_depth.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if page_abyss != null and not page_abyss.visible:
		page_abyss.mouse_filter = Control.MOUSE_FILTER_IGNORE

func toggle_open() -> void:
	visible = not visible
	if visible:
		_apply_unlocks()
		_show_meta(_current_meta)
		_show_depth(_current_depth)

func open() -> void:
	visible = true
	_apply_unlocks()
	_show_meta(_current_meta)
	_show_depth(_current_depth)

func close() -> void:
	visible = false

func set_progress(new_max_depth: int, is_abyss_unlocked: bool) -> void:
	max_depth_reached = maxi(1, new_max_depth)
	abyss_unlocked = is_abyss_unlocked
	_apply_unlocks()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# ----------------------------
# Top tabs
# ----------------------------
func _connect_top_tab(btn: Button, which: String) -> void:
	if btn == null:
		return
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if not btn.pressed.is_connected(Callable(self, "_on_top_tab_pressed")):
		btn.pressed.connect(Callable(self, "_on_top_tab_pressed").bind(which))

func _on_top_tab_pressed(which: String) -> void:
	_show_meta(which)

func _show_meta(which: String) -> void:
	_current_meta = which

	# IMPORTANT: hidden pages must not block clicks
	if page_perm != null:
		page_perm.visible = (which == "perm")
		page_perm.mouse_filter = Control.MOUSE_FILTER_STOP if page_perm.visible else Control.MOUSE_FILTER_IGNORE

	if page_depth != null:
		page_depth.visible = (which == "depth")
		page_depth.mouse_filter = Control.MOUSE_FILTER_STOP if page_depth.visible else Control.MOUSE_FILTER_IGNORE

	if page_abyss != null:
		page_abyss.visible = (which == "abyss")
		page_abyss.mouse_filter = Control.MOUSE_FILTER_STOP if page_abyss.visible else Control.MOUSE_FILTER_IGNORE

	# snap back if abyss locked
	if which == "abyss" and (tab_abyss == null or tab_abyss.disabled):
		_current_meta = "depth"
		if page_perm != null:
			page_perm.visible = false
			page_perm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if page_depth != null:
			page_depth.visible = true
			page_depth.mouse_filter = Control.MOUSE_FILTER_STOP
		if page_abyss != null:
			page_abyss.visible = false
			page_abyss.mouse_filter = Control.MOUSE_FILTER_IGNORE

# ----------------------------
# Unlocks / Depth tabs
# ----------------------------
func _apply_unlocks() -> void:
	if page_depth == null:
		page_depth = find_child("DepthPage", true, false) as Control
	if page_depth != null and (depth_tabs == null or depth_pages == null):
		depth_tabs = page_depth.find_child("DepthTabs", true, false) as Control
		depth_pages = page_depth.find_child("DepthPages", true, false) as Control

	if depth_tabs == null or depth_pages == null:
		push_warning("MetaPanelController: DepthTabs or DepthPages not found. Check node names.")
		return

	# Abyss tab visibility
	var abyss_ok := abyss_unlocked or (max_depth_reached >= 15)
	if tab_abyss != null:
		tab_abyss.visible = abyss_ok
		tab_abyss.disabled = not abyss_ok

	# Depth tab setup
	for i in range(1, 16):
		var tab := depth_tabs.get_node_or_null("DepthTab%d" % i) as Button
		if tab == null:
			continue

		tab.visible = (max_depth_reached >= i)
		tab.disabled = false
		tab.mouse_filter = Control.MOUSE_FILTER_STOP

		var depth_title := DepthMetaSystem.get_depth_name(i)
		var amount := 0.0
		if depth_meta_system != null:
			amount = depth_meta_system.currency[i]

		tab.text = "%s (%.0f)" % [depth_title, amount]

		if not tab.pressed.is_connected(Callable(self, "_on_depth_tab_pressed")):
			tab.pressed.connect(Callable(self, "_on_depth_tab_pressed").bind(i))

	if _current_depth > max_depth_reached:
		_current_depth = max_depth_reached
	_show_depth(_current_depth)

func _on_depth_tab_pressed(depth_index: int) -> void:
	_show_depth(depth_index)

func _show_depth(depth_index: int) -> void:
	if depth_pages == null:
		return
	_current_depth = clampi(depth_index, 1, 15)

	for i in range(1, 16):
		var page := depth_pages.get_node_or_null("DepthPage%d" % i) as Control
		if page != null:
			page.visible = (i == _current_depth)
			page.mouse_filter = Control.MOUSE_FILTER_STOP if page.visible else Control.MOUSE_FILTER_IGNORE

func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		close()
