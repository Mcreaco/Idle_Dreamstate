extends PanelContainer

# ── State ──────────────────────────────────────────────────────────────────────
var current_wave: int = 1
var current_subwave: int = 1
var highest_wave_reached: int = 1
var _wave_in_progress: bool = false
var _is_manual_wave: bool = false # Disable auto-advance if manual nav used
var auto_battle_active: bool = true:
	set(v):
		auto_battle_active = v
		if not v and _is_smooth_looping:
			_stop_smooth_auto_battle()

# ── Node refs ─────────────────────────────────────────────────────────────────
var _combat_view: Control = null
var _equipment_view: Control = null
var _forge_view: Control = null
var _wave_label: Label = null
var _start_wave_btn: Button = null
var _prev_wave_btn: Button = null
var _next_wave_btn: Button = null
var _gm: Node = null
var _ce: CombatEngine = null
var _em: EquipmentManager = null
var _p_stats: Dictionary = {}
var _e_data: Dictionary = {}
var _smooth_auto_box: Control = null
var _smooth_bar: ProgressBar = null
var _is_smooth_looping: bool = false

@onready var _mastery_label: Label = find_child("MasteryLabel", true, false)
@onready var _player_status_box: HBoxContainer = find_child("PlayerStatusBox", true, false)
@onready var _enemy_status_box: HBoxContainer = find_child("EnemyStatusBox", true, false)
@onready var _total_stats_lbl: RichTextLabel = find_child("StatsLbl", true, false)

const ICONS = {
	"weapon": "res://assets/combat/icon_weapon.png",
	"armor": "res://assets/combat/icon_armor.png",
	"amulet": "res://assets/combat/icon_amulet.png",
	"ring1": "res://assets/combat/icon_ring.png",
	"helmet": "res://assets/combat/icon_helmet.png",
	"talisman": "res://assets/combat/icon_talisman.png"
}
const SPRITES = {
	"sheep": "res://assets/combat/sheep.png",
	"shadow": "res://assets/combat/shadow.png",
	"nightmare": "res://assets/combat/nightmare.png"
}

# ── Ready ──────────────────────────────────────────────────────────────────────
func _ready() -> void:
	visible = false
	_gm = get_tree().current_scene.find_child("GameManager", true, false)
	if _gm:
		_ce = _gm.get("combat_engine") as CombatEngine
		_em = _gm.get("equipment_manager") as EquipmentManager
		if _em: print("[DEBUG] DreamsPanel: Linked to EquipmentManager ID: ", _em.get_instance_id())
	
	_combat_view    = find_child("CombatView",    true, false)
	_equipment_view = find_child("EquipmentView", true, false)
	_forge_view     = find_child("ForgeView",      true, false)
	_wave_label     = find_child("WaveLabel",      true, false)
	_start_wave_btn = find_child("StartWaveBtn",   true, false)
	_prev_wave_btn  = find_child("PrevWaveBtn",    true, false)
	_next_wave_btn  = find_child("NextWaveBtn",    true, false)
	_smooth_auto_box = find_child("SmoothAutoBox", true, false)
	_smooth_bar      = find_child("SmoothProgressBar", true, false)
	
	# Show combat view by default
	_show_view("combat")
	
	# Button sidebar connections (connected in tscn but also safe to wire here)
	var btn_combat = find_child("BtnCombat", true, false)
	var btn_equip  = find_child("BtnEquipment", true, false)
	var btn_forge  = find_child("BtnForge", true, false)
	var btn_close  = find_child("BtnClose", true, false)
	if btn_combat: btn_combat.pressed.connect(func(): _show_view("combat"))
	if btn_equip:  btn_equip.pressed.connect(func():  _show_view("equipment"))
	if btn_forge:  btn_forge.pressed.connect(func():  _show_view("forge"))
	if btn_close:  btn_close.pressed.connect(func():  visible = false)
	
	if _start_wave_btn:
		_start_wave_btn.pressed.connect(_on_start_wave_pressed)
	if _prev_wave_btn:
		_prev_wave_btn.pressed.connect(_on_prev_wave_pressed)
	if _next_wave_btn:
		_next_wave_btn.pressed.connect(_on_next_wave_pressed)
	
	if _ce:
		_ce.combat_ended.connect(_on_wave_ended)
		_ce.hp_changed.connect(_on_hp_changed)
		_ce.damage_dealt.connect(_on_damage_dealt)
	
	_update_wave_label()

# ── View switching ──────────────────────────────────────────────────────────────
func _show_view(which: String) -> void:
	if _combat_view:    _combat_view.visible    = (which == "combat")
	if _equipment_view: _equipment_view.visible = (which == "equipment")
	if _forge_view:     _forge_view.visible     = (which == "forge")
	if which == "equipment": _refresh_equipment_view()
	if which == "forge":     _refresh_forge_view()

# ── Wave logic ─────────────────────────────────────────────────────────────────
func open_panel() -> void:
	visible = true
	_update_wave_label()
	_clear_attack_grid()

func _on_start_wave_pressed() -> void:
	if _wave_in_progress or _ce == null:
		return
	_wave_in_progress = true
	if _start_wave_btn:
		_start_wave_btn.disabled = true
	
	# 1. Overpower Check for Smooth Auto-battle
	var enemy: Dictionary = _build_enemy_for_wave(current_wave)
	var p_stats: Dictionary = _em.get_player_combat_stats() if _em != null else {"attack": 10.0, "max_hp": 100.0, "defense": 5.0}
	
	# 1. Indestructible Check (Defense > 2x Enemy MAX possible attack)
	var is_overpowered = (p_stats.defense > enemy.attack * 2.0)
	
	if auto_battle_active and is_overpowered:
		_start_smooth_auto_battle(p_stats, enemy)
		return

	# 1. NEW: Wave Cap check (Limit progress by main game depth)
	var max_wave_allowed = (_gm.max_depth_reached * 10) if _gm else 10
	if current_wave > max_wave_allowed:
		# UI feedback or simple block
		print("COMBAT: Wave capped by depth progress. Deepen your run to unlock more waves!")
		_wave_in_progress = false
		if _start_wave_btn: _start_wave_btn.disabled = false
		return

	_update_combat_ui_for_start(p_stats, enemy)
	_ce.start_combat(p_stats, enemy, current_wave)
	_p_stats = p_stats
	_e_data = enemy

