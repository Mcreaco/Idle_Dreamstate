extends Control

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
var _blacksmith_view: Control = null
var _skills_view: Control = null # NEW v13
var _bulk_dismantle_v: Control = null # NEW
var _slotted_blacksmith_items: Array[Dictionary] = [] # 3 slots
var _bulk_dismantle_items: Array[Dictionary] = [] # NEW
var _wave_label: Label = null
var _start_wave_btn: Button = null
var _prev_wave_btn: Button = null
var _next_wave_btn: Button = null
var _farm_btn: Button = null
var _gm: Node = null
var _ce: CombatEngine = null
var _em: EquipmentManager = null
var _subwave_prev_btn: Button = null
var _subwave_next_btn: Button = null
var _precompiled_shaders: Dictionary = {}
var _p_stats: Dictionary = {}
var _e_data: Dictionary = {}
var _smooth_auto_box: Control = null
var _smooth_bar: ProgressBar = null
var _is_smooth_looping: bool = false
var _current_smooth_tween: Tween = null
var _farming_mode: bool = false
var _last_automated_subwave: int = 1
var _auto_stats_lbl: Label = null

@onready var _mastery_label: Label = find_child("MasteryLabel", true, false)
@onready var _player_status_box: HBoxContainer = find_child("PlayerStatusBox", true, false)
@onready var _enemy_status_box: HBoxContainer = find_child("EnemyStatusBox", true, false)
@onready var _total_stats_lbl: RichTextLabel = find_child("StatsLbl", true, false)
@onready var _combat_bg: TextureRect = find_child("CombatBackground", true, false)
@onready var _attack_grid: GridContainer = find_child("AttackGrid", true, false)
@onready var tip: PanelContainer = find_child("CustomTooltip", true, false)
@onready var _content_area: Control = find_child("ContentArea", true, false)

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

const CLOUD_SHADER = """
shader_type canvas_item;
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 0.5);
uniform float density : hint_range(0.0, 2.0) = 1.0;

void fragment() {
    vec2 uv = UV - 0.5;
    float dist = length(uv * vec2(1.0, 2.5)); // Oblong shape
    
    // Perlin-like layered noise using sines
    float noise = sin(uv.x * 12.0 + TIME * 0.5) * cos(uv.y * 8.0 - TIME * 0.3);
    noise += sin(uv.y * 15.0 + TIME * 0.8) * 0.5;
    
    float alpha = smoothstep(0.4 + noise * 0.1, 0.1, dist);
    COLOR = vec4(cloud_color.rgb, alpha * cloud_color.a * density);
}
"""

const EDGE_BLEND_SHADER = """
shader_type canvas_item;
uniform float softness : hint_range(0.0, 1.0) = 0.6;
uniform float falloff_power : hint_range(1.0, 10.0) = 2.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 2.0; 
	// Use a power-based falloff for a very soft "stretched" look
	float alpha = clamp(1.0 - pow(dist, falloff_power), 0.0, 1.0);
	color.a *= alpha;
	COLOR = color;
}
"""

const SHIMMER_SHADER = """
shader_type canvas_item;
uniform float speed : hint_range(0.1, 2.0) = 0.5;
uniform float frequency : hint_range(1.0, 50.0) = 10.0;
uniform float amplitude : hint_range(0.0, 0.1) = 0.005;

void fragment() {
    vec2 uv = UV;
    uv.x += sin(uv.y * frequency + TIME * speed) * amplitude;
    uv.y += cos(uv.x * frequency + TIME * speed) * amplitude;
    COLOR = texture(TEXTURE, uv);
}
"""

const V_SLASH_SHADER = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
    vec2 uv = UV - 0.5;
    float dist = abs(uv.y + uv.x * 0.5); // Slanted line
    float line = smoothstep(0.02, 0.0, dist);
    
    // Moving stroke instead of solid wipe
    float pos = progress * 2.0 - 0.5;
    float tail = smoothstep(pos - 0.5, pos, UV.x);
    float head = 1.0 - smoothstep(pos, pos + 0.1, UV.x);
    
    // Respect external modulate (COLOR.a)
    COLOR = vec4(color.rgb, line * head * tail * color.a * COLOR.a);
}
"""

const V_STAB_SHADER = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(1.0, 0.95, 0.6, 1.0);

void fragment() {
    vec2 uv = UV - 0.5;
    // Enhanced Luminescent Tapered streak
    float sharpness = 1.0 - abs(uv.x) * 1.5;
    float dist = abs(uv.y) * (4.0 + sharpness * 15.0);
    float glow = smoothstep(0.15, 0.0, dist) * 1.5;
    float core = smoothstep(0.04, 0.0, dist);
    
    // Smooth traversal with lingering tail
    float streak_pos = progress * 2.2 - 0.6;
    float tail = smoothstep(streak_pos - 0.7, streak_pos, UV.x);
    float head = 1.0 - smoothstep(streak_pos, streak_pos + 0.15, UV.x);
    float mask = head * tail;
    
    // Impact glint
    float glint = smoothstep(0.06, 0.0, length(vec2(UV.x - streak_pos, uv.y))) * 2.0;
    
    vec3 out_color = color.rgb * (core + glow * 0.5) + (vec3(1.0) * glint);
    COLOR = vec4(out_color, (mask * (glow + core) + glint) * color.a);
}
"""

const V_BLUNT_SHADER = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.9, 0.9, 1.0, 1.0);

void fragment() {
    vec2 uv = UV - 0.5;
    float dist = length(uv);
    
    // Multi-layered Shockwaves
    float wave1 = smoothstep(progress - 0.15, progress, dist) * (1.0 - smoothstep(progress, progress + 0.01, dist));
    float wave2 = smoothstep(progress * 0.7 - 0.1, progress * 0.7, dist) * (1.0 - smoothstep(progress * 0.7, progress * 0.7 + 0.01, dist));
    
    // Sharp Radial Cracks
    float angle = atan(uv.y, uv.x);
    float crack_pattern = sin(angle * 16.0 + progress * 2.0) * cos(angle * 9.0);
    float cracks = smoothstep(0.6, 1.0, crack_pattern) * smoothstep(0.3, 0.0, abs(dist - progress * 0.8));
    
    // High-fidelity Impact Flash
    float flash = pow(1.0 - progress, 3.0) * smoothstep(0.3, 0.0, dist) * 2.0;
    
    vec3 final_rgb = mix(color.rgb, vec3(1.0), flash);
    float final_alpha = (wave1 * 1.0 + wave2 * 0.5 + cracks * 2.0 + flash) * (1.0 - progress);
    
    COLOR = vec4(final_rgb, final_alpha * color.a);
}
"""

const V_AWAKENED_SHADER = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.7, 0.4, 1.0, 1.0);

// High-fidelity hash for organic noise
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Simple noise for fluid edges
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
    vec2 uv = UV - 0.5;
    float dist = length(uv);
    
    // Multi-frequency noise for ultra-smooth Dimensional Tear
    float n1 = noise(vec2(uv.y * 8.0, progress * 4.0));
    float n2 = noise(vec2(uv.y * 15.0 - progress * 2.0, progress * 3.0));
    float rift_offset = (n1 * 0.6 + n2 * 0.4 - 0.5) * 0.08;
    float rift_x = uv.x + rift_offset;
    
    // Cinematic opening/closing profile
    float rift_width = smoothstep(0.0, 0.3, progress) * (1.0 - pow(progress, 3.0));
    float thickness = 0.04 * rift_width;
    float rift = smoothstep(thickness, 0.0, abs(rift_x));
    
    // Shimmering Void core
    float star_noise = hash(UV + progress * 0.05);
    float stars = smoothstep(0.98, 1.0, star_noise) * rift;
    
    // Smooth atmospheric aura
    float aura_size = rift_width * 0.5;
    float aura = smoothstep(aura_size + 0.1, aura_size, dist) * (1.0 - progress);
    
    vec3 col = color.rgb;
    col = mix(col, vec3(0.0), rift * 0.8); // Deep black core
    col += vec3(1.2, 0.9, 1.5) * (rift * 0.6 + stars * 3.0); // Luminescent edges
    
    float alpha = (rift * 1.5 + aura + stars) * (1.0 - pow(progress, 4.0));
    COLOR = vec4(col, alpha * color.a);
}
"""

const SCANNER_SHADER = """
shader_type canvas_item;
uniform float speed = 1.0;
uniform vec4 scan_color : source_color = vec4(0.0, 1.0, 0.4, 0.1);

void fragment() {
    float line = fract(UV.y * 20.0 - TIME * speed);
    float grid = fract(UV.x * 20.0 + sin(TIME * 0.1));
    float alpha = smoothstep(0.95, 1.0, line) + smoothstep(0.95, 1.0, grid);
    
    vec4 final_color = scan_color;
    final_color.a *= alpha * (1.0 - UV.y * 0.5);
    COLOR = final_color;
}
"""

const PREMIUM_BUBBLE_SHADER = """
shader_type canvas_item;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.8;

void fragment() {
    vec2 uv = UV - 0.5;
    float dist = length(uv);
    
    // Circle mask
    if (dist > 0.48) {
        discard;
    }
    
    // Thin outer rim
    float rim = smoothstep(0.48, 0.45, dist);
    float rim_edge = (1.0 - rim) * 0.5;
    
    // Base color (soft blue-white)
    vec4 color = vec4(0.8, 0.9, 1.0, 0.1);
    
    // Specular highlight (top-left)
    vec2 spec_pos = vec2(-0.18, -0.18);
    float spec_dist = length(uv - spec_pos);
    float specular = smoothstep(0.12, 0.0, spec_dist) * highlight_strength;
    
    // Small secondary glint (bottom-right)
    float glint = smoothstep(0.05, 0.0, length(uv - vec2(0.15, 0.15))) * 0.3;
    
    color.a += rim_edge + specular + glint;
    color.rgb += specular + glint;
    
    COLOR = color;
}
"""

const GOD_RAY_SHADER = """
shader_type canvas_item;
uniform float speed = 0.5;
uniform float density = 0.5;
uniform float opacity = 0.2;

void fragment() {
    // Source from the top center
    vec2 pos = vec2(UV.x - 0.5, UV.y * 1.5);
    float dist = length(pos);
    
    // Radial rays expanding and retracting from the top
    float ray = sin(dist * 12.0 - TIME * speed);
    ray += sin(dist * 8.0 + TIME * speed * 0.4);
    ray = smoothstep(0.1, 0.8, ray);
    
    // Fade at edges and towards bottom
    float mask = (1.0 - UV.y) * dist;
    
    COLOR = texture(TEXTURE, UV);
    COLOR.rgb += vec3(1.0, 0.95, 0.8) * ray * density * opacity * mask;
}
"""

const MIST_SHADER = """
shader_type canvas_item;
uniform vec4 mist_color : source_color = vec4(0.2, 0.4, 0.3, 0.5);
uniform float speed = 0.2;

void fragment() {
    vec2 uv = UV + vec2(TIME * speed, TIME * speed * 0.1);
	// Use large sine waves instead of high-frequency noise for a smoother "mist" look
    float wave = sin(uv.x * 2.0 + uv.y * 1.5 + TIME * speed);
    wave += sin(uv.y * 3.0 - uv.x * 1.0 + TIME * speed * 0.5);
    COLOR = mist_color;
    COLOR.a *= (0.5 + 0.5 * wave);
}
"""

const RIFT_PULSE_SHADER = """
shader_type canvas_item;
uniform vec4 glow_color : source_color = vec4(0.4, 0.8, 1.0, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv * vec2(1.0, 4.0)); // Stretched horizontal rift
	float mask = smoothstep(0.5, 0.0, dist);
	float pulse = 0.5 + 0.5 * sin(TIME * 5.0);
	COLOR = vec4(glow_color.rgb, mask * glow_color.a * pulse);
}
"""

const VOID_SHADER = """
shader_type canvas_item;
uniform float speed = 1.0;
uniform vec4 void_color : source_color = vec4(0.0, 0.0, 0.07, 0.6);

void fragment() {
    vec2 uv = UV;
    float noise = sin(uv.x * 10.0 + TIME * speed) * cos(uv.y * 10.0 - TIME * speed);
    float alpha = smoothstep(0.4, 0.6, abs(noise)) * void_color.a;
    COLOR = vec4(void_color.rgb, alpha);
}
"""

const GLOW_ORB_SHADER = """
shader_type canvas_item;
uniform vec4 orb_color : source_color = vec4(1.0, 1.0, 0.8, 0.5);

void fragment() {
    float d = length(UV - 0.5);
    float alpha = smoothstep(0.5, 0.0, d);
    COLOR = orb_color;
    COLOR.a *= alpha * (1.0 - d * 2.0);
}
"""

const STAR_SHADER = """
shader_type canvas_item;
uniform float flicker_speed = 2.0;

void fragment() {
    float f = sin(TIME * flicker_speed + fract(UV.x * 100.0) * 10.0) * 0.5 + 0.5;
    COLOR = texture(TEXTURE, UV);
    COLOR.a *= f;
}
"""

