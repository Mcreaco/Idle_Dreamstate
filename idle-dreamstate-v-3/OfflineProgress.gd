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
	
	var last_time = float(data["last_play_time"])
	var now = Time.get_unix_time_from_system()
	var away_seconds = clamp(now - last_time, 0.0, max_offline_seconds)
	
	if away_seconds < 5:
		_save_time()
		return
	
	# Determine active depth from save data
	var active_depth = 1
	
	if data.has("depth_run_controller"):
		var drc_data = data["depth_run_controller"]
		if drc_data.has("active_depth"):
			active_depth = int(drc_data["active_depth"])
			print("Found active_depth in save: ", active_depth)
	
	# Wait for nodes
	await get_tree().create_timer(0.5).timeout
	
	var drc = get_node_or_null("/root/DepthRunController")
	var gm = get_node_or_null("/root/Main/GameManager")  # Used for thoughts/dreamcloud later
	
	# Set DRC to correct depth
	if drc and active_depth > 1:
		drc.active_depth = active_depth
		if drc.has_method("_ensure_depth_runtime"):
			drc.call("_ensure_depth_runtime", active_depth)
	
	var crystal_name = _get_crystal_name(active_depth)
	var mem_gain = 0.0
	var cry_gain = 0.0
	var progress_gain = 0.0
	var depth_name = ""
	var thoughts_gain = 0.0
	var dreamcloud_gain = 0.0
	
	# Calculate gains
	if drc and data.has("depth_run_controller"):
		var drc_data = data["depth_run_controller"]
		var run_data = drc.get("run")  # Use DRC's current run data
		
		if active_depth <= run_data.size():
			# Use the actual depth data from DRC
			var depth_data = run_data[active_depth - 1]  # NOW USED
			
			# Get upgrades
			var local_upgs = drc_data.get("local_upgrades", {})
			var depth_upgs = local_upgs.get(str(active_depth), {})
			
			var base_mem = float(drc.get("base_memories_per_sec"))
			var base_cry = float(drc.get("base_crystals_per_sec"))
			var base_prog = float(drc.get("base_progress_per_sec"))
			
			var mem_lvl = int(depth_upgs.get("memories_gain", 0))
			var cry_lvl = int(depth_upgs.get("crystals_gain", 0))
			var speed_lvl = int(depth_upgs.get("progress_speed", 0))
			
			var mem_mult = 1.0 + (0.15 * mem_lvl)
			var cry_mult = 1.0 + (0.12 * cry_lvl)
			var prog_mult = 1.0 + (0.25 * speed_lvl)
			
			# Calculate gains
			mem_gain = base_mem * mem_mult * away_seconds
			cry_gain = base_cry * cry_mult * away_seconds
			
			var length = 1.0
			if drc.has_method("get_depth_length"):
				length = drc.call("get_depth_length", active_depth)
			
			var dream_current = drc_data.get("dream_current", 1.0)
			var per_sec = (base_prog * dream_current * prog_mult) / max(length, 0.0001)
			progress_gain = per_sec * away_seconds
			
			# Get name
			var def = drc.call("get_depth_def", active_depth) if drc.has_method("get_depth_def") else {}
			depth_name = def.get("new_title", "Depth %d" % active_depth)
			
			# APPLY TO DRC
			var current_progress = float(depth_data.get("progress", 0.0))
			var cap = drc.call("get_depth_progress_cap", active_depth) if drc.has_method("get_depth_progress_cap") else 1000.0
			depth_data["progress"] = min(cap, current_progress + progress_gain)
			depth_data["memories"] = float(depth_data.get("memories", 0.0)) + mem_gain
			depth_data["crystals"] = float(depth_data.get("crystals", 0.0)) + cry_gain
			
			# Update DRC
			run_data[active_depth - 1] = depth_data
			# DRC internal data is already updated since we modified the reference
			
			# Sync UI
			if drc.has_method("_sync_all_to_panel"):
				drc.call("_sync_all_to_panel")
	
	# Calculate thoughts/dreamcloud using gm (NOW USED)
	if gm:
		var multipliers = 1.0
		if gm.has_method("_calculate_all_multipliers"):
			multipliers = gm._calculate_all_multipliers()
		
		var idle_rate = gm.get("idle_thoughts_rate") if gm.get("idle_thoughts_rate") != null else 0.8
		var dreamcloud_rate = gm.get("idle_dreamcloud_rate") if gm.get("idle_dreamcloud_rate") != null else 0.5
		
		thoughts_gain = idle_rate * multipliers * away_seconds
		dreamcloud_gain = dreamcloud_rate * away_seconds
		
		gm.thoughts += thoughts_gain
		gm.dreamcloud += dreamcloud_gain
	
	_show_popup(away_seconds, thoughts_gain, dreamcloud_gain, mem_gain, cry_gain, progress_gain, depth_name, crystal_name, active_depth)
	_save_time()

func _get_crystal_name(depth: int) -> String:
	match depth:
		1: return "Amethyst"
		2: return "Ruby"
		3: return "Emerald"
		4: return "Sapphire"
		5: return "Diamond"
		6: return "Topaz"
		7: return "Garnet"
		8: return "Opal"
		9: return "Aquamarine"
		10: return "Onyx"
		11: return "Jade"
		12: return "Moonstone"
		13: return "Obsidian"
		14: return "Citrine"
		15: return "Quartz"
		_: return "Crystal"
		
func _save_time():
	var data = SaveSystem.load_game()
	data["last_play_time"] = Time.get_unix_time_from_system()
	SaveSystem.save_game(data)

func _show_popup(seconds: float, thoughts: float, dreamcloud: float, memories: float = 0.0, crystals: float = 0.0, progress: float = 0.0, depth_name: String = "", crystal_name: String = "Crystals", _active_depth: int = 1):
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
	
	# dreamcloud
	var dreamcloud_label = Label.new()
	dreamcloud_label.text = "dreamcloud:"
	dreamcloud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(dreamcloud_label)
	
	var dreamcloud_value = Label.new()
	dreamcloud_value.text = "+%s" % _fmt(dreamcloud)
	dreamcloud_value.add_theme_color_override("font_color", Color(0.4, 0.7, 0.9))
	grid.add_child(dreamcloud_value)
	
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