func _auto_win_wave() -> void:
	_wave_in_progress = false
	var wave = current_wave
	var reward: float = float(wave) * 25.0 * 2.0 * (1.0 + (current_subwave * 0.05)) # Subwave bonus
	
	if _gm:
		_gm.dreamcloud += reward
		_gm._refresh_top_ui()
		
		# Drop Check
		var rarity = _calculate_drop_rarity_v2(current_wave, current_subwave)
		var slot_pool = ["weapon","armor","amulet","ring1","helmet","talisman"]
		var item = _em.generate_item(rarity, slot_pool.pick_random(), current_wave)
		_em.inventory.append(item)
		print("[DEBUG] Auto-Win: Generated %s (%s) from Wave %d Subwave %d" % [item.name, rarity, current_wave, current_subwave])

		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
		if not (wave_data is Dictionary): wave_data = {"mastery": int(wave_data), "best_subwave": 0}
		wave_data.mastery = int(wave_data.get("mastery", 0)) + 1
		wave_data.best_subwave = maxi(int(wave_data.get("best_subwave", 0)), current_subwave)
		_gm.wave_mastery[wave_id] = wave_data
		
		_gm.save_game()
	
	current_subwave += 1
	_update_wave_label()
	
	 # Repeat wave if Auto-Battle is ON
	if auto_battle_active:
		await get_tree().create_timer(0.1).timeout
		_on_start_wave_pressed()
		
		# Update highest wave reached (moved into result logic usually, but here for auto-win)
		highest_wave_reached = maxi(highest_wave_reached, current_wave + 1)
		if _gm: _gm.save_game()

func _start_smooth_auto_battle(p_stats: Dictionary, enemy_data: Dictionary) -> void:
	if _is_smooth_looping: return
	_is_smooth_looping = true
	# 1. Hide the standard HP bars
	var php = find_child("PlayerHpBar", true, false)
	var ehp = find_child("EnemyHpBar", true, false)
	if php: php.visible = false
	if ehp: ehp.visible = false
	
	# 2. Show smooth UI box (Overlay)
	if _smooth_auto_box: 
		_smooth_auto_box.visible = true
	
	_smooth_loop(p_stats, enemy_data)

func _calculate_smooth_battle_time(ps: Dictionary, ed: Dictionary) -> float:
	var damage_per_hit = max(1.0, ps.attack - ed.defense)
	var hits_to_kill = ceil(ed.hp / damage_per_hit)
	# 1.0s per hit base
	return maxf(1.0, float(hits_to_kill) * 1.0)

func _smooth_loop(ps: Dictionary, ed: Dictionary) -> void:
	var battle_time = _calculate_smooth_battle_time(ps, ed)
	
	while _is_smooth_looping and auto_battle_active and visible:
		# REFRESH STATS EVERY TICK (Sync with Forge/Equip changes)
		if _em: ps = _em.get_player_combat_stats()
		ed = _build_enemy_for_wave(current_wave)
		battle_time = _calculate_smooth_battle_time(ps, ed)
		
		# Update the UI labels for current stats
		_update_stats_panel(ps, ed)
		
		if _smooth_bar:
			_smooth_bar.value = 0
			var tween = create_tween()
			tween.tween_property(_smooth_bar, "value", 100, battle_time) 
			await tween.finished
		else:
			await get_tree().create_timer(battle_time).timeout
			
		_give_smooth_rewards()
		current_subwave += 1
		_update_wave_label()
		
		# EFFICIENCY CHECK: Exit if enemy attack is too high relative to your net damage
		# User formula: ed.attack > 0.5 * (ps.attack - ed.defense)
		var net_player_dmg = ps.attack - ed.defense
		if ed.attack > 0.5 * net_player_dmg:
			print("SMOOTH LOOP: Efficiency threshold reached (Enemy ATK too high), dropping to manual combat.")
			_stop_smooth_auto_battle()
			break
			
		battle_time = _calculate_smooth_battle_time(ps, ed)

func _give_smooth_rewards() -> void:
	var wave = current_wave
	var subwave = current_subwave
	var reward: float = float(wave) * 25.0 * 2.0 * (1.0 + (subwave * 0.05))
	
	if _gm:
		_gm.dreamcloud += reward
		_gm._refresh_top_ui()
		
		var wave_id = "wave_%d" % wave
		var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
		if not (wave_data is Dictionary): wave_data = {"mastery": int(wave_data), "best_subwave": 0}
		wave_data.mastery = int(wave_data.get("mastery", 0)) + 1
		wave_data.best_subwave = maxi(int(wave_data.get("best_subwave", 0)), subwave)
		_gm.wave_mastery[wave_id] = wave_data

		# Drop Check
		var drop_chance = 0.05 * (1.0 + (subwave * 0.05))
		if randf() < drop_chance:
			var rarity = _calculate_drop_rarity_v2(wave, subwave)
			var item = _em.generate_item(rarity, ["weapon","armor","amulet","ring1","helmet","talisman"].pick_random(), wave)
			_em.inventory.append(item)
			print("SMOOTH DROP: ", item.name, " (", rarity, ")")
		
		_gm.save_game()
	
	current_subwave += 1
	_update_wave_label()

