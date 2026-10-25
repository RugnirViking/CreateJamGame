# Run: godot --headless --path . --script tests/menu_music.gd
extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	set_meta("skip_menu_intro", true)
	assert(change_scene_to_file("res://scenes/mainmenu.tscn") == OK)
	await _settle_scene()
	var music := root.get_node("MenuMusic") as AudioStreamPlayer
	assert(music.playing)
	assert(is_equal_approx(music.volume_db, 0.0))
	music.seek(12.0)
	var playback := music.get_stream_playback()
	for cycle in range(3):
		current_scene.get_node("MenuButtons/Play").pressed.emit()
		await _settle_scene()
		assert(current_scene.scene_file_path == "res://scenes/tank_select.tscn")
		_assert_continuous(music, playback)
		current_scene._back()
		await _settle_scene()
		assert(current_scene.scene_file_path == "res://scenes/mainmenu.tscn")
		_assert_continuous(music, playback)
	print("PASS music keeps the same playback and volume across repeated menu transitions")
	current_scene.get_node("MenuButtons/Play").pressed.emit()
	await _settle_scene()
	current_scene._deploy()
	await _settle_scene()
	assert(current_scene.scene_file_path == "res://scenes/main.tscn")
	assert(not music.playing, "Menu music must stop when deploying")
	print("PASS menu music stops on deployment")
	quit()


func _settle_scene() -> void:
	for frame in range(3):
		await process_frame


func _assert_continuous(music: AudioStreamPlayer, playback: AudioStreamPlayback) -> void:
	assert(music.playing)
	assert(music.get_stream_playback() == playback, "Scene changes must keep the existing playback")
	assert(music.get_playback_position() >= 12.0, "Scene changes must not reset the song")
	assert(is_equal_approx(music.volume_db, 0.0), "Both screens must use main menu volume")
