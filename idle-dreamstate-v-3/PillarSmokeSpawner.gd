extends Node3D

@export var pillar_stack_path: NodePath
@export var particle_count: int = 2800
@export var radius_top: float = 16.0
@export var radius_mid: float = 28.0
@export var radius_bottom: float = 20.0
@export var height: float = 36.0   # taller vertical spread
@export var lifetime: float = 18.0
@export var speed: float = 0.12
@export var scale_min: float = 2.6
@export var scale_max: float = 5.2
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

	var m := QuadMesh.new()
	m.size = Vector2(1, 1)
	p.draw_passes = 1
	p.draw_pass_1 = m

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
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(radius_mid, height * 0.5, radius_mid) # vertical spread ±height/2
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.18
	pm.angular_velocity_min = -0.12
	pm.angular_velocity_max = 0.12
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	pm.scale_curve = null
	pm.color = color
	pm.color_ramp = _make_soft_ramp(color)

	p.process_material = pm
	add_child(p)
	p.emitting = true

	var pillar := get_node_or_null(pillar_stack_path)
	if pillar:
		global_position = pillar.global_position + Vector3(0, -height * 0.25, 0)

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
	var half := size * 0.5
	for y in size:
		for x in size:
			var dx := (x + 0.5 - half) / half
			var dy := (y + 0.5 - half) / half
			var d := sqrt(dx * dx + dy * dy)
			var a: float = clamp(1.0 - pow(d, 1.6), 0.0, 1.0)
			a = a * a
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