func _stop_smooth_auto_battle() -> void:
	_is_smooth_looping = false
	_wave_in_progress = false
	if _smooth_auto_box: _smooth_auto_box.visible = false
	# Restore standard combat elements
	var php = find_child("PlayerHpBar", true, false)
	var ehp = find_child("EnemyHpBar", true, false)
	if php: php.visible = true
	if ehp: ehp.visible = true
	# Force result banner/etc to be hidden if we just stopped
	var res = find_child("ResultBanner", true, false)
	if res: res.visible = false
	_update_wave_label()

func _build_enemy_for_wave(wave: int) -> Dictionary:
	var subwave_mult := 1.0 + ((current_subwave - 1) * 0.1)
	var hp   := (30.0 + float(wave) * 15.0) * subwave_mult
	var atk  := (4.0  + float(wave) * 2.5) * subwave_mult
	var def_ := (1.0  + float(wave) * 1.2) * subwave_mult
	
	var tier := clampi(int(float(wave - 1) / 5.0), 0, 3)
	var names := [
		["Fading Thought", "Hollow Echo", "Dream Shard", "Whisper Wisp", "Mind Flicker"],
		["Shifting Shadow", "Void Tendril", "Dread Spectre", "Nightmare Wraith", "Rift Stalker"],
		["Abyssal Sentinel", "Crystalline Horror", "Mind Aberration", "Voidborn", "Oblivion Reaper"],
		["The Dreaming Abyss", "Eternity's Edge", "Shattered Ego", "The Waking Fear", "Infinite Regret"]
	]
	var pool: Array = names[tier]
	var sprite_key = "sheep"
	if wave > 30: sprite_key = "nightmare"
	elif wave > 15: sprite_key = "shadow"
	
	return {
		"name":    "%s (%d-%d)" % [pool[wave % pool.size()], wave, current_subwave],
		"hp":      hp,
		"attack":  atk,
		"defense": def_,
		"wave":    wave,
		"subwave": current_subwave,
		"sprite":  SPRITES[sprite_key]
	}

func _on_wave_ended(result: Dictionary) -> void:
	_wave_in_progress = false
	var won: bool = result.get("won", false)
	var perfect: bool = result.get("perfect", false)
	var wave: int = result.get("depth", current_wave)
	
	# Disconnect per-combat signals
	if _ce:
		if _ce.turn_started.is_connected(_on_turn_update): _ce.turn_started.disconnect(_on_turn_update)
		if _ce.intent_revealed.is_connected(_on_intent_revealed): _ce.intent_revealed.disconnect(_on_intent_revealed)
		if _ce.player_turn.is_connected(_on_player_turn): _ce.player_turn.disconnect(_on_player_turn)
		if _ce.damage_dealt.is_connected(_on_damage_dealt): _ce.damage_dealt.disconnect(_on_damage_dealt)
	
	if won:
		highest_wave_reached = maxi(highest_wave_reached, current_wave + 1)
		var reward: float = float(wave) * 25.0 * (2.0 if perfect else 1.0)
		if _gm:
			_gm.dreamcloud += reward
			_gm._refresh_top_ui()
		
		var drop: Dictionary = result.get("drop", {})
		if not drop.is_empty() and _em != null:
			print("[DEBUG] DreamsPanel (EM ID: %d): Adding drop to inventory. New size: %d" % [_em.get_instance_id(), _em.inventory.size() + 1])
			_em.inventory.append(drop)
			if _gm: _gm.save_game()
		
		# Wave Mastery Integration
		if _gm:
			if not _gm.get("wave_mastery") is Dictionary:
				_gm.set("wave_mastery", {})
			var wave_id = "wave_%d" % current_wave
			var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
			if not (wave_data is Dictionary):
				wave_data = {"mastery": int(wave_data), "best_subwave": 0}
			
			wave_data.mastery = int(wave_data.get("mastery", 0)) + 1
			wave_data.best_subwave = maxi(int(wave_data.get("best_subwave", 0)), current_subwave)
			_gm.wave_mastery[wave_id] = wave_data
		
		current_subwave += 1
		_update_wave_label() # Refresh display
		_show_wave_result(true, perfect, reward, result.get("drop", {}))
		
		# In subwave mode, we don't automatically jump to the next BASE wave
		# The player manually chooses Wave X, and stays in it climbing subwaves.
		
		# AUTO-ADVANCE (Legacy behavior when Auto-Battle is OFF but we haven't manually selected a wave)
		if not _is_manual_wave and visible:
			var timer = get_tree().create_timer(1.5)
			timer.timeout.connect(func():
				if visible and not _wave_in_progress:
					_on_start_wave_pressed()
			)
	else:
		# On loss: stay at same wave, small instability penalty
		if _gm:
			_gm.instability = minf(_gm.instability + 3.0, _gm.get_instability_cap(_gm.get_current_depth()))
			_gm._refresh_top_ui()
		_show_wave_result(false, false, 0.0, {})
	
	if _gm:
		_gm.save_game()

# ── Combat UI helpers ──────────────────────────────────────────────────────────
func _update_combat_ui_for_start(p_stats: Dictionary, enemy: Dictionary) -> void:
	var enemy_lbl := find_child("EnemyNameLbl", true, false) as Label
	var player_hp := find_child("PlayerHpBar", true, false) as ProgressBar
	var enemy_hp  := find_child("EnemyHpBar",  true, false) as ProgressBar
	var intent_lbl := find_child("IntentLbl",   true, false) as Label
	if enemy_lbl:  enemy_lbl.text = enemy.name
	if intent_lbl: intent_lbl.text = "..."
	if player_hp:
		player_hp.max_value = p_stats.max_hp
		player_hp.value     = p_stats.max_hp
	if enemy_hp:
		enemy_hp.max_value = enemy.hp
		enemy_hp.value     = enemy.hp
	
	var sprite_rect := find_child("EnemySprite", true, false) as TextureRect
	if sprite_rect:
		sprite_rect.texture = load(enemy.sprite)
		sprite_rect.visible = true

	_ce.turn_started.connect(_on_turn_update)
	_ce.intent_revealed.connect(_on_intent_revealed)
	_ce.player_turn.connect(_on_player_turn)
	_update_stats_panel(p_stats, enemy)

