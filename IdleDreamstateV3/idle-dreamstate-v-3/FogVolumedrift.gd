extends FogVolume

@export var drift_speed: Vector3 = Vector3(0.05, 0.02, 0.03) # units/sec in noise-space
@export var pulse_speed: float = 0.35                        # 0 = no pulse
@export var pulse_amount: float = 0.05                       # 0 = no pulse

var _t: float = 0.0
var _base_density: float = 0.35

func _ready() -> void:
	# Cache base density from FogMaterial
	if material is FogMaterial:
		_base_density = (material as FogMaterial).density

func _process(delta: float) -> void:
	_t += delta

	# 1) Optional "breathing" density pulse
	if material is FogMaterial:
		var fm := material as FogMaterial
		if pulse_speed > 0.0 and pulse_amount > 0.0:
			fm.density = _base_density + sin(_t * TAU * pulse_speed) * pulse_amount
		else:
			fm.density = _base_density

	# 2) Drift the 3D noise via Density Texture -> NoiseTexture3D -> FastNoiseLite offset
	var noise := _get_fast_noise()
	if noise != null:
		noise.offset += drift_speed * delta

func _get_fast_noise() -> FastNoiseLite:
	# FogMaterial exposes "density_texture" (shown in your inspector as "Density Text")
	if !(material is FogMaterial):
		return null

	var fm := material as FogMaterial
	var tex := fm.density_texture
	if tex == null:
		return null

	# In Godot 4.x this is NoiseTexture3D with a "noise" resource (FastNoiseLite)
	if tex is NoiseTexture3D:
		var n := (tex as NoiseTexture3D).noise
		if n is FastNoiseLite:
			return n as FastNoiseLite

	return null
