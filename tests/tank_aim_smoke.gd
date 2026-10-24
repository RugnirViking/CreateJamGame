extends SceneTree

# godot --headless --path . --script tests/tank_aim_smoke.gd
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
	var turret: Node3D = aim.turret
	var gun: Node3D = aim.gun_elevation

	# A side target must take time to reach, then converge without overshooting.
	var target := turret.global_position + Vector3(0.0, 0.0, 10.0)
	aim._aim_at(target, 0.1)
	check(is_equal_approx(turret.rotation.y, deg_to_rad(6.0)), "Traverse must respect degrees per second")
	for step in 180:
		aim._aim_at(target, 1.0 / 60.0)
	check((-turret.global_basis.x).normalized().dot((target - turret.global_position).normalized()) > 0.999,
		"The -X turret axis must converge on the target")

	# Crossing +/-180 degrees must use the short route.
	turret.rotation.y = deg_to_rad(179.0)
	var wrapped_target := turret.get_parent_node_3d().to_global(
		turret.position + Basis(Vector3.UP, deg_to_rad(-179.0)) * Vector3.LEFT * 100.0
	)
	aim._aim_at(wrapped_target, 0.1)
	check(absf(angle_difference(turret.rotation.y, deg_to_rad(-179.0))) < 0.0001,
		"Traverse must take the shortest path across the angle boundary")

	# Check the actual barrel direction, including on a tilted and rotated hull.
	for hull_rotation in [Vector3.ZERO, Vector3(0.2, 0.7, -0.15)]:
		tank.rotation = hull_rotation
		turret.rotation = Vector3.ZERO
		gun.rotation = Vector3.ZERO
		for pitch_degrees in [20.0, -10.0]:
			var direction := Basis(Vector3.FORWARD, deg_to_rad(pitch_degrees)) * Vector3.LEFT
			var gun_target := gun.global_position + turret.global_basis * direction * 100.0
			target = gun_target
			gun.rotation.z = 0.0
			aim._aim_at(target, 0.1)
			check(is_equal_approx(absf(gun.rotation.z), deg_to_rad(3.0)), "Elevation must respect its speed")
			for step in 180:
				aim._aim_at(target, 1.0 / 60.0)
			check((-gun.global_basis.x).normalized().dot((target - gun.global_position).normalized()) > 0.999,
				"GunElevation must point its barrel at high and low targets on slopes")
			# Return the yaw to its original direction before constructing the next target.
			turret.rotation = Vector3.ZERO

	tank.rotation = Vector3.ZERO
	turret.rotation = Vector3.ZERO
	gun.rotation = Vector3.ZERO
	aim._aim_at(gun.global_position + Vector3(0.0, 100.0, 0.0), 10.0)
	check(is_equal_approx(gun.rotation.z, -deg_to_rad(aim.max_gun_elevation)), "Upward aim must respect elevation limit")
	aim._aim_at(gun.global_position + Vector3(0.0, -100.0, 0.0), 10.0)
	check(is_equal_approx(gun.rotation.z, -deg_to_rad(aim.min_gun_elevation)), "Downward aim must respect depression limit")

	# Place a surface on the cursor ray and let physics register its collider.
	var mouse_pos := root.get_mouse_position()
	var camera: Camera3D = aim.camera
	var origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3.ONE * 2.0
	shape.shape = box
	obstacle.add_child(shape)
	world.add_child(obstacle)
	obstacle.global_position = origin + ray_direction * 10.0
	await physics_frame
	await physics_frame
	aim._physics_process(1.0 / 60.0)
	check(aim.aim_point.distance_to(obstacle.global_position) < 2.0, "Mouse ray must hit the real surface")
	aim._update_crosshair()
	# Turn the gun at a separate surface to distinguish its impact from the mouse.
	turret.rotation = Vector3.ZERO
	gun.rotation = Vector3.ZERO
	var muzzle: Marker3D = aim.muzzle
	obstacle.global_position = muzzle.global_position - muzzle.global_basis.x.normalized() * 10.0
	await physics_frame
	await physics_frame
	aim.turret_traverse_speed = 0.0
	aim.gun_elevation_speed = 0.0
	aim._physics_process(1.0 / 60.0)
	aim._update_crosshair()
	check(aim.gun_aim_point.distance_to(obstacle.global_position) < 2.0, "Gun ray must hit the surface along the barrel")
	check(aim.crosshair.visible, "Crosshair must be visible at the gun hit")
	check((aim.crosshair.position + aim.crosshair.size * 0.5).distance_to(camera.unproject_position(aim.gun_aim_point)) < 0.01,
		"Crosshair center must project onto the gun ray intersection")
	check(aim.gun_aim_point.distance_to(aim.aim_point) > 1.0, "Gun impact and mouse command must remain separate while traversing")
	check(aim.crosshair.texture.resource_path == "res://art/textures/crosshair-nobg.png", "Use the requested crosshair image")
	check(aim.crosshair.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Crosshair must not consume mouse input")

	# The player's hull must not obstruct the ray, and sky aim must stay finite.
	obstacle.global_position = origin + ray_direction * 0.5
	obstacle.collision_layer = 2
	tank.global_position = origin + ray_direction * 2.0
	await physics_frame
	await physics_frame
	aim._physics_process(1.0 / 60.0)
	check(aim.aim_point.is_equal_approx(origin + ray_direction * aim.aim_distance),
		"A miss must use the distant endpoint, ignoring the hull and masked surfaces")
	aim.gun_aim_point = camera.global_position + camera.global_basis.z * 10.0
	aim._update_crosshair()
	check(not aim.crosshair.visible, "Hide the crosshair when its point is behind the camera")
	print("AIM smoke failed=", failed)
	quit(1 if failed else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