func _update_stats_panel(p_stats: Dictionary, enemy_data: Dictionary) -> void:
	# Update Player Panel
	var php  := find_child("PHP",  true, false) as Label
	var patk := find_child("PATK", true, false) as Label
	var pdef := find_child("PDEF", true, false) as Label
	if php:  php.text  = "HP:  %.0f / %.0f" % [_ce.player_hp, p_stats.max_hp]
	if patk: patk.text = "ATK: %.1f" % p_stats.attack
	if pdef: pdef.text = "DEF: %.1f" % p_stats.defense
	
	# Update Enemy Panel
	var ehp  := find_child("EHP",  true, false) as Label
	var eatk := find_child("EATK", true, false) as Label
	var edef := find_child("EDEF", true, false) as Label
	if ehp:  ehp.text  = "HP:  %.0f / %.0f" % [_ce.enemy_hp, enemy_data.hp]
	if eatk: eatk.text = "ATK: %.1f" % enemy_data.attack
	if edef: edef.text = "DEF: %.1f" % enemy_data.defense

func _on_hp_changed(p_hp: float, e_hp: float) -> void:
	var player_hp_bar := find_child("PlayerHpBar", true, false) as ProgressBar
	var enemy_hp_bar  := find_child("EnemyHpBar",  true, false) as ProgressBar
	if player_hp_bar: player_hp_bar.value = p_hp
	if enemy_hp_bar:  enemy_hp_bar.value  = e_hp
	if not _p_stats.is_empty():
		_update_stats_panel(_p_stats, _e_data)

func _on_damage_dealt(amount: float, target_type: String) -> void:
	var anchor: Control = null
	if target_type == "enemy":
		anchor = find_child("EnemyHpBar", true, false) as Control
	else:
		anchor = find_child("PlayerHpBar", true, false) as Control
	
	var pos = Vector2.ZERO
	# ALWAYS prioritize smooth bars if looping
	# ALWAYS prioritize side anchors for separation
	var side_anchor: Control = null
	if target_type == "enemy":
		side_anchor = find_child("EnemyStatsPanel", true, false) as Control
	else:
		side_anchor = find_child("PlayerStatsPanel", true, false) as Control
		
	if side_anchor:
		var rect = side_anchor.get_global_rect()
		pos = rect.position + Vector2(rect.size.x / 2.0, rect.size.y / 2.0)
		# Add randomization to prevent stacking
		pos += Vector2(randf_range(-40, 40), randf_range(-20, 20))
	
	if pos == Vector2.ZERO and anchor:
		# Standard combat positioning: Use side boxes for better separation than just the bars
		var side_box: Control = null
		if target_type == "enemy":
			side_box = find_child("EnemyStatsPanel", true, false) as Control
		else:
			side_box = find_child("PlayerStatsPanel", true, false) as Control
			
		if side_box:
			var rect = side_box.get_global_rect()
			pos = rect.position + Vector2(rect.size.x / 2.0, -30) # Above the box
		else:
			# Fallback to bar center
			var rect = anchor.get_global_rect()
			pos = rect.position + Vector2(rect.size.x / 2.0, -10)
	
	if pos != Vector2.ZERO:
		_spawn_damage_popup(amount, pos, target_type)

