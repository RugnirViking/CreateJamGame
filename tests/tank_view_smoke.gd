extends SceneTree

# godot --headless --path . --script tests/tank_view_smoke.gd
var failed := false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	root.size = Vector2i(1152, 648)
	var world := Node3D.new()
	root.add_child(world)
	var player: Node3D = load("res://scenes/playertank.tscn").instantiate()
	world.add_child(player)
	var tank: VehicleBody3D = player.get_node("vehicle")
	tank.freeze = true
	var aim: Node3D = player.get_node("followcam")
	aim.set_process(false)
	aim.set_physics_process(false)
	var dust: MultiMeshInstance3D = player.get_node("CameraDust")
	dust.set_process(false)
	var original_mouse_mode := Input.mouse_mode

	var zoom_in := InputEventAction.new()
	zoom_in.action = &"zoom_in"
	zoom_in.pressed = true
	for step in 6:
		aim._unhandled_input(zoom_in)
	check(aim.sniper_mode, "Reaching minimum zoom must enter sniper mode")
	check(aim.sniper_camera.current and not aim.camera.current, "Only the sniper camera must be current")
	check(aim.sniper_hud.visible, "Sniper mode must show the hull/turret HUD")
	if DisplayServer.get_name() != "headless":
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Sniper mode must capture relative mouse movement")
	check(is_equal_approx(aim.sniper_camera.fov, aim.sniper_fov), "Scope must use its narrow FOV")

	# The captured FPS camera responds immediately; the gun follows at capped speed.
	aim.turret.rotation = Vector3.ZERO
	aim.gun_elevation.rotation = Vector3.ZERO
	aim.sniper_yaw = 0.0
	aim.sniper_pitch = 0.0
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(50.0, -50.0)
	motion.screen_relative = Vector2(100.0, -100.0)
	aim._unhandled_input(motion)
	check(aim.sniper_yaw < 0.0 and aim.sniper_pitch > 0.0, "Mouse right/up must command right/up")
	check(is_equal_approx(aim.sniper_yaw, -deg_to_rad(12.0)), "Camera yaw must respond directly to unscaled mouse movement")
	check(is_equal_approx(aim.sniper_pitch, deg_to_rad(12.0)), "Camera pitch must respond directly to unscaled mouse movement")
	check(is_zero_approx(aim.turret.rotation.y) and is_zero_approx(aim.gun_elevation.rotation.z), "Mouse events must not snap the physical gun")
	var stopped_camera: Transform3D = aim.sniper_camera.global_transform
	aim._physics_process(0.1)
	check(is_equal_approx(aim.turret.rotation.y, -deg_to_rad(6.0)), "Sniper traverse must respect its degrees per second")
	check(is_equal_approx(aim.gun_elevation.rotation.z, -deg_to_rad(3.0)), "Sniper elevation must respect its degrees per second")
	aim._update_crosshair()
	var screen_center := root.get_visible_rect().size * 0.5
	var reticle_position: Vector2 = aim.crosshair.position + aim.crosshair.size * 0.5
	var lag_distance := reticle_position.distance_to(screen_center)
	check(lag_distance > 20.0, "The gun reticle must lag behind a quick camera movement")
	check(reticle_position.distance_to(aim.sniper_camera.unproject_position(aim.gun_aim_point)) < 0.01,
		"The lagging reticle must show the actual barrel ray")
	for step in 60:
		aim._physics_process(1.0 / 60.0)
		aim._process(0.0)
	check(aim.sniper_camera.global_transform.is_equal_approx(stopped_camera), "Camera must stay still while the gun catches up")
	aim._update_crosshair()
	reticle_position = aim.crosshair.position + aim.crosshair.size * 0.5
	check(reticle_position.distance_to(screen_center) < lag_distance * 0.1, "Gun reticle must converge onto the camera aim")
	motion.screen_relative = Vector2.ZERO
	aim._unhandled_input(motion)
	check(aim.sniper_camera.global_transform.is_equal_approx(stopped_camera), "A stationary centered mouse must not move the camera")
	aim._process(0.0)
	check((-aim.sniper_camera.global_basis.z).dot(-aim.gun_elevation.global_basis.x.normalized()) > 0.9999,
		"The gun must settle onto the stationary camera aim")
	aim._process(0.0)
	check(is_equal_approx(aim.sniper_hud.turret_yaw, aim.turret.rotation.y), "HUD must display actual hull-relative turret yaw")
	# Further mouse input accumulates from camera aim, even if the gun is behind.
	var held_camera_yaw: float = aim.sniper_yaw
	aim.turret.rotation.y = 0.0
	aim._apply_sniper_mouse(Vector2(20.0, 0.0))
	check(is_equal_approx(aim.sniper_yaw, held_camera_yaw - deg_to_rad(2.4)), "Further mouse input must start from the camera aim")
	aim._apply_sniper_mouse(Vector2(-20.0, 0.0))
	for step in 60:
		aim._physics_process(1.0 / 60.0)
	tank.rotation = Vector3(0.1, 0.7, -0.1)
	for step in 120:
		aim._sync_sniper_camera(1.0 / 60.0)
	check((-aim.sniper_camera.global_basis.z).dot(-aim.gun_elevation.global_basis.x.normalized()) > 0.9999,
		"Scope must settle onto the barrel direction on a slope")
	check(absf(aim.sniper_camera.global_basis.x.y) < 0.0001, "Scope horizon must remain level on a slope")
	check_stabilization(aim, tank)
	aim._apply_sniper_mouse(Vector2(0.0, -10000.0))
	check(is_equal_approx(aim.sniper_pitch, deg_to_rad(aim.max_gun_elevation)), "Mouse aim must clamp at max elevation")
	aim._apply_sniper_mouse(Vector2(0.0, 10000.0))
	check(is_equal_approx(aim.sniper_pitch, deg_to_rad(aim.min_gun_elevation)), "Mouse aim must clamp at min elevation")

	# Recycled motes must stay in world space and brighten as speed increases.
	dust._update_particles(0.0)
	check(dust._last_camera == aim.sniper_camera, "Dust must follow the active camera")
	var zoom_out := InputEventAction.new()
	zoom_out.action = &"zoom_out"
	zoom_out.pressed = true
	aim._unhandled_input(zoom_out)
	check(not aim.sniper_mode and aim.camera.current, "Scroll out must return to third person")
	check(not aim.sniper_hud.visible and Input.mouse_mode == original_mouse_mode, "Leaving scope must hide HUD and restore mouse")
	dust._update_particles(0.0)
	check(dust._last_camera == aim.camera, "Dust must switch back to the follow camera")
	dust._positions[0] = aim.camera.global_position + Vector3(0.0, 1.0, -2.0)
	var world_position: Vector3 = dust._positions[0]
	var idle_alpha := 0.0
	tank.linear_velocity = Vector3.ZERO
	dust._update_particles(0.0)
	idle_alpha = dust.multimesh.get_instance_color(0).a
	aim.camera.global_position += Vector3(0.05, 0.0, 0.0)
	tank.linear_velocity = Vector3.LEFT * tank.max_forward_speed
	dust._update_particles(0.0)
	check(dust._positions[0].is_equal_approx(world_position), "Dust must stay in the world as the camera passes it")
	# The dummy headless renderer returns white for MultiMesh instance colors.
	if DisplayServer.get_name() != "headless":
		check(dust.multimesh.get_instance_color(0).a > idle_alpha * 2.0, "Speed must strengthen the dust effect")
	aim.camera.global_position += Vector3(1000.0, -1000.0, 1000.0)
	dust._update_particles(0.0)
	for i in dust.particle_count:
		var offset: Vector3 = (dust._positions[i] - aim.camera.global_position).abs()
		check(offset.x <= dust.field_half_size.x + 0.001 and offset.y <= dust.field_half_size.y + 0.001 and offset.z <= dust.field_half_size.z + 0.001,
			"Motes must recycle into the field after movement or teleports")
	check(dust.multimesh.instance_count == dust.particle_count, "Dust must keep a bounded particle pool")

	# Escape provides a reliable release from captured aiming, including re-entry.
	aim._set_sniper_mode(true)
	var cancel := InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	aim._unhandled_input(cancel)
	check(not aim.sniper_mode and Input.mouse_mode == original_mouse_mode, "Escape must leave sniper mode and release the mouse")
	aim._unhandled_input(zoom_in)
	check(aim.sniper_mode, "Zooming back in after Escape must re-enter sniper mode")
	aim._set_sniper_mode(false)
	world.queue_free()
	await process_frame
	print("VIEW smoke failed=", failed)
	quit(1 if failed else 0)


