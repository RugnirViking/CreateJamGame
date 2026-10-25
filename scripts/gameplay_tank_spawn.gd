extends Node3D


func _enter_tree() -> void:
	var path: String = get_tree().get_meta("selected_player_scene", "")
	if not TankCatalog.has_scene(path):
		return
	var previous := get_node("playertank") as Node3D
	var spawn_pose := previous.transform
	var spawn_index := previous.get_index()
	var target: Node3D = previous.get("chevron_target")
	remove_child(previous)
	previous.free()
	var selected := (load(path) as PackedScene).instantiate() as Node3D
	selected.name = "playertank"
	selected.transform = spawn_pose
	selected.set("chevron_target", target)
	# Replace before the level's enemies enter the tree and resolve their target.
	add_child(selected)
	move_child(selected, spawn_index)
