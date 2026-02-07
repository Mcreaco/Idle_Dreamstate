extends Node3D
class_name DarkVoidFog

# Size of the dark fog walls
@export var fog_size: Vector3 = Vector3(140, 120, 160)

# How dark & thick it is
@export var fog_density: float = 0.018
@export var fog_color: Color = Color(0.02, 0.04, 0.08, 1.0)
@export var fog_emission: Color = Color(0.0, 0.0, 0.0, 0.0)

# Noise
@export var noise_scale: float = 180.0
@export var height_falloff: float = 0.004

# Positions (leave center clear)
@export var offset_left: Vector3  = Vector3(-90, 0, -10)
@export var offset_right: Vector3 = Vector3( 90, 0, -10)
@export var offset_back: Vector3  = Vector3(  0, 0, -110)

func _ready() -> void:
	_create_fog(offset_left)
	_create_fog(offset_right)
	_create_fog(offset_back)

func _create_fog(offset: Vector3) -> void:
	var fog := FogVolume.new()
	fog.size = fog_size
	fog.position = offset

	var mat := FogMaterial.new()
	mat.density = fog_density
	mat.albedo = fog_color
	mat.emission = fog_emission
	mat.height_falloff = height_falloff

	# Soft noise so it isn't flat
	var noise_tex := NoiseTexture3D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 1.0 / noise_scale
	noise.fractal_octaves = 2
	noise.fractal_gain = 0.4
	noise.seed = randi()

	noise_tex.noise = noise
	noise_tex.width = 96
	noise_tex.height = 96
	noise_tex.depth = 96

	mat.density_texture = noise_tex
	fog.material = mat

	add_child(fog)