func _spawn_damage_popup(amount: float, pos: Vector2, target_type: String) -> void:
	var lbl = Label.new()
	lbl.text = "-%.0f" % amount
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
	lbl.add_theme_constant_override("shadow_outline_size", 4)
	lbl.modulate = Color.RED if target_type == "player" else Color.YELLOW
	
	add_child(lbl)
	# Directly use global positioning
	lbl.custom_minimum_size = Vector2(250, 0)
	lbl.global_position = pos - Vector2(125, 0)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(lbl, "global_position:y", lbl.global_position.y - 80, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(lbl, "modulate:a", 0.0, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(lbl.queue_free)

func _on_turn_update(_t: int, _m: int) -> void:
	# Keep bars synced just in case, but hp_changed does the heavy lifting
	_on_hp_changed(_ce.player_hp, _ce.enemy_hp)
	_refresh_status_icons()

func _refresh_status_icons() -> void:
	if not _ce: return
	for box in [_player_status_box, _enemy_status_box]:
		if box:
			for c in box.get_children(): c.queue_free()
	
	_add_status_icons(_player_status_box, _ce.player_statuses)
	_add_status_icons(_enemy_status_box, _ce.enemy_statuses)

func _add_status_icons(box: HBoxContainer, statuses: Array) -> void:
	if not box: return
	for s in statuses:
		var lbl = Label.new()
		var s_display = s.id.substr(0, 3).to_upper() # BLE, STU
		var magnitude = ""
		var strength = int(s.get("strength", 5))
		var tt = s.id.capitalize() + " (" + str(s.duration) + "t): "
		
		match s.id:
			"bleed":
				magnitude = " [%d dmg/t]" % strength
				lbl.text = "[BLEED: %d dmg]" % [s.duration * strength]
				tt += "Deals %d damage at turn start for %d turns (Total: %d)" % [strength, s.duration, s.duration * strength]
			"stun":
				magnitude = " [STUN]"
				lbl.text = "[STUNNED]"
				tt += "Skips next turn"
			_:
				lbl.text = "[%s:%d%s]" % [s_display, s.duration, magnitude]
		
		lbl.tooltip_text = tt
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		var color = Color.WHITE
		match s.id:
			"bleed": color = Color(1.0, 0.3, 0.3)
			"stun": color = Color(1.0, 1.0, 0.6)
		lbl.add_theme_color_override("font_color", color)
		box.add_child(lbl)
	
	# Also update the Stat labels to show icons next to them if needed
	# For simplicity, we just keep the boxes hidden and re-bind them in _update_stats_panel

func _on_intent_revealed(intent: Dictionary) -> void:
	var intent_lbl := find_child("IntentLbl", true, false) as Label
	if intent_lbl == null: return
	if intent.size() == 0:
		intent_lbl.text = "Auto-resolving..."
		return
	var text := "Enemy: "
	if intent.get("type","single") == "dual":
		var opts: Array = intent.get("options",[])
		text += "???" if opts.size() == 1 else " or ".join(opts)
	else:
		text += str(intent.get("selected","?")).to_upper()
	intent_lbl.text = text

func _on_player_turn(options: Array) -> void:
	_clear_attack_grid()
	var grid := find_child("AttackGrid", true, false) as GridContainer
	if grid == null: return
	for option in options:
		var btn := Button.new()
		btn.text = "%s\n%s" % [option.name, option.desc]
		btn.custom_minimum_size = Vector2(100, 50)
		btn.pressed.connect(_on_attack_selected.bind(option.id))
		grid.add_child(btn)



func _on_attack_selected(attack_id: String) -> void:
	_clear_attack_grid()
	if _ce: _ce.execute_player_attack(attack_id)

func _clear_attack_grid() -> void:
	var grid := find_child("AttackGrid", true, false) as GridContainer
	if grid:
		for child in grid.get_children():
			child.queue_free()

func _show_wave_result(won: bool, perfect: bool, reward: float, drop: Dictionary) -> void:
	# Build small result banner inside combat view
	var banner_parent: Control = find_child("ResultBanner", true, false)
	if banner_parent == null: return
	for child in banner_parent.get_children():
		child.queue_free()
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if perfect:
		label.text = "✦ PERFECT! +%.0f DC" % reward
		label.add_theme_color_override("font_color", Color(1.0,0.85,0.2))
	elif won:
		label.text = "Victory! +%.0f DC" % reward
		label.add_theme_color_override("font_color", Color(0.4,0.9,0.5))
	else:
		label.text = "Defeated! Wave %d again" % current_wave
		label.add_theme_color_override("font_color", Color(0.9,0.35,0.35))
	banner_parent.add_child(label)
	if not drop.is_empty():
		var drop_lbl := Label.new()
		drop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		drop_lbl.add_theme_font_size_override("font_size", 13)
		drop_lbl.add_theme_color_override("font_color", Color(0.9,0.8,0.5))
		drop_lbl.text = "Drop: %s [%s]" % [drop.get("name","Item"), drop.get("rarity","?").capitalize()]
		banner_parent.add_child(drop_lbl)
	banner_parent.visible = true
	
	# Auto-hide after 5 seconds
	var timer = get_tree().create_timer(5.0)
	timer.timeout.connect(func(): 
		if banner_parent: banner_parent.visible = false
	)
	
	# Re-enable start button
	if _start_wave_btn:
		_start_wave_btn.disabled = false
		_start_wave_btn.text = "Start Wave %d" % current_wave
	_update_wave_label()

func _update_wave_label() -> void:
	if _wave_label:
		var wave_id = "wave_%d" % current_wave
		var best_sub = 0
		if _gm and _gm.get("wave_mastery"):
			var wave_data = _gm.wave_mastery.get(wave_id, {})
			if wave_data is Dictionary:
				best_sub = wave_data.get("best_subwave", 1)
			else:
				# Migration if it was just an int
				best_sub = int(wave_data)
		
		_wave_label.text = "Wave %d - Subwave %d (Best: %d)" % [current_wave, current_subwave, best_sub]
	
	var mastery_count = 0
	if _gm:
		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, 0)
		if wave_data is Dictionary:
			mastery_count = int(wave_data.get("mastery", 0))
		else:
			mastery_count = int(wave_data)
	if _mastery_label:
		_mastery_label.text = "Mastery: %d/10" % mastery_count
		_mastery_label.modulate = Color(1, 0.9, 0) if mastery_count >= 10 else Color(0.6, 0.8, 1, 0.8)

	if _start_wave_btn:
		_start_wave_btn.text = "Start Wave %d" % current_wave
		_start_wave_btn.modulate = Color.WHITE

	# Wave Cap tied to Depth
	var max_allowed_wave = 10
	if _gm:
		max_allowed_wave = maxi(_gm.max_depth_reached * 10, 10)
	
	if current_wave > max_allowed_wave:
		current_wave = max_allowed_wave
		if _wave_label: _wave_label.text = "Wave %d (CAP)" % current_wave

	if _prev_wave_btn:
		_prev_wave_btn.disabled = (current_wave <= 1)
	if _next_wave_btn:
		var has_reached_next = current_wave < highest_wave_reached
		var can_reach_next = current_wave < max_allowed_wave
		_next_wave_btn.disabled = not (has_reached_next and can_reach_next)
	
	if _start_wave_btn and current_wave > max_allowed_wave:
		_start_wave_btn.disabled = true
		_start_wave_btn.text = "Depth Too Low"

func _calculate_drop_rarity_v2(wave: int, subwave: int) -> String:
	var roll = randf()
	# Every 10 subwaves increases rarity quality by shift-factor
	var quality_boost = float(subwave) / 50.0 # 2% per 10 subwaves
	
	if wave >= 40:
		if roll < 0.10 + quality_boost: return "god_tier"
		if roll < 0.30 + quality_boost: return "legendary"
		if roll < 0.70 + quality_boost: return "epic"
		return "rare"
	elif wave >= 21:
		if roll < 0.05 + quality_boost: return "legendary"
		if roll < 0.20 + quality_boost: return "epic"
		if roll < 0.60 + quality_boost: return "rare"
		return "uncommon"
	elif wave >= 11:
		if roll < 0.10 + quality_boost: return "epic"
		if roll < 0.30 + quality_boost: return "rare"
		if roll < 0.70 + quality_boost: return "uncommon"
		return "common"
	else:
		if roll < 0.20 + quality_boost: return "rare"
		if roll < 0.50 + quality_boost: return "uncommon"
		return "common"

func _on_prev_wave_pressed() -> void:
	if current_wave > 1:
		var was_auto = _is_smooth_looping
		if _wave_in_progress:
			_cancel_current_combat()
		current_wave -= 1
		current_subwave = 1
		_is_manual_wave = true
		_update_wave_label()
		if was_auto: _on_start_wave_pressed()

func _on_next_wave_pressed() -> void:
	if current_wave < highest_wave_reached:
		var was_auto = _is_smooth_looping
		if _wave_in_progress:
			_cancel_current_combat()
		current_wave += 1
		current_subwave = 1
		_is_manual_wave = true
		_update_wave_label()
		if was_auto: _on_start_wave_pressed()

func _cancel_current_combat() -> void:
	_wave_in_progress = false
	if _is_smooth_looping:
		_stop_smooth_auto_battle()
	if _ce:
		_ce.active = false
	_clear_attack_grid()
	if _start_wave_btn:
		_start_wave_btn.disabled = false
		_start_wave_btn.text = "Start Wave %d" % current_wave

# ── Equipment View ─────────────────────────────────────────────────────────────
func _refresh_equipment_view() -> void:
	if _em == null: return
	var slots_box := find_child("EquipSlotsBox", true, false)
	if slots_box:
		for child in slots_box.get_children():
			child.queue_free()
		
		# Create a grid for slots
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 30)
		grid.add_theme_constant_override("v_separation", 25)
		slots_box.add_child(grid)
		
		for slot_name in ["weapon","armor","amulet","ring1","helmet","talisman"]:
			var slot_panel := PanelContainer.new()
			slot_panel.custom_minimum_size = Vector2(100, 100)
			
			var item = _em.equipped.get(slot_name, null)
			
			# Background tech/dreamy style
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.08, 0.08, 0.12, 0.9)
			sb.set_border_width_all(3)
			var rarity = item.get("rarity", "common") if item else "none"
			match rarity:
				"common": sb.border_color = Color(0.4, 0.4, 0.4)
				"uncommon": sb.border_color = Color(0.2, 0.8, 0.2)
				"rare": sb.border_color = Color(0.2, 0.4, 1.0)
				"epic": sb.border_color = Color(0.6, 0.2, 1.0)
				"legendary": sb.border_color = Color(1.0, 0.8, 0.2)
				_: sb.border_color = Color(0.15, 0.15, 0.2)
			
			slot_panel.add_theme_stylebox_override("panel", sb)
			
			var vbx := VBoxContainer.new()
			vbx.alignment = BoxContainer.ALIGNMENT_CENTER
			
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(ICONS[slot_name])
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(50, 50)
			if item == null: icon_rect.modulate.a = 0.2
			vbx.add_child(icon_rect)
			
			var name_lbl := Label.new()
			name_lbl.text = slot_name.capitalize()
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 11)
			vbx.add_child(name_lbl)
			
			slot_panel.add_child(vbx)
			
			if item:
				var _it = item # capture for lambda
				slot_panel.mouse_entered.connect(func(): _show_custom_tooltip(slot_panel, _it))
				slot_panel.mouse_exited.connect(func(): _hide_custom_tooltip())
				_set_item_tooltip(slot_panel, item) # Fallback
			
			grid.add_child(slot_panel)
		
		_refresh_total_stats()
	
	var inv_box := find_child("InventoryBox", true, false)
	if inv_box:
		for child in inv_box.get_children():
			child.queue_free()
		
		# 6-Column Grid for Categories
		var categories_grid := GridContainer.new()
		categories_grid.columns = 3
		categories_grid.add_theme_constant_override("h_separation", 20)
		categories_grid.add_theme_constant_override("v_separation", 20)
		categories_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inv_box.add_child(categories_grid)
		
		var slots = ["weapon","armor","amulet","ring1","helmet","talisman"]
		var slot_groups := {}
		for s in slots:
			var container := VBoxContainer.new()
			container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var hdr := Label.new()
			hdr.text = s.capitalize()
			hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			container.add_child(hdr)
			container.add_child(HSeparator.new())
			
			categories_grid.add_child(container)
			slot_groups[s] = container
			
		for idx in range(_em.inventory.size()):
			var item: Dictionary = _em.inventory[idx]
			var _it = item # capture for lambda
			var slot = item.get("slot", "weapon")
			var target_vbox = slot_groups.get(slot, slot_groups["weapon"])
			
			var row := HBoxContainer.new()
			
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(ICONS.get(slot, ICONS.weapon))
			icon_rect.custom_minimum_size = Vector2(24, 24)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			row.add_child(icon_rect)
			
			var name_lbl := Label.new()
			# Add shorthand stats: [A:10 H:20]
			var stats = item.get("stats", {})
			var shorthand = ""
			if stats.has("attack"): shorthand += "A:%.1f " % (stats.attack * (1.0 + item.get("level",1)*0.05))
			if stats.has("hp"):     shorthand += "H:%.1f " % (stats.hp * (1.0 + item.get("level",1)*0.05))
			
			name_lbl.text = "%s [%s]" % [item.get("name","?"), shorthand.strip_edges()]
			name_lbl.add_theme_font_size_override("font_size", 14)
			var rarity_color = _get_rarity_color(item.get("rarity","common"))
			name_lbl.add_theme_color_override("font_color", rarity_color)
			name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
			row.add_child(name_lbl)
			
			var dismantle_btn := Button.new()
			dismantle_btn.text = "Dismantle"
			dismantle_btn.custom_minimum_size = Vector2(80, 24)
			dismantle_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
			dismantle_btn.pressed.connect(_on_dismantle_item.bind(idx))
			dismantle_btn.mouse_entered.connect(func(): _show_custom_tooltip(row, _it))
			dismantle_btn.mouse_exited.connect(func(): _hide_custom_tooltip())
			row.add_child(dismantle_btn)
			
			var e_btn := Button.new()
			e_btn.text = "Equip"
			e_btn.custom_minimum_size = Vector2(60, 24)
			e_btn.pressed.connect(_on_equip_item.bind(idx))
			e_btn.mouse_entered.connect(func(): _show_custom_tooltip(row, _it))
			e_btn.mouse_exited.connect(func(): _hide_custom_tooltip())
			row.add_child(e_btn)
			
			target_vbox.add_child(row)

