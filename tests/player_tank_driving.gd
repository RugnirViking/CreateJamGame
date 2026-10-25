# Run: godot --headless --path . --script tests/player_tank_driving.gd --fixed-fps 60
# Add -- --tick-rate=120 to also verify a different physics timestep.
extends SceneTree

const MODELS := ["tank1", "tog2", "sdkfz", "greydog", "cattank"]
var _tanks: Array[playertank_tracks] = []
var _failed := false
var _tick_rate := 60

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--tick-rate="):
			_tick_rate = int(argument.get_slice("=", 1))
	Engine.physics_ticks_per_second = _tick_rate
	call_deferred("_run")

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var music := AudioStreamPlayer.new()
	music.name = "BGMusic"
	stage.add_child(music)
	var terrain := MeshInstance3D.new()
	terrain.name = "heightmap"
	stage.add_child(terrain)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10000, 1, 10000)
	collision.shape = box
	collision.position.y = -0.5
	floor_body.add_child(collision)
	stage.add_child(floor_body)
	for i in MODELS.size():
		var scene := load("res://scenes/tanks/player/player_%s.tscn" % MODELS[i]) as PackedScene
		var player := scene.instantiate()
		var tank := player.get_node("vehicle") as playertank_tracks
		tank.position = Vector3(i * 30, 0.8, 0)
		stage.add_child(player)
		player.get_node("GroundTracks").set_physics_process(false)
		_tanks.append(tank)
	await _simulate(2.0)
	for i in _tanks.size():
		for wheel in _tanks[i].wheels:
			_check(wheel.basis.z.dot(Vector3.RIGHT) > 0.99, "%s: reversed rolling axis" % MODELS[i])
	await _drive("forward", "accelerate", "", 7.0, 4.8, 1.5)
	for i in _tanks.size():
		_check(_forward_speed(_tanks[i]) > 4.2, "%s: forward direction or acceleration" % MODELS[i])
	await _drive("stop", "", "", 5.0, 4.8, 1.5)
	for i in _tanks.size():
		_check(_tanks[i].linear_velocity.length() < 0.2, "%s: failed to stop" % MODELS[i])
	await _drive("pivot", "", "turn_left", 6.0, 0.4, 1.5)
	for i in _tanks.size():
		_check(_tanks[i].angular_velocity.dot(_tanks[i].global_basis.y) > 0.3, "%s: pivot direction" % MODELS[i])
	await _drive("reverse", "reverse", "", 7.0, 4.8, 1.5)
	for i in _tanks.size():
		_check(_forward_speed(_tanks[i]) < -4.2, "%s: reverse direction or acceleration" % MODELS[i])
	await _drive("drive and turn", "accelerate", "turn_right", 7.0, 4.8, 1.5)
	await _drive("stop before custom limits", "", "", 5.0, 4.8, 1.5)
	for tank in _tanks:
		tank.max_forward_speed = 2.0
		tank.max_reverse_speed = 1.0
		tank.max_turn_speed = 0.6
	await _drive("custom forward limit", "accelerate", "", 7.0, 2.0, 0.6)
	for i in _tanks.size():
		_check(_forward_speed(_tanks[i]) > 1.7, "%s: custom forward setting" % MODELS[i])
	await _drive("custom reverse limit", "reverse", "", 7.0, 2.0, 0.6)
	for i in _tanks.size():
		_check(_forward_speed(_tanks[i]) < -0.8 and _forward_speed(_tanks[i]) > -1.15, "%s: custom reverse setting" % MODELS[i])
	await _drive("custom pivot limit", "", "turn_left", 7.0, 1.0, 0.6)
	_release_inputs()
	stage.queue_free()
	await process_frame
	if not _failed:
		print("PASS: all five player tanks, driving/reverse/braking/pivot/combined inputs/custom limits at %s Hz" % _tick_rate)
	quit(1 if _failed else 0)

func _drive(label: String, drive_action: String, turn_action: String, seconds: float, speed_limit: float, yaw_limit: float) -> void:
	_release_inputs()
	if not drive_action.is_empty():
		Input.action_press(drive_action)
	if not turn_action.is_empty():
		Input.action_press(turn_action)
	var peak_speed := 0.0
	var peak_yaw := 0.0
	for frame in range(roundi(seconds * _tick_rate)):
		await physics_frame
		for i in _tanks.size():
			var tank := _tanks[i]
			var speed := Vector2(tank.linear_velocity.x, tank.linear_velocity.z).length()
			var yaw := absf(tank.angular_velocity.dot(tank.global_basis.y))
			peak_speed = maxf(peak_speed, speed)
			peak_yaw = maxf(peak_yaw, yaw)
			_check(speed < speed_limit + 0.25, "%s %s: speed %s exceeds %s" % [MODELS[i], label, speed, speed_limit])
			_check(yaw < yaw_limit + 0.25, "%s %s: yaw %s exceeds %s" % [MODELS[i], label, yaw, yaw_limit])
			_check(tank.global_basis.y.dot(Vector3.UP) > 0.9, "%s %s: unstable body" % [MODELS[i], label])
	print("%s: peak speed=%.3f m/s, peak yaw=%.3f rad/s" % [label, peak_speed, peak_yaw])

func _simulate(seconds: float) -> void:
	for frame in range(roundi(seconds * _tick_rate)):
		await physics_frame

func _forward_speed(tank: playertank_tracks) -> float:
	return tank.linear_velocity.dot(-tank.global_basis.x)

func _release_inputs() -> void:
	for action in ["accelerate", "reverse", "turn_left", "turn_right"]:
		Input.action_release(action)

func _check(condition: bool, message: String) -> void:
	if not condition and not _failed:
		_failed = true
		push_error(message)
