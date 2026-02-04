extends Node3D

func _ready() -> void:
	print("SEGMENTS WATCH _ready. path=", get_path(), " visible=", visible, " children=", get_child_count())

func _process(_d: float) -> void:
	# If anything turns Segments off, you'll see it instantly
	if not visible:
		print("SEGMENTS WATCH: Segments became invisible!")
		visible = true

	# If children get hidden, force Segment01 back on
	var s1 := get_node_or_null("Segment01")
	if s1 and s1 is Node3D and not (s1 as Node3D).visible:
		print("SEGMENTS WATCH: Segment01 was hidden -> forcing visible")
		(s1 as Node3D).visible = true