const SKILL_DATA = {
	# --- COMBAT BRANCH ---
	"block": {"name": "Block", "branch": "combat", "cost": 1, "req": [], "wave": 0, "desc": "Unlocks Block Action", "max": 1},
	"strike_mastery": {"name": "Strike Mastery", "branch": "combat", "cost": 2, "req": ["block"], "wave": 0, "desc": "+10% Atk per level", "max": 20},
	"dodge": {"name": "Dodge", "branch": "combat", "cost": 5, "req": ["block"], "wave": 10, "desc": "Unlocks Dodge Action", "max": 1},
	"brace": {"name": "Brace", "branch": "combat", "cost": 5, "req": ["block"], "wave": 10, "desc": "Unlocks Brace Action", "max": 1},
	"counter_strike": {"name": "Counter-Strike", "branch": "combat", "cost": 8, "req": ["strike_mastery"], "wave": 15, "desc": "20% Retaliation chance", "max": 5},
	"lethal_precision": {"name": "Lethal Precision", "branch": "combat", "cost": 10, "req": ["counter_strike"], "wave": 20, "desc": "+5% Crit Chance per level", "max": 10},
	"meditate": {"name": "Meditate", "branch": "combat", "cost": 12, "req": ["brace"], "wave": 25, "desc": "Unlocks Meditate Action", "max": 1},
	"overclock": {"name": "Overclock", "branch": "combat", "cost": 15, "req": ["meditate"], "wave": 40, "desc": "Unlocks Overclock Action", "max": 1},
	"interrupt": {"name": "Interrupt", "branch": "combat", "cost": 20, "req": ["overclock"], "wave": 60, "desc": "Unlocks Interrupt Action", "max": 1},
	"feint": {"name": "Feint", "branch": "combat", "cost": 30, "req": ["interrupt"], "wave": 90, "desc": "Unlocks Feint Action", "max": 1},
	"special": {"name": "Amulet Specialty", "branch": "combat", "cost": 40, "req": ["feint"], "wave": 120, "desc": "Unlocks Amulet Special Action", "max": 1},
	"s_tier_res": {"name": "S-Tier Resonance", "branch": "combat", "cost": 20, "req": ["lethal_precision"], "wave": 30, "desc": "+50% Awakened Dmg per level", "max": 5},
	"bloodlust": {"name": "Bloodlust", "branch": "combat", "cost": 30, "req": ["s_tier_res"], "wave": 50, "desc": "Heal 2% Max HP on hit", "max": 5},
	"omega_strike": {"name": "Omega Strike", "branch": "combat", "cost": 50, "req": ["bloodlust"], "wave": 80, "desc": "Base Attack hits twice", "max": 1},
	"ripper": {"name": "Dimensional Ripper", "branch": "combat", "cost": 75, "req": ["omega_strike"], "wave": 110, "desc": "Attacks ignore 50% DEF", "max": 1},
	"god_slayer": {"name": "God-Slayer", "branch": "combat", "cost": 150, "req": ["ripper"], "wave": 150, "desc": "+300% Total Dmg vs Bosses", "keystone": true, "max": 1},

	# --- ECONOMY BRANCH ---
	"mem_catalyst": {"name": "Memory Catalyst", "branch": "economy", "cost": 3, "req": [], "wave": 0, "desc": "+5% Memories gained on Wake", "max": 30},
	"thought_stream": {"name": "Thought Stream", "branch": "economy", "cost": 4, "req": ["mem_catalyst"], "wave": 0, "desc": "+10% Idle Thought speed", "max": 20},
	"dream_weaver": {"name": "Dream Weaver", "branch": "economy", "cost": 6, "req": ["thought_stream"], "wave": 5, "desc": "+15% Dreamcloud gain", "max": 10},
	"prestige_echo": {"name": "Prestige Echo", "branch": "economy", "cost": 15, "req": ["dream_weaver"], "wave": 15, "desc": "Keep 10% Thoughts on Fail", "max": 5},
	"abyssal_greed": {"name": "Abyssal Greed", "branch": "economy", "cost": 25, "req": ["prestige_echo"], "wave": 30, "desc": "+20% Gem drops from bosses", "max": 5},
	"insight_overflow": {"name": "Insight Overflow", "branch": "economy", "cost": 40, "req": ["abyssal_greed"], "wave": 60, "desc": "+50% Thoughts in Overclock", "max": 10},
	"compound_growth": {"name": "Compound Growth", "branch": "economy", "cost": 60, "req": ["insight_overflow"], "wave": 90, "desc": "+1% Memories per 10 Waves", "max": 1},
	"infinite_ref": {"name": "Infinite Reflections", "branch": "economy", "cost": 90, "req": ["compound_growth"], "wave": 120, "desc": "Memories Gained x5", "max": 1},
	"reality_arch": {"name": "Reality Architect", "branch": "economy", "cost": 200, "req": ["infinite_ref"], "wave": 150, "desc": "Unlock Memory Rebirth stat buys", "keystone": true, "max": 1},

	# --- SOUL/UTILITY BRANCH ---
	"safe_descent": {"name": "Safe Descent", "branch": "soul", "cost": 2, "req": [], "wave": 0, "desc": "-5% Instab growth/depth", "max": 20},
	"rapid_reflex": {"name": "Rapid Reflex", "branch": "soul", "cost": 5, "req": ["safe_descent"], "wave": 0, "desc": "-10% Dive Cooldown", "max": 10},
	"subconscious": {"name": "Subconscious Reach", "branch": "soul", "cost": 8, "req": ["rapid_reflex"], "wave": 10, "desc": "+4 Hrs Offline Limit", "max": 5},
	"lucid_control": {"name": "Lucid Control", "branch": "soul", "cost": 12, "req": ["subconscious"], "wave": 20, "desc": "Overclock reduces Instab by 5", "max": 10},
	"void_step": {"name": "Void Step", "branch": "soul", "cost": 20, "req": ["lucid_control"], "wave": 40, "desc": "10% Sub-wave skip chance", "max": 5},
	"eternal_sleeper": {"name": "Eternal Sleeper", "branch": "soul", "cost": 35, "req": ["void_step"], "wave": 70, "desc": "Instab cap 500%", "max": 1},
	"wake_guard": {"name": "Wake-Guard Aura", "branch": "soul", "cost": 55, "req": ["eternal_sleeper"], "wave": 100, "desc": "1 Second Chance per Dive", "max": 1},
	"drift": {"name": "Dimensional Drift", "branch": "soul", "cost": 80, "req": ["wake_guard"], "wave": 130, "desc": "No Instab during Boss fights", "max": 1},
	"sovereign": {"name": "Sovereign of Dreams", "branch": "soul", "cost": 250, "req": ["drift"], "wave": 150, "desc": "Total Instab Growth -90%", "keystone": true, "max": 1},
}

const PLASMA_SHADER = """
shader_type canvas_item;
uniform vec3 plasma_color = vec3(0.5, 0.8, 1.0);
uniform float speed = 1.0;

void fragment() {
    vec2 uv = UV * 2.0 - 1.0;
    float d = length(uv);
    float glow = 0.05 / abs(d - 0.5 + sin(TIME * speed + uv.x * 5.0) * 0.1);
    COLOR = vec4(plasma_color * glow, glow);
}
"""

