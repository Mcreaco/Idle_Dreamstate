extends Node3D

@export var pillar_stack_path: NodePath
@export var fog_size: Vector3 = Vector3(14, 18, 14)
@export var fog_offset: Vector3 = Vector3(0, -2.0, 0)
@export var density: float = 0.25
@export var albedo: Color = Color(0.35, 0.45, 0.60, 1.0)
@export var emission: Color = Color(0.08, 0.12, 0.25, 0.4)
@export var noise_scale: float = 18.0
@export var noise_detail: float = 2.5
@export var anisotropy: float = 0.15
@export var height_falloff: float = 0.06
@export var edge_fade: float = 0.35

func _ready() -> void:
	var fog := FogVolumedrift.new()
	fog.name = "PillarFog"
	fog.size = fog_size
	fog.position = fog_offset
	fog.drift_speed = Vector3(0.03, 0.01, 0.02)
	fog.pulse_speed = 0.15
	fog.pulse_amount = 0.05

	var fm := FogMaterial.new()
	fm.density = density              # base density
	fm.albedo = albedo
	fm.emission = emission
	fm.height_falloff = height_falloff

	# Optional 3D noise
	var noise := NoiseTexture3D.new()
	var fn := FastNoiseLite.new()
	fn.frequency = 1.0 / noise_scale
	fn.fractal_octaves = 3
	fn.fractal_lacunarity = 2.0
	fn.seed = randi()
	noise.noise = fn
	noise.width = 64
	noise.height = 64
	noise.depth = 64

	fm.density_texture = noise
	# no density_texture_strength in FogMaterial; omit it
	# if you want stronger noise effect, tweak density: fm.density = density * noise_detail

	fog.material = fm
	add_child(fog)

	var pillar := get_node_or_null(pillar_stack_path)
	if pillar:
		global_position = pillar.global_position
