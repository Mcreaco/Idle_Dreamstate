extends PanelContainer

# ── State ──────────────────────────────────────────────────────────────────────
var current_wave: int = 1
var current_subwave: int = 1
var highest_wave_reached: int = 1
var _wave_in_progress: bool = false
var _selected_item_ref: Dictionary = {}
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
@onready var _combat_bg: TextureRect = find_child("CombatBackground", true, false)
@onready var _attack_grid: GridContainer = find_child("AttackGrid", true, false)

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

const EDGE_BLEND_SHADER = """
shader_type canvas_item;
uniform float softness : hint_range(0.0, 1.0) = 0.6;
uniform float falloff_power : hint_range(1.0, 10.0) = 2.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 2.0; 
	// Use a power-based falloff for a very soft "stretched" look
	float alpha = clamp(1.0 - pow(dist, falloff_power), 0.0, 1.0);
	vec4 color = texture(TEXTURE, UV);
	color.a *= alpha;
	COLOR = color;
}
"""

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
		_ce.message_logged.connect(_on_message_logged)
		_ce.turn_started.connect(_on_turn_update)
		_ce.intent_revealed.connect(_on_intent_revealed)
		_ce.player_turn.connect(_on_player_turn)
	
	_setup_hp_bar_styles()
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
	# Proactively start if auto-battle is on and we just opened
	if auto_battle_active and not _wave_in_progress:
		_on_start_wave_pressed()

func _on_start_wave_pressed() -> void:
	if _wave_in_progress or _ce == null:
		return
	
	_clear_attack_grid() # Extra safety cleanup
	_wave_in_progress = true
	if _start_wave_btn:
		_start_wave_btn.disabled = true
	
	# 1. Overpower Check for Smooth Auto-battle
	var enemy: Dictionary = _build_enemy_for_wave(current_wave)
	var p_stats: Dictionary = _em.get_player_combat_stats() if _em != null else {"attack": 10.0, "max_hp": 100.0, "defense": 5.0}
	
	# 1. Indestructible Check (Defense > 2x Enemy MAX possible attack)
	var is_overpowered = (p_stats.defense > enemy.attack * 2.0)
	
	# Atmospheric Background Shift (Apply BEFORE auto-battle check)
	_apply_depth_atmosphere(current_wave)

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
	
	# Start Thought Particles
	_start_thought_particles()

func _apply_depth_atmosphere(wave: int) -> void:
	var depth = clampi(int(float(wave - 1) / 10.0) + 1, 1, 15)
	
	# Update Background Texture
	if _combat_bg:
		var bg_names = [
			"shallow.png", "descent.png", "pressure.png", "murk.png", "rift.png",
			"hollow.png", "dread.png", "chasm.png", "silence.png", "veil.png",
			"ruin.png", "eclipse.png", "voidline.png", "blackwater.png", "abyss.png"
		]
		var bg_file = bg_names[depth - 1]
		var bg_path = "res://UI/DepthBarBG/" + bg_file
		if FileAccess.file_exists(bg_path):
			_combat_bg.texture = load(bg_path)
			_combat_bg.visible = true
	
	var content_area = find_child("ContentArea", true, false) as Control
	if content_area:
		# Shift background color based on depth
		var bg_color = _get_depth_color(depth)
		var style = content_area.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			style = StyleBoxFlat.new()
			content_area.add_theme_stylebox_override("panel", style)
		
		# Animate background color shift
		var tween = create_tween()
		tween.tween_property(style, "bg_color", bg_color, 1.5).set_trans(Tween.TRANS_SINE)

func _get_depth_color(depth: int) -> Color:
	match depth:
		1: return Color(0.04, 0.08, 0.15, 0.95) # Shallows
		2: return Color(0.06, 0.06, 0.1, 0.95)  # Descent
		3: return Color(0.08, 0.04, 0.08, 0.95) # Pressure
		# ... continue for other depths
		15: return Color(0.02, 0.01, 0.03, 0.98) # Abyss
		_:
			# General darkened interpolation
			var factor = float(depth) / 15.0
			return Color(0.04, 0.05, 0.09).lerp(Color(0.01, 0.01, 0.02), factor)

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
		await get_tree().create_timer(1.5).timeout
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
		_update_combat_ui_for_start(ps, ed)
		
		if _smooth_bar:
			_smooth_bar.value = 0
			var tween = create_tween()
			tween.tween_property(_smooth_bar, "value", 100, battle_time) 
			await tween.finished
		else:
			await get_tree().create_timer(battle_time).timeout
			
		_give_smooth_rewards()
		# REMOVED double increment: current_subwave += 1
		_update_wave_label()
		
		# EFFICIENCY CHECK: Exit if enemy attack is too high relative to your defense
		# User formula: ed.attack > 0.5 * ps.defense
		if ed.attack > 0.5 * ps.defense:
			print("SMOOTH LOOP: Efficiency threshold reached (Enemy ATK > 0.5 * Player DEF), dropping to manual combat.")
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
		
		# UNLOCK NEXT WAVE: Only if mastery >= 10
		if wave_data.mastery >= 10:
			highest_wave_reached = maxi(highest_wave_reached, wave + 1)

		# Drop Check
		var drop_chance = 0.05 * (1.0 + (subwave * 0.05))
		if randf() < drop_chance:
			var rarity = _calculate_drop_rarity_v2(wave, subwave)
			var item = _em.generate_item(rarity, ["weapon","armor","amulet","ring1","helmet","talisman"].pick_random(), wave)
			_em.inventory.append(item)
			_add_reward_item(item.name, item.rarity.capitalize(), _get_item_icon_path(item, item.slot))
			print("SMOOTH DROP: ", item.name, " (", rarity, ")")
		
		_add_reward_item("Dreamclouds", "+%d" % reward, "")
		
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
	
	# BUG FIX: If auto-battle is active, immediately start normal combat to avoid black screen/stuck state
	if auto_battle_active and visible:
		_on_start_wave_pressed()

