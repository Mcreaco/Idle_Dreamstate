extends Node3D

@export var min_scale: float = 0.9
@export var max_scale: float = 1.3

@export var calm_color: Color = Color(0.2, 0.4, 1.0)
@export var danger_color: Color = Color(1.0, 0.2, 0.2)
@export var nightmare_color: Color = Color(0.6, 0.0, 0.8)

@export var rotate_speed: float = 0.4
@export var bob_amount: float = 0.15
@export var bob_speed: float = 1.2

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $OmniLight3D
@onready var mat: StandardMaterial3D = mesh.get_active_material(0)

var pulse_time: float = 0.0
var bob_time: float = 0.0

func update_visual(instability: float, corruption_active: bool, nightmare_unlocked: bool) -> void:
	# rotation drift
	rotate_y(rotate_speed * 0.01)

	# bobbing motion
	bob_time += bob_speed * 0.01
	position.y = sin(bob_time) * bob_amount

	# pulse scale from instability
	var speed: float = lerp(0.5, 3.0, instability / 100.0)
	pulse_time += speed * 0.05
	var pulse: float = (sin(pulse_time) + 1.0) * 0.5
	var s: float = lerp(min_scale, max_scale, pulse)
	scale = Vector3.ONE * s

	# color blend
	var c: Color = calm_color.lerp(danger_color, instability / 100.0)

	if corruption_active:
		c = c.lerp(Color.GREEN, 0.5)

	if nightmare_unlocked:
		c = c.lerp(nightmare_color, 0.5)

	mat.albedo_color = c
	mat.emission_enabled = true
	mat.emission = c
	mat.emission_energy = lerp(0.2, 1.5, instability / 100.0)

	light.light_color = c
	light.light_energy = lerp(1.5, 4.0, instability / 100.0)
