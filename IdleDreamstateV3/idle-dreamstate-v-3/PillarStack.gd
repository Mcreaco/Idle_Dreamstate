extends Node3D

@export var segment_spacing: float = 1.5
@export var segment_scale: Vector3 = Vector3(0.65, 0.65, 0.65)
@export var rise_distance: float = 2.0
@export var rise_time: float = 0.35

@export var debug_print: bool = false

# Start ramping visuals after this instability (0..1)
@export var start_instab01: float = 0.15  # set to 0.20 for 20%

# Noise frequency range (applied AFTER start_instab01)
@export var freq_low: float = 0.05
@export var freq_high: float = 0.10

# We pick the ColorRamp point closest to this offset (your “middle moving one”)
@export var ramp_target_offset_hint: float = 0.90

# Where the moving point ends up at 100% (don’t go to 0.0 or it can flood)
@export var ramp_end_offset: float = 0.35

var segments: Array[Node3D] = []
var shown: int = 0

var _instab01: float = 0.0

# Cached resources
var _noise_tex: NoiseTexture2D = null
var _ramp: Gradient = null
var _ramp_mid_index: int = -1


func _ready() -> void:
	randomize()

	segments.clear()
	for c: Node in get_children():
		if c is Node3D:
			segments.append(c as Node3D)

	segments.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.name < b.name
	)

	# Layout + per-segment variation (only affects visuals if shader uses instance uniforms)
	for i: int in range(segments.size()):
		var s: Node3D = segments[i]
		s.scale = segment_scale
		s.position = Vector3(0.0, -float(i) * segment_spacing, 0.0)

		var mi: MeshInstance3D = _get_mesh_instance(s)
		if mi != null:
			mi.set_instance_shader_parameter(&"uv_offset", Vector2(randf() * 50.0, randf() * 50.0))
			mi.set_instance_shader_parameter(&"time_offset", randf() * 100.0)

	# Start hidden
	for s2: Node3D in segments:
		s2.visible = false
	shown = 0

	_cache_noise_and_ramp()

	if debug_print:
		print("[PillarStack] READY segments=", segments.size(),
			" noise_tex=", _noise_tex,
			" ramp=", _ramp,
			" mid_index=", _ramp_mid_index)


# -------------------------
# DEPTH / REVEAL
# -------------------------
func set_depth(d: int) -> void:
	var target: int = clampi(int(d), 0, segments.size())

	for i: int in range(segments.size()):
		segments[i].visible = (i < target)

	while shown < target:
		_show_one(shown)
		shown += 1

	while shown > target:
		shown -= 1


func _show_one(i: int) -> void:
	var s: Node3D = segments[i]
	var final_y: float = -float(i) * segment_spacing

	s.visible = true
	s.position.y = final_y - rise_distance

	create_tween() \
		.set_trans(Tween.TRANS_QUAD) \
		.set_ease(Tween.EASE_OUT) \
		.tween_property(s, "position:y", final_y, rise_time)


# -------------------------
# INSTABILITY DRIVER
# -------------------------
func set_instability(instability: float, max_instability: float = 100.0) -> void:
	_instab01 = clampf(instability / max_instability, 0.0, 1.0)

	# Always push instab01 to shader (even if noise/ramp caching failed)
	for s: Node3D in segments:
		var mi: MeshInstance3D = _get_mesh_instance(s)
		if mi != null:
			mi.set_instance_shader_parameter(&"instab01", _instab01)

	# If we can’t drive NoiseTexture2D / ColorRamp, stop here
	if _noise_tex == null or _ramp == null or _ramp_mid_index < 0:
		if debug_print:
			print("[PillarStack] set_instability instab01=", _instab01, " (no noise/ramp cached)")
		return

	# Gate: do nothing until start_instab01, then smoothly ramp to 1 at 100%
	var t: float = inverse_lerp(start_instab01, 1.0, _instab01)
	t = clampf(t, 0.0, 1.0)
	# smoothstep easing
	t = t * t * (3.0 - 2.0 * t)

	# 1) Frequency: 0.05 -> 0.10 (after threshold)
	var noise_obj: Noise = _noise_tex.noise
	var freq: float = lerpf(freq_low, freq_high, t)
	if noise_obj != null:
		noise_obj.frequency = freq
		noise_obj.emit_changed()

	# 2) Ramp moving point: 0.90 -> ramp_end_offset (after threshold)
	var pc: int = _ramp.get_point_count()
	if pc >= 3:
		var new_off: float = lerpf(0.90, ramp_end_offset, t)

		# Keep ordered so it can't cross neighbors
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

	# Force the noise texture itself to refresh
	_noise_tex.emit_changed()

	if debug_print:
		print("[PillarStack] instab01=", _instab01,
			" t=", t,
			" freq=", freq,
			" ramp_mid=", _ramp.get_offset(_ramp_mid_index))


func reset_visuals() -> void:
	for s: Node3D in segments:
		s.visible = false
	shown = 0
	set_instability(0.0, 100.0)


# -------------------------
# CACHING
# -------------------------
func _cache_noise_and_ramp() -> void:
	_noise_tex = null
	_ramp = null
	_ramp_mid_index = -1

	var any_mat: ShaderMaterial = _find_any_shader_material()
	if any_mat == null:
		if debug_print:
			print("[PillarStack] ERROR: no ShaderMaterial found on segments.")
		return

	var tex_v: Variant = any_mat.get_shader_parameter("crack_mask")
	if not (tex_v is NoiseTexture2D):
		if debug_print:
			print("[PillarStack] ERROR: crack_mask is not NoiseTexture2D. It is: ", tex_v)
		return

	_noise_tex = tex_v as NoiseTexture2D
	_ramp = _noise_tex.color_ramp
	if _ramp == null:
		if debug_print:
			print("[PillarStack] ERROR: NoiseTexture2D has no ColorRamp assigned.")
		return

	# Choose the ramp point closest to ~0.90
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

	if debug_print:
		print("[PillarStack] cache ok. points=", count,
			" chosen=", _ramp_mid_index,
			" offset=", _ramp.get_offset(_ramp_mid_index))


func _find_any_shader_material() -> ShaderMaterial:
	for s: Node3D in segments:
		var mi: MeshInstance3D = _get_mesh_instance(s)
		if mi == null:
			continue
		var mat: Material = mi.get_material_override()
		if mat is ShaderMaterial:
			return mat as ShaderMaterial
	return null


func _get_mesh_instance(s: Node3D) -> MeshInstance3D:
	if s is MeshInstance3D:
		return s as MeshInstance3D
	for child: Node in s.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
	return null