const ENEMY_NAMES = [
	"Cloud Sheep", "Wisp of Thought", "Bubble Elf", "Cotton Moth", "Pastel Spark", "Floating Petal", "Silk Butterfly", "Pale Dragonfly", "Shallows Wisp", "Dream Lamb",
	"Heavy Pebble", "Falling Spore", "Lead Dove", "Gravity Mote", "Sinking Sensation", "Weight of Sleep", "Plummeting Star", "Anchored Hope", "Downward Spiral", "Deepening Echo",
	"Iron Lung", "Crushed Echo", "Heavy Mist", "Compacted Fear", "Pressure Valve", "Steel Shell", "Weighted Breath", "Tight Grip", "Bone Cruncher", "Deep Pressure",
	"Bog Creeper", "Fog Stalker", "Mossy Eye", "Mud Sprite", "Murk Dweller", "Drip Geist", "Sludge Shambler", "Reedy Wraith", "Damp Shadow", "Lord of Murk",
	"Spark Geist", "Rift Lizard", "Static Wraith", "Fissure Imp", "Cracked Memory", "Arc Spirit", "Jolt Spectre", "Energy Flare", "Split Ego", "Rift Guardian",
	"Bone Flute", "Empty Garb", "Echoing Skull", "Hollow Shell", "Dust Shuck", "Brittle Soul", "Scraped Mind", "Ivory Ghoul", "Vacant Stare", "Hollow King",
	"Gnasher", "Fear Eater", "Wide-Eyed Stalker", "Panic Pulse", "Shiver", "Cold Sweat", "Heartbeat Horror", "Jagged Edge", "Terrifying Truth", "Peak of Dread",
	"Spike Crawler", "Chasm Bat", "Deep Dweller", "Abyss Fisher", "Void Needle", "Razor Shadow", "Pit Lurker", "Falling Scream", "Chasm Maw", "Guardian of the Gap",
	"Bound Whisper", "Gauze Spirit", "Muffled Scream", "Quiet Ripper", "Stitched Mouth", "Deafening Stillness", "Silent Stalker", "Wrapped Guilt", "Hush", "Warden of Silence",
	"Lace Phantom", "Veiled Maiden", "Mist Weaver", "Gossamer Geist", "Shroud Stalker", "Hidden Heart", "Translucent Terror", "Fading Face", "Veil Ripper", "Queen of the Veil",
	"Rusted Knight", "Broken Idol", "Crumbling Wall", "Decay Sprite", "Shattered Mirror", "Ruined Hope", "Fallen Pillar", "Corroded Core", "Dust Sentinel", "Architect of Ruin",
	"Solar Shadow", "Lunar Wisp", "Eclipse Eye", "Black Sun Remnant", "Corona Ghoul", "Twilight Terror", "Umbra Elemental", "Starless Void", "Celestial Husk", "Eclipse Lord",
	"Cube Entity", "Glitch Ghost", "Vector Horror", "Polygon Prowler", "Binary Beast", "Broken Logic", "Abstract Aggression", "Vertex Void", "Static Man", "Error Source",
	"Ink Tentacle", "Drowned Soul", "Black Tide", "Murky Hand", "Tar Spectre", "Fluid Fear", "Abyssal Current", "Pressure Beast", "Inky Depth", "Lord of Water",
	"The Unmaker", "Abyss Crawler", "Final Regret", "Singularity", "End of Days", "Total Oblivion", "Waking Nightmare", "The Void Caller", "Shattered Infinity", "DREAMER'S END"
]

func _build_enemy_for_wave(wave: int) -> Dictionary:
	var subwave_mult := 1.0 + ((current_subwave - 1) * 0.1)
	var hp   := (30.0 + float(wave) * 15.0) * subwave_mult
	var atk  := (4.0  + float(wave) * 2.5) * subwave_mult
	var def_ := (1.0  + float(wave) * 1.2) * subwave_mult
	
	# Lookup name from the 150 unique list
	var enemy_idx = clampi(wave - 1, 0, ENEMY_NAMES.size() - 1)
	var enemy_name = ENEMY_NAMES[enemy_idx]
	
	# 1. Visual "Darkness" based on Wave progress
	var darkness = clampf(float(wave) / 150.0, 0.0, 1.0)
	
	# 2. Dynamic Sprite Lookup
	var sprite_path = "res://assets/combat/enemy_%d.png" % wave
	if not FileAccess.file_exists(sprite_path):
		# Fallback to depth-based sprites
		var depth = clampi(int(float(wave - 1) / 10.0) + 1, 1, 15)
		if depth >= 10: sprite_path = SPRITES["nightmare"]
		elif depth >= 5: sprite_path = SPRITES["shadow"]
		else: sprite_path = SPRITES["sheep"]
	
	return {
		"name":    "%s (%d-%d)" % [enemy_name, wave, current_subwave],
		"hp":      hp,
		"attack":  atk,
		"defense": def_,
		"wave":    wave,
		"subwave": current_subwave,
		"sprite":  sprite_path,
		"darkness": darkness
	}

func _on_wave_ended(result: Dictionary) -> void:
	print("[COMBAT] Wave ended handler triggered. Won: ", result.get("won", false))
	_wave_in_progress = false
	if _ce: _ce.active = false # Force engine state reset
	var won: bool = result.get("won", false)
	var perfect: bool = result.get("perfect", false)
	var wave: int = result.get("depth", current_wave)
	
	# Don't disconnect persistent signals here anymore
	
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
			if not (_gm.get("wave_mastery") is Dictionary):
				_gm.set("wave_mastery", {})
			var wave_id = "wave_%d" % current_wave
			var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
			if not (wave_data is Dictionary):
				wave_data = {"mastery": int(wave_data), "best_subwave": 0}
			
			wave_data.mastery = int(wave_data.get("mastery", 0)) + 1
			wave_data.best_subwave = maxi(int(wave_data.get("best_subwave", 0)), current_subwave)
			_gm.wave_mastery[wave_id] = wave_data
			
			# UNLOCK NEXT WAVE: Only if mastery for current wave is >= 10
			if wave_data.mastery >= 10:
				highest_wave_reached = maxi(highest_wave_reached, current_wave + 1)
		
		# Auto-advance handled in _on_wave_ended to avoid conflicts
		current_subwave += 1
		_update_wave_label() # Refresh display
		_show_wave_result(true, perfect, reward, result.get("drop", {}))
		
		# In subwave mode, we don't automatically jump to the next BASE wave
		# The player manually chooses Wave X, and stays in it climbing subwaves.
		
		# AUTO-ADVANCE: Reset or move to next wave
		if auto_battle_active and visible:
			var cur_mastery = 0
			if _gm:
				var w_id = "wave_%d" % current_wave
				var w_data = _gm.wave_mastery.get(w_id, {"mastery": 0})
				cur_mastery = int(w_data.get("mastery", 0)) if w_data is Dictionary else int(w_data)

			if cur_mastery >= 10 and current_wave < highest_wave_reached:
				current_wave += 1
				_update_wave_label()
			
			var timer = get_tree().create_timer(1.2)
			timer.timeout.connect(func():
				if visible and not _wave_in_progress:
					print("[COMBAT] Auto-starting next combat (Manual Victory Path)...")
					call_deferred("_on_start_wave_pressed")
				else:
					print("[COMBAT] Auto-start skipped: visible=%s, in_progress=%s" % [visible, _wave_in_progress])
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
		
		# Apply edge blend shader
		var mat = ShaderMaterial.new()
		var sh = Shader.new()
		sh.code = EDGE_BLEND_SHADER
		mat.shader = sh
		sprite_rect.material = mat

	if _attack_grid:
		_attack_grid.visible = true

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

	# Overhaul Aesthetics
	_apply_overhaul_aesthetics(enemy_data)

func _apply_overhaul_aesthetics(enemy_data: Dictionary) -> void:
	var darkness = enemy_data.get("darkness", 0.0)
	var p_panel = find_child("PlayerStatsPanel", true, false) as PanelContainer
	var e_panel = find_child("EnemyStatsPanel", true, false) as PanelContainer
	
	# Premium border color shifting from Cyan (light) to Deep Purple/Red (dark)
	var color_a = Color(0.1, 0.8, 1.0, 1.0) # Light Dream
	var color_b = Color(0.8, 0.0, 0.3, 1.0) # Nightmare
	var current_border = color_a.lerp(color_b, darkness)
	
	var p_sb = _get_glass_style(Color(0, 0.7, 0.9, 0.6))
	var e_sb = _get_glass_style(current_border)
	
	if p_panel: p_panel.add_theme_stylebox_override("panel", p_sb)
	if e_panel: e_panel.add_theme_stylebox_override("panel", e_sb)
	
	# Sprite Modulate & Texture
	var enemy_sprite = find_child("EnemySprite", true, false) as TextureRect
	if enemy_sprite:
		# Update Texture if changed
		if enemy_data.has("sprite"):
			var tex_path = enemy_data.sprite
			if enemy_sprite.texture == null or enemy_sprite.texture.resource_path != tex_path:
				enemy_sprite.texture = load(tex_path)
		
		# Gradually darken and tint the enemy
		var tint = Color(1.0, 1.0, 1.0).lerp(Color(0.4, 0.2, 0.5), darkness)
		enemy_sprite.modulate = tint

	# Floating Animation
	if p_panel and not p_panel.has_meta("animating"):
		p_panel.set_meta("animating", true)
		_animate_float(p_panel, randf() * 2.0)
	if e_panel and not e_panel.has_meta("animating"):
		e_panel.set_meta("animating", true)
		_animate_float(e_panel, randf() * 2.0)

func _get_glass_style(border_color: Color) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.08, 0.85)
	sb.set_border_width_all(2)
	sb.border_color = border_color
	sb.set_corner_radius_all(4)
	# Subtle outer glow
	sb.shadow_color = border_color
	sb.shadow_color.a = 0.3
	sb.shadow_size = 4
	return sb

