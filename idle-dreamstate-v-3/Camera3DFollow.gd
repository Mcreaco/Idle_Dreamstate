extends Camera3D

@export var stack_path: NodePath = NodePath("../PillarRig/Segments")

@export var close_distance: float = 8.0
@export var distance_per_depth: float = 1.4
@export var max_distance: float = 280.0
@export var follow_smooth: float = 8.0
@export var zoom_time: float = 0.35

@export var pitch_degrees: float = -8.0
@export var yaw_degrees: float = 0.0
@export var roll_degrees: float = 0.0
@export var world_volfog_length: float = 64.0

# -------------------------------------------------------------------
# Atmosphere (scripts-only): make the background feel layered + deep
# -------------------------------------------------------------------

# Clear color (background). We lerp between shallow and deep as depth increases.
@export var clear_shallow: Color = Color(0.02, 0.06, 0.20, 1.0) # nice blue
@export var clear_deep: Color = Color(0.005, 0.01, 0.04, 1.0)  # near-black blue
@export var clear_depth_start: int = 0
@export var clear_depth_end: int = 15

# Global fog settings (do NOT hard-disable at depth >= 3; that makes it look flat)
@export var world_fog_base: float = 0.010
@export var world_fog_per_depth: float = 0.0012
@export var world_fog_min: float = 0.006
@export var world_fog_max: float = 0.045
@export var world_volfog_length_base: float = 64.0
@export var world_volfog_length_per_depth: float = 6.0

# Fog look (bluish mist + slight “energy”)
@export var fog_light_color: Color = Color(0.55, 0.75, 1.00, 1.0)
@export var fog_albedo: Color = Color(0.35, 0.55, 0.85, 1.0)
@export var fog_emission: Color = Color(0.08, 0.18, 0.35, 1.0)
@export var fog_emission_energy: float = 0.55
@export var fog_anisotropy: float = 0.65

# Optional “vignette-ish” depth darkening (affects clear color and fog slightly)
@export var depth_darkening_strength: float = 0.012
@export var min_brightness: float = 0.40

var stack: Node3D = null
var _last_depth: int = -1
var _distance: float = 8.0
var _zoom_tween: Tween = null

func _ready() -> void:
	current = true
	cull_mask = 0xFFFFFFFF
	near = 0.05
	far = 50000.0

	stack = get_node_or_null(stack_path) as Node3D
	if stack == null:
		stack = get_tree().current_scene.find_child("Segments", true, false) as Node3D

	_distance = close_distance
	_apply_world_env_visual_defaults()
	_apply_clear_color_for_depth(0)
	_adjust_fog(0)

func _process(delta: float) -> void:
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, roll_degrees)

	if stack == null:
		return

	var depth := _get_depth(stack)

	if depth != _last_depth:
		_last_depth = depth
		_request_zoom_for_depth(depth)

	var origin := stack.global_position
	var framing: Dictionary = _framing_for_depth(depth)
	var target_pos := origin + Vector3(0.0, float(framing["y"]), _distance)

	global_position = global_position.lerp(target_pos, 1.0 - exp(-follow_smooth * delta))
	look_at(origin + Vector3(0, float(framing["look_y"]), 0), Vector3.UP)

	_apply_clear_color_for_depth(depth)
	_adjust_fog(depth)

func _request_zoom_for_depth(depth: int) -> void:
	var framing: Dictionary = _framing_for_depth(depth)
	var wanted: float = float(framing["dist"])
	wanted = clampf(wanted, close_distance, max_distance)

	if _zoom_tween != null and _zoom_tween.is_running():
		_zoom_tween.kill()

	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_QUAD)
	_zoom_tween.set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "_distance", wanted, zoom_time)

