extends Node3D
class_name PillarSegment

var _rings: Array[MeshInstance3D] = []

func _ready() -> void:
	_rings.clear()
	for c in get_children():
		if c is MeshInstance3D:
			_rings.append(c)

	_rings.sort_custom(func(a, b): return a.name < b.name)

	# IMPORTANT: duplicate materials so alpha changes don't affect all rings globally
	for r in _rings:
		var mat := r.get_active_material(0)
		if mat != null:
			r.set_surface_override_material(0, mat.duplicate(true))

func set_ring_count(count: int) -> void:
	count = clampi(count, 0, _rings.size())
	for i in range(_rings.size()):
		_rings[i].visible = (i < count)

func set_ring_alpha_by_index(ring_index: int, a: float) -> void:
	if ring_index < 0 or ring_index >= _rings.size():
		return

	a = clampf(a, 0.0, 1.0)
	var ring := _rings[ring_index]

	var mat := ring.get_active_material(0)
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c := sm.albedo_color
		c.a = a
		sm.albedo_color = c

func set_all_visible_ring_alpha(a: float) -> void:
	a = clampf(a, 0.0, 1.0)
	for i in range(_rings.size()):
		if _rings[i].visible:
			set_ring_alpha_by_index(i, a)

func set_crack_intensity(v: float) -> void:
	var crack: float = clampf(v, 0.0, 1.0)
	for ring in _rings:
		var mat := ring.get_active_material(0)
		if mat is StandardMaterial3D:
			var sm := mat as StandardMaterial3D
			sm.emission_energy_multiplier = lerp(1.0, 0.4, crack)