func _animate_float(node: Control, delay: float) -> void:
	var tween = create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	var start_pos = node.position
	tween.tween_property(node, "position:y", start_pos.y - 5.0, 2.0).set_ease(Tween.EASE_IN_OUT).set_delay(delay)
	tween.tween_property(node, "position:y", start_pos.y, 2.0).set_ease(Tween.EASE_IN_OUT)

func _on_hp_changed(p_hp: float, e_hp: float) -> void:
	var player_hp_bar := find_child("PlayerHpBar", true, false) as ProgressBar
	var enemy_hp_bar  := find_child("EnemyHpBar",  true, false) as ProgressBar
	if player_hp_bar: player_hp_bar.value = p_hp
	if enemy_hp_bar:  enemy_hp_bar.value  = e_hp
	if not _p_stats.is_empty():
		_update_stats_panel(_p_stats, _e_data)

func _setup_hp_bar_styles() -> void:
	var php = find_child("PlayerHpBar", true, false) as ProgressBar
	var ehp = find_child("EnemyHpBar", true, false) as ProgressBar
	
	if php:
		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.1, 0.1, 0.15, 0.5)
		sb_bg.set_border_width_all(1)
		sb_bg.border_color = Color(0.2, 0.2, 0.3)
		php.add_theme_stylebox_override("background", sb_bg)
		
		var sb_fg = StyleBoxFlat.new()
		sb_fg.bg_color = Color(1.0, 0.4, 0.7) # Pinkish
		sb_fg.border_color = Color(0.4, 0.9, 1.0) # Cyan border
		sb_fg.set_border_width_all(1)
		# Subtle gradient effect via shadow
		sb_fg.shadow_color = Color(0.4, 0.9, 1.0, 0.4)
		sb_fg.shadow_size = 4
		php.add_theme_stylebox_override("fill", sb_fg)

	if ehp:
		var sb_bg = StyleBoxFlat.new()
		sb_bg.bg_color = Color(0.1, 0.1, 0.15, 0.5)
		sb_bg.set_border_width_all(1)
		sb_bg.border_color = Color(0.2, 0.2, 0.3)
		ehp.add_theme_stylebox_override("background", sb_bg)
		
		var sb_fg = StyleBoxFlat.new()
		sb_fg.bg_color = Color(0.8, 0.1, 0.2) # Deep Red
		sb_fg.border_color = Color(0.5, 0.0, 0.5) # Purple border
		sb_fg.set_border_width_all(1)
		sb_fg.shadow_color = Color(0.5, 0.0, 0.5, 0.4)
		sb_fg.shadow_size = 4
		ehp.add_theme_stylebox_override("fill", sb_fg)

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

func _on_message_logged(text: String) -> void:
	var log_box = find_child("CombatLog", true, false) as RichTextLabel
	if log_box:
		log_box.append_text("\n" + text)

func _start_thought_particles() -> void:
	if not _wave_in_progress: return
	# Spawn a random thought particle every 3-5 seconds
	var timer = get_tree().create_timer(randf_range(3.0, 5.0))
	timer.timeout.connect(func():
		if _wave_in_progress and visible:
			_spawn_thought_particle()
			_start_thought_particles()
	)

func _spawn_thought_particle() -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	
	var label = Label.new()
	var thoughts = ["...", "??", "!!", "dreaming", "hollow", "void", "deep", "shadows"]
	label.text = thoughts.pick_random()
	label.modulate = Color(0.6, 0.8, 1.0, 0.0)
	label.add_theme_font_size_override("font_size", 10)
	content.add_child(label)
	
	# Random position in the combat view
	var rect = content.get_global_rect()
	var start_pos = Vector2(
		randf_range(rect.position.x + 50, rect.position.x + rect.size.x - 50),
		randf_range(rect.position.y + 100, rect.position.y + rect.size.y - 150)
	)
	label.global_position = start_pos
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(label, "modulate:a", 0.4, 1.5)
	tween.tween_property(label, "global_position:y", start_pos.y - 40, 3.0).set_trans(Tween.TRANS_SINE)
	tween.chain().tween_property(label, "modulate:a", 0.0, 1.5)
	tween.chain().tween_callback(label.queue_free)

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
	
	# Make the grid bigger for large buttons
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 15)
	grid.visible = true

	for option in options:
		var btn := Button.new()
		# Action Category Styling
		var color = Color(0.4, 0.7, 1.0) # Weapon
		if option.type == "armor": color = Color(0.4, 1.0, 0.6)
		if option.type == "ring": color = Color(1.0, 0.8, 0.3)
		if option.type == "amulet": color = Color(1.0, 0.4, 0.8)
		
		var sb_normal = _get_action_button_style(color, 0.3)
		var sb_hover = _get_action_button_style(color, 0.6)
		var sb_press = _get_action_button_style(color, 0.9)
		
		btn.add_theme_stylebox_override("normal", sb_normal)
		btn.add_theme_stylebox_override("hover", sb_hover)
		btn.add_theme_stylebox_override("pressed", sb_press)
		
		btn.text = "%s\n[ %s ]" % [option.name.to_upper(), option.desc]
		btn.custom_minimum_size = Vector2(240, 80)
		btn.add_theme_font_size_override("font_size", 16)
		btn.pressed.connect(_on_attack_selected.bind(option.id))
		grid.add_child(btn)

