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

# WorldEnvironment fog clamps
@export var world_fog_base: float = 0.02      # starting density (much lower than 0.2)
@export var world_fog_per_depth: float = 0.00  # no growth with depth; keep flat
@export var world_fog_min: float = 0.0
@export var world_fog_max: float = 0.04       # hard cap; keep very thin
@export var world_volfog_length: float = 64.0 # matches inspector; keep if you like

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
	_force_world_fog_defaults()

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

func _adjust_fog(depth: int) -> void:
	var env := _get_env()
	if env == null:
		return

	# Fully off at depth >= 3
	if depth >= 3:
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.fog_density = 0.0
		env.volumetric_fog_density = 0.0
		return

	env.fog_enabled = true
	env.volumetric_fog_enabled = true

	var d: float = clamp(
		world_fog_base + world_fog_per_depth * float(max(0, depth - 1)),
		world_fog_min,
		world_fog_max
	)
	env.fog_density = d
	env.volumetric_fog_density = d
	env.volumetric_fog_length = world_volfog_length

func _force_world_fog_defaults() -> void:
	var env := _get_env()
	if env == null:
		return
	env.fog_enabled = true
	env.volumetric_fog_enabled = true
	env.fog_density = clamp(world_fog_base, world_fog_min, world_fog_max)
	env.volumetric_fog_density = clamp(world_fog_base, world_fog_min, world_fog_max)
	env.volumetric_fog_length = world_volfog_length

func _get_env() -> Environment:
	var world := get_viewport().get_world_3d()
	if world == null:
		return null
	return world.environment
