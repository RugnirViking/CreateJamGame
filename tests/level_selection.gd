# Run: godot --headless --path . --script tests/level_selection.gd --fixed-fps 60
extends SceneTree

const Levels = preload("res://scripts/level_catalog.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	# Keep test victories separate from the player's saved progress.
	Levels.progress_path = "res://builds/test_mission_progress_%d.cfg" % OS.get_process_id()
	root.size = Vector2i(1280, 720)
	set_meta("selected_tank_index", 2)
	assert(change_scene_to_file("res://scenes/tank_select.tscn") == OK)
	await _frames()
	current_scene.get_node("Interface/Deploy").pressed.emit()
	await _frames()
	assert(current_scene.scene_file_path == "res://scenes/level_select.tscn")
	var screen := current_scene
	assert(screen._previews.size() == 4)
	assert(get_nodes_in_group("player").is_empty())
	assert(screen.get_node("Interface/SelectedTank/Preview/Viewport/World/Model").get_child_count() == 1)
	screen._navigate(-1)
	assert(screen.selected_index == 3)
	screen._navigate(1)
	assert(screen.selected_index == 0)
	for i in range(4):
		screen.get_node("Interface/Tank%d/Select" % i).pressed.emit()
		assert(screen.selected_index == i)
		assert(screen.get_node("Interface/TankName").text == Levels.LEVELS[i].name)
		assert(screen.get_node("Interface/Stats/Description").text == Levels.LEVELS[i].description)
		assert(screen.get_node("Interface/Tank%d/Select" % i).button_pressed)
	screen._back()
	await _frames()
	assert(current_scene.scene_file_path == "res://scenes/tank_select.tscn")
	assert(current_scene.selected_index == 2)
	current_scene._deploy()
	await _frames()
	assert(current_scene.selected_index == 3)
	if "--screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/level_select.png")
	print("PASS tank → level selection, four choices, descriptions, tank preview, wraparound and back navigation")
	var full := preload("res://art/textures/heightmap.jpg").get_image()
	if full.is_compressed():
		full.decompress()
	for i in range(4):
		var image := Levels.quarter_image(i)
		var half := Vector2i((full.get_width() - 1) / 2, (full.get_height() - 1) / 2)
		var origin := Vector2i(i % 2, i / 2) * half
		assert(image.get_size() == half + Vector2i.ONE)
		for point in [Vector2i.ZERO, half / 2, half]:
			assert(image.get_pixelv(point) == full.get_pixelv(origin + point))
		current_scene._select(i)
		current_scene._deploy()
		await _frames()
		assert(current_scene.scene_file_path == Levels.LEVELS[i].path)
		assert(current_scene.get_node("playertank").scene_file_path == TankCatalog.TANKS[2].path)
		var shape := current_scene.get_node("heightmapCollision").shape as HeightMapShape3D
		assert(shape.map_width == half.x + 1 and shape.map_depth == half.y + 1)
		assert(is_equal_approx(shape.map_data[0], image.get_pixel(0, 0).r * 20.0))
		assert(current_scene.get_node("heightmap").mesh.get_aabb().size.x == half.x)
		assert(current_scene.get_node("heightmap").mesh.get_aabb().size.z == half.y)
		assert(get_nodes_in_group("terrain_target_markers").is_empty())
		assert(not current_scene.has_node("Town1") and not current_scene.has_node("enemytank"))
		var player := current_scene.get_node("playertank/vehicle") as Node3D
		for frame in range(60):
			await physics_frame
		assert(player.global_position.y > Levels.height_at(image, Vector2.ZERO) - 1.0, "Player must land on terrain")
		for patch_name in ["SolidScatter", "CrushableScatter"]:
			var patch := current_scene.get_node(patch_name)
			assert(patch.generated_count > 0, "Both scatter types must generate on every quarter")
			assert(patch.ground_body_path == NodePath(".."))
		assert(current_scene.get_node("CrushableScatter").source_scenes.size() == 3)
		assert(current_scene.get_node("CrushableScatter").instance_count == 5000)
		assert(not player.you_win.visible)
		assert(not Levels.is_completed(Levels.LEVELS[i].path))
		# The shortcut must still work once ordinary gameplay input has begun.
		player._zeroing_started = true
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F10
		key.pressed = true
		Input.parse_input_event(key)
		await process_frame
		assert(not player.you_win.visible, "F10 alone must not win")
		key = key.duplicate()
		key.ctrl_pressed = true
		key.shift_pressed = true
		Input.parse_input_event(key)
		await process_frame
		assert(player.you_win.visible, "Ctrl+Shift+F10 must trigger victory")
		assert(player.win_fanfare.playing)
		assert(player.you_win.has_node("DancingCactuses"))
		assert(Levels.is_completed(Levels.LEVELS[i].path), "Completion must save at victory before leaving the win screen")
		key = InputEventKey.new()
		key.keycode = KEY_ENTER
		key.physical_keycode = KEY_ENTER
		key.pressed = true
		Input.parse_input_event(key)
		await _frames()
		assert(current_scene.scene_file_path == "res://scenes/level_select.tscn")
		assert(current_scene.selected_index == i)
		assert(int(get_meta("selected_tank_index")) == 2)
		for tile in range(4):
			var stamp := current_scene.get_node("Interface/Tank%d/CompletedStamp" % tile) as TextureRect
			assert(stamp.visible == (tile <= i), "Only completed missions get a stamp; prior victories must persist")
			assert(stamp.texture.resource_path == "res://art/textures/checkmark.png")
			assert(stamp.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	print("PASS four distinct source quarters, terrain collision, chosen tank, both scatter types and hidden victory shortcut")
	print("PASS completion saved at victory, Enter returns to mission select, correct checkmark stamps and remembered tank/mission")
	if "--screenshot" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://builds/mission_completed.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Levels.progress_path))
	quit()


func _frames() -> void:
	for frame in range(4):
		await process_frame