func _get_action_button_style(base_color: Color, alpha: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(base_color.r * 0.1, base_color.g * 0.1, base_color.b * 0.1, 0.8)
	sb.set_border_width_all(2)
	sb.border_color = base_color
	sb.border_color.a = alpha
	sb.set_corner_radius_all(8)
	sb.shadow_color = base_color
	sb.shadow_color.a = alpha * 0.2
	sb.shadow_size = 6
	return sb



func _on_attack_selected(attack_id: String) -> void:
	_clear_attack_grid()
	if _ce: _ce.execute_player_attack(attack_id)

func _clear_attack_grid() -> void:
	var grid := find_child("AttackGrid", true, false) as GridContainer
	if grid:
		for child in grid.get_children():
			child.queue_free()

func _show_wave_result(won: bool, perfect: bool, reward: float, drop: Dictionary) -> void:
	_clear_attack_grid()
	
	if won:
		_add_reward_item("Victory", "Wave Complete", "")
		if perfect:
			_add_reward_item("Perfect!", "Bonus Applied", "")
		
		_add_reward_item("Dreamclouds", "+%d" % reward, "")
		
		if not drop.is_empty():
			_add_reward_item(drop.name, drop.rarity.capitalize(), _get_item_icon_path(drop, drop.slot))
	else:
		_add_reward_item("Defeat", "Wave %d Failed" % current_wave, "")
		_wave_in_progress = false
		if _start_wave_btn:
			_start_wave_btn.disabled = false
			_start_wave_btn.text = "Start Wave %d" % current_wave
		await get_tree().create_timer(2.0).timeout
		_show_view("combat")
	
	_update_wave_label()

func _clear_rewards() -> void:
	var list := find_child("RewardList", true, false)
	if list:
		for c in list.get_children(): c.queue_free()

func _add_reward_item(title: String, subtitle: String, icon_path: String) -> void:
	var list := find_child("RewardList", true, false)
	if not list: return
	
	var hbx = HBoxContainer.new()
	hbx.alignment = BoxContainer.ALIGNMENT_BEGIN
	
	if icon_path != "" and FileAccess.file_exists(icon_path):
		var tex_rect = TextureRect.new()
		tex_rect.texture = load(icon_path)
		tex_rect.custom_minimum_size = Vector2(24, 24)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hbx.add_child(tex_rect)
	
	var vbx = VBoxContainer.new()
	vbx.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var l1 = Label.new()
	l1.text = title
	l1.add_theme_font_size_override("font_size", 11)
	vbx.add_child(l1)
	
	var l2 = Label.new()
	l2.text = subtitle
	l2.modulate = Color(0.7, 0.7, 0.7)
	l2.add_theme_font_size_override("font_size", 9)
	vbx.add_child(l2)
	
	hbx.add_child(vbx)
	list.add_child(hbx)
	
	# Limit to last 12 rewards
	if list.get_child_count() > 12:
		list.get_child(0).queue_free()

func _update_wave_label() -> void:
	var mastery: int = 0
	if _gm:
		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0})
		mastery = int(wave_data.get("mastery", 0)) if wave_data is Dictionary else int(wave_data)

	if _wave_label:
		var label_text = "Wave %d - Subwave %d" % [current_wave, current_subwave]
		if current_wave > 1 and highest_wave_reached < current_wave:
			label_text += " [color=#ff5555][LOCKED][/color]"
		_wave_label.text = label_text
	
	if _mastery_label:
		_mastery_label.text = "Mastery: %d/10" % mastery
		_mastery_label.modulate = Color(1, 0.9, 0) if mastery >= 10 else Color(0.6, 0.8, 1, 0.8)

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
		
		# Create a grid for slots - 6x1 layout
		var grid := GridContainer.new()
		grid.columns = 6
		grid.add_theme_constant_override("h_separation", 20)
		grid.add_theme_constant_override("v_separation", 10)
		slots_box.add_child(grid)
		
		for slot_name in ["weapon","armor","amulet","ring1","helmet","talisman"]:
			var slot_panel := PanelContainer.new()
			slot_panel.custom_minimum_size = Vector2(150, 150)
			
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
				"mythic": sb.border_color = Color(1.0, 0.2, 0.4)
				_: sb.border_color = Color(0.15, 0.15, 0.2)
			
			# Glassy glow for slots
			sb.set_corner_radius_all(6)
			sb.shadow_color = sb.border_color
			sb.shadow_color.a = 0.2
			sb.shadow_size = 5
			
			slot_panel.add_theme_stylebox_override("panel", sb)
			
			var vbx := VBoxContainer.new()
			vbx.alignment = BoxContainer.ALIGNMENT_CENTER
			
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(_get_item_icon_path(item, slot_name))
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(80, 80)
			if item == null: icon_rect.modulate.a = 0.2
			vbx.add_child(icon_rect)
			
			var name_lbl := Label.new()
			var plus_str = " +%d" % item.get("plus_tier", 0) if item and item.get("plus_tier", 0) > 0 else ""
			name_lbl.text = (item.name + plus_str) if item else slot_name.capitalize()
			name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			name_lbl.add_theme_font_size_override("font_size", 14)
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
		
		# Remove ScrollContainer as requested to fill screen horizontally
		var main_h := HBoxContainer.new()
		main_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inv_box.add_child(main_h)
		
		var categories_grid := GridContainer.new()
		categories_grid.columns = 6 # 6x1 layout
		categories_grid.add_theme_constant_override("h_separation", 10)
		categories_grid.add_theme_constant_override("v_separation", 10)
		categories_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_h.add_child(categories_grid)
		
		# Sidebar for Actions
		var sidebar := VBoxContainer.new()
		sidebar.custom_minimum_size = Vector2(120, 0)
		sidebar.add_theme_constant_override("separation", 10)
		main_h.add_child(sidebar)
		
		var side_hdr := Label.new()
		side_hdr.text = "ACTIONS"
		side_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sidebar.add_child(side_hdr)
		sidebar.add_child(HSeparator.new())
		
		# Use helper for selection check to avoid reference vs value confusion with Dictionaries
		var has_sel = not _selected_item_ref.is_empty()
		
		var equip_btn := Button.new()
		equip_btn.text = "Equip Selected"
		equip_btn.disabled = not has_sel
		if has_sel:
			# Find the current index of the selected item reference
			var s_idx = _em.inventory.find(_selected_item_ref)
			if s_idx != -1:
				equip_btn.pressed.connect(_on_equip_item_ref.bind(_selected_item_ref))
			else:
				equip_btn.disabled = true
		sidebar.add_child(equip_btn)
		
		var dismantle_btn := Button.new()
		dismantle_btn.text = "Dismantle"
		dismantle_btn.modulate = Color(1, 0.4, 0.4)
		dismantle_btn.disabled = not has_sel
		if has_sel:
			dismantle_btn.pressed.connect(_on_dismantle_item_ref.bind(_selected_item_ref))
		sidebar.add_child(dismantle_btn)
		
		# "Power Up" button removed from Inventory as requested; now in Forge.
		
		# SORTING: Sort inventory by rarity (highest first)
		var rarity_order = {
			"god_tier": 7, "transcendent": 6, "mythic": 5, 
			"legendary": 4, "epic": 3, "rare": 2, 
			"uncommon": 1, "common": 0
		}
		_em.inventory.sort_custom(func(a, b):
			var r_a = rarity_order.get(a.get("rarity","common"), 0)
			var r_b = rarity_order.get(b.get("rarity","common"), 0)
			if r_a != r_b: return r_a > r_b
			# Sub-sort by level if rarities are equal
			return a.get("level", 1) > b.get("level", 1)
		)

		var slots = ["weapon","armor","amulet","ring1","helmet","talisman"]
		var slot_groups := {}
		for s in slots:
			var category_panel := PanelContainer.new()
			var cp_sb = StyleBoxFlat.new()
			cp_sb.bg_color = Color(0.1, 0.12, 0.18, 0.5)
			cp_sb.set_border_width_all(1)
			cp_sb.border_color = Color(0.3, 0.5, 0.8, 0.3)
			cp_sb.set_corner_radius_all(8)
			category_panel.add_theme_stylebox_override("panel", cp_sb)
			categories_grid.add_child(category_panel)
			
			var v_box := VBoxContainer.new()
			v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v_box.add_theme_constant_override("separation", 5)
			category_panel.add_child(v_box)
			
			var hdr := Label.new()
			hdr.text = s.capitalize()
			hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
			v_box.add_child(hdr)
			v_box.add_child(HSeparator.new())
			
			var grid := GridContainer.new()
			grid.columns = 4 # 4 wide as requested
			grid.add_theme_constant_override("h_separation", 4)
			grid.add_theme_constant_override("v_separation", 4)
			v_box.add_child(grid)
			slot_groups[s] = grid
			
			# Ensure category has height to fill 8 rows (~500px)
			category_panel.custom_minimum_size = Vector2(0, 500)
			
		for idx in range(_em.inventory.size()):
			var item: Dictionary = _em.inventory[idx]
			var _it = item # capture for lambda
			var _idx = idx
			var slot = item.get("slot", "weapon")
			var target_grid = slot_groups.get(slot, slot_groups["weapon"])
			
			var item_frame := PanelContainer.new()
			item_frame.custom_minimum_size = Vector2(50, 50) # Balanced for 4-wide in 6-col
			
			var is_selected = false
			if not _selected_item_ref.is_empty():
				if item.has("id") and _selected_item_ref.has("id"):
					is_selected = (item.id == _selected_item_ref.id)
				else:
					is_selected = (item == _selected_item_ref)
			var sb = StyleBoxFlat.new()
			sb.bg_color = Color(0.1, 0.1, 0.15, 0.8)
			sb.set_border_width_all(2) # Keep constant to prevent jumping
			sb.border_color = _get_rarity_color(item.rarity)
			if is_selected:
				sb.border_color = Color(1.0, 0.9, 0.3) # Golden border
				sb.shadow_size = 6 # Use shadow for highlight instead of width
				sb.shadow_color = Color(1, 0.8, 0, 0.5)
				sb.bg_color = Color(0.2, 0.2, 0.25, 1.0) # Slightly brighter bg
			else:
				sb.border_color.a = 0.7
			sb.set_corner_radius_all(6)
			item_frame.add_theme_stylebox_override("panel", sb)
			
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(_get_item_icon_path(item, slot))
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon_rect.custom_minimum_size = Vector2(42, 42)
			item_frame.add_child(icon_rect)
			
			# Plus Tier Indicator
			if item.get("plus_tier", 0) > 0:
				var plus_lbl := Label.new()
				plus_lbl.text = "+%d" % item.plus_tier
				plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				plus_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
				plus_lbl.add_theme_font_size_override("font_size", 10)
				plus_lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
				item_frame.add_child(plus_lbl)
			
			# Tooltip and Interaction (Overlay button)
			var btn := Button.new()
			btn.flat = true
			btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			btn.custom_minimum_size = Vector2(50, 50)
			item_frame.add_child(btn)
			
			# capture for lambda (ensure unique local copies)
			var _it_local = item 
			var _frame_local = item_frame
			
			btn.mouse_entered.connect(func(): _show_custom_tooltip(_frame_local, _it_local))
			btn.mouse_exited.connect(func(): _hide_custom_tooltip())
			
			# Selection only (no double click/right click as requested)
			btn.pressed.connect(_on_inventory_item_clicked.bind(_it_local, _frame_local))
			
			target_grid.add_child(item_frame)
		
		_refresh_total_stats()