const MERGE_SHADER = """
shader_type canvas_item;
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 glow_color : source_color = vec4(1.0, 0.8, 0.4, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float dist = length(uv);
	
	// Vortex swirl
	float angle = atan(uv.y, uv.x) + progress * 10.0;
	float radius = dist * (1.0 + progress * 2.0);
	
	// Pulse and shrink
	float ring = abs(sin(radius * 15.0 - progress * 20.0));
	float mask = smoothstep(0.5, 0.0, dist + progress * 0.2);
	
	vec4 color = glow_color;
	color.a *= ring * mask * (1.0 - progress);
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
		# if _em: print("[DEBUG] DreamsPanel: Linked to EquipmentManager ID: ", _em.get_instance_id())
	
	_combat_view    = find_child("CombatView",    true, false)
	_equipment_view = find_child("EquipmentView", true, false)
	_forge_view     = find_child("ForgeView",      true, false)
	_blacksmith_view = find_child("BlacksmithView", true, false)
	if _blacksmith_view == null:
		# Create it dynamically if missing in tscn
		_blacksmith_view = Control.new()
		_blacksmith_view.name = "BlacksmithView"
		_blacksmith_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if _content_area: _content_area.add_child(_blacksmith_view)
	
	_skills_view = find_child("SkillsView", true, false)
	if _skills_view == null:
		_skills_view = Control.new()
		_skills_view.name = "SkillsView"
		_skills_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if _content_area: _content_area.add_child(_skills_view)
	
	_bulk_dismantle_v = find_child("BulkDismantleView", true, false)
	if _bulk_dismantle_v == null:
		_bulk_dismantle_v = Control.new()
		_bulk_dismantle_v.name = "BulkDismantleView"
		_bulk_dismantle_v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		if _content_area: _content_area.add_child(_bulk_dismantle_v)
	
	_wave_label     = find_child("WaveLabel",      true, false)
	_start_wave_btn = find_child("StartWaveBtn",   true, false)
	_prev_wave_btn  = find_child("PrevWaveBtn",    true, false)
	_next_wave_btn  = find_child("NextWaveBtn",    true, false)
	_smooth_auto_box = find_child("SmoothAutoBox", true, false)
	_smooth_bar      = find_child("SmoothProgressBar", true, false)
	
	# SUBWAVE BUTTON INJECTION
	if _wave_label:
		var wave_header = _wave_label.get_parent()
		if wave_header:
			var sub_hbx = HBoxContainer.new()
			sub_hbx.name = "SubwaveControls"
			
			_subwave_prev_btn = Button.new()
			_subwave_prev_btn.text = "<"
			_subwave_prev_btn.custom_minimum_size = Vector2(30, 30)
			_subwave_prev_btn.pressed.connect(_on_prev_subwave_pressed)
			
			_subwave_next_btn = Button.new()
			_subwave_next_btn.text = ">"
			_subwave_next_btn.custom_minimum_size = Vector2(30, 30)
			_subwave_next_btn.pressed.connect(_on_next_subwave_pressed)
			
			sub_hbx.add_child(_subwave_prev_btn)
			sub_hbx.add_child(_subwave_next_btn)
			
			wave_header.add_child(sub_hbx)
			wave_header.move_child(sub_hbx, _wave_label.get_index() + 1)
	
	# AUTO STATS INJECTION
	var action_panel = find_child("ActionPanel", true, false)
	if action_panel:
		_auto_stats_lbl = Label.new()
		_auto_stats_lbl.name = "AutoStatsLbl"
		_auto_stats_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_auto_stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_auto_stats_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_auto_stats_lbl.add_theme_color_override("font_color", Color(0, 1, 0.4, 0.7))
		_auto_stats_lbl.add_theme_font_size_override("font_size", 24)
		_auto_stats_lbl.visible = false
		action_panel.add_child(_auto_stats_lbl)
	
	# Show combat view by default
	_show_view("combat")
	
	# Button sidebar connections
	var btn_combat = find_child("BtnCombat", true, false)
	var btn_equip  = find_child("BtnEquipment", true, false)
	var btn_forge  = find_child("BtnForge", true, false)
	var btn_close  = find_child("BtnClose", true, false)
	
	# v13: Skills button
	var btn_skills = find_child("BtnSkills", true, false)
	if btn_skills == null:
		var side_vbox = find_child("SidebarVBox", true, false)
		if side_vbox:
			btn_skills = Button.new()
			btn_skills.name = "BtnSkills"
			btn_skills.text = "✦ Skills"
			btn_skills.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn_skills.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var ref_btn = btn_forge if btn_forge else btn_equip
			if ref_btn:
				btn_skills.add_theme_stylebox_override("normal", ref_btn.get_theme_stylebox("normal"))
				btn_skills.add_theme_stylebox_override("hover", ref_btn.get_theme_stylebox("hover"))
				btn_skills.add_theme_stylebox_override("pressed", ref_btn.get_theme_stylebox("pressed"))
				btn_skills.add_theme_font_size_override("font_size", ref_btn.get_theme_font_size("font_size"))
			
			side_vbox.add_child(btn_skills)
			side_vbox.move_child(btn_skills, btn_combat.get_index() + 1)
	
	# BLACKSMITH BUTTON DYNAMIC INJECTION
	var btn_blacksmith = find_child("BtnBlacksmith", true, false)
	if btn_blacksmith == null:
		var side_vbox = find_child("SidebarVBox", true, false)
		if side_vbox:
			btn_blacksmith = Button.new()
			btn_blacksmith.name = "BtnBlacksmith"
			btn_blacksmith.text = "⚒ Blacksmith"
			btn_blacksmith.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn_blacksmith.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			# Style it like the Forge button
			var ref_btn = btn_forge if btn_forge else btn_equip
			if ref_btn:
				btn_blacksmith.add_theme_stylebox_override("normal", ref_btn.get_theme_stylebox("normal"))
				btn_blacksmith.add_theme_stylebox_override("hover", ref_btn.get_theme_stylebox("hover"))
				btn_blacksmith.add_theme_stylebox_override("pressed", ref_btn.get_theme_stylebox("pressed"))
				btn_blacksmith.add_theme_font_size_override("font_size", ref_btn.get_theme_font_size("font_size"))
				if ref_btn.icon: btn_blacksmith.icon = ref_btn.icon
			
			side_vbox.add_child(btn_blacksmith)
			if btn_forge:
				side_vbox.move_child(btn_blacksmith, btn_forge.get_index() + 1)
	
	# BULK DISMANTLE BUTTON DYNAMIC INJECTION
	var btn_bulk = find_child("BtnBulkDismantle", true, false)
	if btn_bulk == null:
		var side_vbox = find_child("SidebarVBox", true, false)
		if side_vbox:
			btn_bulk = Button.new()
			btn_bulk.name = "BtnBulkDismantle"
			btn_bulk.text = "✖ Bulk Dismantle"
			btn_bulk.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn_bulk.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			
			var ref_btn = btn_forge if btn_forge else btn_equip
			if ref_btn:
				btn_bulk.add_theme_stylebox_override("normal", ref_btn.get_theme_stylebox("normal"))
				btn_bulk.add_theme_stylebox_override("hover", ref_btn.get_theme_stylebox("hover"))
				btn_bulk.add_theme_stylebox_override("pressed", ref_btn.get_theme_stylebox("pressed"))
				btn_bulk.add_theme_font_size_override("font_size", ref_btn.get_theme_font_size("font_size"))
			
			side_vbox.add_child(btn_bulk)
			if btn_blacksmith:
				side_vbox.move_child(btn_bulk, btn_blacksmith.get_index() + 1)
			
			btn_bulk.pressed.connect(func(): _show_view("bulk_dismantle"))

	# FARM BUTTON DYNAMIC INJECTION
	var main_header = find_child("HeaderRow", true, false)
	if main_header and _farm_btn == null:
		_farm_btn = Button.new()
		_farm_btn.name = "BtnFarm"
		_farm_btn.text = "PUSHING"
		_farm_btn.custom_minimum_size = Vector2(100, 44)
		_farm_btn.add_theme_color_override("font_color", Color(1, 0.4, 0.4)) # Red for Pushing
		main_header.add_child(_farm_btn)
		main_header.move_child(_farm_btn, main_header.get_child_count() - 1) # Put it after Start button
		_farm_btn.pressed.connect(_on_farm_pressed)

	if btn_combat: 
		btn_combat.pressed.connect(func(): 
			_show_view("combat")
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("BtnCombat")
		)
	if btn_equip:  
		btn_equip.pressed.connect(func():  
			_show_view("equipment")
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("BtnEquipment")
		)
	if btn_forge:  
		btn_forge.pressed.connect(func():  
			_show_view("forge")
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("BtnForge")
		)
	if btn_blacksmith:
		btn_blacksmith.pressed.connect(func(): 
			_show_view("blacksmith")
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("BtnBlacksmith")
		)
	if btn_skills:
		btn_skills.pressed.connect(func(): 
			_show_view("skills")
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("BtnSkills")
		)
	if btn_close:  btn_close.pressed.connect(func():  visible = false)
	
	if _start_wave_btn:
		_start_wave_btn.pressed.connect(func():
			_on_start_wave_pressed()
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("StartWaveBtn")
		)
	if _prev_wave_btn:
		_prev_wave_btn.pressed.connect(func():
			_on_prev_wave_pressed()
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("PrevWaveBtn")
		)
	if _next_wave_btn:
		_next_wave_btn.pressed.connect(func():
			_on_next_wave_pressed()
			var tm = get_node_or_null("/root/TutorialManage")
			if tm and tm.has_method("on_ui_element_clicked"):
				tm.on_ui_element_clicked("NextWaveBtn")
		)
	
	# Initial progress load
	_load_wave_progress(current_wave)
	
	if _ce:
		_ce.combat_ended.connect(_on_wave_ended)
		_ce.hp_changed.connect(_on_hp_changed)
		_ce.damage_dealt.connect(_on_damage_dealt)
		_ce.message_logged.connect(_on_message_logged)
		_ce.turn_started.connect(_on_turn_update)
		_ce.intent_revealed.connect(_on_intent_revealed)
		_ce.player_turn.connect(_on_player_turn)
		_ce.vfx_triggered.connect(_trigger_attack_vfx)
	
	_setup_hp_bar_styles()
	_update_wave_label()

	# Precompile shaders
	_precompile_shaders()

func _on_prev_subwave_pressed() -> void:
	if current_subwave > 1:
		current_subwave -= 1
		_update_wave_label()
		if _wave_in_progress:
			_cancel_current_combat()
			_on_start_wave_pressed()
		
func _on_next_subwave_pressed() -> void:
	var max_subwave = _get_max_subwave_for_current_wave()
	if current_subwave < max_subwave:
		current_subwave += 1
		_update_wave_label()
		if _wave_in_progress:
			_cancel_current_combat()
			_on_start_wave_pressed()
		
func _get_max_subwave_for_current_wave() -> int:
	if _gm:
		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, {})
		if wave_data is Dictionary:
			return maxi(1, int(wave_data.get("best_subwave", 1)))
	return 1

func _precompile_shaders() -> void:
	_precompiled_shaders["slash"] = ShaderMaterial.new()
	_precompiled_shaders["slash"].shader = Shader.new()
	_precompiled_shaders["slash"].shader.code = V_SLASH_SHADER

	_precompiled_shaders["stab"] = ShaderMaterial.new()
	_precompiled_shaders["stab"].shader = Shader.new()
	_precompiled_shaders["stab"].shader.code = V_STAB_SHADER

	_precompiled_shaders["blunt"] = ShaderMaterial.new()
	_precompiled_shaders["blunt"].shader = Shader.new()
	_precompiled_shaders["blunt"].shader.code = V_BLUNT_SHADER

	_precompiled_shaders["awakened"] = ShaderMaterial.new()
	_precompiled_shaders["awakened"].shader = Shader.new()
	_precompiled_shaders["awakened"].shader.code = V_AWAKENED_SHADER

# ── View switching ──────────────────────────────────────────────────────────────
func _show_view(which: String) -> void:
	if _combat_view:    _combat_view.visible    = (which == "combat")
	if _equipment_view: _equipment_view.visible = (which == "equipment")
	if _forge_view:     _forge_view.visible     = (which == "forge")
	if _blacksmith_view: _blacksmith_view.visible = (which == "blacksmith")
	if _skills_view:     _skills_view.visible     = (which == "skills")
	if _bulk_dismantle_v: _bulk_dismantle_v.visible = (which == "bulk_dismantle")
	
	if which == "equipment": _refresh_equipment_view()
	if which == "forge":     _refresh_forge_view()
	if which == "blacksmith": _refresh_blacksmith_view()
	if which == "skills":     _refresh_skills_view()
	if which == "bulk_dismantle": _refresh_bulk_dismantle_view()
	
	# Polish: Always hide tooltip when switching tabs to avoid lingering UI
	_hide_custom_tooltip(true)

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
	
	# 1. Overpower Check (High Defense OR High Attack Efficiency)
	var enemy: Dictionary = _build_enemy_for_wave(current_wave)
	var p_stats: Dictionary = _em.get_player_combat_stats() if _em != null else {"attack": 10.0, "max_hp": 100.0, "defense": 5.0}
	
	var is_overpowered = (p_stats.attack > enemy.hp)
	
	# Atmospheric Background Shift (Apply BEFORE auto-battle check)
	_apply_depth_atmosphere(current_wave)
	
	# REFRESH UI INSTANTLY
	_update_combat_ui_for_start(p_stats, enemy)

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
	
	# Global Cleanup (Stop all previous loops/FX)
	_stop_all_depth_fx()
	
	# 1. Update Background Texture
	if _combat_bg:
		var bg_names = [
			"shallow.png", "descent.png", "pressure.png", "murk.png", "rift.png",
			"hollow.png", "dread.png", "chasm.png", "silence.png", "veil.png",
			"ruin.png", "eclipse.png", "voidline.png", "blackwater.png", "abyss.png"
		]
		var bg_file = bg_names[depth - 1]
		var bg_path = "res://UI/DepthBarBG/" + bg_file
		if ResourceLoader.exists(bg_path):
			_combat_bg.texture = load(bg_path)
			_combat_bg.visible = true
			_combat_bg.material = null # Reset material
			_combat_bg.modulate = Color(1, 1, 1, 1.0) # Ensure full visibility
			# instead of z_index -1 which can hide it, ensure it's first child
			var p = _combat_bg.get_parent()
			if p: p.move_child(_combat_bg, 0)
	
	# 2. Content Area Color
	var content_area = find_child("ContentArea", true, false) as Control
	if content_area:
		var bg_color = _get_depth_color(depth)
		# Depth 4 special: Make background darker to show murk better
		if depth == 4: bg_color = Color(0.02, 0.05, 0.03, 0.95)
		
		var style = content_area.get_theme_stylebox("panel") as StyleBoxFlat
		if style == null:
			style = StyleBoxFlat.new()
			content_area.add_theme_stylebox_override("panel", style)
		var tween = create_tween()
		tween.tween_property(style, "bg_color", bg_color, 1.5).set_trans(Tween.TRANS_SINE)

	# 3. Depth-Specific Logic (Manual Effect Control)
	match depth:
		1: # Shallows
			_set_bg_shader(SHIMMER_SHADER)
			_start_bubble_loop(Color(1, 1, 1, 0.4))
		2: # Descent - Sunlight shimmer
			_set_bg_shader(GOD_RAY_SHADER, {"speed": 0.4, "opacity": 0.2})
		3: # Pressure - Sunlight shimmer downwards
			_set_bg_shader(GOD_RAY_SHADER, {"speed": 0.2, "angle": 0.0, "opacity": 0.3})
		4: # Murk - 100% visibility + restored subtle mist
			if _combat_bg: 
				_combat_bg.modulate.a = 1.0
				_combat_bg.material = null
			_start_mist_loop(Color(0.2, 0.3, 0.2, 0.5), 0.1)
		5: # Rift - Premium Energy Flashes
			_start_rift_flash_loop()
		6: # Hollow - Floor reflection
			_set_bg_shader(GOD_RAY_SHADER, {"speed": 0.6, "angle": 1.5, "opacity": 0.4})
		7: # Dread - Wind + Lava Light
			_start_void_ripple_loop() # Changed from fast clouds
			_start_lava_glow_loop()
		8: # Chasm - Slow Clouds
			_start_void_ripple_loop() # Changed from slow clouds
		9: # Silence - No movement
			# No specific effects, just the background and color changes
			pass
		10: # Veil - Heavy Shimmer + Stars
			_set_bg_shader(SHIMMER_SHADER, {"amplitude": 0.02, "speed": 1.0})
			_start_star_field_loop(true) # Including shooting stars
		11: # Ruin - Plasma floor + Mist
			_start_plasma_fissure_loop()
			_start_mist_loop(Color(0.3, 0.3, 0.3, 0.3), 0.1)
		12: # Eclipse - Flickering Stars
			_start_star_field_loop(false) # Just flickering
		13: # Voidline - Lightning + Distorted Stars
			_start_lightning_loop()
			_start_star_field_loop(false, true) # Distorted stars
		14: # Blackwater - Shimmer + Black Bubbles
			_set_bg_shader(SHIMMER_SHADER, {"speed": 0.3})
			_start_bubble_loop(Color(0, 0, 0, 0.6))
		15: # Abyss - Top shimmer + Fading lights
			_set_bg_shader(GOD_RAY_SHADER, {"speed": 0.1, "angle": 0.0, "opacity": 0.15})
			_start_fading_lights_loop()

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
	if _is_smooth_looping: return # Block legacy logic if smooth loop is active
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
		_em.add_to_inventory(item)

		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
		if not (wave_data is Dictionary): wave_data = {"mastery": int(wave_data), "best_subwave": 0}
		wave_data.mastery = int(wave_data.get("mastery", 0)) + 1
		wave_data.best_subwave = maxi(int(wave_data.get("best_subwave", 0)), current_subwave)
		_gm.wave_mastery[wave_id] = wave_data
		
		_gm.save_game()
	
	if not _farming_mode:
		current_subwave += 1
	_update_wave_label()
	
	if auto_battle_active:
		await get_tree().create_timer(1.0).timeout
		_on_start_wave_pressed()

func _start_smooth_auto_battle(p_stats: Dictionary, enemy_data: Dictionary) -> void:
	if _is_smooth_looping: return
	_is_smooth_looping = true
	
	# STOP standard engine to prevent parallel reward triggers
	if _ce: _ce.active = false

	# 1. Hide the HP bars and log, but keep nav buttons
	var php = find_child("PlayerHpBar", true, false)
	var ehp = find_child("EnemyHpBar", true, false)
	var log_box = find_child("CombatLog", true, false)
	
	# REDUNDANT LABELS: Usually named "LabelYou" and "LabelEnemy" or similar
	var lbl_you = find_child("LabelYou", true, false)
	var lbl_enemy = find_child("LabelEnemy", true, false)
	var you_lbl_node = find_child("YouLbl", true, false)
	var enemy_lbl_node = find_child("EnemyLbl", true, false)
	
	if php: php.visible = false
	if ehp: ehp.visible = false
	if log_box: log_box.visible = false
	if lbl_you: lbl_you.visible = false
	if lbl_enemy: lbl_enemy.visible = false
	if you_lbl_node: you_lbl_node.visible = false
	if enemy_lbl_node: enemy_lbl_node.visible = false
	
	# Ensure nav buttons are visible as per user request
	if _prev_wave_btn: _prev_wave_btn.visible = true
	if _next_wave_btn: _next_wave_btn.visible = true
	if _start_wave_btn: _start_wave_btn.visible = true
	
	# 2. Show smooth UI box
	if _smooth_auto_box: 
		_smooth_auto_box.visible = true
	if _smooth_bar:
		_smooth_bar.visible = true
	
	if _auto_stats_lbl:
		_auto_stats_lbl.visible = true
	
	_smooth_loop(p_stats, enemy_data)

func _calculate_smooth_efficiency(ps: Dictionary, ed: Dictionary) -> Dictionary:
	var ratio = ps.attack / max(1.0, ed.hp)
	var subwaves = maxi(1, int(floor(ratio)))
	return {"time": 4.0, "subwaves": subwaves}

func _smooth_loop(ps: Dictionary, ed: Dictionary) -> void:
	var cycle_count = 0
	while _is_smooth_looping and auto_battle_active:
		cycle_count += 1
		# REFRESH STATS
		if _em: ps = _em.get_player_combat_stats()
		ed = _build_enemy_for_wave(current_wave)
		
		# STOP loop if no longer overpowered
		if ps.attack <= ed.hp:
			_stop_smooth_auto_battle()
			break
			
		var data = _calculate_smooth_efficiency(ps, ed)
		
		if visible:
			_update_stats_panel(ps, ed)
			_update_combat_ui_for_start(ps, ed)
			
			if _auto_stats_lbl:
				var efficiency = (ps.attack / max(1.0, ed.hp)) * 100.0
				_auto_stats_lbl.text = "AUTOMATION ACTIVE\\nEfficiency: %.0f%% | Compression: %dx" % [efficiency, data.subwaves]
		
		# 1. Progress the Bar
		if _smooth_bar and visible:
			_smooth_bar.value = 0
			_current_smooth_tween = create_tween()
			_current_smooth_tween.set_trans(Tween.TRANS_LINEAR)
			_current_smooth_tween.tween_property(_smooth_bar, "value", 100, data.time)
			await _current_smooth_tween.finished
			_current_smooth_tween = null
		else:
			await get_tree().create_timer(data.time).timeout
		
		# Track last successful automated subwave
		_last_automated_subwave = current_subwave
		
		# 2. Give Rewards (Only save every 10 cycles for performance)
		var should_save = (cycle_count % 10 == 0)
		_give_condensed_rewards(data.subwaves, should_save)
		_update_wave_label()
		
		# 3. Reset for next cycle (Safeguard for restart)
		if not auto_battle_active:
			_is_smooth_looping = false
			break
			
		# Safety halt if enemy becomes too strong
		if ed.attack > 0.8 * ps.defense:
			_stop_smooth_auto_battle()
			break

func _give_condensed_rewards(count: float, save: bool = true) -> void:
	var total_reward = 0.0
	var base_reward_per_wave = float(current_wave) * 25.0 * 2.0
	
	# Calculate summed rewards for all subwaves in this cycle
	for i in range(int(count)):
		total_reward += base_reward_per_wave * (1.0 + ((current_subwave + i) * 0.05))
	
	if _gm:
		_gm.dreamcloud += total_reward
		_gm._refresh_top_ui()
		
		# Batch mastery
		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
		if not (wave_data is Dictionary): wave_data = {"mastery": int(wave_data), "best_subwave": 0}
		wave_data.mastery = int(wave_data.get("mastery", 0)) + int(count)
		wave_data.best_subwave = maxi(int(wave_data.get("best_subwave", 0)), current_subwave + int(count))
		_gm.wave_mastery[wave_id] = wave_data
		
		# UNLOCK NEXT WAVE if mastery is hit
		if wave_data.mastery >= 10:
			highest_wave_reached = maxi(highest_wave_reached, current_wave + 1)
		
		# NEW LOOT SYSTEM: 20% chance, 1 drop max, Rarity up per subwave milestones
		if randf() < 0.20:
			var base_rarity = _calculate_drop_rarity_v2(current_wave, current_subwave)
			
			# Updated Rarity scaling logic as requested
			var tier_boost = 0
			if count >= 30: tier_boost = 4
			elif count >= 15: tier_boost = 3
			elif count >= 10: tier_boost = 2
			elif count >= 5: tier_boost = 1
			
			var final_rarity = base_rarity
			for j in range(tier_boost):
				final_rarity = _em.get_next_rarity(final_rarity)
			
			var slots = ["weapon","armor","amulet","ring1","helmet","talisman"]
			var item = _em.generate_item(final_rarity, slots.pick_random(), current_wave)
			
			if _em.add_to_inventory(item):
				_add_reward_item(item.name, item.rarity, _get_item_icon_path(item, item.slot))
			
		_add_reward_item("Dreamclouds", "+%s" % _gm.call("_fmt_num_compact", total_reward) if _gm.has_method("_fmt_num_compact") else str(int(total_reward)), "")
		if save: 
			_save_wave_progress() # PERSISTENCE FIX
			_gm.save_game()
	
	# UPDATE: If farming mode, DO NOT increment current_subwave
	if not _farming_mode:
		current_subwave += int(count)

func _stop_smooth_auto_battle() -> void:
	_is_smooth_looping = false
	_wave_in_progress = false
	if _current_smooth_tween:
		_current_smooth_tween.kill()
		_current_smooth_tween = null
	if _smooth_bar:
		_smooth_bar.value = 0
	if _smooth_auto_box: _smooth_auto_box.visible = false
	# Restore standard combat elements
	var php = find_child("PlayerHpBar", true, false)
	var ehp = find_child("EnemyHpBar", true, false)
	var log_box = find_child("CombatLog", true, false)
	if php: php.visible = true
	if ehp: ehp.visible = true
	if log_box: log_box.visible = true
	if _prev_wave_btn: _prev_wave_btn.visible = true
	if _next_wave_btn: _next_wave_btn.visible = true
	if _start_wave_btn: _start_wave_btn.visible = true
	
	if _auto_stats_lbl:
		_auto_stats_lbl.visible = false
	
	var lbl_you = find_child("LabelYou", true, false)
	var lbl_enemy = find_child("LabelEnemy", true, false)
	var you_lbl_node = find_child("YouLbl", true, false)
	var enemy_lbl_node = find_child("EnemyLbl", true, false)
	if lbl_you: lbl_you.visible = true
	if lbl_enemy: lbl_enemy.visible = true
	if you_lbl_node: you_lbl_node.visible = true
	if enemy_lbl_node: enemy_lbl_node.visible = true
	
	# Force result banner/etc to be hidden if we just stopped
	var res = find_child("ResultBanner", true, false)
	if res: res.visible = false
	_update_wave_label()
	
	# BUG FIX: If auto-battle is active, immediately start normal combat
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
	"Still Watcher", "Breathless Ghoul", "Muted Echo", "Statatonic Horror", "Silent Sereph", "Quiet Whisper", "Stillness", "Void Lurker", "Oblivion", "The Silent One",
	"Star Drifter", "Nebula Wraith", "Shimmering Husk", "Veil Walker", "Comet Horror", "Astral Spinner", "Black Hole Heart", "Constellation Ghoul", "Nova Spirit", "The Veil Sovereign",
	"Rusted Knight", "Broken Idol", "Crumbling Wall", "Decay Sprite", "Shattered Mirror", "Ruined Hope", "Fallen Pillar", "Corroded Core", "Dust Sentinel", "Architect of Ruin",
	"Solar Shadow", "Lunar Wisp", "Eclipse Eye", "Black Sun Remnant", "Corona Ghoul", "Twilight Terror", "Umbra Elemental", "Starless Void", "Celestial Husk", "Eclipse Lord",
	"Cube Entity", "Glitch Ghost", "Vector Horror", "Polygon Prowler", "Binary Beast", "Broken Logic", "Abstract Aggression", "Vertex Void", "Static Man", "Error Source",
	"Ink Tentacle", "Drowned Soul", "Black Tide", "Murky Hand", "Tar Spectre", "Fluid Fear", "Abyssal Current", "Pressure Beast", "Inky Depth", "Lord of Water",
	"The Unmaker", "Abyss Crawler", "Final Regret", "Singularity", "End of Days", "Total Oblivion", "Waking Nightmare", "The Void Caller", "Shattered Infinity", "DREAMER'S END"
]

func _build_enemy_for_wave(wave: int) -> Dictionary:
	var subwave_mult: float = 1.0 + ((current_subwave - 1) * 0.1)
	
	# Exponential scaling to match gear budget jumps, significantly boosted for challenge
	var wave_pow: float = pow(1.1, float(wave - 1)) # 10% per wave compound
	var hp: float   = (20.0  + (wave_pow * 100.0)) * subwave_mult # Wave 1 = 120 HP
	var atk: float  = (10.0 + (wave_pow * 15.0)) * subwave_mult  # Wave 1 = 25 Atk
	var def_: float = (2.0  + (wave_pow * 4.0)) * subwave_mult   # Wave 1 = 6 Def
	
	# NEW: Special case for absolute first encounter (Wave 1, Subwave 1)
	if wave == 1 and current_subwave == 1:
		atk = 5.0
		def_ = 0.0
		hp = 50.0
	
	# Lookup name from the 150 unique list
	var enemy_idx = clampi(wave - 1, 0, ENEMY_NAMES.size() - 1)
	var enemy_name = ENEMY_NAMES[enemy_idx]
	
	# 1. Visual "Darkness" based on Wave progress
	var darkness = clampf(float(wave) / 150.0, 0.0, 1.0)
	
	# 2. Dynamic Sprite Lookup
	var sprite_path = "res://assets/combat/enemy_%d.png" % wave
	if not ResourceLoader.exists(sprite_path):
		# Fallback to depth-based sprites
		var depth = clampi(int(float(wave - 1) / 10.0) + 1, 1, 15)
		if depth >= 10: sprite_path = SPRITES["nightmare"]
		elif depth >= 5: sprite_path = SPRITES["shadow"]
		else: sprite_path = SPRITES["sheep"]
	
	return {
		"name":    enemy_name, # Clean name
		"hp":      hp,
		"attack":  atk,
		"defense": def_,
		"wave":    wave,
		"subwave": current_subwave,
		"sprite":  sprite_path,
		"darkness": darkness
	}

func _on_wave_ended(result: Dictionary) -> void:
	# print("[COMBAT] Wave ended handler triggered. Won: ", result.get("won", false))
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
			_em.add_to_inventory(drop)
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
		if not _farming_mode:
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

			# PUSHING MODE: Auto-advance to next wave if mastery is high enough
			if not _farming_mode and cur_mastery >= 10 and current_wave < highest_wave_reached:
				current_wave += 1
				_update_wave_label() # Instant update
			
			var timer = get_tree().create_timer(1.2)
			timer.timeout.connect(func():
				if visible and not _wave_in_progress:
					# print("[COMBAT] Auto-starting next combat (Manual Victory Path)...")
					call_deferred("_on_start_wave_pressed")
			)
	else:
		# On loss: stay at same wave, decrement subwave by 1
		current_subwave = maxi(1, current_subwave - 1)
		_update_wave_label()
		
		if _gm:
			_gm.instability = minf(_gm.instability + 3.0, _gm.get_instability_cap(_gm.get_current_depth()))
			_gm._refresh_top_ui()
		_show_wave_result(false, false, 0.0, {})
	
	if _gm:
		_save_wave_progress()
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
		# Boost enemy size
		sprite_rect.custom_minimum_size = Vector2(480, 480)
		sprite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
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
	
	# Smooth transitions
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	if player_hp_bar:
		tween.tween_property(player_hp_bar, "value", p_hp, 0.4)
	if enemy_hp_bar:
		tween.tween_property(enemy_hp_bar, "value", e_hp, 0.4)
		
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
		# Add a subtle shake on enemy hit
		if target_type == "enemy" and amount > 0:
			_shake_enemy_sprite()

func _shake_enemy_sprite(intensity: float = 1.0) -> void:
	var sprite := find_child("EnemySprite", true, false) as Control
	if not sprite: return
	var orig = sprite.position
	var t = create_tween()
	var amt = 5.0 * intensity
	for i in range(4):
		t.tween_property(sprite, "position", orig + Vector2(randf_range(-amt, amt), randf_range(-amt, amt)), 0.05)
	t.tween_property(sprite, "position", orig, 0.05)

func _trigger_attack_vfx(type: String) -> void:
	var sprite := find_child("EnemySprite", true, false) as Control
	if not sprite: return
	
	var overlay = ColorRect.new()
	overlay.custom_minimum_size = sprite.size
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.add_child(overlay)
	
	var code = V_SLASH_SHADER
	var color = Color(1, 1, 1, 0.8)
	
	match type:
		"stab", "pierce":
			code = V_STAB_SHADER
			color = Color(1, 0.9, 0.5, 0.9) # Golden Pierce
			_shake_enemy_sprite(0.4) # Sharp but light shake
		"blunt", "bludgeon":
			code = V_BLUNT_SHADER
			color = Color(0.9, 0.9, 1.0, 0.8) # Heavy Impact
			_shake_enemy_sprite(2.0) # HEAVY shake for bludgeon
		"awakened":
			code = V_AWAKENED_SHADER
			color = Color(0.7, 0.3, 1.0, 1.0) # Void
			_shake_enemy_sprite(3.5) # MAXIMUM SHAKE
	
	# Create Material using precompiled shader if possible
	var mat: ShaderMaterial
	if _precompiled_shaders.has(type) and _precompiled_shaders[type] is ShaderMaterial:
		mat = _precompiled_shaders[type].duplicate() as ShaderMaterial
	else:
		mat = ShaderMaterial.new()
		var s = Shader.new()
		s.code = code
		mat.shader = s
		_precompiled_shaders[type] = mat
		
	mat.set_shader_parameter("color", color)
	overlay.material = mat
	
	# Small delay to ensure shader parses before tweening its parameters
	await get_tree().process_frame
	
	var t = create_tween()
	var duration = 0.25
	if type == "awakened":
		duration = 0.6 # Cinematic slower animation for S-Tier
	
	t.tween_method(func(val: float): if is_instance_valid(mat): mat.set_shader_parameter("progress", val), 0.0, 1.0, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(overlay, "modulate:a", 0.0, 0.2)
	t.chain().tween_callback(func(): if is_instance_valid(overlay): overlay.queue_free())

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

func _start_bubble_loop(color: Color) -> void:
	if not _wave_in_progress: return
	
	var timer = get_tree().create_timer(randf_range(0.5, 1.5))
	timer.timeout.connect(func():
		var d = clampi(int(float(current_wave - 1) / 10.0) + 1, 1, 15)
		if _wave_in_progress and visible and d == 1:
			_spawn_bubble(color)
			_start_bubble_loop(color)
	)

func _spawn_bubble(color: Color = Color(1, 1, 1, 0.4)) -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	
	# Create a premium shader-based bubble
	var bubble = ColorRect.new()
	var b_size = randf_range(10.0, 30.0)
	bubble.custom_minimum_size = Vector2(b_size, b_size)
	bubble.color = Color.WHITE
	bubble.modulate = color 
	
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = PREMIUM_BUBBLE_SHADER
	mat.shader = sh
	bubble.material = mat
	
	content.add_child(bubble)
	if _combat_bg and _combat_bg.get_parent() == content:
		content.move_child(bubble, _combat_bg.get_index() + 1)
	else:
		content.move_child(bubble, 0)
	
	var rect = content.get_global_rect()
	var start_pos = Vector2(
		randf_range(rect.position.x + 20, rect.position.x + rect.size.x - 20),
		rect.position.y + rect.size.y + 20
	)
	bubble.global_position = start_pos
	bubble.pivot_offset = Vector2(b_size/2.0, b_size/2.0)
	
	var duration = randf_range(5.0, 9.0)
	var drift = randf_range(-60, 60)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(bubble, "global_position:y", rect.position.y - 40, duration).set_trans(Tween.TRANS_SINE)
	tween.tween_property(bubble, "global_position:x", start_pos.x + drift, duration).set_trans(Tween.TRANS_SINE)
	
	var wobble_tween = create_tween().set_loops()
	var wobble_speed = randf_range(0.4, 0.8)
	wobble_tween.tween_property(bubble, "scale", Vector2(1.1, 0.9), wobble_speed).set_trans(Tween.TRANS_SINE)
	wobble_tween.tween_property(bubble, "scale", Vector2(0.9, 1.1), wobble_speed).set_trans(Tween.TRANS_SINE)
	
	tween.chain().tween_property(bubble, "modulate:a", 0.0, 1.0)
	tween.chain().tween_callback(bubble.queue_free)
	tween.chain().tween_callback(wobble_tween.kill)

# ── New Loop Handlers ──────────────────────────────────────────────────────────

func _set_bg_shader(code: String, params: Dictionary = {}) -> void:
	if not _combat_bg: return
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = code
	mat.shader = sh
	for key in params:
		mat.set_shader_parameter(key, params[key])
	_combat_bg.material = mat


func _start_mist_loop(color: Color, speed: float) -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	
	var mist = ColorRect.new()
	mist.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mist.color = Color.WHITE
	
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = MIST_SHADER
	mat.shader = sh
	mat.set_shader_parameter("mist_color", color)
	mat.set_shader_parameter("speed", speed)
	mist.material = mat
	
	content.add_child(mist)
	if _combat_bg: content.move_child(mist, _combat_bg.get_index() + 1)
	else: content.move_child(mist, 0)
	
	mist.modulate.a = 0.0
	create_tween().tween_property(mist, "modulate:a", 1.0, 2.0)
	# Unlike particles, mist is a persistent overlay. 
	# We should tag it for removal in _stop_all_depth_fx.
	mist.add_to_group("depth_fx")

func _start_fading_lights_loop() -> void:
	_start_generic_spawner(func():
		var color = Color(0.1, 0.4, 1.0, 0.2) # Deep blue/cyan glow
		if randf() < 0.3: color = Color(1.0, 0.2, 0.5, 0.15) # Rare pinkish wisp
		_spawn_glow_orb(color)
	, 1.0, 3.0)

func _start_rift_flash_loop() -> void:
	var d = clampi(int(float(current_wave - 1) / 10.0) + 1, 1, 15)
	if d != 5: return
	_start_generic_spawner(func():
		var cd = clampi(int(float(current_wave - 1) / 10.0) + 1, 1, 15)
		if cd == 5: _spawn_rift_flash(Color(0.4, 0.8, 1.0, 0.6))
	, 0.8, 2.0)

func _spawn_rift_flash(color: Color) -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	
	var flash = ColorRect.new()
	var f_width = randf_range(60, 150)
	var f_height = randf_range(20, 40)
	flash.custom_minimum_size = Vector2(f_width, f_height)
	flash.pivot_offset = Vector2(f_width/2.0, f_height/2.0)
	flash.rotation = randf_range(-PI, PI)
	
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = RIFT_PULSE_SHADER
	mat.shader = sh
	mat.set_shader_parameter("glow_color", color)
	flash.material = mat
	
	content.add_child(flash)
	flash.add_to_group("depth_fx")
	if _combat_bg: content.move_child(flash, _combat_bg.get_index() + 1)
	
	var rect = content.get_global_rect()
	flash.global_position = Vector2(
		randf_range(rect.position.x + 100, rect.position.x + rect.size.x - 100),
		randf_range(rect.position.y + 50, rect.position.y + rect.size.y - 150)
	)
	
	flash.modulate.a = 0
	flash.scale = Vector2(0.5, 0.1)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(flash, "modulate:a", 1.0, 0.3)
	tween.tween_property(flash, "scale", Vector2(1.2, 1.0), 1.0).set_trans(Tween.TRANS_ELASTIC)
	tween.chain().tween_property(flash, "modulate:a", 0.0, 0.8)
	tween.chain().tween_callback(flash.queue_free)

func _spawn_glow_orb(color: Color) -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	var orb = ColorRect.new()
	var o_size = randf_range(40, 100)
	orb.custom_minimum_size = Vector2(o_size, o_size)
	
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = GLOW_ORB_SHADER
	mat.shader = sh
	mat.set_shader_parameter("orb_color", color)
	orb.material = mat
	
	content.add_child(orb)
	orb.add_to_group("depth_fx")
	if _combat_bg: content.move_child(orb, _combat_bg.get_index() + 1)
	
	var rect = content.get_global_rect()
	orb.global_position = Vector2(
		randf_range(rect.position.x, rect.position.x + rect.size.x - o_size),
		randf_range(rect.position.y, rect.position.y + rect.size.y - o_size)
	)
	orb.modulate.a = 0
	var tween = create_tween()
	tween.tween_property(orb, "modulate:a", color.a, 2.0)
	tween.tween_property(orb, "modulate:a", 0, 3.0)
	tween.tween_callback(orb.queue_free)

func _start_fast_cloud_loop(color: Color) -> void:
	_start_generic_spawner(func(): _spawn_cloud(color, randf_range(300, 500)), 0.5, 1.0)

func _start_slow_cloud_loop(color: Color) -> void:
	_start_generic_spawner(func(): _spawn_cloud(color, randf_range(50, 100)), 2.0, 4.0)

func _spawn_cloud(color: Color, speed: float) -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	
	var cloud = ColorRect.new() # Use ColorRect for shaders
	var c_wide = randf_range(300, 500)
	var c_high = randf_range(120, 200)
	cloud.custom_minimum_size = Vector2(c_wide, c_high)
	
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = CLOUD_SHADER
	mat.shader = sh
	mat.set_shader_parameter("cloud_color", color)
	mat.set_shader_parameter("density", randf_range(0.6, 1.2))
	cloud.material = mat
	
	content.add_child(cloud)
	cloud.add_to_group("depth_fx")
	if _combat_bg: content.move_child(cloud, _combat_bg.get_index() + 1)
	
	var rect = content.get_global_rect()
	cloud.global_position = Vector2(rect.position.x - 600, randf_range(rect.position.y, rect.position.y + rect.size.y * 0.6))
	
	var tween = create_tween()
	var travel_dist = rect.size.x + 1200
	tween.tween_property(cloud, "global_position:x", rect.position.x + rect.size.x + 600, travel_dist / speed)
	tween.chain().tween_callback(cloud.queue_free)

func _start_star_field_loop(shooting: bool, _distorted: bool = false) -> void:
	# Persistent star field
	_start_mist_loop(Color(1, 1, 1, 0.1), 0.05) # Static flickering overlay via MIST_SHADER (abuse it)
	if shooting:
		_start_generic_spawner(func(): _spawn_shooting_star(), 4.0, 8.0)

func _spawn_shooting_star() -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	var star = ColorRect.new()
	star.add_to_group("depth_fx")
	star.custom_minimum_size = Vector2(20, 2)
	star.rotation = PI/4
	content.add_child(star)
	
	var rect = content.get_global_rect()
	star.global_position = Vector2(randf_range(rect.position.x, rect.position.x + rect.size.x * 0.5), rect.position.y)
	
	var tween = create_tween().set_parallel(true)
	tween.tween_property(star, "global_position", star.global_position + Vector2(400, 400), 0.5)
	tween.tween_property(star, "modulate:a", 0, 0.5)
	tween.chain().tween_callback(star.queue_free)

func _start_lightning_loop() -> void:
	_start_generic_spawner(func(): _trigger_lightning(), 5.0, 12.0)

func _trigger_lightning() -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	var flash = ColorRect.new()
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.8, 0.9, 1.0, 0.4)
	content.add_child(flash)
	
	var tween = create_tween()
	tween.tween_property(flash, "modulate:a", 0, 0.1)
	tween.tween_property(flash, "modulate:a", 0.4, 0.05)
	tween.tween_property(flash, "modulate:a", 0, 0.3)
	tween.chain().tween_callback(flash.queue_free)

func _start_plasma_fissure_loop() -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	var fissure = ColorRect.new()
	fissure.custom_minimum_size = Vector2(content.get_global_rect().size.x, 80)
	fissure.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	var mat = ShaderMaterial.new()
	var sh = Shader.new()
	sh.code = PLASMA_SHADER
	mat.shader = sh
	fissure.material = mat
	content.add_child(fissure)
	fissure.add_to_group("depth_fx")

func _start_lava_glow_loop() -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	var rect = content.get_global_rect()
	var glow = ColorRect.new()
	glow.custom_minimum_size = Vector2(rect.size.x, 100)
	glow.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	glow.color = Color(1.0, 0.2, 0.0, 0.3)
	content.add_child(glow)
	glow.add_to_group("depth_fx")
	
func _start_void_ripple_loop() -> void:
	var content = find_child("ContentArea", true, false) as Control
	if not content: return
	var void_ov := ColorRect.new()
	void_ov.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	void_ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat = ShaderMaterial.new()
	mat.shader = load_shader(VOID_SHADER)
	void_ov.material = mat
	content.add_child(void_ov)
	void_ov.add_to_group("depth_fx")
	if _combat_bg: content.move_child(void_ov, _combat_bg.get_index() + 1)
	
	void_ov.modulate.a = 0
	create_tween().tween_property(void_ov, "modulate:a", 1.0, 2.0)

func _start_generic_spawner(callback: Callable, min_t: float, max_t: float) -> void:
	if not _wave_in_progress: return
	var timer = get_tree().create_timer(randf_range(min_t, max_t))
	timer.timeout.connect(func():
		if _wave_in_progress and visible:
			callback.call()
			_start_generic_spawner(callback, min_t, max_t)
	)

func _stop_all_depth_fx() -> void:
	for node in get_tree().get_nodes_in_group("depth_fx"):
		node.queue_free()
	# Ensure background material is reset if needed
	if _combat_bg: _combat_bg.material = null

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
	# 6-wide layout to shrink bottom bar height
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
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
		btn.custom_minimum_size = Vector2(240, 80) # Restored large size for premium feel
		btn.add_theme_font_size_override("font_size", 14) # Clearer text for large buttons
		
		# Premium Interaction: Hover & Press animations
		btn.mouse_entered.connect(func():
			create_tween().set_trans(Tween.TRANS_SINE).tween_property(btn, "scale", Vector2(1.05, 1.05), 0.1)
		)
		btn.mouse_exited.connect(func():
			create_tween().set_trans(Tween.TRANS_SINE).tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
		)
		
		btn.pressed.connect(func():
			var t = create_tween()
			t.tween_property(btn, "scale", Vector2(0.95, 0.95), 0.05)
			t.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.1)
			_on_attack_selected(option.id)
		)
		btn.pivot_offset = btn.custom_minimum_size / 2.0
		grid.add_child(btn)

func _get_action_button_style(base_color: Color, alpha: float) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	# Glassmorphism base
	sb.bg_color = Color(base_color.r * 0.05, base_color.g * 0.05, base_color.b * 0.05, 0.9)
	sb.draw_center = true
	
	# Gradient effect
	sb.set_border_width_all(2)
	sb.border_color = base_color
	sb.border_color.a = alpha
	
	sb.set_corner_radius_all(10)
	
	# Glow & Shadow
	sb.shadow_color = base_color
	sb.shadow_color.a = alpha * 0.3
	sb.shadow_size = 8
	
	# Inner Highlight (Top-left accent)
	sb.content_margin_left = 10
	sb.content_margin_top = 10
	
	return sb



func _on_attack_selected(attack_id: String) -> void:
	_clear_attack_grid()
	# Trigger VFX based on attack ID
	var vfx_type = "slash"
	if "pierce" in attack_id or "stab" in attack_id: vfx_type = "stab"
	elif "blunt" in attack_id or "bludgeon" in attack_id or "hammer" in attack_id: vfx_type = "blunt"
	elif "awakened" in attack_id: vfx_type = "awakened"
	_trigger_attack_vfx(vfx_type)
	
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
	
	if icon_path != "" and ResourceLoader.exists(icon_path):
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
	if _wave_label == null: return
	
	# SPEED CHECK FOR CONDENSATION DISPLAY
	if _is_smooth_looping:
		var p_stats = _em.get_player_combat_stats() if _em else {"attack": 10}
		var enemy = _build_enemy_for_wave(current_wave)
		var data = _calculate_smooth_efficiency(p_stats, enemy)
		_wave_label.text = "Wave %d | Subwave %d | Rewards per Cycle: %d" % [current_wave, current_subwave, data.subwaves]
		return

	var mastery: int = 0
	if _gm:
		var wave_id = "wave_%d" % current_wave
		var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0})
		mastery = int(wave_data.get("mastery", 0)) if wave_data is Dictionary else int(wave_data)

	_wave_label.text = "Wave %d - Subwave %d" % [current_wave, current_subwave]
	if current_wave > 1 and highest_wave_reached < current_wave:
		_wave_label.text += " [color=#ff5555][LOCKED][/color]"
	
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
	var quality_boost = float(subwave) / 50.0 # 2% per 10 subwaves
	
	if wave >= 141: # God Tier
		if roll < 0.05 + quality_boost: return "god_tier"
		if roll < 0.20 + quality_boost: return "transcendent"
		return "mythic"
	elif wave >= 121: # Transcendent
		if roll < 0.05 + quality_boost: return "transcendent"
		if roll < 0.20 + quality_boost: return "mythic"
		return "legendary"
	elif wave >= 101: # Mythic
		if roll < 0.05 + quality_boost: return "mythic"
		if roll < 0.20 + quality_boost: return "legendary"
		return "epic"
	elif wave >= 81: # Legendary
		if roll < 0.05 + quality_boost: return "legendary"
		if roll < 0.20 + quality_boost: return "epic"
		return "rare"
	elif wave >= 61: # Epic
		if roll < 0.05 + quality_boost: return "epic"
		if roll < 0.20 + quality_boost: return "rare"
		return "uncommon"
	elif wave >= 41: # Rare
		if roll < 0.10 + quality_boost: return "rare"
		if roll < 0.40 + quality_boost: return "uncommon"
		return "common"
	elif wave >= 21: # Uncommon
		if roll < 0.30 + quality_boost: return "uncommon"
		return "common"
	else: # Common
		return "common"

func _on_prev_wave_pressed() -> void:
	if current_wave > 1:
		_save_wave_progress()
		var was_auto = _is_smooth_looping
		if _wave_in_progress:
			_cancel_current_combat()
		current_wave -= 1
		_load_wave_progress(current_wave)
		_is_manual_wave = true
		_update_wave_label()
		if was_auto: _on_start_wave_pressed()

func _on_next_wave_pressed() -> void:
	if current_wave < highest_wave_reached:
		_save_wave_progress()
		var was_auto = _is_smooth_looping
		if _wave_in_progress:
			_cancel_current_combat()
		current_wave += 1
		_load_wave_progress(current_wave)
		_is_manual_wave = true
		_update_wave_label()
		if was_auto: _on_start_wave_pressed()

func _on_farm_pressed() -> void:
	_farming_mode = not _farming_mode
	if _farm_btn:
		if _farming_mode:
			_farm_btn.text = "FARMING"
			_farm_btn.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4)) # Green for Farming
			# Automatically jump back to last known good subwave
			if current_subwave > _last_automated_subwave:
				current_subwave = _last_automated_subwave
				if _is_smooth_looping:
					_cancel_current_combat()
					_on_start_wave_pressed()
		else:
			_farm_btn.text = "PUSHING"
			_farm_btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4)) # Red for Pushing
			# Restore to highest subwave reached for this wave
			var wave_id = "wave_%d" % current_wave
			var wave_data = _gm.wave_mastery.get(wave_id, {})
			if wave_data is Dictionary and wave_data.has("best_subwave"):
				var best = int(wave_data["best_subwave"])
				if best > current_subwave:
					current_subwave = best
					if _is_smooth_looping:
						_cancel_current_combat()
						_on_start_wave_pressed()
	
	_update_wave_label()

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

func _save_wave_progress() -> void:
	if _gm == null: return
	var wave_id = "wave_%d" % current_wave
	var wave_data = _gm.wave_mastery.get(wave_id, {"mastery": 0, "best_subwave": 0})
	if not (wave_data is Dictionary):
		wave_data = {"mastery": int(wave_data), "best_subwave": current_subwave}
	
	wave_data["saved_subwave"] = current_subwave
	wave_data["last_auto_subwave"] = _last_automated_subwave
	_gm.wave_mastery[wave_id] = wave_data

func _load_wave_progress(wave_idx: int) -> void:
	if _gm == null: 
		current_subwave = 1
		_last_automated_subwave = 1
		return
		
	var wave_id = "wave_%d" % wave_idx
	var wave_data = _gm.wave_mastery.get(wave_id, {})
	if wave_data is Dictionary and wave_data.has("saved_subwave"):
		current_subwave = int(wave_data["saved_subwave"])
		_last_automated_subwave = int(wave_data.get("last_auto_subwave", 1))
	else:
		current_subwave = 1
		_last_automated_subwave = 1

# ── Equipment View ─────────────────────────────────────────────────────────────
func _refresh_equipment_view() -> void:
	if _em == null: return
	_em.sort_inventory()
	
	var inv_box := find_child("InventoryBox", true, false)
	var scroll_val = 0
	var scroll_cont: ScrollContainer = null
	if inv_box:
		# Save scroll position if parented by a ScrollContainer
		var p = inv_box.get_parent()
		while p and not (p is ScrollContainer):
			p = p.get_parent()
		if p is ScrollContainer:
			scroll_cont = p
			scroll_val = p.scroll_vertical

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
				
				# Interaction Button for Equipped items
				var e_btn = Button.new()
				e_btn.flat = true
				e_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				slot_panel.add_child(e_btn)
				e_btn.pressed.connect(_on_equipped_item_clicked.bind(_it, slot_panel))
				
				# v8 Fix: Connect tooltip to the button which covers the panel
				e_btn.mouse_entered.connect(_show_custom_tooltip.bind(slot_panel, _it))
				e_btn.mouse_exited.connect(_hide_custom_tooltip)
			
			grid.add_child(slot_panel)
		
		_refresh_total_stats()
	
	inv_box = find_child("InventoryBox", true, false)
	if inv_box:
		for child in inv_box.get_children():
			child.queue_free()
		
		# Remove ScrollContainer as requested to fill screen horizontally
		var main_h := HBoxContainer.new()
		main_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
		inv_box.add_child(main_h)
		
		var categories_grid := GridContainer.new()
		categories_grid.columns = 6 # 6 category columns (Weapon, Armor, etc)
		categories_grid.add_theme_constant_override("h_separation", 8)
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
		var reward_dc = _em.salvage_item(_selected_item_ref) if has_sel else 0
		if has_sel:
			dismantle_btn.text = "Dismantle (+%d DC)" % reward_dc
		else:
			dismantle_btn.text = "Dismantle"
		dismantle_btn.modulate = Color(1, 0.4, 0.4)
		dismantle_btn.disabled = not has_sel
		if has_sel:
			dismantle_btn.pressed.connect(_on_dismantle_item_ref.bind(_selected_item_ref))
		sidebar.add_child(dismantle_btn)
		
		# "Power Up" button removed from Inventory as requested; now in Forge.
		
		# SORTING: Sort inventory by rarity (highest first), then level, then stable ID
		var rarity_order = {
			"god_tier": 7, "transcendent": 6, "mythic": 5, 
			"legendary": 4, "epic": 3, "rare": 2, 
			"uncommon": 1, "common": 0
		}
		_em.inventory.sort_custom(func(a, b):
			var r_a = rarity_order.get(a.get("rarity","common"), 0)
			var r_b = rarity_order.get(b.get("rarity","common"), 0)
			if r_a != r_b: return r_a > r_b
			var l_a = a.get("level", 1)
			var l_b = b.get("level", 1)
			if l_a != l_b: return l_a > l_b
			# Final stable sort by ID
			return a.get("id", "") < b.get("id", "")
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
			
			# Locked size for category panels to fit 4x8 grid (Approx 240px wide)
			category_panel.custom_minimum_size = Vector2(240, 540)
			

			for item in _em.inventory:
				if item.get("slot", "weapon") != s: continue
				
				var item_frame := PanelContainer.new()
				item_frame.custom_minimum_size = Vector2(56, 56)
				
				var is_selected = false
				if not _selected_item_ref.is_empty():
					var s_id = _selected_item_ref.get("id", "NONE_S")
					var i_id = item.get("id", "NONE_I")
					if (s_id != "NONE_S" and i_id != "NONE_I" and s_id == i_id) or (item == _selected_item_ref):
						is_selected = true
				
				var sb = StyleBoxFlat.new()
				sb.bg_color = Color(0.1, 0.1, 0.15, 0.8)
				sb.set_border_width_all(2)
				sb.border_color = _get_rarity_color(item.rarity)
				if is_selected:
					sb.border_color = Color(1.0, 0.9, 0.3)
					sb.shadow_size = 6
					sb.shadow_color = Color(1, 0.8, 0, 0.5)
					sb.bg_color = Color(0.2, 0.2, 0.25, 1.0)
				else:
					sb.border_color.a = 0.7
				sb.set_corner_radius_all(6)
				item_frame.add_theme_stylebox_override("panel", sb)
				
				var icon_rect := TextureRect.new()
				icon_rect.texture = load(_get_item_icon_path(item, s))
				icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				icon_rect.custom_minimum_size = Vector2(48, 48) # Increased icon size
				item_frame.add_child(icon_rect)
				

				if item.get("plus_tier", 0) > 0:
					var plus_lbl := Label.new()
					plus_lbl.text = "+%d" % item.plus_tier
					plus_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					plus_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
					plus_lbl.add_theme_font_size_override("font_size", 10)
					plus_lbl.add_theme_color_override("font_color", Color(1, 0.8, 0.2))
					item_frame.add_child(plus_lbl)
				
				var btn := Button.new()
				btn.flat = true
				btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
				btn.custom_minimum_size = Vector2(56, 56)
				item_frame.add_child(btn)
				
				var _t_it = item 
				var _t_fr = item_frame
				
				btn.mouse_entered.connect(_show_custom_tooltip.bind(_t_fr, _t_it))
				btn.mouse_exited.connect(_hide_custom_tooltip)
				btn.pressed.connect(_on_inventory_item_clicked.bind(_t_it, _t_fr))
				
				grid.add_child(item_frame)
		
		_refresh_total_stats()

		# Restore scroll position
		if scroll_cont and scroll_val > 0:
			scroll_cont.set_deferred("scroll_vertical", scroll_val)

# ── Blacksmith View ─────────────────────────────────────────────────────────────
func _refresh_blacksmith_view() -> void:
	if _blacksmith_view == null or _em == null: return
	
	# Clear previous
	for child in _blacksmith_view.get_children():
		child.queue_free()
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 30)
	_blacksmith_view.add_child(main_vbox)
	
	var header := Label.new()
	header.text = "ANCIENT BLACKSMITH - MANUAL MERGING"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	main_vbox.add_child(header)
	
	var desc := Label.new()
	desc.text = "Place 3 identical items on the table to combine them into a higher rarity."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.modulate.a = 0.7
	main_vbox.add_child(desc)

	# THE TABLE (3 Slots)
	var center_h := HBoxContainer.new()
	center_h.alignment = BoxContainer.ALIGNMENT_CENTER
	center_h.add_theme_constant_override("separation", 40)
	main_vbox.add_child(center_h)
	
	for i in range(3):
		var slot_panel := PanelContainer.new()
		slot_panel.custom_minimum_size = Vector2(160, 160)
		
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.05, 0.08, 0.9)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.3, 0.3, 0.4)
		sb.set_corner_radius_all(10)
		
		var item = null
		if _slotted_blacksmith_items.size() > i:
			item = _slotted_blacksmith_items[i]
		
		if item:
			sb.border_color = _get_rarity_color(item.rarity)
			sb.shadow_size = 10
			sb.shadow_color = sb.border_color
			sb.shadow_color.a = 0.3
		
		slot_panel.add_theme_stylebox_override("panel", sb)
		center_h.add_child(slot_panel)
		
		if item:
			var icon := TextureRect.new()
			icon.texture = load(_get_item_icon_path(item, item.slot))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(100, 100)
			slot_panel.add_child(icon)
			
			var btn := Button.new()
			btn.flat = true
			slot_panel.add_child(btn)
			btn.pressed.connect(func(): 
				_slotted_blacksmith_items.remove_at(i)
				_refresh_blacksmith_view()
			)
			# v8 Fix: Add tooltips to blacksmith table
			var _b_it = item
			btn.mouse_entered.connect(_show_custom_tooltip.bind(slot_panel, _b_it))
			btn.mouse_exited.connect(_hide_custom_tooltip)
		else:
			var lbl := Label.new()
			lbl.text = "SLOT %d" % (i + 1)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.modulate.a = 0.2
			slot_panel.add_child(lbl)

	# FUSE BUTTON
	var fuse_area := VBoxContainer.new()
	fuse_area.alignment = BoxContainer.ALIGNMENT_CENTER
	main_vbox.add_child(fuse_area)
	
	var fuse_btn := Button.new()
	fuse_btn.text = "MANUAL FUSE"
	fuse_btn.custom_minimum_size = Vector2(240, 60)
	fuse_btn.disabled = true
	
	var cost_val = 0
	var can_fuse = false
	var reason = "Slots incomplete"
	
	if _slotted_blacksmith_items.size() == 3:
		var it0 = _slotted_blacksmith_items[0]
		var it1 = _slotted_blacksmith_items[1]
		var it2 = _slotted_blacksmith_items[2]
		
		if it0.name == it1.name and it1.name == it2.name and it0.rarity == it1.rarity and it1.rarity == it2.rarity:
			# ENFORCE MAX LEVEL
			if it0.level < it0.max_level or it1.level < it1.max_level or it2.level < it2.max_level:
				reason = "All items must be MAX LEVEL (%d)" % it0.max_level
			else:
				cost_val = _get_merge_cost(it0.rarity)
				if _gm and _gm.dreamcloud >= cost_val:
					can_fuse = true
					fuse_btn.disabled = false
					fuse_btn.text = "FUSE (%s DC)" % _gm.call("_fmt_num_compact", float(cost_val)) if _gm.has_method("_fmt_num_compact") else str(cost_val)
				else:
					reason = "Not enough Dreamcloud"
		else:
			reason = "Items must be identical"
	
	if not can_fuse and _slotted_blacksmith_items.size() == 3:
		fuse_btn.text = reason

	fuse_btn.pressed.connect(_on_blacksmith_fuse_pressed)
	fuse_area.add_child(fuse_btn)

	# INVENTORY SELECTION
	var split_h := HBoxContainer.new()
	split_h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_h.add_theme_constant_override("separation", 20)
	main_vbox.add_child(split_h)
	
	# --- LEFT: MAIN INVENTORY (STACKED) ---
	var left_vbox := VBoxContainer.new()
	left_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split_h.add_child(left_vbox)
	
	var left_lbl := Label.new()
	left_lbl.text = "Inventory Items (Select to Slot)"
	left_lbl.modulate.a = 0.5
	left_vbox.add_child(left_lbl)
	
	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_vbox.add_child(inv_scroll)
	
	var inv_grid := GridContainer.new()
	inv_grid.columns = 16 # WIDER VIEW (v3)
	inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(inv_grid)
	
	# --- RIGHT: FUSABLE CANDIDATES ---
	var right_vbox := VBoxContainer.new()
	right_vbox.custom_minimum_size = Vector2(300, 0)
	split_h.add_child(right_vbox)
	
	var right_lbl := Label.new()
	right_lbl.text = "Fusing Options"
	right_lbl.modulate = Color(1, 0.9, 0.4, 0.8)
	right_vbox.add_child(right_lbl)
	
	var fuse_scroll := ScrollContainer.new()
	fuse_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(fuse_scroll)
	
	var fuse_list := VBoxContainer.new()
	fuse_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuse_scroll.add_child(fuse_list)

	# 1. Group items for the "Fuse All" buttons, but show individual items in the grid
	var stacks = {} 
	for item in _em.inventory:
		if _slotted_blacksmith_items.has(item): continue
		
		# ONLY SHOW MAX LEVEL
		if item.level < item.max_level: continue
		
		# Display individual items in the left grid
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(80, 80)
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.12, 0.15, 0.8)
		sb.set_border_width_all(2)
		sb.border_color = _get_rarity_color(item.rarity)
		sb.set_corner_radius_all(5)
		frame.add_theme_stylebox_override("panel", sb)
		
		var icon := TextureRect.new()
		icon.texture = load(_get_item_icon_path(item, item.slot))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(56, 56)
		frame.add_child(icon)
		
		# Compatibility Check
		var is_compat = true
		if _slotted_blacksmith_items.size() > 0:
			var first = _slotted_blacksmith_items[0]
			if item.rarity != first.rarity or item.slot != first.slot:
				is_compat = false
		
		if not is_compat: frame.modulate.a = 0.2
			
		var btn := Button.new()
		btn.flat = true
		frame.add_child(btn)
		btn.pressed.connect(func():
			if not is_compat: return
			if _slotted_blacksmith_items.size() < 3:
				_slotted_blacksmith_items.append(item)
				_refresh_blacksmith_view()
		)
		inv_grid.add_child(frame)

		# Build stacks for the right-hand fuse list
		var stack_key = item.name + "|" + item.rarity + "|" + str(item.get("plus_tier", 0))
		if not stacks.has(stack_key): stacks[stack_key] = []
		stacks[stack_key].append(item)

	# Render stacks in right-hand list if they have 3+ items
	var sorted_keys = stacks.keys()
	sorted_keys.sort()
	
	for key in sorted_keys:
		var stack_items = stacks[key]
		if stack_items.size() >= 3:
			var base_item = stack_items[0]
			var cand_btn := Button.new()
			cand_btn.text = "Fuse %s (%s)" % [base_item.name, base_item.rarity]
			cand_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cand_btn.add_theme_color_override("font_color", _get_rarity_color(base_item.rarity))
			fuse_list.add_child(cand_btn)
			cand_btn.pressed.connect(func():
				_slotted_blacksmith_items.clear()
				_slotted_blacksmith_items.append(stack_items[0])
				_slotted_blacksmith_items.append(stack_items[1])
				_slotted_blacksmith_items.append(stack_items[2])
				_refresh_blacksmith_view()
			)

func _get_merge_cost(rarity: String) -> int:
	if _em: return _em.get_merge_cost(rarity)
	return 500

func _on_blacksmith_fuse_pressed() -> void:
	if _slotted_blacksmith_items.size() != 3 or _gm == null or _em == null: return
	
	var cost = _get_merge_cost(_slotted_blacksmith_items[0].rarity)
	if _gm.dreamcloud < cost: return
	
	_gm.dreamcloud -= cost
	
	# THE ANIMATION
	var overlay := ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(1, 0.8, 0.4, 0)
	_blacksmith_view.add_child(overlay)
	
	var mat = ShaderMaterial.new()
	mat.shader = load_shader(MERGE_SHADER)
	mat.set_shader_parameter("progress", 0.0) # Ensure parameter exists for tween
	overlay.material = mat
	
	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 0.8, 0.5)
	tween.tween_property(mat, "shader_parameter/progress", 1.0, 1.0)
	tween.tween_callback(func():
		# Logic
		var base = _slotted_blacksmith_items[0]
		var next_rarity = _em.get_next_rarity(base.rarity)
		var new_item = _em.generate_item(next_rarity, base.slot, current_wave)
		
		# Transfer plus tier if any
		new_item.plus_tier = base.get("plus_tier", 0)
		
		# Remove originals
		for it in _slotted_blacksmith_items:
			var idx = _em.inventory.find(it)
			if idx != -1: _em.inventory.remove_at(idx)
		
		_slotted_blacksmith_items.clear()
		_em.add_to_inventory(new_item)
		_gm._refresh_top_ui()
		_gm.save_game()
		
		_refresh_blacksmith_view()
	)
	tween.tween_property(overlay, "color:a", 0.0, 0.5)
	tween.tween_callback(overlay.queue_free)


func load_shader(source: String) -> Shader:
	var s = Shader.new()
	s.code = source
	return s

func _on_inventory_item_clicked(item: Dictionary, frame: Control) -> void:
	_selected_item_ref = item
	_refresh_equipment_view()
	# Tooltip will be updated by the refresh or manually
	_show_custom_tooltip(frame, item)

func _on_equipped_item_clicked(item: Dictionary, frame: Control) -> void:
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

func _on_level_up_item(slot: String) -> void:
	if _em == null or _gm == null: return
	var item = _em.equipped.get(slot)
	if item == null: return
	
	var cost = int(item.level) * 100
	if _gm.dreamcloud >= cost and item.level < item.max_level:
		_gm.dreamcloud -= cost
		item.level += 1
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()
		_refresh_equipment_view()

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
		
		# Prevent screen jump: Forge view rebuilds entirely, so we'll 
		# have to accept some jump unless we keep scroll position
		_refresh_forge_view() 
		_refresh_equipment_view()
		_hide_custom_tooltip()

func _on_inventory_buy_max_ref(item: Dictionary) -> void:
	if _em == null or _gm == null: return
	
	var items_upgraded = 0
	while item.level < item.max_level:
		var cost = int(item.level) * 100
		if _gm.dreamcloud >= cost:
			_gm.dreamcloud -= cost
			item.level += 1
			items_upgraded += 1
		else:
			break
	
	if items_upgraded > 0:
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()
		_refresh_equipment_view()
		_hide_custom_tooltip()


func _on_buy_max_equipped(slot: String) -> void:
	if _em == null or _gm == null: return
	var item = _em.equipped.get(slot)
	if item == null: return
	
	while item.level < item.max_level:
		var cost = int(item.level) * 100
		if _gm.dreamcloud >= cost:
			_gm.dreamcloud -= cost
			item.level += 1
		else:
			break
			
	_gm._refresh_top_ui()
	_gm.save_game()
	_refresh_forge_view()
	_refresh_equipment_view()

func _on_upgrade_all_equipped() -> void:
	if _em == null or _gm == null: return
	var upgraded = false
	for slot in _em.equipped.keys():
		var item = _em.equipped[slot]
		if item == null: continue
		while item.level < item.max_level:
			var cost = int(item.level) * 100
			if _gm.dreamcloud >= cost:
				_gm.dreamcloud -= cost
				item.level += 1
				upgraded = true
			else:
				break
	if upgraded:
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()
		_refresh_equipment_view()

func _on_upgrade_all_inventory(slot_name: String) -> void:
	if _em == null or _gm == null: return
	var upgraded = false
	for item in _em.inventory:
		if item.get("slot", "weapon") != slot_name: continue
		while item.level < item.max_level:
			var cost = int(item.level) * 100
			if _gm.dreamcloud >= cost:
				_gm.dreamcloud -= cost
				item.level += 1
				upgraded = true
			else:
				break
	if upgraded:
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()
		_refresh_equipment_view()

func _calculate_buy_max_cost(item: Dictionary) -> Dictionary:
	var total_cost = 0
	var levels_to_buy = 0
	var temp_level = item.level
	var temp_dc = _gm.dreamcloud if _gm else 0
	
	while temp_level < item.max_level:
		var cost = int(temp_level) * 100
		if temp_dc >= cost:
			temp_dc -= cost
			total_cost += cost
			temp_level += 1
			levels_to_buy += 1
		else:
			break
	return {"cost": total_cost, "levels": levels_to_buy}

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
		_em.add_to_inventory(_em.equipped[slot], true) # swap old back, allow overfill to avoid loss
	_em.equipped[slot] = item
	_em.inventory.remove_at(idx)
	if _gm: _gm.save_game()
	_refresh_equipment_view()


func _refresh_forge_inventory() -> void:
	var forge_inv := find_child("ForgeInventoryBox", true, false)
	if forge_inv == null or _em == null: return
	_em.sort_inventory()
	
	# Save scroll positions for each category column
	var scroll_positions = {}
	for child in forge_inv.get_children():
		if child is HBoxContainer: # This is the inv_columns container
			for col in child.get_children(): # These are col_container
				var inner_vbox = col.get_child(0)
				for element in inner_vbox.get_children():
					if element is ScrollContainer:
						# Find identifying name or index
						var col_header = inner_vbox.get_child(0) as Label
						if col_header:
							scroll_positions[col_header.text.to_lower()] = element.scroll_vertical
	
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
	lvl_hdr.text = "(EQUIPPED ITEMS (LEVEL UP & FUSION TARGETS)"
	lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lvl_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lvl_hdr.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
	lvl_hdr.add_theme_font_size_override("font_size", 14)
	
	var eq_vbox := VBoxContainer.new()
	eq_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq_vbox.add_theme_constant_override("separation", 5)
	
	forge_inv.add_child(lvl_hdr)
	forge_inv.add_child(eq_vbox)
	
	for slot in _em.equipped.keys():
		var item = _em.equipped[slot]
		if item == null: continue
		
		var row_container := PanelContainer.new()
		row_container.add_theme_stylebox_override("panel", style)
		row_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 20)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_container.add_child(row)
		
		var icon_rect := TextureRect.new()
		icon_rect.texture = load(_get_item_icon_path(item, slot))
		icon_rect.custom_minimum_size = Vector2(64, 64)
		icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon_rect)
		
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		var plus_str = " +%d" % item.get("plus_tier", 0) if item.get("plus_tier", 0) > 0 else ""
		name_lbl.text = "%s%s" % [item.name, plus_str]
		name_lbl.add_theme_color_override("font_color", _get_rarity_color(item.rarity))
		details.add_child(name_lbl)
		
		var lv_lbl := Label.new()
		lv_lbl.text = "Lv %d/%d" % [item.level, item.max_level]
		lv_lbl.add_theme_font_size_override("font_size", 12)
		details.add_child(lv_lbl)
		
		# PROGRESS BAR SECTION
		var bar_container := VBoxContainer.new()
		bar_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar_container.alignment = BoxContainer.ALIGNMENT_CENTER
		
		var bar := ProgressBar.new()
		bar.min_value = 0
		bar.max_value = item.max_level
		bar.value = item.level
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(100, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Premium Bar Style
		var bar_bg = StyleBoxFlat.new()
		bar_bg.bg_color = Color(0.05, 0.05, 0.1, 0.5)
		bar_bg.set_corner_radius_all(4)
		bar.add_theme_stylebox_override("background", bar_bg)
		
		var bar_fg = StyleBoxFlat.new()
		var r_color = _get_rarity_color(item.rarity)
		bar_fg.bg_color = r_color
		bar_fg.set_corner_radius_all(4)
		# Add a slight glow/border for premium feel
		bar_fg.set_border_width_all(1)
		bar_fg.border_color = Color(1, 1, 1, 0.3)
		bar.add_theme_stylebox_override("fill", bar_fg)
		
		bar_container.add_child(bar)
		row.add_child(bar_container)

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
		
		var buymax_info = _calculate_buy_max_cost(item)
		var buymax_btn := Button.new()
		buymax_btn.text = "Buy Max (%d DC)" % buymax_info.cost
		buymax_btn.pressed.connect(_on_buy_max_equipped.bind(slot))
		if _gm and _gm.dreamcloud < (int(item.level) * 100): buymax_btn.disabled = true
		if item.level >= item.max_level: buymax_btn.disabled = true
		if buymax_info.levels == 0: buymax_btn.disabled = true
		actions.add_child(buymax_btn)
		

		row.add_child(actions)
		eq_vbox.add_child(row_container)
		
		# v8 Fix: Add tooltips to Forge Equipped rows
		var _f_it = item
		row_container.mouse_entered.connect(_show_custom_tooltip.bind(row_container, _f_it))
		row_container.mouse_exited.connect(_hide_custom_tooltip)
		
		eq_vbox.add_child(Control.new()) # Spacer
	
	# UPGRADE ALL EQUIPPED BUTTON (Outside Scroll)
	var eq_total_cost = 0
	for item in _em.equipped.values():
		if item: eq_total_cost += _calculate_buy_max_cost(item).cost
	
	if eq_total_cost > 0:
		var up_all_eq_btn := Button.new()
		up_all_eq_btn.text = "UPGRADE ALL EQUIPPED (%d DC)" % eq_total_cost
		up_all_eq_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
		up_all_eq_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if _gm and _gm.dreamcloud < eq_total_cost: up_all_eq_btn.disabled = true
		up_all_eq_btn.pressed.connect(_on_upgrade_all_equipped)
		forge_inv.add_child(up_all_eq_btn)
	
	forge_inv.add_child(HSeparator.new())
	
	# 2. INVENTORY ITEMS (LEVEL UP) section - NEW
	var inv_lvl_hdr := Label.new()
	inv_lvl_hdr.text = "INVENTORY ITEMS (POWER UP)"
	inv_lvl_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_lvl_hdr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_lvl_hdr.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	inv_lvl_hdr.add_theme_font_size_override("font_size", 14)
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
		slot_vbox_map[s_name + "_vbox"] = col_vbox # Store outer vbox for buttons
		
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
		
		# Restore specific scroll position for this column
		var s_key = s_name.capitalize().replace("Ring1", "Ring").to_lower()
		if scroll_positions.has(s_key):
			col_scroll.set_deferred("scroll_vertical", scroll_positions[s_key])
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
		
		var bmax_info = _calculate_buy_max_cost(item)
		var bmax_btn := Button.new()
		bmax_btn.text = "Max (%d)" % bmax_info.cost
		bmax_btn.tooltip_text = "Buy %d levels for %d DC" % [bmax_info.levels, bmax_info.cost]
		if _gm and _gm.dreamcloud < cost: bmax_btn.disabled = true
		if item.level >= item.max_level: bmax_btn.disabled = true
		if bmax_info.levels == 0: bmax_btn.disabled = true
		bmax_btn.pressed.connect(_on_inventory_buy_max_ref.bind(item))
		row.add_child(bmax_btn)
		
		# v8 Fix: Add tooltips to Forge Inventory rows
		var _fi_it = item
		row_container.mouse_entered.connect(_show_custom_tooltip.bind(row_container, _fi_it))
		row_container.mouse_exited.connect(_hide_custom_tooltip)
		
		slot_vbox_map[slot_name].add_child(row_container)
	
	# Add Upgrade All buttons to category columns
	for s_name in slots_list:
		var slot_total_cost = 0
		for item in _em.inventory:
			if item.get("slot", "weapon") == s_name:
				slot_total_cost += _calculate_buy_max_cost(item).cost
		
		if slot_total_cost > 0:
			var foot_sep = HSeparator.new()
			foot_sep.modulate.a = 0.5
			slot_vbox_map[s_name].add_child(foot_sep)
			
			var up_all_col_btn := Button.new()
			up_all_col_btn.text = "UPGRADE ALL %s (%d DC)" % [s_name.to_upper(), slot_total_cost]
			up_all_col_btn.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
			if _gm and _gm.dreamcloud < slot_total_cost: up_all_col_btn.disabled = true
			up_all_col_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			up_all_col_btn.pressed.connect(_on_upgrade_all_inventory.bind(s_name))

			var col_v := slot_vbox_map.get(s_name + "_vbox") as VBoxContainer
			if col_v:
				col_v.add_child(up_all_col_btn)

	# End of forge refresh


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
		
		_em.add_to_inventory(new_item)
		_gm._refresh_top_ui()
		_gm.save_game()
		_refresh_forge_view()

func _refresh_forge_view() -> void:
	if _gm:
		var dc: float = _gm.dreamcloud 
		var info_lbl := find_child("ForgeInfoLbl", true, false) as Label
		if info_lbl: info_lbl.text = "Dreamcloud: %.0f" % dc
	_refresh_forge_inventory()

func _on_fuse_targeted(_slot: String, _fodder_indices: Array) -> void:
	if _em == null or _gm == null: return
	tip.reset_size()

# ── Skill Tree (v13) ────────────────────────────────────────────────────────
func _refresh_skills_view() -> void:
	if not _skills_view: return
	for c in _skills_view.get_children(): c.queue_free()
	
	# Layout Container
	var main_scroll = ScrollContainer.new()
	main_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skills_view.add_child(main_scroll)
	
	var control_field = Control.new()
	control_field.custom_minimum_size = Vector2(1600, 1500)
	main_scroll.add_child(control_field)
	
	# Header: Skill Points
	var sp_header = PanelContainer.new()
	sp_header.add_theme_stylebox_override("panel", _get_glass_style(Color(0.4, 0.8, 1.0, 0.5)))
	sp_header.custom_minimum_size.y = 60
	sp_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_field.add_child(sp_header)
	sp_header.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	
	var sp_hbox = HBoxContainer.new()
	sp_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	sp_hbox.add_theme_constant_override("separation", 40)
	sp_header.add_child(sp_hbox)
	
	var sp_label = Label.new()
	var sp_val = _gm.skill_points if _gm else 0
	sp_label.text = "✦ SKILL POINTS: %d" % sp_val
	sp_label.add_theme_font_size_override("font_size", 24)
	sp_label.add_theme_color_override("font_color", Color(0, 1, 0.8))
	sp_hbox.add_child(sp_label)
	
	var buy_btn = Button.new()
	buy_btn.name = "BuySPButton"
	var cost = _gm.get_sp_cost() if _gm else 0
	buy_btn.text = "BUY SP (+1) | Cost: %.0f Memories" % cost
	buy_btn.custom_minimum_size = Vector2(300, 40)
	buy_btn.pressed.connect(_on_buy_sp_pressed)
	sp_hbox.add_child(buy_btn)
	
	# Connector Layer (Draws lines)
	var connector = Control.new()
	connector.name = "ConnectorLayer"
	connector.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	control_field.add_child(connector)
	
	# Group skills by branch and tier
	var branch_x_offsets = {"combat": 300, "economy": 800, "soul": 1300}
	var node_map = {} # id -> node
	
	# Branch Labels
	for b in [["combat", "⚔ COMBAT", Color(0.8, 0.2, 0.2)], ["economy", "💎 ECONOMY", Color(0.9, 0.8, 0.1)], ["soul", "🌑 SOUL", Color(0.6, 0.2, 0.9)]]:
		var lbl = Label.new()
		lbl.text = b[1]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 28)
		lbl.add_theme_color_override("font_color", b[2])
		lbl.position = Vector2(branch_x_offsets[b[0]] - 100, 100)
		lbl.size = Vector2(200, 40)
		control_field.add_child(lbl)

	# Calculate Tier (Depth)
	var skill_tiers = {}
	for id in SKILL_DATA:
		skill_tiers[id] = _get_skill_tier(id)

	# Build Nodes
	for id in SKILL_DATA:
		var data = SKILL_DATA[id]
		var node = _build_skill_node_v2(id, data)
		control_field.add_child(node)
		
		# Position node
		var tier = skill_tiers[id]
		var x = branch_x_offsets[data.branch]
		var y = 200 + (tier * 160)
		# Horizontal jitter for split paths (e.g., combat has two branches after block)
		if id == "dodge": x -= 100
		if id == "brace": x += 100
		if id == "meditate": x += 100
		if id == "overclock": x += 100
		if id == "interrupt": x += 100
		if id == "feint": x += 100
		if id == "special": x += 100
		if id == "counter_strike": x -= 100
		if id == "lethal_precision": x -= 100
		if id == "s_tier_res": x -= 100
		if id == "bloodlust": x -= 100
		if id == "omega_strike": x -= 100
		if id == "ripper": x -= 100
		if id == "god_slayer": x -= 100
		
		node.position = Vector2(x - 60, y) # Center it (node size 120x120)
		node_map[id] = node

	# Connect drawing logic (inline lambda for simple connection drawing)
	connector.draw.connect(func():
		for id in SKILL_DATA:
			var data = SKILL_DATA[id]
			if not node_map.has(id): continue
			var start_node = node_map[id]
			var start_pos = start_node.position + start_node.size / 2
			
			for req_id in data.req:
				if not node_map.has(req_id): continue
				var end_node = node_map[req_id]
				var end_pos = end_node.position + end_node.size / 2
				
				# Check if unlocked
				var is_unlocked = _gm.get_skill_level(req_id) > 0 if _gm else false
				var line_col = Color(0.4, 0.4, 0.4, 0.5)
				if is_unlocked:
					line_col = Color(0.4, 0.8, 1.0, 0.8)
				
				connector.draw_line(start_pos, end_pos, line_col, 3.0, true)
	)
	connector.queue_redraw()

func _get_skill_tier(id: String) -> int:
	var data = SKILL_DATA[id]
	if data.req.is_empty(): return 0
	var max_tier = 0
	for r in data.req:
		max_tier = max(max_tier, _get_skill_tier(r) + 1)
	return max_tier

func _build_skill_node_v2(id: String, data: Dictionary) -> PanelContainer:
	var node = PanelContainer.new()
	node.custom_minimum_size = Vector2(120, 120)
	var level = _gm.get_skill_level(id) if _gm else 0
	var is_max = data.has("max") and level >= data.max
	
	# Styling
	var border_col = Color(0.2, 0.2, 0.2, 0.8)
	if is_max: border_col = Color(0, 1, 0.5, 0.9)
	elif level > 0: border_col = Color(0.4, 0.8, 1.0, 0.9)
	
	var sb = _get_glass_style(border_col)
	sb.set_corner_radius_all(60) # Circular
	node.add_theme_stylebox_override("panel", sb)
	
	var vb = VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	node.add_child(vb)
	
	var icon = Label.new()
	var symbols = {
		"block":"🛡️", "strike_mastery":"⚔️", "dodge":"💨", "brace":"🧱", "counter_strike":"↩️",
		"lethal_precision":"🎯", "meditate":"🧘", "overclock":"⚡", "interrupt":"🚫", "feint":"🎭",
		"special":"✨", "s_tier_res":"🌀", "bloodlust":"🩸", "omega_strike":"☄️", "ripper":"🔪", "god_slayer":"👑",
		"mem_catalyst":"🧠", "thought_stream":"🌊", "dream_weaver":"🧵", "prestige_echo":"📣", "abyssal_greed":"💰",
		"insight_overflow":"💡", "compound_growth":"📈", "infinite_ref":"♾️", "reality_arch":"🏛️",
		"safe_descent":"🪂", "rapid_reflex":"🕑", "subconscious":"🛌", "lucid_control":"👁️", "void_step":"🌌",
		"eternal_sleeper":"📽️", "wake_guard":"🛡️", "drift":"⛵", "sovereign":"🪐"
	}
	icon.text = symbols.get(id, "✦")
	icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon.add_theme_font_size_override("font_size", 32)
	vb.add_child(icon)
	
	var name_lbl = Label.new()
	name_lbl.text = data.name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.modulate.a = 0.7
	vb.add_child(name_lbl)
	
	var lv_lbl = Label.new()
	lv_lbl.text = "Lv %d/%d" % [level, data.max]
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 12)
	lv_lbl.add_theme_color_override("font_color", Color(1, 1, 0.5))
	vb.add_child(lv_lbl)
	
	# Interaction
	node.mouse_entered.connect(func(): _show_item_tooltip(data.name, data.desc, Color.WHITE))
	node.mouse_exited.connect(func(): if tip: tip.visible = false)
	
	# Click to Buy
	var btn = Button.new()
	btn.flat = true
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	node.add_child(btn)
	btn.pressed.connect(func(): _on_skill_pressed(id))
	
	return node

func _on_buy_sp_pressed() -> void:
	if _gm:
		var res = _gm.buy_skill_point()
		if res.success:
			_refresh_skills_view()
		else:
			# Visual shake or message?
			pass

func _on_unlock_pressed(skill_id: String, sp_cost: int) -> void:
	if _gm:
		var res = _gm.unlock_skill(skill_id, sp_cost)
		if res.success:
			_refresh_skills_view()
			_clear_attack_grid()

func _update_tooltip_position() -> void:
	if not is_instance_valid(tip) or not tip.visible: return
	
	tip.reset_size()
	var v_size = get_viewport_rect().size
	var margin = 40.0
	var target_pos = Vector2(
		(v_size.x - tip.size.x) / 2.0,
		v_size.y - tip.size.y - margin
	)
	
	tip.global_position.x = clamp(target_pos.x, margin, v_size.x - tip.size.x - margin)
	tip.global_position.y = clamp(target_pos.y, margin, v_size.y - tip.size.y - margin)
	tip.z_index = 200

func _show_custom_tooltip(_node: Control, item: Dictionary) -> void:
	if not is_instance_valid(tip) or item.is_empty(): 
		if is_instance_valid(tip): tip.visible = false
		return
	
	tip.visible = true
	# Use names that actually exist in DreamsPanel.tscn
	var name_lbl = tip.find_child("Title", true, false)
	var stats_lbl = tip.find_child("Stats", true, false)
	var rarity_lbl = tip.find_child("ItemRarity", true, false) # Might be null, that's okay
	
	var rarity = item.get("rarity", "common")
	var rarity_color = _get_rarity_color(rarity)
	
	if name_lbl:
		var n_text = item.get("name", "Unknown Item")
		if not rarity_lbl:
			# If no separate rarity label, append rarity to title
			n_text += " (%s)" % rarity.to_upper()
			name_lbl.add_theme_color_override("font_color", rarity_color)
		name_lbl.text = n_text
		name_lbl.visible = true
	
	if rarity_lbl: 
		rarity_lbl.text = rarity.to_upper()
		rarity_lbl.add_theme_color_override("font_color", rarity_color)
		rarity_lbl.visible = true
	
	if stats_lbl:
		var txt = ""
		var stats = item.get("stats", {})
		var slot = item.get("slot", "weapon")
		var equipped_item = _em.equipped.get(slot)
		var is_hovering_equipped = (equipped_item != null and equipped_item.get("id") == item.get("id"))

		var lv_mult = 1.0 + (item.get("level", 1) * 0.05)
		
		if stats is Dictionary:
			for s_name in stats:
				var val = stats[s_name] * lv_mult
				var line = "%s: [b]%.1f[/b]" % [str(s_name).capitalize(), val]
				
				# Comparison logic
				if equipped_item != null and not is_hovering_equipped:
					var eq_lv_mult = 1.0 + (equipped_item.get("level", 1) * 0.05)
					var eq_stats = equipped_item.get("stats", {})
					if eq_stats.has(s_name):
						var eq_val = eq_stats[s_name] * eq_lv_mult
						var diff = val - eq_val
						if abs(diff) > 0.05: # ignore tiny floating precision
							if diff > 0:
								line += " [color=#00ff00](+%.1f)[/color]" % diff
							else:
								line += " [color=#ff5555](%.1f)[/color]" % diff
				
				txt += line + "\n"
		
		var secondaries = item.get("secondary_stats", {})
		if secondaries is Dictionary:
			for s_name in secondaries:
				var val = secondaries[s_name] * lv_mult
				var line = "%s: [color=#ffccbb]+%.1f%%[/color]" % [str(s_name).capitalize(), val * 100.0]
				
				# Comparison logic for secondaries
				if equipped_item != null and not is_hovering_equipped:
					var eq_lv_mult = 1.0 + (equipped_item.get("level", 1) * 0.05)
					var eq_sec = equipped_item.get("secondary_stats", {})
					if eq_sec.has(s_name):
						var eq_val = eq_sec[s_name] * eq_lv_mult
						var diff = (val - eq_val) * 100.0
						if abs(diff) > 0.05:
							if diff > 0:
								line += " [color=#00ff00](+%.1f%%)[/color]" % diff
							else:
								line += " [color=#ff5555](%.1f%%)[/color]" % diff
						
				txt += line + "\n"
		
		if txt == "": txt = "No stats."
		
		if stats_lbl is RichTextLabel:
			stats_lbl.bbcode_enabled = true
			stats_lbl.text = "[center]%s[/center]" % txt
		else:
			stats_lbl.text = txt
		stats_lbl.visible = true
	
	_update_tooltip_position()

func _hide_custom_tooltip(force: bool = false) -> void:
	if not is_instance_valid(tip): return

	if not force and not _selected_item_ref.is_empty(): 
		# If something is selected, keep the tooltip showing THAT item's stats
		_show_custom_tooltip(null, _selected_item_ref)
		return
			
	tip.visible = false

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
	
	var lower_name = item.name.to_lower()
	var clean_name = item.name.to_lower().replace(" ", "_").replace("-", "_")
	
	# 1. New Premium Assets (Direct Name Mapping - Try both extensions)
	var paths = [
		"res://assets/combat/gear_%s.jpg" % clean_name,
		"res://assets/combat/gear_%s.png" % clean_name
	]
	for p in paths:
		if ResourceLoader.exists(p):
			return p
	
	# 2. Keyword Fallback for specific equipment types
	var keyword_map = {
		"voidreever": "gear_voidreever.jpg",
		"voidreaver": "gear_voidreever.jpg",
		"mace": "gear_heavy_mace.jpg",
		"dagger": "gear_sharp_dagger.jpg",
		"abyssal": "gear_abyssal_garb.jpg",
		"void gaze": "gear_void_gaze.jpg",
		"eternal loop": "gear_eternal_loop.jpg",
		"heart of dreams": "gear_heart_of_dreams.jpg",
		"leather": "gear_leather_tunic.jpg",
		"steel plate": "gear_steel_plate.jpg",
		"iron helm": "gear_iron_helm.jpg",
		"great helm": "gear_great_helm.png", # User provided PNG
		"gold ring": "gear_gold_ring.png",    # User provided PNG
		"soul eye": "gear_soul_eye.png",      # User provided PNG
		"silver band": "gear_silver_band.jpg",
		"crystal neck": "gear_crystal_neck.jpg"
	}
	
	for kw in keyword_map:
		if kw in lower_name:
			var res_path = "res://assets/combat/%s" % keyword_map[kw]
			if ResourceLoader.exists(res_path):
				return res_path
	
	# 3. Last Fallback: Original Generic Icons
	return ICONS.get(category, ICONS["weapon"])
# ── Bulk Dismantle View ────────────────────────────────────────────────────────
func _refresh_bulk_dismantle_view() -> void:
	if _bulk_dismantle_v == null or _em == null: return
	_em.sort_inventory()
	for child in _bulk_dismantle_v.get_children(): child.queue_free()
	
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	main_vbox.add_theme_constant_override("separation", 20)
	_bulk_dismantle_v.add_child(main_vbox)
	
	var header := Label.new()
	header.text = "BULK DISMANTLE"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 24)
	header.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	main_vbox.add_child(header)
	
	# THE TABLE (Selected items)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 180
	main_vbox.add_child(scroll)
	
	var table_grid := GridContainer.new()
	table_grid.columns = 10
	table_grid.add_theme_constant_override("h_separation", 10)
	table_grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(table_grid)
	
	var total_reward: float = 0
	for i in range(_bulk_dismantle_items.size()):
		var item = _bulk_dismantle_items[i]
		total_reward += _em.salvage_item(item)
		
		var item_frame := PanelContainer.new()
		item_frame.custom_minimum_size = Vector2(64, 64)
		item_frame.add_theme_stylebox_override("panel", _get_glass_style(_get_rarity_color(item.rarity)))
		
		var icon := TextureRect.new()
		icon.texture = load(_get_item_icon_path(item, item.slot))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_frame.add_child(icon)
		
		var btn := Button.new()
		btn.flat = true
		item_frame.add_child(btn)
		btn.pressed.connect(_on_bulk_slotted_clicked.bind(i))
		btn.mouse_entered.connect(_show_custom_tooltip.bind(item_frame, item))
		btn.mouse_exited.connect(_hide_custom_tooltip)
		
		table_grid.add_child(item_frame)

	# ACTION BUTTONS
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 20)
	main_vbox.add_child(actions)
	
	var dismantle_all_btn := Button.new()
	dismantle_all_btn.text = "DISMANTLE ALL (%d DC)" % total_reward
	dismantle_all_btn.custom_minimum_size = Vector2(300, 50)
	dismantle_all_btn.disabled = _bulk_dismantle_items.is_empty()
	dismantle_all_btn.pressed.connect(_on_bulk_dismantle_all_pressed)
	actions.add_child(dismantle_all_btn)
	
	var clear_btn := Button.new()
	clear_btn.text = "CLEAR ALL"
	clear_btn.custom_minimum_size = Vector2(120, 50)
	clear_btn.pressed.connect(func(): _bulk_dismantle_items.clear(); _refresh_bulk_dismantle_view())
	actions.add_child(clear_btn)
	
	# INVENTORY
	var inv_lbl := Label.new()
	inv_lbl.text = "SELECT ITEMS TO DISMANTLE"
	inv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inv_lbl.modulate.a = 0.6
	main_vbox.add_child(inv_lbl)
	
	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(inv_scroll)
	
	var inv_grid := GridContainer.new()
	inv_grid.columns = 12
	inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_grid.add_theme_constant_override("h_separation", 8)
	inv_grid.add_theme_constant_override("v_separation", 8)
	inv_scroll.add_child(inv_grid)
	
	for item in _em.inventory:
		# Skip if already in bulk list
		if _bulk_dismantle_items.has(item): continue
		
		var item_frame := PanelContainer.new()
		item_frame.custom_minimum_size = Vector2(56, 56)
		item_frame.add_theme_stylebox_override("panel", _get_glass_style(_get_rarity_color(item.rarity)))
		
		var icon := TextureRect.new()
		icon.texture = load(_get_item_icon_path(item, item.slot))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		item_frame.add_child(icon)
		
		var btn := Button.new()
		btn.flat = true
		item_frame.add_child(btn)
		btn.pressed.connect(_on_bulk_item_clicked.bind(item))
		btn.mouse_entered.connect(_show_custom_tooltip.bind(item_frame, item))
		btn.mouse_exited.connect(_hide_custom_tooltip)
		
		inv_grid.add_child(item_frame)

func _on_bulk_item_clicked(item: Dictionary) -> void:
	if not _bulk_dismantle_items.has(item):
		_bulk_dismantle_items.append(item)
		_refresh_bulk_dismantle_view()

func _on_bulk_slotted_clicked(idx: int) -> void:
	if idx < _bulk_dismantle_items.size():
		_bulk_dismantle_items.remove_at(idx)
		_refresh_bulk_dismantle_view()

func _on_bulk_dismantle_all_pressed() -> void:
	if _bulk_dismantle_items.is_empty(): return
	
	var total_reward: float = 0
	for item in _bulk_dismantle_items:
		total_reward += _em.salvage_item(item)
		if _em.inventory.has(item):
			_em.inventory.erase(item)
	
	if _gm:
		_gm.dreamcloud += total_reward
		_gm.save_game()
		_gm._refresh_top_ui()
	
	_bulk_dismantle_items.clear()
	_refresh_bulk_dismantle_view()
	
	_on_message_logged("[color=#ffaaaa]Bulk Dismantle complete! Gained %d DC.[/color]" % total_reward)

func _on_skill_pressed(id: String) -> void:
	var data = SKILL_DATA[id]
	var level = _gm.get_skill_level(id) if _gm else 0
	var sp_cost = data.cost
	_on_unlock_pressed(id, sp_cost)

func _get_rarity_color(rarity: String) -> Color:
	match rarity.to_lower():
		"common": return Color(0.8, 0.8, 0.8)
		"uncommon": return Color(0.2, 0.8, 0.2)
		"rare": return Color(0.2, 0.5, 1.0)
		"epic": return Color(0.7, 0.2, 1.0)
		"legendary": return Color(1.0, 0.8, 0.0)
		"mythic": return Color(1.0, 0.2, 0.2)
		"transcendent": return Color(0.2, 1.0, 1.0)
		"god_tier": return Color(1.0, 1.0, 1.0)
		"void": return Color(0.5, 0.0, 1.0) # Added void rarity color
	return Color(1, 1, 1)

func _show_item_tooltip(title: String, desc: String, color: Color) -> void:
	if not tip: return
	tip.visible = true
	var lbl_title := tip.find_child("TooltipTitle", true, false) as Label
	var lbl_desc := tip.find_child("TooltipDesc", true, false) as Label
	if lbl_title: 
		lbl_title.text = title
		lbl_title.add_theme_color_override("font_color", color)
	if lbl_desc: lbl_desc.text = desc
	_update_tooltip_position()
