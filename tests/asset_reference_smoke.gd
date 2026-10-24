extends SceneTree

# godot --headless --path . --script tests/asset_reference_smoke.gd
var failed := false
var checked := 0


func _initialize() -> void:
	check_folder("res://scenes")
	check_folder("res://scripts")
	check_folder("res://art")
	check_folder("res://sound")
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	if main_scene != "res://scenes/main.tscn" or not ResourceLoader.exists(main_scene):
		failed = true
		push_error("Main scene must resolve to its organized path")
	print("ASSET REFERENCES checked=", checked, " failed=", failed)
	quit(1 if failed else 0)


func check_folder(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		failed = true
		push_error("Missing asset folder: " + path)
		return
	for file in directory.get_files():
		if file.get_extension() not in ["gd", "tscn", "gdshader", "png", "jpg", "svg", "wav", "mp3", "glb"]:
			continue
		var resource_path := path.path_join(file)
		var resource := ResourceLoader.load(resource_path)
		if resource == null or (resource is Script and not resource.can_instantiate()):
			failed = true
			push_error("Cannot load moved asset: " + resource_path)
		checked += 1
	for child in directory.get_directories():
		check_folder(path.path_join(child))