func _on_inventory_item_clicked(item: Dictionary, frame: Control) -> void:
	_selected_item_ref = item
	_refresh_equipment_view()
	_show_custom_tooltip(frame, item)

func _on_dismantle_item_ref(item: Dictionary) -> void:
	if _em == null: return
	var idx = _em.inventory.find(item)
	if idx != -1:
		_on_dismantle_item(idx)

func _on_dismantle_item(idx: int) -> void:
	if _em == null or idx < 0 or idx >= _em.inventory.size(): return
	var _reward = _em.dismantle_item(idx)
	_selected_item_ref = {}
	if _gm: 
		_gm._refresh_top_ui()
		_gm.save_game()
	_refresh_equipment_view()
	_hide_custom_tooltip()

func _on_inventory_power_up_ref(item: Dictionary) -> void:
	if _em == null: return
	var idx = _em.inventory.find(item)
	if idx != -1:
		_on_inventory_power_up(idx)

func _on_inventory_power_up(idx: int) -> void:
	if _em == null or _gm == null: return
	if idx < 0 or idx >= _em.inventory.size(): return
	
	var item = _em.inventory[idx]
	var cost = int(item.level) * 100
	
	if _gm.dreamcloud >= cost:
		_gm.dreamcloud -= cost
		item.level = min(item.level + 1, item.max_level)
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view() # Correct view for Forge menu
		_refresh_equipment_view()
		_hide_custom_tooltip()

func _on_equip_item_ref(item: Dictionary) -> void:
	if _em == null: return
	var idx = _em.inventory.find(item)
	if idx != -1:
		_on_equip_item(idx)

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