func _on_dismantle_item(idx: int) -> void:
	if _em == null: return
	var _reward = _em.dismantle_item(idx)
	if _gm: 
		_gm._refresh_top_ui()
		_gm.save_game()
	_refresh_equipment_view()

func _on_equip_item(idx: int) -> void:
	if _em == null or idx >= _em.inventory.size(): return
	var item: Dictionary = _em.inventory[idx]
	var slot: String = item.get("slot", "weapon")
	if _em.equipped[slot] != null:
		_em.inventory.append(_em.equipped[slot])  # swap old back to inventory
	_em.equipped[slot] = item
	_em.inventory.remove_at(idx)
	if _gm: _gm.save_game()
	_refresh_equipment_view()

# ── Forge View ─────────────────────────────────────────────────────────────────
func _refresh_forge_view() -> void:
	var info_lbl := find_child("ForgeInfoLbl", true, false) as Label
	if info_lbl:
		var dc: float = _gm.dreamcloud if _gm else 0.0
		info_lbl.text = "Dreamcloud: %.0f\nSelect 3 same-rarity items to Fuse" % dc
	_refresh_forge_inventory()

func _refresh_forge_inventory() -> void:
	var forge_inv := find_child("ForgeInventoryBox", true, false)
	if forge_inv == null or _em == null: return
	for child in forge_inv.get_children():
		child.queue_free()
	
	# 1. Level Up section
	var lvl_hdr := Label.new()
	lvl_hdr.text = "— Level Up Equipped Items —"
	lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_inv.add_child(lvl_hdr)
	
	for slot in _em.equipped.keys():
		var item = _em.equipped[slot]
		if item == null: continue
		var row := HBoxContainer.new()
		
		var icon_rect := TextureRect.new()
		icon_rect.texture = load(ICONS.get(slot, ICONS.weapon))
		icon_rect.custom_minimum_size = Vector2(32, 32)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon_rect)
		
		var lbl := Label.new()
		lbl.text = " %s [Lv%d/%d]" % [item.get("name","?"), item.get("level",1), item.get("max_level",10)]
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		row.add_child(lbl)
		
		_set_item_tooltip(row, item)
		
		var lvlup_btn := Button.new()
		var cost: int = int(item.get("level", 1)) * 100
		lvlup_btn.text = "Lv+ (%d DC)" % cost
		lvlup_btn.custom_minimum_size = Vector2(100, 28)
		if _gm and _gm.dreamcloud < cost: lvlup_btn.disabled = true
		if item.get("level",1) >= item.get("max_level",10):
			lvlup_btn.disabled = true
			lvlup_btn.text = "MAX"
		lvlup_btn.pressed.connect(_on_level_up_item.bind(slot))
		row.add_child(lvlup_btn)
		forge_inv.add_child(row)
	
	forge_inv.add_child(HSeparator.new())
	
	# 2. Fusion section
	var fuse_hdr := Label.new()
	fuse_hdr.text = "— Fusion (3 Max-Level same-rarity/slot items) —"
	fuse_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	forge_inv.add_child(fuse_hdr)
	
	var pools := {} # rarity_slot -> [indices]
	for i in range(_em.inventory.size()):
		var it: Dictionary = _em.inventory[i]
		if it.get("level",1) >= it.get("max_level",10):
			var key = "%s_%s" % [it.get("rarity","common"), it.get("slot","weapon")]
			if not pools.has(key): pools[key] = []
			pools[key].append(i)
	
	var found_fuse := false
	for key in pools.keys():
		var indices: Array = pools[key]
		if indices.size() >= 3:
			found_fuse = true
			var first_item = _em.inventory[indices[0]]
			var row := HBoxContainer.new()
			var lbl := Label.new()
			lbl.text = "3x %s %s" % [first_item.rarity.capitalize(), first_item.slot.capitalize()]
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(lbl)
			
			var fuse_btn := Button.new()
			var cost: int = int(_em.call("_get_fusion_cost", first_item.rarity))
			fuse_btn.text = "Fuse (%d DC)" % cost
			fuse_btn.custom_minimum_size = Vector2(120, 28)
			if _gm and _gm.dreamcloud < cost: fuse_btn.disabled = true
			fuse_btn.pressed.connect(_on_fuse_pressed.bind(indices[0], indices[1], indices[2]))
			row.add_child(fuse_btn)
			forge_inv.add_child(row)
	
	if not found_fuse:
		var none_lbl := Label.new()
		none_lbl.text = "No items ready for fusion (Need 3 max-level same-type items in inventory)"
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_lbl.add_theme_font_size_override("font_size", 12)
		none_lbl.modulate.a = 0.6
		forge_inv.add_child(none_lbl)

