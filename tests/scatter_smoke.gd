extends SceneTree

# godot --headless --path . --script tests/scatter_smoke.gd
var failed := false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var ground_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(60.0, 0.2, 60.0)
	ground_shape.shape = box
	ground_shape.position.y = -0.1
	ground.add_child(ground_shape)
	world.add_child(ground)
	var crush: Node3D = load("res://scenes/scatter/crushable_scatter.tscn").instantiate()
	var cactus: PackedScene = load("res://scenes/scatter/cactus_visual.tscn")
	var rock: PackedScene = load("res://scenes/scatter/rock_visual.tscn")
	crush.source_scenes.assign([cactus, null, rock, cactus])
	crush.instance_count = 12
	crush.density_enabled = false
	crush.area_size = Vector2(12.0, 10.0)
	crush.center_clearance = 0.0
	crush.scale_range = Vector2.ONE
	crush.ground_body_path = NodePath("../Ground")
	world.add_child(crush)
	var solid: Node3D = load("res://scenes/scatter/solid_scatter.tscn").instantiate()
	solid.source_scenes.assign([rock, cactus])
	solid.instance_count = 12
	solid.density_enabled = false
	solid.area_size = Vector2(8.0, 8.0)
	solid.center_clearance = 0.0
	solid.position.x = 15.0
	solid.ground_body_path = NodePath("../Ground")
	world.add_child(solid)
	for frame in 5:
		await physics_frame
	check(crush.generated_count == 12 and solid.generated_count == 12, "Both scatter types must generate their requested counts")
	check(crush._renderers.size() > 0 and solid._renderers.size() > 0, "Both scatter types must use MultiMesh renderers")
	for patch in [crush, solid]:
		check(patch._variants.size() == 2, "Null slots must be skipped and repeated source scenes must share batches")
		var total_instances := 0
		for variant in patch._variants:
			var indices: Array = variant["indices"]
			check(not indices.is_empty(), "The seeded mixed layout must include both models")
			total_instances += indices.size()
			for renderer in variant["renderers"]:
				check(renderer is MultiMeshInstance3D and renderer.multimesh.instance_count == indices.size(),
					"Each model part must batch only the instances using that model")
		check(total_instances == patch.generated_count, "Each placement must choose exactly one source model")
		for collider in patch._colliders:
			check(collider.get_node("BoxCollider").shape is BoxShape3D, "Every scatter instance must have a box collider")
		for a in patch.generated_count:
			var bounds: AABB = patch._variants[patch._instance_variants[a]]["bounds"]
			var expected_size: Vector3 = (bounds.size * patch._placements[a].basis.get_scale().x).max(Vector3.ONE * 0.05)
			check(patch._colliders[a].get_node("BoxCollider").shape.size.is_equal_approx(expected_size),
				"Every box must use its selected model's dimensions")
			for b in a:
				check(patch._placements[a].origin.distance_to(patch._placements[b].origin) >= patch.minimum_spacing,
					"Scatter instances must respect minimum spacing")
	check(crush._colliders[0] is Area3D and crush._colliders[0].collision_layer == 0,
		"Crushable props must detect overlap without blocking the tank")
	check(solid._colliders[0] is StaticBody3D, "Solid props must use physical static bodies")
	var placement: Transform3D = solid._placements[0]
	var query := PhysicsRayQueryParameters3D.create(placement.origin + Vector3.UP * 2.0, placement.origin - Vector3.UP, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == solid._colliders[0], "Solid scatter must be physically collidable")
	placement = crush._placements[0]
	query = PhysicsRayQueryParameters3D.create(placement.origin + Vector3.UP * 2.0, placement.origin - Vector3.UP, 1)
	hit = world.get_world_3d().direct_space_state.intersect_ray(query)
	check(hit.get("collider") == ground, "Crushable scatter must not obstruct body raycasts")
	# Rebuilding with a fixed seed must preserve placement and clear old colliders.
	var originals: Array[Transform3D] = crush._placements.duplicate()
	var original_choices: Array[int] = crush._instance_variants.duplicate()
	crush.rebuild()
	for frame in 4:
		await physics_frame
	for index in originals.size():
		check(originals[index].is_equal_approx(crush._placements[index]), "Rebuilding must reproduce a seeded layout")
	check(original_choices == crush._instance_variants, "Rebuilding must reproduce seeded model choices")
	crush.source_scenes.assign([null, null])
	crush.rebuild()
	for frame in 4:
		await physics_frame
	check(crush.generated_count == 0 and crush._renderers.is_empty(), "An array of empty slots must generate no props")
	crush.source_scenes.assign([cactus])
	crush.rebuild()
	for frame in 4:
		await physics_frame
	for index in originals.size():
		check(originals[index].is_equal_approx(crush._placements[index]), "Changing source choices must not shift seeded positions")
	crush.source_scenes.assign([cactus, null, rock, cactus])
	crush.rebuild()
	for frame in 4:
		await physics_frame
	# Use the actual player scene and its vehicle collision layer/group.
	var player: Node3D = load("res://scenes/playertank.tscn").instantiate()
	world.add_child(player)
	var tank: VehicleBody3D = player.get_node("vehicle")
	tank.freeze = true
	tank.global_position = crush._placements[0].origin + Vector3.UP * 0.25
	for frame in 30:
		await physics_frame
	check(crush._flattened[0], "The player's hull entering a crushable box must flatten that instance")
	for index in range(1, crush.generated_count):
		check(not crush._flattened[index], "Crushing one prop must leave neighboring MultiMesh instances standing")
	if DisplayServer.get_name() != "headless":
		for index in crush.generated_count:
			var variant: Dictionary = crush._variants[crush._instance_variants[index]]
			var squash := Transform3D(Basis.from_scale(Vector3(1.25, 0.08, 1.25)), Vector3.ZERO) if index == 0 else Transform3D.IDENTITY
			for part in variant["renderers"].size():
				var actual: Transform3D = variant["renderers"][part].multimesh.get_instance_transform(crush._instance_slots[index])
				var expected: Transform3D = crush._placements[index] * squash * variant["parts"][part]["transform"]
				check(actual.is_equal_approx(expected), "Crushing must change only the touched instance in its selected model batches")
	check(crush._colliders[0].get_node("BoxCollider").disabled, "Flattened props must stop monitoring overlaps")
	solid.flatten_instance(0)
	check(not solid._flattened[0], "Solid props must remain solid when asked to flatten")
	# An unrelated body on the vehicle layer must not crush vegetation.
	var unrelated := StaticBody3D.new()
	unrelated.collision_layer = 2
	var unrelated_shape := CollisionShape3D.new()
	unrelated_shape.shape = BoxShape3D.new()
	unrelated.add_child(unrelated_shape)
	world.add_child(unrelated)
	unrelated.global_position = crush._placements[1].origin + Vector3.UP * 0.2
	for frame in 5:
		await physics_frame
	check(not crush._flattened[1], "Only bodies in the crusher group may flatten props")
	# Surface normals must orient both the visual batch and collider on a slope.
	tank.global_position = Vector3(40.0, 5.0, 40.0)
	unrelated.queue_free()
	ground.rotation.z = 0.15
	await physics_frame
	await physics_frame
	crush.rebuild()
	for frame in 5:
		await physics_frame
	check(crush.generated_count == 12, "Scatter must project onto sloped terrain")
	for transform in crush._placements:
		check(transform.basis.y.normalized().dot(ground.global_basis.y) > 0.9999,
			"Scatter must align to the terrain normal")
	crush.maximum_slope = 2.0
	crush.rebuild()
	for frame in 4:
		await physics_frame
	check(crush.generated_count == 0, "Scatter must reject slopes above its limit")
	crush.maximum_slope = 35.0
	crush.source_scenes.clear()
	crush.source_scene = rock
	crush.rebuild()
	for frame in 4:
		await physics_frame
	check(crush.generated_count == 12 and crush._variants.size() == 1,
		"Previously saved single-source settings must remain usable")
	solid.clear_scatter()
	check(solid.generated_count == 0 and solid._renderers.is_empty() and solid._colliders.is_empty(),
		"Clear Scatter must remove the generated geometry and collision together")
	print("SCATTER smoke failed=", failed)
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