func _refresh_forge_inventory() -> void:
	var forge_inv := find_child("ForgeInventoryBox", true, false)
	if forge_inv == null or _em == null: return
	for child in forge_inv.get_children():
		child.queue_free()
	
	# GLASSY STYLE for Forge
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.18, 0.8)
	style.set_border_width_all(2)
	style.border_color = Color(0.3, 0.5, 0.8, 0.5)
	style.set_corner_radius_all(10)
	
	# 1. Level Up / Targeted Fusion section
	var lvl_hdr := Label.new()
	lvl_hdr.text = "EQUIPPED ITEMS (LEVEL UP & FUSION TARGETS)"
	lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	forge_inv.add_child(lvl_hdr)
	
	for slot in _em.equipped.keys():
		var item = _em.equipped[slot]
		if item == null: continue
		
		var row_container := PanelContainer.new()
		row_container.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 15)
		row_container.add_child(row)
		
		var icon_rect := TextureRect.new()
		icon_rect.texture = load(_get_item_icon_path(item, slot))
		icon_rect.custom_minimum_size = Vector2(48, 48)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(icon_rect)
		
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		var plus_str = " +%d" % item.get("plus_tier", 0) if item.get("plus_tier", 0) > 0 else ""
		name_lbl.text = "%s%s" % [item.name, plus_str]
		name_lbl.add_theme_color_override("font_color", _get_rarity_color(item.rarity))
		details.add_child(name_lbl)
		
		var lv_lbl := Label.new()
		lv_lbl.text = "Level %d / %d" % [item.level, item.max_level]
		lv_lbl.add_theme_font_size_override("font_size", 12)
		details.add_child(lv_lbl)

		# STATS DISPLAY in Forge
		var stats_box := HBoxContainer.new()
		stats_box.add_theme_constant_override("separation", 10)
		details.add_child(stats_box)
		
		var lv_mult = 1.0 + (item.level * 0.05)
		var stats = item.get("stats", {})
		for key in ["attack", "hp", "defense"]:
			if stats.has(key):
				var s_lbl := Label.new()
				s_lbl.text = "%s: %.1f" % [key.capitalize().left(3), stats[key] * lv_mult]
				s_lbl.add_theme_font_size_override("font_size", 11)
				s_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				stats_box.add_child(s_lbl)
		
		row.add_child(details)
		
		var actions := HBoxContainer.new()
		
		# LEVEL UP BUTTON
		var cost: int = int(item.level) * 100
		var lvlup_btn := Button.new()
		lvlup_btn.text = "Power Up (%d DC)" % cost
		if _gm and _gm.dreamcloud < cost: lvlup_btn.disabled = true
		if item.level >= item.max_level:
			lvlup_btn.disabled = true
			lvlup_btn.text = "MAX LEVEL"
		lvlup_btn.pressed.connect(_on_level_up_item.bind(slot))
		actions.add_child(lvlup_btn)
		
		# FUSION FODDER SCAN
		if item.level >= item.max_level:
			var fodder_indices = []
			var req_count = 1
			var req_rarity = item.rarity
			var req_plus = 0
			var logic_desc = ""
			
			if ["common", "uncommon", "rare"].has(item.rarity):
				req_count = 2 # Target + 2 = 3 Total
				req_rarity = item.rarity
				req_plus = 0
				# Level check: Only Commons don't need max level
				var can_rarity_up = (item.rarity == "common" or item.level >= item.max_level)
				if not can_rarity_up:
					logic_desc = "Need Max Level to Fuse"
				else:
					logic_desc = "Need 2x same %s" % [req_rarity.capitalize()]
			else: # Epic+
				if item.get("plus_tier", 0) == 0:
					req_count = 1
					req_rarity = item.rarity
					req_plus = 0
					logic_desc = "Enhance (+1): Need 1x %s" % [req_rarity.capitalize()]
				elif item.get("plus_tier", 0) == 1:
					req_count = 2
					req_rarity = item.rarity
					req_plus = 0
					logic_desc = "Enhance (+2): Need 2x %s" % [req_rarity.capitalize()]
				elif item.get("plus_tier", 0) == 2:
					req_count = 1
					req_rarity = item.rarity
					req_plus = 2
					logic_desc = "Tier Up: Need 1x %s+2" % [req_rarity.capitalize()]
			
			# Find fodder (Must match NAME and slot)
			for i in range(_em.inventory.size()):
				var f = _em.inventory[i]
				if f.name == item.name and f.rarity == req_rarity and f.slot == slot and f.get("plus_tier", 0) == req_plus:
					fodder_indices.append(i)
			
			var fuse_btn := Button.new()
			var fuse_cost = _em.call("_get_fusion_cost", item.rarity) * (1 if item.get("plus_tier", 0) == 0 else (2 if item.get("plus_tier", 0) == 1 else 4))
			
			if logic_desc.begins_with("Need"):
				fuse_btn.disabled = true
			elif fodder_indices.size() < req_count:
				fuse_btn.disabled = true
				fuse_btn.text = "NEED %d MORE SAME GEAR" % (req_count - fodder_indices.size())
			elif _gm and _gm.dreamcloud < fuse_cost:
				fuse_btn.disabled = true
				fuse_btn.text = "NOT ENOUGH DC (%d)" % fuse_cost
			else:
				var chosen_fodder: Array[Dictionary] = []
				var actual_indices = []
				for i in range(req_count):
					chosen_fodder.append(_em.inventory[fodder_indices[i]])
					actual_indices.append(fodder_indices[i])
				
				fuse_btn.text = "FUSE (%d DC)" % fuse_cost
				fuse_btn.pressed.connect(_on_fuse_targeted_ref.bind(slot, chosen_fodder))
				fuse_btn.add_theme_color_override("font_color", Color(1, 0.8, 0.2)) # Highlight
			
			actions.add_child(fuse_btn)

		row.add_child(actions)
		forge_inv.add_child(row_container)
		forge_inv.add_child(Control.new()) # Spacer
	
	forge_inv.add_child(HSeparator.new())
	
	# 2. INVENTORY ITEMS (LEVEL UP) section - NEW
	var inv_lvl_hdr := Label.new()
	inv_lvl_hdr.text = "INVENTORY ITEMS (POWER UP)"
	inv_lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_lvl_hdr.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	forge_inv.add_child(inv_lvl_hdr)
	
	# Categorized columns for inventory items
	var inv_columns := HBoxContainer.new()
	inv_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_columns.add_theme_constant_override("separation", 10)
	inv_columns.custom_minimum_size = Vector2(0, 300)
	forge_inv.add_child(inv_columns)
	
	var slot_vbox_map = {}
	var slots_list = ["weapon", "armor", "amulet", "ring1", "helmet", "talisman"]
	
	for s_name in slots_list:
		var col_container := PanelContainer.new()
		col_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_container.add_theme_stylebox_override("panel", style)
		inv_columns.add_child(col_container)
		
		var col_vbox := VBoxContainer.new()
		col_container.add_child(col_vbox)
		
		var col_hdr := Label.new()
		col_hdr.text = s_name.capitalize().replace("Ring1", "Ring")
		col_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col_hdr.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
		col_vbox.add_child(col_hdr)
		col_vbox.add_child(HSeparator.new())
		
		var col_scroll := ScrollContainer.new()
		col_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col_vbox.add_child(col_scroll)
		
		var col_content := VBoxContainer.new()
		col_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_scroll.add_child(col_content)
		slot_vbox_map[s_name] = col_content

	for idx in range(_em.inventory.size()):
		var item = _em.inventory[idx]
		var slot_name = item.get("slot", "weapon")
		if not slot_vbox_map.has(slot_name): continue
		
		var row_container := PanelContainer.new()
		# Subtle background for individual items in the column
		var item_style = StyleBoxFlat.new()
		item_style.bg_color = Color(1,1,1, 0.05)
		row_container.add_theme_stylebox_override("panel", item_style)
		
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row_container.add_child(row)
		
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		var plus_str = " +%d" % item.get("plus_tier", 0) if item.get("plus_tier", 0) > 0 else ""
		name_lbl.text = "%s%s (Lv %d)" % [item.name, plus_str, item.level]
		name_lbl.add_theme_color_override("font_color", _get_rarity_color(item.rarity))
		name_lbl.add_theme_font_size_override("font_size", 11)
		details.add_child(name_lbl)
		
		# Compact stats for column view
		var stats_box := HBoxContainer.new()
		var lv_mult = 1.0 + (item.level * 0.05)
		var st = item.get("stats", {})
		for key in ["attack", "hp", "defense"]:
			if st.has(key):
				var s_lbl := Label.new()
				s_lbl.text = "%.0f" % (st[key] * lv_mult)
				s_lbl.add_theme_font_size_override("font_size", 9)
				s_lbl.modulate.a = 0.7
				stats_box.add_child(s_lbl)
		details.add_child(stats_box)
		row.add_child(details)
		
		var cost = int(item.level) * 100
		var lvlup_btn := Button.new()
		lvlup_btn.text = "Lv+"
		lvlup_btn.tooltip_text = "Power Up: %d DC" % cost
		if _gm and _gm.dreamcloud < cost: lvlup_btn.disabled = true
		if item.level >= item.max_level:
			lvlup_btn.disabled = true
			lvlup_btn.text = "MAX"
		lvlup_btn.pressed.connect(_on_inventory_power_up_ref.bind(item))
		row.add_child(lvlup_btn)
		
		slot_vbox_map[slot_name].add_child(row_container)

	forge_inv.add_child(HSeparator.new())
	
	# 3. INVENTORY FUSION section
	var content_vbox := VBoxContainer.new()
	content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	forge_inv.add_child(content_vbox)
	
	var inv_hdr := Label.new()
	inv_hdr.text = "INVENTORY FUSION (UNEQUIPPED ITEMS)"
	inv_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_hdr.add_theme_color_override("font_color", Color(0.6, 1.0, 0.8))
	content_vbox.add_child(inv_hdr)
	
	# Group inventory by name/slot/rarity/plus
	var pools := {} # key -> [indices]
	for i in range(_em.inventory.size()):
		var it = _em.inventory[i]
		var key = "%s_%s_%s_%d" % [it.get("slot","weapon"), it.name, it.rarity, it.get("plus_tier", 0)]
		if not pools.has(key): pools[key] = []
		pools[key].append(i)
	
	var any_inv_fuse = false
	for key in pools.keys():
		var indices = pools[key]
		if indices.size() < 2: continue
		
		# Find a potential target
		var target_idx = -1
		for idx in indices:
			var it = _em.inventory[idx]
			# Commons don't need max level; others do
			if it.rarity == "common" or it.level >= it.max_level:
				target_idx = idx
				break
		
		if target_idx == -1: continue # No valid target item
		
		var target_item = _em.inventory[target_idx]
		var slot = target_item.get("slot", "weapon")
		var rarity = target_item.rarity
		var plus = target_item.get("plus_tier", 0)
		
		# Determine requirements
		var req_count = 1
		var req_plus = 0
		if ["common", "uncommon", "rare"].has(rarity):
			req_count = 2 # Target + 2 = 3 Total
			req_plus = 0
		else: # Epic+
			if plus == 0: req_count = 1; req_plus = 0
			elif plus == 1: req_count = 2; req_plus = 0
			elif plus == 2: req_count = 1; req_plus = 2
		
		# Collect fodder indices (excluding the target)
		var fodder_indices = []
		for idx in indices:
			if idx == target_idx: continue
			var it = _em.inventory[idx]
			if it.get("plus_tier", 0) == req_plus:
				fodder_indices.append(idx)
			if fodder_indices.size() >= req_count: break
		
		if fodder_indices.size() >= req_count:
			var fodder_items: Array[Dictionary] = []
			for idx in fodder_indices: fodder_items.append(_em.inventory[idx])
			
			any_inv_fuse = true
			var row_container := PanelContainer.new()
			row_container.add_theme_stylebox_override("panel", style)
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 15)
			row_container.add_child(row)
			
			var icon_rect := TextureRect.new()
			icon_rect.texture = load(_get_item_icon_path(target_item, slot))
			icon_rect.custom_minimum_size = Vector2(32, 32)
			icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			row.add_child(icon_rect)
			
			var details := Label.new()
			details.text = "3x %s %s" % [rarity.capitalize(), slot.capitalize()]
			if ["epic","legendary","mythic"].has(rarity):
				details.text = "%s %s%s + %d fodder" % [rarity.capitalize(), slot.capitalize(), (" +%d"%plus if plus>0 else ""), req_count]
			details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(details)
			
			var fuse_btn := Button.new()
			var fuse_cost = _em.call("_get_fusion_cost", rarity) * (1 if plus == 0 else (2 if plus == 1 else 4))
			fuse_btn.text = "FUSE (%d DC)" % fuse_cost
			if _gm and _gm.dreamcloud < fuse_cost: fuse_btn.disabled = true
			fuse_btn.pressed.connect(_on_fuse_inventory_ref.bind(target_item, fodder_items))
			row.add_child(fuse_btn)
			
			content_vbox.add_child(row_container)
			content_vbox.add_child(Control.new())
	
	if not any_inv_fuse:
		var none_lbl := Label.new()
		none_lbl.text = "(No fusions available for unequipped items)"
		none_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none_lbl.modulate.a = 0.5
		content_vbox.add_child(none_lbl)