func _on_level_up_item(slot: String) -> void:
	if _em == null or _gm == null: return
	if _em.level_up_item(slot):
		_gm._refresh_top_ui() # Update currency display
		_gm.save_game()
		_refresh_forge_view()

func _on_fuse_pressed(idx1: int, idx2: int, idx3: int) -> void:
	if _em == null or _gm == null: return
	# Get items
	var items = [_em.inventory[idx1], _em.inventory[idx2], _em.inventory[idx3]]
	var new_item = _em.fuse_items(items[0], items[1], items[2])
	if not new_item.is_empty():
		# Success! fuse_items already deducted cost. 
		# Remove old items (higher indices first to keep remaining indices valid)
		var sort_indices = [idx1, idx2, idx3]
		sort_indices.sort()
		_em.inventory.remove_at(sort_indices[2])
		_em.inventory.remove_at(sort_indices[1])
		_em.inventory.remove_at(sort_indices[0])
		
		# Add new item
		_em.inventory.append(new_item)
		
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()

func _set_item_tooltip(node: Control, item: Dictionary) -> void:
	# Keep basic fallback tooltips just in case
	var text = "[%s] %s (Lv %d)\n" % [item.rarity.capitalize(), item.name, item.level]
	var stats = item.get("stats", {})
	if stats.has("attack"): text += "• Attack: +%.1f\n" % stats.attack
	if stats.has("hp"):     text += "• HP: +%.1f\n" % stats.hp
	if stats.has("defense"): text += "• Defense: +%.1f\n" % stats.defense
	
	var s_stats = item.get("secondary_stats", {})
	for k in s_stats.keys():
		text += "• %s: +%.1f%%\n" % [k.replace("_mult","").capitalize(), s_stats[k]*100.0]
		
	node.tooltip_text = text

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"uncommon": return Color(0.3, 1.0, 0.3)
		"rare": return Color(0.3, 0.6, 1.0)
		"epic": return Color(0.8, 0.3, 1.0)
		"legendary": return Color(1.0, 0.8, 0.2)
		"mythic": return Color(1.0, 0.2, 0.4)
	return Color.WHITE

