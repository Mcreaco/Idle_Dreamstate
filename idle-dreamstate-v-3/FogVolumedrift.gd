extends FogVolume
class_name FogVolumedrift

# ---------------------------------------------------------
# DRIFT / PULSE (kept)
# ---------------------------------------------------------
@export var drift_speed: Vector3 = Vector3(0.05, 0.02, 0.03) # units/sec in noise-space
@export var pulse_speed: float = 0.35                        # 0 = no pulse
@export var pulse_amount: float = 0.05                       # 0 = no pulse

# ---------------------------------------------------------
# DEPTH / LAYERING (makes background feel less plain)
# ---------------------------------------------------------
@export var base_density_override: float = -1.0  # -1 = read from FogMaterial on ready
@export var min_density: float = 0.10
@export var max_density: float = 0.55

# Density increases gently as you go deeper (abs(y))
@export var depth_density_per_y: float = 0.0015
@export var depth_density_cap_add: float = 0.18

# Make fog slightly thicker near the center (pillar), thinner at edges
@export var center_boost_strength: float = 0.18
@export var center_falloff_radius: float = 22.0
@export var center_reference_path: NodePath = NodePath("../PillarRig/Segments") # fallback: find "Segments"

@export var extra_softening: float = 0.0 # 0..0.25

var _t: float = 0.0
var _base_density: float = 0.35
var _center_ref: Node3D = null

func _ready() -> void:
	# Cache base density from FogMaterial
	if material is FogMaterial:
		var fm := material as FogMaterial
		if base_density_override >= 0.0:
			_base_density = base_density_override
			fm.density = _base_density
		else:
			_base_density = float(fm.density)

	# Try to bind a center reference (pillar/segments) to shape fog around it
	_center_ref = get_node_or_null(center_reference_path) as Node3D
	if _center_ref == null:
		_center_ref = get_tree().current_scene.find_child("Segments", true, false) as Node3D

func _process(delta: float) -> void:
	_t += delta

	# 1) Drift the 3D noise via Density Texture -> NoiseTexture3D -> FastNoiseLite offset
	var noise := _get_fast_noise()
	if noise != null:
		noise.offset += drift_speed * delta

	# 2) Compute layered target density (base + depth + center boost + pulse)
	if material is FogMaterial:
		var fm := material as FogMaterial

		# IMPORTANT: absf keeps this typed as float (no Variant warnings)
		var depth_y: float = absf(global_position.y)
		var depth_add: float = minf(depth_y * depth_density_per_y, depth_density_cap_add)

		var center_mul: float = 1.0
		if _center_ref != null and center_boost_strength > 0.0:
			var dx: float = global_position.x - _center_ref.global_position.x
			var dz: float = global_position.z - _center_ref.global_position.z
			var dxz: float = sqrt(dx * dx + dz * dz)

			var near01: float = clampf(1.0 - (dxz / maxf(0.001, center_falloff_radius)), 0.0, 1.0)
			center_mul = 1.0 + (near01 * center_boost_strength)

		var pulse: float = 0.0
		if pulse_speed > 0.0 and pulse_amount > 0.0:
			pulse = sin(_t * TAU * pulse_speed) * pulse_amount

		var target: float = (_base_density + depth_add + pulse) * center_mul
		target *= (1.0 - clampf(extra_softening, 0.0, 0.25))

		fm.density = clampf(target, min_density, max_density)

func _get_fast_noise() -> FastNoiseLite:
	if !(material is FogMaterial):
		return null
	var fm := material as FogMaterial
	var tex := fm.density_texture
	if tex == null:
		return null
	if tex is NoiseTexture3D:
		var n := (tex as NoiseTexture3D).noise
		if n is FastNoiseLite:
			return n as FastNoiseLite
	return null