func _on_fuse_inventory_ref(target: Dictionary, fodder_list: Array) -> void:
	if _em == null: return
	var t_idx = _em.inventory.find(target)
	var f_idxs = []
	for f in fodder_list:
		var idx = _em.inventory.find(f)
		if idx != -1: f_idxs.append(idx)
	if t_idx != -1 and f_idxs.size() == fodder_list.size():
		_on_fuse_inventory(t_idx, f_idxs)

func _on_fuse_targeted_ref(slot: String, fodder_list: Array) -> void:
	if _em == null: return
	# Target is equipped, so slot is sufficient
	var f_idxs = []
	for f in fodder_list:
		var idx = _em.inventory.find(f)
		if idx != -1: f_idxs.append(idx)
	if f_idxs.size() == fodder_list.size():
		_on_fuse_targeted(slot, f_idxs)

func _on_fuse_inventory(target_idx: int, fodder_indices: Array) -> void:
	if _em == null or _gm == null: return
	var target_item = _em.inventory[target_idx]
	var fodder: Array[Dictionary] = []
	for idx in fodder_indices:
		fodder.append(_em.inventory[idx])
	
	var new_item = _em.fuse_items(target_item, fodder)
	if not new_item.is_empty():
		# Remove fodder AND the target using references to be safe
		var items_to_remove = []
		for idx in fodder_indices: items_to_remove.append(_em.inventory[idx])
		items_to_remove.append(_em.inventory[target_idx])
		
		for it in items_to_remove:
			var cur_idx = _em.inventory.find(it)
			if cur_idx != -1:
				_em.inventory.remove_at(cur_idx)
		
		_em.inventory.append(new_item)
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()

