extends Node3D
class_name PillarFogSpawner

@export var pillar_stack_path: NodePath

# Side/back fog only (front clear)
@export var fog_size: Vector3 = Vector3(46, 14, 46)
@export var fog_density: float = 0.0016
@export var fog_albedo: Color = Color(0.06, 0.10, 0.14, 1.0)
@export var fog_emission: Color = Color(0.03, 0.07, 0.16, 0.06) # slightly dimmer
@export var fog_noise_scale: float = 68.0
@export var fog_height_falloff: float = 0.008
@export var fog_offset_left: Vector3 = Vector3(-32, -0.5, -8)
@export var fog_offset_right: Vector3 = Vector3(32, -0.5, -8)
@export var fog_offset_back: Vector3 = Vector3(0, -0.5, -38)

# Fade side/back fog; leave a visible hint
@export var fade_start_depth: int = 1
@export var fade_end_depth: int = 4
@export var min_density_factor: float = 0.12
@export var min_emission_factor: float = 0.08

# Clear tube (zero density) centered on the tower
@export var clear_size: Vector3 = Vector3(42, 44, 60)
@export var clear_offset: Vector3 = Vector3(0, 0, 0)

# Beam / lights (DIMMED)
@export var beam_radius: float = 0.7
@export var beam_height_mult: float = 3.0
@export var beam_emission: Color = Color(0.22, 0.52, 0.85, 1.0)
@export var beam_energy: float = 9.0          # was ~18
@export var beam_alpha: float = 0.22          # was ~0.32

@export var rung_count: int = 6
@export var rung_energy: float = 6.0         # was ~10
@export var rung_range_mul: float = 1.4

@export var ring_count: int = 6
@export var ring_radius: float = 1.2
@export var ring_thickness: float = 0.08
@export var ring_emission: Color = Color(0.30, 0.65, 1.05, 1.0)
@export var ring_energy: float = 6.0         # was ~11
@export var ring_height_span: float = 1.0

@export var top_light_energy: float = 2.6    # was ~5
@export var bottom_light_energy: float = 2.0 # was ~4

# Ground/floor panel (DIMMED)
@export var floor_radius: float = 220.0
@export var floor_thickness: float = 0.15
@export var floor_y_offset: float = -60.0
@export var floor_color: Color = Color(0.03, 0.05, 0.08, 1.0)
@export var floor_emission: Color = Color(0.10, 0.22, 0.55, 0.40)
@export var floor_emission_energy: float = 0.7  # was ~1.6

# Backdrop wall (this is usually the “too bright / flat” culprit)
@export var backdrop_enabled: bool = true
@export var backdrop_size: Vector2 = Vector2(520.0, 320.0)
@export var backdrop_pos: Vector3 = Vector3(0, 0, -260)
@export var backdrop_color: Color = Color(0.01, 0.02, 0.05, 1.0)
@export var backdrop_emission: Color = Color(0.02, 0.05, 0.10, 1.0)
@export var backdrop_energy: float = 0.25
@export var backdrop_alpha: float = 0.18

var fog_materials: Array[FogMaterial] = []
var pillar: Node = null
var base_density: float
var base_emission: Color

func _ready() -> void:
	pillar = get_node_or_null(pillar_stack_path)

	_create_fog_volume(fog_offset_left)
	_create_fog_volume(fog_offset_right)
	_create_fog_volume(fog_offset_back)
	_add_clear_tube()

	if backdrop_enabled:
		_add_backdrop_wall()

	_add_beam_and_lights()
	_add_floor_panel()

	if pillar:
		global_position = (pillar as Node3D).global_position
		_disable_pillar_fog(pillar)

	base_density = fog_density
	base_emission = fog_emission

func _process(_delta: float) -> void:
	if pillar != null and pillar.has_method("get"):
		var v: Variant = pillar.get("shown")
		if typeof(v) == TYPE_INT:
			_set_depth_internal(int(v))

func set_depth(depth: int) -> void:
	_set_depth_internal(depth)

func _set_depth_internal(depth: int) -> void:
	var t: float = 0.0
	if depth >= fade_start_depth:
		if depth >= fade_end_depth:
			t = 1.0
		else:
			t = float(depth - fade_start_depth) / float(fade_end_depth - fade_start_depth)
	t = clamp(t, 0.0, 1.0)

	var dens_factor: float = lerp(1.0, min_density_factor, t)
	var emiss_factor: float = lerp(1.0, min_emission_factor, t)

	for fm in fog_materials:
		if fm != null:
			fm.density = base_density * dens_factor
			fm.emission = Color(
				base_emission.r * emiss_factor,
				base_emission.g * emiss_factor,
				base_emission.b * emiss_factor,
				base_emission.a
			)

