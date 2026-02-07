extends Node3D
class_name PillarSmokeSpawner

@export var pillar_stack_path: NodePath

@export var particle_count: int = 3200

# --- Vertical reach (keep what you said is perfect) ---
@export var lifetime: float = 22.0
@export var speed: float = 1.0 # GPUParticles3D speed_scale (kept)

# --- Where it starts (CORE) ---
@export var origin_radius: float = 0.55      # <<< small = originates in the middle
@export var origin_thickness: float = 0.35   # spawn slab thickness
@export var vent_y_offset: float = -28.0

# --- Expansion while rising (BLOOM) ---
@export var expand_accel_min: float = 0.22   # <<< outward push (min)
@export var expand_accel_max: float = 0.46   # <<< outward push (max)
@export var swirl_strength: float = 0.55     # keeps a nice roll
@export var drag_min: float = 0.12
@export var drag_max: float = 0.22

# --- Upward motion (KEEP SAME RATE) ---
@export var rise_spread: float = 28.0
@export var upward_vel_min: float = 1.4
@export var upward_vel_max: float = 3.2

# --- Look ---
@export var scale_min: float = 2.4
@export var scale_max: float = 5.6
@export var color: Color = Color(0.04, 0.07, 0.12, 0.80)

func _ready() -> void:
	var p := GPUParticles3D.new()
	p.name = "PillarSmoke"
	p.amount = particle_count
	p.lifetime = lifetime
	p.one_shot = false
	p.preprocess = lifetime * 0.9
	p.speed_scale = speed
	p.local_coords = true
	p.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME

	# IMPORTANT: prevent GPU particle culling as the plume gets tall
	p.visibility_aabb = AABB(Vector3(-250, -250, -250), Vector3(500, 500, 500))

	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	p.draw_passes = 1
	p.draw_pass_1 = quad

	var tex := _make_round_smoke_texture(128)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 1, 1, 1)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	p.material_override = mat

	var pm := ParticleProcessMaterial.new()

	# Spawn from a tiny core (center)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(origin_radius, origin_thickness * 0.5, origin_radius)

	pm.gravity = Vector3(0, 0, 0)

	# Keep your rise rate exactly the same
	pm.direction = Vector3.UP
	pm.spread = rise_spread
	pm.initial_velocity_min = upward_vel_min
	pm.initial_velocity_max = upward_vel_max

	# Expand outward as it rises (this is the key)
	# Positive radial accel = pushes away from the center over time.
	pm.radial_accel_min = expand_accel_min
	pm.radial_accel_max = expand_accel_max

	# Optional swirl so it doesn't look like a perfect cone
	pm.orbit_velocity_min = -swirl_strength
	pm.orbit_velocity_max =  swirl_strength

	pm.damping_min = drag_min
	pm.damping_max = drag_max

	pm.scale_min = scale_min
	pm.scale_max = scale_max
	pm.color = color
	pm.color_ramp = _make_soft_ramp(color)

	p.process_material = pm
	add_child(p)
	p.emitting = true

	var pillar := get_node_or_null(pillar_stack_path)
	if pillar:
		global_position = pillar.global_position

	# Vent position
	p.position = Vector3(0, vent_y_offset, 0)

func _make_soft_ramp(c: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.add_point(0.0, Color(c.r, c.g, c.b, 0.0))
	g.add_point(0.18, Color(c.r, c.g, c.b, c.a * 0.7))
	g.add_point(0.50, c)
	g.add_point(0.82, Color(c.r, c.g, c.b, c.a * 0.7))
	g.add_point(1.0, Color(c.r, c.g, c.b, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	return gt

func _make_round_smoke_texture(size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var half: float = float(size) * 0.5
	for y in range(size):
		for x in range(size):
			var dx: float = (float(x) + 0.5 - half) / half
			var dy: float = (float(y) + 0.5 - half) / half
			var d: float = sqrt(dx * dx + dy * dy)
			var a: float = clampf(1.0 - pow(d, 1.6), 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