func _refresh_forge_view() -> void:
	if _gm:
		var dc: float = _gm.dreamcloud 
		var info_lbl := find_child("ForgeInfoLbl", true, false) as Label
		if info_lbl: info_lbl.text = "Dreamcloud: %.0f" % dc
	_refresh_forge_inventory()


func _on_fuse_targeted(slot: String, fodder_indices: Array) -> void:
	if _em == null or _gm == null: return
	var target_item = _em.equipped[slot]
	var fodder: Array[Dictionary] = []
	for idx in fodder_indices:
		fodder.append(_em.inventory[idx])
	
	var new_item = _em.fuse_items(target_item, fodder)
	if not new_item.is_empty():
		# Remove fodder using references to be safe
		var fodder_to_remove = []
		for idx in fodder_indices: fodder_to_remove.append(_em.inventory[idx])
		for it in fodder_to_remove:
			var cur_idx = _em.inventory.find(it)
			if cur_idx != -1:
				_em.inventory.remove_at(cur_idx)
		
		_em.equipped[slot] = new_item
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()

func _on_level_up_item(slot: String) -> void:
	if _em == null or _gm == null: return
	if _em.level_up_item(slot):
		_gm._refresh_top_ui() 
		_gm.save_game()
		_refresh_forge_view()

func _get_rarity_color(rarity: String) -> Color:
	match rarity:
		"common": return Color(0.8, 0.8, 0.8)
		"uncommon": return Color(0.2, 0.8, 0.2)
		"rare": return Color(0.2, 0.5, 1.0)
		"epic": return Color(0.7, 0.2, 1.0)
		"legendary": return Color(1.0, 0.8, 0.0)
		"mythic": return Color(1.0, 0.2, 0.2)
		"transcendent": return Color(0.2, 1.0, 1.0)
		"god_tier": return Color(1.0, 1.0, 1.0)
	return Color(1, 1, 1)

func _set_item_tooltip(node: Control, item: Dictionary) -> void:
	var lv_mult = 1.0 + (item.get("level", 1) * 0.05)
	var plus_str = " (+%d)" % item.get("plus_tier", 0) if item.get("plus_tier", 0) > 0 else ""
	var text = "[%s] %s%s (Lv %d)\n" % [item.rarity.capitalize(), item.name, plus_str, item.level]
	var stats = item.get("stats", {})
	if stats.has("attack"): text += "• Attack: +%.1f\n" % (stats.attack * lv_mult)
	if stats.has("hp"):     text += "• HP: +%.1f\n" % (stats.hp * lv_mult)
	if stats.has("defense"): text += "• Defense: +%.1f\n" % (stats.defense * lv_mult)
	
	var s_stats = item.get("secondary_stats", {})
	for k in s_stats.keys():
		text += "• %s: +%.1f%%\n" % [k.replace("_mult","").capitalize(), s_stats[k]*100.0]
		
	node.tooltip_text = text


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
		var e_sec = equipped_item.get("secondary_stats", {}) if equipped_item else {}
		
		# Combine all unique primary keys from both items
		var p_keys = stats.keys()
		if equipped_item:
			for k in e_stats.keys():
				if k not in p_keys: p_keys.append(k)
		p_keys.sort()
		
		var lv_mult = 1.0 + (item.get("level", 1) * 0.05)
		var e_lv_mult = 1.0 + (equipped_item.get("level", 1) * 0.05) if equipped_item else 1.0
		
		for key in p_keys:
			var val = stats.get(key, 0.0) * lv_mult
			var e_val = e_stats.get(key, 0.0) * e_lv_mult
			var diff = val - e_val
			
			var diff_str = ""
			if equipped_item and diff != 0:
				var d_color = "00ffaa" if diff > 0 else "ff5555"
				diff_str = " ([color=#%s]%s%.1f[/color])" % [d_color, "+" if diff > 0 else "", diff]
			
			s_text += "• %s: +%.1f%s\n" % [key.capitalize(), val, diff_str]
		
		# Secondary Stats in Tooltip
		var sec_stats = item.get("secondary_stats", {})
		var sec_keys = sec_stats.keys()
		if equipped_item:
			for k in e_sec.keys():
				if k not in sec_keys: sec_keys.append(k)
		sec_keys.sort()
		
		if not sec_keys.is_empty():
			s_text += "\n[i]Utility Bonuses:[/i]\n"
			for k in sec_keys:
				var val = sec_stats.get(k, 0.0) * 100.0
				var e_val = e_sec.get(k, 0.0) * 100.0
				var diff = val - e_val
				var diff_str = ""
				if equipped_item and diff != 0:
					var d_color = "00ffaa" if diff > 0 else "ff5555"
					diff_str = " ([color=#%s]%s%.1f%%[/color])" % [d_color, "+" if diff > 0 else "", diff]
				s_text += "• %s: +%.1f%%%s\n" % [k.replace("_mult","").capitalize(), val, diff_str]

		# Salvage Reward (moved outside any tag nesting if needed, though s_text is just a string)
		var salvage = _em.salvage_item(item) if _em else 0
		s_text += "\n[right][color=#ffcc55]Salvage: %d DC[/color][/right]" % salvage
		s_text += "[/color]"
		stats_lbl.text = s_text
		# Ensure the label can show all text (Fit content)
		stats_lbl.autohide_scrollbar = false
		stats_lbl.fit_content = true

	tip.visible = true
	# Position tip near the node
	if node:
		var viewport_pos = node.get_global_position()
		tip.global_position = viewport_pos + Vector2(110, 0)
		# Snap inside bounds
		if tip.global_position.x + tip.size.x > get_viewport_rect().size.x:
			tip.global_position.x = viewport_pos.x - tip.size.x - 10
	# else: keep current position (sticky behavior)

func _hide_custom_tooltip() -> void:
	if not _selected_item_ref.is_empty(): 
		# If something is selected, keep the tooltip showing THAT item's stats
		var tip := find_child("CustomTooltip", true, false) as PanelContainer
		if tip:
			# We don't hide it, but we might want to "lock" its data to the selected item
			_show_custom_tooltip(null, _selected_item_ref)
			return
			
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

func _get_item_icon_path(item, category: String) -> String:
	if item == null or not (item is Dictionary) or not item.has("name"):
		return ICONS.get(category, ICONS["weapon"])
	
	var clean_name = item.name.to_lower().replace(" ", "_").replace("-", "_")
	var path = "res://assets/combat/gear_%s.png" % clean_name
	
	if FileAccess.file_exists(path):
		return path
	
	return ICONS.get(category, ICONS["weapon"])