func _show_custom_tooltip(node: Control, item: Dictionary) -> void:
	var tip := find_child("CustomTooltip", true, false) as PanelContainer
	if not tip: return
	
	var title := tip.find_child("Title", true, false) as Label
	var stats_lbl := tip.find_child("Stats", true, false) as RichTextLabel
	
	if title:
		title.text = "[%s] %s (Lv %d)" % [item.get("rarity","common").capitalize(), item.get("name","?"), item.get("level",1)]
		title.add_theme_color_override("font_color", _get_rarity_color(item.get("rarity","common")))
		
	if stats_lbl:
		var s_text = "[color=#cccccc]"
		var stats = item.get("stats", {})
		
		# COMPARISON LOGIC
		var slot = item.get("slot", "weapon")
		var equipped_item = _em.equipped.get(slot)
		var e_stats = equipped_item.get("stats", {}) if equipped_item else {}
		
		var stat_keys = ["attack", "hp", "defense"]
		var lv_mult = 1.0 + (item.get("level", 1) * 0.05)
		for key in stat_keys:
			if stats.has(key):
				var val = stats[key] * lv_mult
				# Base stat for comparison
				var e_val = 0.0
				if equipped_item:
					var e_lv_mult = 1.0 + (equipped_item.get("level", 1) * 0.05)
					e_val = e_stats.get(key, 0.0) * e_lv_mult
				
				var diff = val - e_val
				var diff_str = ""
				if equipped_item and diff != 0:
					var d_color = "00ffaa" if diff > 0 else "ff5555"
					diff_str = " ([color=#%s]%s%.1f[/color])" % [d_color, "+" if diff > 0 else "", diff]
				
				s_text += "• %s: +%.1f%s\n" % [key.capitalize(), val, diff_str]
		
		# Secondary Stats in Tooltip
		var sec_stats = item.get("secondary_stats", {})
		if not sec_stats.is_empty():
			s_text += "\n[i]Utility Bonuses:[/i]\n"
			var e_sec = equipped_item.get("secondary_stats", {}) if equipped_item else {}
			for k in sec_stats.keys():
				var val = sec_stats[k] * 100.0
				var e_val = e_sec.get(k, 0.0) * 100.0
				var diff = val - e_val
				var diff_str = ""
				if equipped_item and diff != 0:
					var d_color = "00ffaa" if diff > 0 else "ff5555"
					diff_str = " ([color=#%s]%s%.1f%%[/color])" % [d_color, "+" if diff > 0 else "", diff]
				s_text += "• %s: +%.1f%%%s\n" % [k.replace("_mult","").capitalize(), val, diff_str]

		s_text += "[/color]"
		stats_lbl.text = s_text

	tip.visible = true
	# Position tip near the node
	var viewport_pos = node.get_global_position()
	tip.global_position = viewport_pos + Vector2(110, 0)
	# Snap inside bounds
	if tip.global_position.x + tip.size.x > get_viewport_rect().size.x:
		tip.global_position.x = viewport_pos.x - tip.size.x - 10

func _hide_custom_tooltip() -> void:
	var tip := find_child("CustomTooltip", true, false) as PanelContainer
	if tip: tip.visible = false

func _refresh_total_stats() -> void:
	if not _total_stats_lbl or not _em: return
	
	var c_stats = _em.get_player_combat_stats()
	var u_stats = _em.get_total_secondary_bonuses()
	
	var text = "[center][b]Combat Focus[/b][/center]\n"
	text += "• ATK: [color=#ffcc55]%.1f[/color]\n" % c_stats.attack
	text += "• HP: [color=#55ffaa]%.1f[/color]\n" % c_stats.max_hp
	text += "• DEF: [color=#55aaff]%.1f[/color]\n" % c_stats.defense
	
	text += "\n[center][b]Utility Bonuses[/b][/center]\n"
	text += "• Thoughts: [color=#ff88ff]+%.1f%%[/color]\n" % (u_stats.thoughts_mult * 100.0)
	text += "• Crystals: [color=#88ffff]+%.1f%%[/color]\n" % (u_stats.crystals_mult * 100.0)
	text += "• Memories: [color=#ffff88]+%.1f%%[/color]\n" % (u_stats.memories_mult * 100.0)
	
	_total_stats_lbl.text = text