func check_stabilization(aim: Node3D, tank: VehicleBody3D) -> void:
	tank.rotation = Vector3.ZERO
	tank.position = Vector3.ZERO
	aim.turret.rotation = Vector3.ZERO
	aim.gun_elevation.rotation = Vector3.ZERO
	aim.sniper_yaw = 0.0
	aim.sniper_pitch = 0.0
	aim._sync_sniper_camera(0.0, true)
	var initial_height: float = aim.sniper_camera.global_position.y
	var initial_direction: Vector3 = -aim.sniper_camera.global_basis.z
	var max_height_sway := 0.0
	var max_angle_sway := 0.0
	# Simulate suspension bounce at 6 Hz, with simultaneous hull pitch and roll.
	for frame in 180:
		var bump := sin(float(frame) / 60.0 * TAU * 6.0)
		tank.position.y = 0.15 * bump
		tank.rotation = Vector3(0.1 * bump, 0.0, 0.12 * bump)
		aim._sync_sniper_camera(1.0 / 60.0)
		max_height_sway = maxf(max_height_sway, absf(aim.sniper_camera.global_position.y - initial_height))
		var facing: Vector3 = -aim.sniper_camera.global_basis.z
		max_angle_sway = maxf(max_angle_sway, acos(clampf(facing.dot(initial_direction), -1.0, 1.0)))
		check(absf(aim.sniper_camera.global_basis.x.y) < 0.0001, "Hull roll must not roll the scope horizon")
	check(max_height_sway < 0.07, "Stabilization must remove most of a 15 cm suspension bounce")
	check(max_angle_sway < 0.04, "Stabilization must remove most of a 0.12 rad hull jolt")
	# Mouse aiming changes the camera immediately, independently of the physical gun.
	tank.position = Vector3.ZERO
	tank.rotation = Vector3.ZERO
	aim._sync_sniper_camera(0.0, true)
	aim._apply_sniper_mouse(Vector2(-100.0, 0.0))
	var camera_direction := Basis(Vector3.UP, aim.sniper_yaw) * Vector3.LEFT
	check((-aim.sniper_camera.global_basis.z).dot(camera_direction) > 0.9999,
		"Hull stabilization must not add lag to mouse camera aiming")
	check(is_zero_approx(aim.turret.rotation.y), "The camera must be able to turn ahead of the gun")
	# Equal elapsed time should produce the same response at different frame rates.
	var results: Array[Transform3D] = []
	for fps in [30, 120]:
		tank.position = Vector3.ZERO
		tank.rotation = Vector3.ZERO
		aim._sync_sniper_camera(0.0, true)
		tank.position.y = 0.4
		tank.rotation.z = 0.2
		for frame in fps / 2:
			aim._sync_sniper_camera(1.0 / float(fps))
		results.append(aim.sniper_camera.global_transform)
	check(results[0].origin.distance_to(results[1].origin) < 0.0001,
		"Position stabilization must be independent of frame rate")
	check(results[0].basis.z.dot(results[1].basis.z) > 0.99999,
		"Rotation stabilization must be independent of frame rate")
	var rendered_transform: Transform3D = aim.sniper_camera.global_transform
	aim._physics_process(1.0 / 60.0)
	check(aim.sniper_camera.global_transform.is_equal_approx(rendered_transform),
		"Physics ticks must not overwrite the smoothed rendered camera")
	tank.position.x += 100.0
	aim._sync_sniper_camera(1.0 / 60.0)
	check(aim.sniper_camera.global_position.distance_to(aim.gun_elevation.global_position) < 0.2,
		"Teleporting must reset the scope rather than leave the camera behind")
	print("STABILIZATION peak_height=", max_height_sway, " peak_angle=", max_angle_sway)


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
