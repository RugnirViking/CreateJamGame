# Run: godot --headless --path . --script tests/tank_selection.gd --fixed-fps 60
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta("skip_menu_intro", true)
	assert(change_scene_to_file("res://scenes/mainmenu.tscn") == OK)
	for frame in range(3):
		await process_frame
	current_scene.get_node("MenuButtons/Play").pressed.emit()
	for frame in range(3):
		await process_frame
	assert(current_scene.scene_file_path == "res://scenes/tank_select.tscn")
	var screen = current_scene
	assert(screen._previews.size() == 5)
	assert(get_nodes_in_group("player").is_empty(), "Previews must not run player physics")
	for index in TankCatalog.TANKS.size():
		var source := (load(TankCatalog.TANKS[index].path) as PackedScene).instantiate()
		var vehicle := source.get_node("vehicle") as playertank_tracks
		var aim := source.get_node("followcam")
		screen._select(index, false)
		var data: Dictionary = screen._stats[index]
		assert(data.forward_speed == vehicle.max_forward_speed)
		assert(data.reverse_speed == vehicle.max_reverse_speed)
		assert(data.engine_power == vehicle.engine_force_value)
		assert(data.turret_traverse == aim.turret_traverse_speed)
		assert(data.gun_elevation == aim.gun_elevation_speed)
		assert(data.min_elevation == aim.min_gun_elevation)
		assert(data.max_elevation == aim.max_gun_elevation)
		assert(data.max_hp == vehicle.hits_to_destroy)
		assert(data.reload_time == vehicle.reload_duration)
		assert(screen.tank_name.text == TankCatalog.TANKS[index].name)
		assert(screen.get_node("Interface/Stats/HP/Value").text == "%d HP" % vehicle.hits_to_destroy)
		assert(screen._previews[index].position.is_equal_approx(Vector3(0, 0.37, 0)))
		source.free()
	screen._select(0, false)
	screen.get_node("Interface/Previous").pressed.emit()
	assert(screen.selected_index == 4, "Left navigation must wrap")
	screen.get_node("Interface/Next").pressed.emit()
	assert(screen.selected_index == 0, "Right navigation must wrap")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_D
	Input.parse_input_event(key)
	await process_frame
	assert(screen.selected_index == 1, "D must navigate right")
	key = InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_A
	Input.parse_input_event(key)
	await process_frame
	assert(screen.selected_index == 0, "A must navigate left")
	screen.dots.get_child(3).pressed.emit()
	assert(screen.selected_index == 3, "Number buttons must select directly")
	for frame in range(30):
		await process_frame
	assert(screen._previews[3].position.is_equal_approx(Vector3(0, 0.37, 0)))
	print("PASS carousel navigation, wraparound, scene-derived stats, and animated focus")
	key = InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(key)
	for frame in range(3):
		await process_frame
	assert(current_scene.scene_file_path == "res://scenes/mainmenu.tscn")
	current_scene.get_node("MenuButtons/Play").pressed.emit()
	for frame in range(3):
		await process_frame
	screen = current_scene
	assert(screen.selected_index == 3, "Returning to selection must remember the last tank")
	screen.get_node("Interface/Deploy").pressed.emit()
	for frame in range(3):
		await process_frame
	_assert_deployed(3)
	for index in [0, 1, 2, 4]:
		set_meta("selected_player_scene", TankCatalog.TANKS[index].path)
		assert(change_scene_to_file("res://scenes/main.tscn") == OK)
		for frame in range(3):
			await process_frame
		_assert_deployed(index)
	print("PASS deployment of all five tanks; enemies and boss target the selected vehicle")
	quit()


func _assert_deployed(index: int) -> void:
	var player := current_scene.get_node("playertank")
	assert(player.scene_file_path == TankCatalog.TANKS[index].path)
	var vehicle := player.get_node("vehicle")
	assert(current_scene.get_node("enemytank").playertank == vehicle)
	assert(current_scene.get_node("enemytank8").playertank == vehicle)
	assert(current_scene.get_node("enemytank8").has_node("tank3"))
	assert(vehicle.wheels.size() == [4, 4, 6, 8, 4][index])

