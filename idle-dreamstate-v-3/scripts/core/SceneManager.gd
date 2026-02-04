extends Node

func goto_path(path: String) -> void:
	var err: int = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("Scene change failed: " + path + " (err=" + str(err) + ")")
