# Run: godot --headless --path . --script tests/tank_selection.gd --fixed-fps 60
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1280, 720)
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
		screen._select(index)
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
		assert(screen.get_node("Interface/Tank%d/Select" % index).button_pressed)
		assert(screen.get_node("Interface/Tank%d/Preview" % index).size == Vector2(224, 224))
		source.free()
	screen._select(0)
	screen._navigate(-1)
	assert(screen.selected_index == 4, "Left navigation must wrap")
	screen._navigate(1)
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
	var tile := screen.get_node("Interface/Tank3/Select") as Button
	var motion := InputEventMouseMotion.new()
	motion.position = tile.get_global_rect().get_center()
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await process_frame
	var click := InputEventMouseButton.new()
	click.position = tile.get_global_rect().get_center()
	click.global_position = click.position
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	Input.parse_input_event(click)
	await process_frame
	click = click.duplicate()
	click.pressed = false
	Input.parse_input_event(click)
	await process_frame
	assert(screen.selected_index == 3, "Clicking a tank square must select it")
	screen.set_process(false)
	screen._select(3)
	screen._process(0.0)
	assert(screen._previews[3].scale.is_equal_approx(Vector3.ONE * 1.5))
	screen._process(0.25)
	assert(screen._previews[3].scale.is_equal_approx(Vector3.ONE * 2.25))
	screen._process(0.25)
	assert(screen._previews[3].scale.is_equal_approx(Vector3.ONE * 3.0))
	screen._process(0.5)
	assert(screen._previews[3].scale.is_equal_approx(Vector3.ONE * 1.5))
	for i in range(5):
		assert(screen._previews[i].rotation.y > 0.0, "All five previews must turn")
		if i != 3:
			assert(screen._previews[i].scale.is_equal_approx(Vector3.ONE * 1.5))
	print("PASS clickable square previews, scene-derived stats, and exact 1-second 1.5x–3x pulse")
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
	assert(current_scene.scene_file_path == "res://scenes/level_select.tscn")
	current_scene.get_node("Interface/Deploy").pressed.emit()
	for frame in range(3):
		await process_frame
	assert(current_scene.scene_file_path == "res://scenes/levels/northwest.tscn")
	# The original full map remains available, including its enemies and boss.
	assert(change_scene_to_file("res://scenes/main.tscn") == OK)
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

