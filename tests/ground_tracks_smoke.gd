extends SceneTree

# godot --headless --path . --script tests/ground_tracks_smoke.gd
var failed := false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 0.2, 20.0)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.3
	world.add_child(floor_body)
	var player: Node3D = load("res://scenes/playertank.tscn").instantiate()
	world.add_child(player)
	var tank: VehicleBody3D = player.get_node("vehicle")
	var marks: MultiMeshInstance3D = player.get_node("GroundTracks")
	check(marks.tread_texture.resource_path == "res://art/textures/treadstransparent.png", "Ground marks must use the supplied tread texture")
	tank.position.y = 0.3
	for frame in 120:
		await physics_frame
	var contacts := 0
	for wheel in tank.wheels:
		if wheel.is_in_contact():
			contacts += 1
	check(contacts == 4, "Fixture must settle with all four wheels touching the ground")
	var idle_marks: int = marks.mark_count
	for frame in 60:
		await physics_frame
	check(marks.mark_count == idle_marks, "A parked tank must not pile up tread marks")
	Input.action_press("accelerate")
	for frame in 120:
		await physics_frame
	Input.action_release("accelerate")
	check(marks.mark_count > idle_marks + 30, "Driving on the ground must leave tread marks")
	var driven_marks: int = marks.mark_count
	tank.freeze = true
	tank.position.y += 4.0
	tank.linear_velocity = Vector3.ZERO
	tank.angular_velocity = Vector3.ZERO
	for frame in 30:
		await physics_frame
	check(marks.mark_count == driven_marks, "Airborne and stale wheel contacts must not leave marks")
	tank.position += Vector3(3.0, -4.0, 0.0)
	# Resume at rest on a different patch, leaving an unmarked gap in between.
	tank.freeze = false
	for frame in 90:
		await physics_frame
	check(marks.mark_count > driven_marks, "New contact after a jump must start fresh tracks")
	check(marks.mark_count - driven_marks < 24, "Landing must not connect tracks across the airborne gap")
	tank.freeze = true
	marks.set_physics_process(false)
	var before_gap: int = marks.mark_count
	# Interpolated samples over an absent surface must be discarded.
	marks._record_contact(0, Vector3(0.0, 3.0, 0.0), Vector3.UP, floor_body, Vector3.LEFT)
	marks._record_contact(0, Vector3(0.5, 3.0, 0.0), Vector3.UP, floor_body, Vector3.LEFT)
	check(marks.mark_count == before_gap, "A contact sample with no ground beneath must never create a mark")
	# A tilted collider must produce a matching surface-aligned quad.
	var slope := StaticBody3D.new()
	var slope_shape := CollisionShape3D.new()
	slope_shape.shape = box
	slope.add_child(slope_shape)
	slope.position = Vector3(0.0, 3.0, 0.0)
	slope.rotation.z = 0.25
	world.add_child(slope)
	await physics_frame
	await physics_frame
	var slope_point := slope.to_global(Vector3(0.0, 0.1, 0.0))
	var slope_normal := slope.global_basis.y
	marks._break_trail(0)
	marks._record_contact(0, slope_point, slope_normal, slope, Vector3.LEFT)
	check(marks.mark_count == before_gap + 1, "Ground contact on a slope must create a mark")
	if DisplayServer.get_name() != "headless":
		var stamp: Transform3D = marks.multimesh.get_instance_transform(marks._next_mark - 1)
		check(stamp.basis.z.dot(slope_normal) > 0.9999, "Tread mark must follow the slope's normal")
		check(stamp.origin.distance_to(slope_point + slope_normal * marks.surface_offset) < 0.001,
			"Tread mark must sit directly on the contacted surface")
	for i in marks.max_marks + 1:
		marks._stamp_surface(slope_point, slope_normal, slope, Vector3.LEFT)
	check(marks.mark_count == marks.max_marks, "Track storage must stay bounded during long drives")
	check(marks.multimesh.visible_instance_count == marks.max_marks, "Recycling must keep the track pool visible")
	print("GROUND TRACKS marks_after_driving=", driven_marks, " failed=", failed)
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
