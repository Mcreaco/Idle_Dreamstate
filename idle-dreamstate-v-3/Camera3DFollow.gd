extends Camera3D

@export var stack_path: NodePath = NodePath("../PillarRig/Segments")

# Framing
@export var base_height: float = 2.4
@export var height_per_depth: float = -0.9     # negative = dive down into fog
@export var look_offset_y: float = -0.5

# Zoom (close-up -> zoom out as depth increases)
@export var close_distance: float = 6.0        # depth 1-ish
@export var distance_per_depth: float = 1.1   # how much to zoom out each segment
@export var max_distance: float = 16
@export var pitch_degrees: float = -8.0   # tilt down a bit (NOT top-down)
@export var yaw_degrees: float = 0.0      # rotate around pillar if needed
@export var roll_degrees: float = 0.0


# Smoothing
@export var follow_smooth: float = 8.0
@export var zoom_time: float = 0.35

var stack: Node3D = null
var _last_depth: int = -1
var _distance: float = 6.0
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

func _process(delta: float) -> void:
	rotation_degrees = Vector3(pitch_degrees, yaw_degrees, roll_degrees)
	if stack == null:
		return

	var depth := _get_depth(stack)

	# Trigger a zoom-out when a new segment appears
	if depth != _last_depth:
		_last_depth = depth
		_request_zoom_for_depth(depth)

	var origin := stack.global_position
	var y := base_height + float(depth) * height_per_depth

	var target_pos := origin + Vector3(0.0, y, _distance)
	global_position = global_position.lerp(target_pos, 1.0 - exp(-follow_smooth * delta))


func _request_zoom_for_depth(depth: int) -> void:
	var wanted := close_distance + float(max(depth - 1, 0)) * distance_per_depth
	wanted = clampf(wanted, close_distance, max_distance)

	if _zoom_tween != null and _zoom_tween.is_running():
		_zoom_tween.kill()

	_zoom_tween = create_tween()
	_zoom_tween.set_trans(Tween.TRANS_QUAD)
	_zoom_tween.set_ease(Tween.EASE_OUT)
	_zoom_tween.tween_property(self, "_distance", wanted, zoom_time)

func _get_depth(s: Node) -> int:
	# Best: PillarStack exposes `shown`
	var v: Variant = s.get("shown")
	if typeof(v) == TYPE_INT:
		return int(v)

	# Fallback: count visible children
	var count := 0
	for c in s.get_children():
		if c is Node3D and (c as Node3D).visible:
			count += 1
	return count
