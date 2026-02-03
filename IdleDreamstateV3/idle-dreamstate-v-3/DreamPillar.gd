extends Node3D
class_name DreamPillar

@export var gm_path: NodePath
@export var segment_scene: PackedScene
@export var segments_root_path: NodePath

@export var max_visible_segments: int = 32
@export var rings_per_segment: int = 4
@export var segment_spacing: float = 1.0

@export var top_scale: float = 1.0
@export var bottom_scale: float = 0.7
@export var taper_curve_pow: float = 1.8

@export var fade_in_time: float = 0.35

var _gm: Node = null
var _segments_root: Node3D = null
var _last_ring_depth: int = 1

func _ready() -> void:
	_gm = get_node_or_null(gm_path)
	_segments_root = get_node_or_null(segments_root_path) as Node3D
	if _segments_root == null:
		_segments_root = Node3D.new()
		_segments_root.name = "Segments"
		add_child(_segments_root)

	if _gm != null and _gm.has_signal("depth_changed"):
		if not _gm.is_connected("depth_changed", Callable(self, "_on_depth_changed")):
			_gm.connect("depth_changed", Callable(self, "_on_depth_changed"))

	var start_depth := 0
	if _gm != null:
		var d = _gm.get("depth")
		if d != null:
			start_depth = int(d)

	# Treat depth as “rings revealed”. Always show at least 1 ring.
	_last_ring_depth = maxi(start_depth, 1)
	_rebuild_segments(_last_ring_depth)

func _on_depth_changed(new_depth: int) -> void:
	var ring_depth := maxi(int(new_depth), 1)
	_rebuild_segments(ring_depth)

func _rebuild_segments(ring_depth: int) -> void:
	if segment_scene == null or _segments_root == null:
		return

	var rps: int = maxi(rings_per_segment, 1)
	var prev_depth: int = _last_ring_depth
	_last_ring_depth = ring_depth

	var max_rings: int = maxi(max_visible_segments * rps, 1)
	var depth_clamped: int = clampi(ring_depth, 1, max_rings)

	var target_segments: int = int(ceil(float(depth_clamped) / float(rps)))
	target_segments = clampi(target_segments, 1, maxi(max_visible_segments, 1))

	for c in _segments_root.get_children():
		c.queue_free()

	var is_dive: bool = depth_clamped > prev_depth
	var new_global_ring_index: int = depth_clamped - 1

	for seg_i in range(target_segments):
		var seg := segment_scene.instantiate() as Node3D
		_segments_root.add_child(seg)

		seg.position = Vector3(0.0, -float(seg_i) * segment_spacing, 0.0)

		var remaining: int = depth_clamped - (seg_i * rps)
		var rings_to_show: int = clampi(remaining, 0, rps)

		var virtual_depth: int = seg_i * rps
		var denom: float = float(maxi((max_visible_segments * rps) - 1, 1))
		var tt: float = clampf(float(virtual_depth) / denom, 0.0, 1.0)
		tt = pow(tt, taper_curve_pow)
		var s: float = lerp(top_scale, bottom_scale, tt)
		seg.scale = Vector3(s, 1.0, s)

		var rings := _get_sorted_rings(seg)
		_prepare_ring_materials(rings)

		for i in range(rings.size()):
			var ring := rings[i]
			ring.visible = (i < rings_to_show)
			if ring.visible:
				_set_ring_alpha(ring, 1.0)

		if is_dive:
			var local_new_seg: int = int(float(new_global_ring_index) / float(rps))
			var local_new_ring: int = new_global_ring_index % rps
			if local_new_seg == seg_i and local_new_ring < rings_to_show and local_new_ring < rings.size():
				var new_ring := rings[local_new_ring]
				_set_ring_alpha(new_ring, 0.0)
				var tw := create_tween()
				tw.tween_method(
					func(a: float) -> void:
						_set_ring_alpha(new_ring, a),
					0.0, 1.0, fade_in_time
				)

func _get_sorted_rings(seg: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for c in seg.get_children():
		if c is MeshInstance3D:
			out.append(c)
	out.sort_custom(func(a, b): return a.name < b.name)
	return out

func _prepare_ring_materials(rings: Array[MeshInstance3D]) -> void:
	for r in rings:
		var mat := r.get_active_material(0)
		if mat != null:
			r.set_surface_override_material(0, mat.duplicate(true))

func _set_ring_alpha(ring: MeshInstance3D, a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	var mat := ring.get_active_material(0)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := sm.albedo_color
		c.a = a
		sm.albedo_color = c
