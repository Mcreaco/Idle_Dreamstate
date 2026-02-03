extends Node

func _ready() -> void:
	var segs := get_tree().current_scene.find_child("Segments", true, false)
	print("WORLDPROBE Segments node =", segs)

	if segs == null:
		return

	print("WORLDPROBE Segments child count =", segs.get_child_count())

	# Print the first few children + whether they are meshes
	var n: int = min(segs.get_child_count(), 5)
	for i in range(n):
		var c := segs.get_child(i)
		print(" - child", i, " name=", c.name, " type=", c.get_class(), " visible_prop=", c.get("visible"))

	# Force the first child visible (only if it’s a VisualInstance3D / Node3D)
	if segs.get_child_count() > 0:
		var c0 := segs.get_child(0)
		if c0 is Node3D:
			(c0 as Node3D).visible = true
			(c0 as Node3D).global_position = Vector3(0, 0, 0)
			print("WORLDPROBE forced child0 visible at origin")

		# If it has no MeshInstance3D under it, inject a cylinder so we *must* see something
		if _count_meshes(c0) == 0:
			print("WORLDPROBE child0 has 0 meshes -> injecting debug cylinder")
			_inject_cylinder(c0)

func _count_meshes(n: Node) -> int:
	var c := 0
	if n is MeshInstance3D:
		c += 1
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c

func _inject_cylinder(parent: Node) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.5
	cyl.bottom_radius = 1.5
	cyl.height = 5.0
	mi.mesh = cyl

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0, 1, 1) # bright magenta
	mi.set_surface_override_material(0, mat)

	parent.add_child(mi)
