extends Node

func _ready() -> void:
	var cam := get_tree().current_scene.find_child("Camera3D", true, false) as Camera3D
	var seg := get_tree().current_scene.find_child("Segmen01", true, false) as MeshInstance3D
	print("HARD cam=", cam, " seg=", seg)

	if cam == null or seg == null:
		return

	# Force the camera to render everything
	cam.current = true
	cam.cull_mask = 0xFFFFFFFF
	cam.near = 0.05
	cam.far = 50000.0

	# Put the segment 5m in front of the camera and make it sane
	seg.visible = true
	seg.scale = Vector3.ONE
	seg.global_position = cam.global_position + (-cam.global_transform.basis.z * 5.0)

	# Aim camera at it
	cam.look_at(seg.global_position, Vector3.UP)

	print("HARD placed seg at ", seg.global_position, " cam pos=", cam.global_position)
