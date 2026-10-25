# Run: godot --headless --path . --script tests/gameplay_input.gd --fixed-fps 60
extends SceneTree

const MODELS := ["tank1", "tog2", "sdkfz", "greydog", "cattank"]
var _failed := false


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1152, 648)
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var music := AudioStreamPlayer.new()
	music.name = "BGMusic"
	stage.add_child(music)
	var terrain := MeshInstance3D.new()
	terrain.name = "heightmap"
	stage.add_child(terrain)
	for model in MODELS:
		var player := (load("res://scenes/tanks/player/player_%s.tscn" % model) as PackedScene).instantiate()
		stage.add_child(player)
		player.get_node("GroundTracks").set_physics_process(false)
		var tank := player.get_node("vehicle") as playertank_tracks
		tank.set_physics_process(false)
		for frame in range(3):
			await process_frame
		_key(KEY_SPACE)
		_check(tank._reload_remaining > 0.0, "%s: Space must fire during gameplay" % model)
		_check(current_scene == stage, "%s: Space must stay in gameplay" % model)
		# Include the fullscreen vignette and the reload meter, which previously
		# swallowed clicks before they reached _unhandled_input.
		tank.vignetteShader.show()
		for path in ["VignetteShader", "SniperHUD/Shell", "HBoxContainer", "ColorRect", "HealthBar"]:
			var control := player.get_node("AimHUD/" + path) as Control
			tank._reload_remaining = 0.0
			_click(control.get_global_rect().get_center())
			_check(tank._reload_remaining > 0.0, "%s: click over %s must fire" % [model, path])
		# A later-added UI overlay must not take priority over the fire action.
		var blocker := ColorRect.new()
		blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		player.get_node("AimHUD").add_child(blocker)
		tank._reload_remaining = 0.0
		_click(root.get_visible_rect().size * 0.5)
		_check(tank._reload_remaining > 0.0, "%s: shooting must work even when a UI overlay consumes clicks" % model)
		blocker.free()
		tank.you_win.show()
		await process_frame
		tank._reload_remaining = 0.0
		_key(KEY_SPACE)
		_click(root.get_visible_rect().size * 0.5)
		_check(current_scene == stage, "%s: Space/click must not leave the win screen" % model)
		_check(is_zero_approx(tank._reload_remaining), "%s: victory must prevent firing" % model)
		if model == MODELS.back():
			_key(KEY_ENTER)
			for frame in range(4):
				await process_frame
			_check(current_scene.scene_file_path == "res://scenes/level_select.tscn", "Enter must return to mission selection")
		else:
			player.queue_free()
			await process_frame
	# Exercise the real menu-to-mission route as well as isolated tank scenes.
	current_scene._deploy()
	for frame in range(8):
		await process_frame
	var mission := current_scene
	var deployed := mission.get_node("playertank/vehicle") as playertank_tracks
	for frame in range(90):
		await physics_frame
	_key(KEY_SPACE)
	_check(deployed._reload_remaining > 0.0, "Deployed mission: Space must spawn a shell")
	for frame in range(100):
		await physics_frame
	_check(is_zero_approx(deployed._reload_remaining), "Deployed mission: reloading must finish")
	_click(root.get_visible_rect().size * 0.5)
	_check(deployed._reload_remaining > 0.0, "Deployed mission: mouse must fire after reloading")
	deployed._reload_remaining = 0.0
	mission.get_node("playertank/followcam")._set_sniper_mode(true)
	_click(root.get_visible_rect().size * 0.5)
	_check(deployed._reload_remaining > 0.0, "Deployed mission: captured mouse must fire in sniper mode")
	_check(current_scene == mission, "Shooting must not change missions")
	if not _failed:
		print("PASS all five tanks: Space/click fire through HUD, victory ignores shooting, Enter opens mission selection")
		print("PASS real mission deployment: Space, reload, left-click, and captured sniper mouse")
	quit(1 if _failed else 0)


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failed = true
		push_error(message)
