extends Camera3D

func _ready() -> void:
	current = true
	cull_mask = 0xFFFFFFFF
	near = 0.05
	far = 50000.0

	global_position = Vector3(0, 2, 10)
	look_at(Vector3(0, 0, 0), Vector3.UP)

	print("CAM DEBUG current=", current, " pos=", global_position, " basis=", global_basis)
	print("CAM DEBUG cull_mask=", cull_mask)