func _create_fog_volume(offset: Vector3) -> void:
	var fog := FogVolume.new()
	fog.name = "PillarFog"
	fog.size = fog_size
	fog.position = offset

	var fm := FogMaterial.new()
	fm.density = fog_density
	fm.albedo = fog_albedo
	fm.emission = fog_emission
	fm.height_falloff = fog_height_falloff

	var noise := NoiseTexture3D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 1.0 / fog_noise_scale
	fn.fractal_octaves = 3
	fn.fractal_lacunarity = 2.0
	fn.seed = randi()
	noise.noise = fn
	noise.width = 96
	noise.height = 96
	noise.depth = 96
	fm.density_texture = noise

	fog.material = fm
	add_child(fog)
	fog_materials.append(fm)

func _add_clear_tube() -> void:
	var clear := FogVolume.new()
	clear.name = "FogClearColumn"
	clear.size = clear_size
	clear.position = clear_offset

	var clear_mat := FogMaterial.new()
	clear_mat.density = 0.0
	clear_mat.albedo = Color(0, 0, 0, 0)
	clear_mat.emission = Color(0, 0, 0, 0)
	clear_mat.height_falloff = 0.0

	clear.material = clear_mat
	add_child(clear)

func _disable_pillar_fog(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var mat := mi.get_active_material(0)
		if mat is BaseMaterial3D:
			(mat as BaseMaterial3D).disable_fog = true
	for child in root.get_children():
		_disable_pillar_fog(child)

func _add_beam_and_lights() -> void:
	var beam := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = beam_radius
	cyl.bottom_radius = beam_radius
	cyl.height = fog_size.y * beam_height_mult
	cyl.radial_segments = 32
	beam.mesh = cyl

	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = beam_emission
	m.emission_energy_multiplier = beam_energy
	m.albedo_color = Color(0.10, 0.22, 0.35, 1.0)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
	m.disable_ambient_light = true
	m.disable_fog = true
	m.metallic = 0.0
	m.roughness = 0.0
	m.albedo_color.a = beam_alpha
	beam.material_override = m

	beam.position = Vector3.ZERO
	add_child(beam)

	for i in range(rung_count):
		var tt: float = float(i) / float(max(rung_count - 1, 1))
		var y: float = lerp(-fog_size.y * 0.45, fog_size.y * 0.65, tt)
		var omni := OmniLight3D.new()
		omni.light_color = beam_emission
		omni.light_energy = rung_energy
		omni.omni_range = max(fog_size.x, fog_size.z) * rung_range_mul
		omni.position = Vector3(0, y, 0)
		add_child(omni)

	var span: float = fog_size.y * ring_height_span
	for i in range(ring_count):
		var tt_ring: float = float(i) / float(max(ring_count - 1, 1))
		var y_ring: float = lerp(-span * 0.5, span * 0.5, tt_ring)

		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.outer_radius = ring_radius
		torus.inner_radius = ring_thickness
		torus.rings = 32
		torus.ring_segments = 16
		ring.mesh = torus

		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.emission_enabled = true
		rm.emission = ring_emission
		rm.emission_energy_multiplier = ring_energy
		rm.albedo_color = Color(0, 0, 0, 0)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		rm.disable_ambient_light = true
		rm.disable_fog = true
		rm.roughness = 0.0
		rm.metallic = 0.0
		ring.material_override = rm
		ring.position = Vector3(0, y_ring, 0)
		add_child(ring)

	var omni_top := OmniLight3D.new()
	omni_top.light_color = beam_emission
	omni_top.light_energy = top_light_energy
	omni_top.omni_range = max(fog_size.x, fog_size.z) * 0.8
	omni_top.position = Vector3(0, fog_size.y * 0.8, 0)
	add_child(omni_top)

	var omni_bottom := OmniLight3D.new()
	omni_bottom.light_color = beam_emission
	omni_bottom.light_energy = bottom_light_energy
	omni_bottom.omni_range = max(fog_size.x, fog_size.z) * 0.8
	omni_bottom.position = Vector3(0, -fog_size.y * 0.7, 0)
	add_child(omni_bottom)

func _add_floor_panel() -> void:
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = floor_radius
	disc.bottom_radius = floor_radius
	disc.height = floor_thickness
	disc.radial_segments = 64
	disc.rings = 1
	floor_mesh.mesh = disc

	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = floor_color
	fm.emission_enabled = true
	fm.emission = floor_emission
	fm.emission_energy_multiplier = floor_emission_energy
	fm.metallic = 0.0
	fm.roughness = 0.9
	fm.disable_fog = true
	floor_mesh.material_override = fm

	floor_mesh.position = Vector3(0, floor_y_offset, 0)
	add_child(floor_mesh)

func _add_backdrop_wall() -> void:
	var wall := MeshInstance3D.new()
	wall.name = "BackdropWall"

	var quad := QuadMesh.new()
	quad.size = backdrop_size
	wall.mesh = quad
	wall.position = backdrop_pos

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.disable_ambient_light = true

	mat.albedo_color = backdrop_color
	mat.albedo_color.a = clampf(backdrop_alpha, 0.0, 1.0)

	mat.emission_enabled = true
	mat.emission = backdrop_emission
	mat.emission_energy_multiplier = maxf(0.0, backdrop_energy)

	wall.material_override = mat
	add_child(wall)
