extends Node

func _ready() -> void:
	var vp := get_viewport()
	print("=== VIEWPORT PROBE ===")
	print("current_scene=", get_tree().current_scene)
	print("viewport=", vp, " disable_3d(before)=", vp.disable_3d, " world3d=", vp.world_3d)

	# Force 3D ON and make the clear color obvious
	vp.disable_3d = false
	RenderingServer.set_default_clear_color(Color(1, 0, 1, 1)) # MAGENTA
	print("viewport disable_3d(after)=", vp.disable_3d)

	# List any SubViewports (if you're rendering via a SubViewport chain)
	var subs := get_tree().current_scene.find_children("*", "SubViewport", true, false)
	print("subviewports found=", subs.size())
	for s in subs:
		print(" - ", s.get_path(), " disable_3d=", s.disable_3d, " world3d=", s.world_3d)

	# Spawn a giant unshaded cube at origin (cannot miss if 3D is visible)
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.scale = Vector3(20, 20, 20)
	cube.global_position = Vector3.ZERO
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 1, 1, 1) # CYAN
	cube.set_surface_override_material(0, mat)

	var w := get_tree().current_scene.find_child("World3D", true, false)
	if w != null:
		w.add_child(cube)
		print("cube parented to World3D:", w.get_path())
	else:
		get_tree().current_scene.add_child(cube)
		print("cube parented to current_scene (World3D not found)")
