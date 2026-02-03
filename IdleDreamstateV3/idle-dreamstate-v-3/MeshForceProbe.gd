extends Node

func _ready() -> void:
	var cam := get_tree().current_scene.find_child("Camera3D", true, false) as Camera3D
	var seg := get_tree().current_scene.find_child("Segmen01", true, false) as MeshInstance3D
	print("=== MESH FORCE PROBE ===")
	print("cam=", cam, " seg=", seg)
	var s1 := get_tree().current_scene.find_child("Segment01", true, false) as Node3D
	var s2 := get_tree().current_scene.find_child("Segment02", true, false) as Node3D
	print("S1 pos=", s1.global_position, " vis=", s1.visible)
	print("S2 pos=", s2.global_position, " vis=", s2.visible)


	if cam == null or seg == null:
		return

	print("before: seg.mesh=", seg.mesh)

	# Force a guaranteed-visible mesh + material
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 1.5
	cyl.height = 5.0
	seg.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0, 1, 1) # magenta
	seg.set_surface_override_material(0, mat)

	# Put it 5m in front of the camera and aim at it
	seg.visible = true
	seg.scale = Vector3.ONE
	seg.global_position = cam.global_position + (-cam.global_transform.basis.z * 5.0)
	cam.current = true
	cam.look_at(seg.global_position, Vector3.UP)

	print("after: seg.mesh=", seg.mesh, " seg.pos=", seg.global_position)
