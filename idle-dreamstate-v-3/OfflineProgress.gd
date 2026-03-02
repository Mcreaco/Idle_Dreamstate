extends Node

@export var max_offline_seconds: float = 28800.0  # 8 hours
static var _instance: Node = null

func _ready():
	# Prevent duplicate instances
	if _instance != null and _instance != self:
		print("OfflineProgress already exists, deleting duplicate")
		queue_free()
		return
	_instance = self
	
	print("OFFLINE PROGRESS SCRIPT STARTED")
	# Remove the timer delay - check immediately
	check_offline_progress()

func check_offline_progress():
	print("=== OFFLINE CHECK START ===")
	var data = SaveSystem.load_game()
	
	if not data.has("last_play_time"):
		_save_time()
		return
	
	# CRITICAL: Calculate time IMMEDIATELY before any saves happen
	var last_time = float(data["last_play_time"])
	var now = Time.get_unix_time_from_system()
	var away_seconds = clamp(now - last_time, 0.0, max_offline_seconds)
	
	print("Calculated away time: ", away_seconds, " seconds")
	
	if away_seconds < 5:  # Change to 5 for testing
		print("Away too short: ", away_seconds)
		_save_time()
		return
	
	# NOW wait for DRC to be ready (timestamp is already calculated safely)
	await get_tree().create_timer(0.5).timeout
	
	var gm = get_parent()
	if not gm:
		return
	
	# Get active_depth from save (already loaded in 'data')
	var active_depth = 1
	if data.has("depth_run_controller"):
		var drc_data = data["depth_run_controller"]
		if drc_data.has("active_depth"):
			active_depth = int(drc_data["active_depth"])  # Cast to int immediately
			print("Using saved active_depth: ", active_depth)
	
	# Get crystal name
	var crystal_name = "Crystal"
	var meta = get_node_or_null("/root/Main/DepthMetaSystem")
	if meta and meta.has_method("get_depth_currency_name"):
		crystal_name = meta.call("get_depth_currency_name", active_depth)
	else:
		# Use int() in the match to handle float values like 5.0
		match int(active_depth):
			1: crystal_name = "Amethyst"
			2: crystal_name = "Ruby"
			3: crystal_name = "Emerald"
			4: crystal_name = "Sapphire"
			5: crystal_name = "Diamond"
			6: crystal_name = "Topaz"
			7: crystal_name = "Garnet"
			8: crystal_name = "Opal"
			9: crystal_name = "Aquamarine"
			10: crystal_name = "Onyx"
			11: crystal_name = "Jade"
			12: crystal_name = "Moonstone"
			13: crystal_name = "Obsidian"
			14: crystal_name = "Citrine"
			15: crystal_name = "Quartz"
			_: crystal_name = "Crystal"
	
	print("Processing depth ", active_depth, " (", crystal_name, ")")
	
	# Now DRC should be ready
	var drc = get_node_or_null("/root/DepthRunController")
	var mem_gain = 0.0
	var cry_gain = 0.0
	var progress_gain = 0.0
	var depth_name = ""
	
	if drc != null and active_depth >= 1:
		var run_data = drc.get("run")
		if run_data != null and active_depth <= run_data.size():
			var depth_data = run_data[active_depth - 1]
			
			var base_mem = float(drc.get("base_memories_per_sec"))
			var base_cry = float(drc.get("base_crystals_per_sec"))
			var base_prog = float(drc.get("base_progress_per_sec"))
			
			var local_upgs = drc.get("local_upgrades")
			var depth_upgs = local_upgs.get(active_depth, {}) if local_upgs else {}
			
			var mem_lvl = int(depth_upgs.get("memories_gain", 0))
			var cry_lvl = int(depth_upgs.get("crystals_gain", 0))
			var speed_lvl = int(depth_upgs.get("progress_speed", 0))
			
			var mem_mult = 1.0 + (0.15 * mem_lvl)
			var cry_mult = 1.0 + (0.12 * cry_lvl)
			var prog_mult = 1.0 + (0.25 * speed_lvl)
			
			var length = 1.0
			if drc.has_method("get_depth_length"):
				length = drc.call("get_depth_length", active_depth)
			
			# Calculate gains
			mem_gain = base_mem * mem_mult * away_seconds
			cry_gain = base_cry * cry_mult * away_seconds
			
			var dream_current = gm.dream_current if "dream_current" in gm else 1.0
			var per_sec = (base_prog * dream_current * prog_mult) / max(length, 0.0001)
			progress_gain = per_sec * away_seconds
			
			var def = drc.call("get_depth_def", active_depth) if drc.has_method("get_depth_def") else {}
			depth_name = def.get("new_title", "Depth %d" % active_depth)
			
			# Apply to DRC
			var current_progress = float(depth_data.get("progress", 0.0))
			var cap = drc.call("get_depth_progress_cap", active_depth) if drc.has_method("get_depth_progress_cap") else 1000.0
			var new_progress = min(cap, current_progress + progress_gain)
			
			depth_data["progress"] = new_progress
			depth_data["memories"] = float(depth_data.get("memories", 0.0)) + mem_gain
			depth_data["crystals"] = float(depth_data.get("crystals", 0.0)) + cry_gain
			run_data[active_depth - 1] = depth_data
			drc.set("run", run_data)
			
			print("Gains: Mem=", mem_gain, " ", crystal_name, "=", cry_gain)
	
	# Apply thoughts/control
	var multipliers = 1.0
	if gm.has_method("_calculate_all_multipliers"):
		multipliers = gm._calculate_all_multipliers()
	
	var thoughts_gain = gm.idle_thoughts_rate * multipliers * away_seconds
	var control_gain = gm.idle_control_rate * away_seconds
	
	gm.thoughts += thoughts_gain
	gm.control += control_gain
	
	# Show popup
	_show_popup(away_seconds, thoughts_gain, control_gain, mem_gain, cry_gain, progress_gain, depth_name, crystal_name, active_depth)
	_save_time()

