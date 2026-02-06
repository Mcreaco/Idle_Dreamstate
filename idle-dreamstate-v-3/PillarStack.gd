extends Node3D

@export var segment_spacing: float = 1.5
@export var segment_scale: Vector3 = Vector3(0.65, 0.65, 0.65)
@export var rise_distance: float = 2.0
@export var rise_time: float = 0.35

@export var debug_print: bool = false

@export var start_instab01: float = 0.15
@export var freq_low: float = 0.05
@export var freq_high: float = 0.10
@export var ramp_target_offset_hint: float = 0.90
@export var ramp_end_offset: float = 0.35

@export var scale_top: float = 0.6
@export var scale_mid: float = 1.25
@export var scale_bottom: float = 0.9
@export var mid_center: float = 0.55
@export var mid_width: float = 0.35

# Spacing modulation: top closer, mid slightly farther, bottom moderate
@export var spacing_top_mul: float = 0.7
@export var spacing_mid_mul: float = 1.1
@export var spacing_bottom_mul: float = 0.95

# Extra separation for deep stacks (applied to bottom band)
@export var bottom_spacing_depth_start: int = 9
@export var bottom_extra_spacing_per_depth: float = 0.35
@export var bottom_extra_spacing_max: float = 3.0
@export var bottom_band_fraction: float = 0.40  # fraction of deepest visible segments that get extra gap

var segments: Array[Node3D] = []
var shown: int = 0
var _instab01: float = 0.0
var _noise_tex: NoiseTexture2D = null
var _ramp: Gradient = null
var _ramp_mid_index: int = -1

var _base_spacing_mul: Array[float] = []
var _base_scale_xy: Array[float] = []

func _ready() -> void:
	randomize()
	segments.clear()
	for c: Node in get_children():
		if c is Node3D:
			segments.append(c as Node3D)

	segments.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.name < b.name
	)

	_base_spacing_mul.resize(segments.size())
	_base_scale_xy.resize(segments.size())

	for i: int in range(segments.size()):
		var s: Node3D = segments[i]
		var t: float = 0.0
		if segments.size() > 1:
			t = float(i) / float(segments.size() - 1)

		var w: float = max(mid_width, 0.05)
		var dist: float = abs(t - mid_center) / w
		var peak: float = clamp(1.0 - dist * dist, 0.0, 1.0)

		var sxy: float = scale_top * (1.0 - peak) + scale_mid * peak
		var bottom_lerp: float = t
		sxy = lerp(sxy, scale_bottom, bottom_lerp * (1.0 - peak) * 0.6)
		sxy = clamp(sxy, min(scale_top, scale_bottom), max(scale_mid, scale_top, scale_bottom))

		var spacing_mul: float = spacing_top_mul * (1.0 - peak) + spacing_mid_mul * peak
		spacing_mul = lerp(spacing_mul, spacing_bottom_mul, t * 0.5)

		_base_scale_xy[i] = sxy
		_base_spacing_mul[i] = spacing_mul

		s.scale = segment_scale * sxy
		s.position = Vector3.ZERO

		var mi: MeshInstance3D = _get_mesh_instance(s)
		if mi != null:
			mi.set_instance_shader_parameter(&"uv_offset", Vector2(randf() * 50.0, randf() * 50.0))
			mi.set_instance_shader_parameter(&"time_offset", randf() * 100.0)

	for s2: Node3D in segments:
		s2.visible = false
	shown = 0

	_cache_noise_and_ramp()
	_layout_segments(0)

func set_depth(d: int) -> void:
	var target: int = clampi(int(d), 0, segments.size())
	var prev: int = shown
	shown = target
	_layout_segments(target)

	# Hide extras
	for i: int in range(target, segments.size()):
		segments[i].visible = false

	# Animate newly shown
	if target > prev:
		for i in range(prev, target):
			_show_one(i)
	elif target < prev:
		# already hidden above; nothing else needed
		pass

