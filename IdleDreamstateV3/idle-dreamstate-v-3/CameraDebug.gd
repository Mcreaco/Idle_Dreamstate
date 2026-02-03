extends Camera3D

func _ready() -> void:
	current = true
	cull_mask = 0xFFFFFFFF
	print("FORCE CAMERA current=", current, " cam=", self, " pos=", global_position)