func _save_time():
	var data = SaveSystem.load_game()
	data["last_play_time"] = Time.get_unix_time_from_system()
	SaveSystem.save_game(data)

func _show_popup(seconds: float, thoughts: float, control: float, memories: float = 0.0, crystals: float = 0.0, progress: float = 0.0, depth_name: String = "", crystal_name: String = "Crystals", _active_depth: int = 1):
	get_tree().paused = true
	
	var popup = PanelContainer.new()
	popup.process_mode = Node.PROCESS_MODE_ALWAYS
	popup.custom_minimum_size = Vector2(500, 400)
	popup.z_index = 300
	
	# Style setup...
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.98)
	sb.border_color = Color(0.24, 0.67, 0.94, 1.0)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.corner_radius_top_left = 12
	sb.corner_radius_top_right = 12
	popup.add_theme_stylebox_override("panel", sb)
	
	# Build UI tree first...
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	popup.add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "Welcome Back!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.35, 0.8, 0.95))
	vbox.add_child(title)
	
	# Time away
	var time_label = Label.new()
	var hours = int(seconds / 3600)
	var mins = int(seconds / 60.0) % 60
	if hours > 0:
		time_label.text = "Away for %dh %dm" % [hours, mins]
	else:
		time_label.text = "Away for %dm" % mins
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(time_label)
	
	vbox.add_child(HSeparator.new())
	
	# Resources section
	var resources_label = Label.new()
	resources_label.text = "Resources Gained"
	resources_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	resources_label.add_theme_font_size_override("font_size", 20)
	vbox.add_child(resources_label)
	
	# Grid for resources
	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	vbox.add_child(grid)
	
	# Thoughts
	var thoughts_label = Label.new()
	thoughts_label.text = "Thoughts:"
	thoughts_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(thoughts_label)
	
	var thoughts_value = Label.new()
	thoughts_value.text = "+%s" % _fmt(thoughts)
	thoughts_value.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	grid.add_child(thoughts_value)
	
	# Control
	var control_label = Label.new()
	control_label.text = "Control:"
	control_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(control_label)
	
	var control_value = Label.new()
	control_value.text = "+%s" % _fmt(control)
	control_value.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9))
	grid.add_child(control_value)
	
	# Memories (if any)
	if memories > 0:
		var mem_label = Label.new()
		mem_label.text = "Memories:"
		mem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(mem_label)
		
		var mem_value = Label.new()
		mem_value.text = "+%s" % _fmt(memories)
		mem_value.add_theme_color_override("font_color", Color(0.9, 0.6, 0.9))
		grid.add_child(mem_value)
	
	# In _show_popup, replace the bottom section (around line 220-240) with:

	# Depth progress section (if active depth)
	if depth_name != "" and progress > 0:
		vbox.add_child(HSeparator.new())
		
		var depth_title = Label.new()
		depth_title.text = depth_name
		depth_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		depth_title.add_theme_font_size_override("font_size", 18)
		vbox.add_child(depth_title)
		
		var prog_label = Label.new()
		prog_label.text = "Progress: +%s" % _fmt(progress)
		prog_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(prog_label)
		
		# MOVE CRYSTAL LABEL HERE - inside the depth section, before adding popup to tree
		if crystals > 0:
			var cry_label = Label.new()
			cry_label.text = "%s: +%s" % [crystal_name, _fmt(crystals)]
			cry_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cry_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			vbox.add_child(cry_label)
	
	# Close button
	var close_btn = Button.new()
	close_btn.text = "Continue"
	close_btn.custom_minimum_size = Vector2(200, 50)
	close_btn.pressed.connect(func():
		get_tree().paused = false
		popup.queue_free()
	)
	vbox.add_child(close_btn)
	
	# SAFE ADD CHILD - Check if already in tree
	if popup.get_parent() == null:
		get_tree().root.call_deferred("add_child", popup)
		# Wait for next frame to center
		await get_tree().process_frame
		if popup.is_inside_tree():
			popup.set_anchors_preset(Control.PRESET_CENTER)
		
func _fmt(v: float) -> String:
	if v >= 1000000:
		return "%.1fM" % (v / 1000000)
	if v >= 1000:
		return "%.1fk" % (v / 1000)
	return str(int(v))
