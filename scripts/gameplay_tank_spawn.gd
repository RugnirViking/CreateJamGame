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


func _ready() -> void:
	var player := get_node("playertank") as Node3D
	if is_instance_valid(player.get("chevron_target")):
		return
	# All level children have entered the tree now, including copied-in targets.
	for node in get_tree().get_nodes_in_group(&"terrain_target_markers"):
		var marker := node as terrain_target_marker
		if is_ancestor_of(marker) and marker.state == terrain_target_marker.State.ACTIVE and marker.is_visible_in_tree():
			player.set("chevron_target", marker)
			return