func _framing_for_depth(depth: int) -> Dictionary:
	if depth <= 1: return { "y": 1.2, "dist": 7.5, "look_y": 0.2 }
	if depth == 2: return { "y": 0.5, "dist": 8.5, "look_y": -0.2 }
	if depth == 3: return { "y": 0.0, "dist": 9.5, "look_y": -0.6 }
	if depth == 4: return { "y": -0.8, "dist": 11.5, "look_y": -1.1 }
	if depth == 5: return { "y": -1.6, "dist": 14.8, "look_y": -1.8 }
	if depth == 6: return { "y": -2.8, "dist": 18.5, "look_y": -2.6 }
	if depth == 7: return { "y": -4.2, "dist": 23.5, "look_y": -3.5 }
	if depth == 8: return { "y": -5.8, "dist": 29.5, "look_y": -4.5 }
	if depth == 9: return { "y": -7.6, "dist": 36.5, "look_y": -5.7 }

	var extra := float(depth - 9)
	var y := -7.6 - extra * 2.4
	var dist := 36.5 + extra * 6.0
	var look_y := -5.7 - extra * 1.2
	return { "y": y, "dist": dist, "look_y": look_y }

func _get_depth(s: Node) -> int:
	var v: Variant = s.get("shown")
	if typeof(v) == TYPE_INT:
		return int(v)

	var count := 0
	for c in s.get_children():
		if c is Node3D and (c as Node3D).visible:
			count += 1
	return count

func _apply_clear_color_for_depth(depth: int) -> void:
	# 1) Depth-based gradient (shallow -> deep)
	var t := 0.0
	if clear_depth_end != clear_depth_start:
		t = clampf((float(depth) - float(clear_depth_start)) / (float(clear_depth_end - clear_depth_start)), 0.0, 1.0)

	var base := clear_shallow.lerp(clear_deep, t)

	# 2) Extra darkening based on camera vertical position (subtle vignette feel)
	var depth_factor := clampf(1.0 - abs(global_position.y) * depth_darkening_strength, min_brightness, 1.0)
	base.r *= depth_factor
	base.g *= depth_factor
	base.b *= depth_factor
	base.a = 1.0

	RenderingServer.set_default_clear_color(base)

func _adjust_fog(depth: int) -> void:
	var env := _get_env()
	if env == null:
		return

	# Keep volumetric fog ON so FogVolume nodes render.
	# We only control the GLOBAL fog density here.
	env.volumetric_fog_enabled = true
	env.fog_enabled = false # optional: disables old-style distance fog

	# At higher depths: keep world fog nearly 0 (but volumes still work)
	var d: float = clampf(
		world_fog_base + world_fog_per_depth * float(maxi(0, depth - 1)),
		world_fog_min,
		world_fog_max
	)

	# If you want "no global wash" after depth 3:
	if depth >= 3:
		d = 0.0

	env.volumetric_fog_density = d
	env.fog_density = 0.0
	env.volumetric_fog_length = world_volfog_length


func _force_world_fog_defaults() -> void:
	var env := _get_env()
	if env == null:
		return

	# Keep ON so FogVolumes work from frame 1
	env.volumetric_fog_enabled = true
	env.fog_enabled = false

	var d: float = clampf(world_fog_base, world_fog_min, world_fog_max)
	env.volumetric_fog_density = d
	env.fog_density = 0.0
	env.volumetric_fog_length = world_volfog_length


func _apply_world_env_visual_defaults() -> void:
	var env := _get_env()
	if env == null:
		return

	# Safe defaults that help atmosphere without blowing out visuals
	env.fog_enabled = true
	env.volumetric_fog_enabled = true

	env.fog_density = clampf(world_fog_base, world_fog_min, world_fog_max)
	env.volumetric_fog_density = clampf(world_fog_base, world_fog_min, world_fog_max)
	env.volumetric_fog_length = world_volfog_length_base

	env.fog_light_color = fog_light_color
	env.volumetric_fog_albedo = fog_albedo
	env.volumetric_fog_emission = fog_emission
	env.volumetric_fog_emission_energy = fog_emission_energy
	env.volumetric_fog_anisotropy = fog_anisotropy

func _get_env() -> Environment:
	var world := get_viewport().get_world_3d()
	if world == null:
		return null
	return world.environment