func _layout_segments(depth: int) -> void:
	var extra_depth_gap: float = 0.0
	if depth >= bottom_spacing_depth_start:
		extra_depth_gap = min(
			max(0.0, float(depth - bottom_spacing_depth_start + 1) * bottom_extra_spacing_per_depth),
			bottom_extra_spacing_max
		)

	var bottom_count: int = int(ceil(float(depth) * bottom_band_fraction))
	var bottom_start: int = max(0, depth - bottom_count)

	var y_accum: float = 0.0
	for i in range(segments.size()):
		var gap: float = segment_spacing * _base_spacing_mul[i]
		if i >= bottom_start and i < depth:
			gap += extra_depth_gap
		var pos_y: float = -y_accum
		segments[i].position = Vector3(0.0, pos_y, 0.0)
		y_accum += gap

func _show_one(i: int) -> void:
	var s: Node3D = segments[i]
	var final_y: float = s.position.y
	s.visible = true
	s.position.y = final_y - rise_distance
	create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).tween_property(s, "position:y", final_y, rise_time)

func set_instability(instability: float, max_instability: float = 100.0) -> void:
	_instab01 = clampf(instability / max_instability, 0.0, 1.0)
	for s: Node3D in segments:
		var mi: MeshInstance3D = _get_mesh_instance(s)
		if mi != null:
			mi.set_instance_shader_parameter(&"instab01", _instab01)

	if _noise_tex == null or _ramp == null or _ramp_mid_index < 0:
		return

	var t: float = inverse_lerp(start_instab01, 1.0, _instab01)
	t = clampf(t, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)

	var noise_obj: Noise = _noise_tex.noise
	var freq: float = lerpf(freq_low, freq_high, t)
	if noise_obj != null:
		noise_obj.frequency = freq
		noise_obj.emit_changed()

	var pc: int = _ramp.get_point_count()
	if pc >= 3:
		var new_off: float = lerpf(0.90, ramp_end_offset, t)
		var left: int = maxi(_ramp_mid_index - 1, 0)
		var right: int = mini(_ramp_mid_index + 1, pc - 1)
		var min_off: float = 0.0
		var max_off: float = 1.0
		if left != _ramp_mid_index:
			min_off = _ramp.get_offset(left) + 0.001
		if right != _ramp_mid_index:
			max_off = _ramp.get_offset(right) - 0.001
		new_off = clampf(new_off, min_off, max_off)
		_ramp.set_offset(_ramp_mid_index, new_off)
		_ramp.emit_changed()

	_noise_tex.emit_changed()

func reset_visuals() -> void:
	for s: Node3D in segments:
		s.visible = false
	shown = 0
	set_instability(0.0, 100.0)
	_layout_segments(0)

func _cache_noise_and_ramp() -> void:
	_noise_tex = null; _ramp = null; _ramp_mid_index = -1
	var any_mat: ShaderMaterial = _find_any_shader_material()
	if any_mat == null:
		return
	var tex_v: Variant = any_mat.get_shader_parameter("crack_mask")
	if not (tex_v is NoiseTexture2D):
		return
	_noise_tex = tex_v as NoiseTexture2D
	_ramp = _noise_tex.color_ramp
	if _ramp == null:
		return
	var count: int = _ramp.get_point_count()
	var best_i: int = -1
	var best_dist: float = 999.0
	for i: int in range(count):
		var off: float = _ramp.get_offset(i)
		var d: float = absf(off - ramp_target_offset_hint)
		if d < best_dist:
			best_dist = d
			best_i = i
	_ramp_mid_index = best_i

func _find_any_shader_material() -> ShaderMaterial:
	for s: Node3D in segments:
		var mi: MeshInstance3D = _get_mesh_instance(s)
		if mi == null: continue
		var mat: Material = mi.get_material_override()
		if mat is ShaderMaterial: return mat as ShaderMaterial
	return null

func _get_mesh_instance(s: Node3D) -> MeshInstance3D:
	if s is MeshInstance3D:
		return s as MeshInstance3D
	for child: Node in s.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null
