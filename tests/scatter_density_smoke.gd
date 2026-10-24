extends SceneTree

# godot --headless --path . --script tests/scatter_density_smoke.gd
var failed := false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(80.0, 0.2, 80.0)
	collision.shape = floor_shape
	collision.position.y = -0.1
	ground.add_child(collision)
	world.add_child(ground)
	var patch: Node3D = load("res://scenes/scatter/solid_scatter.tscn").instantiate()
	patch.generate_on_start = false
	patch.instance_count = 400
	patch.area_size = Vector2(40, 40)
	patch.minimum_spacing = 0.6
	patch.center_clearance = 0.0
	patch.scale_range = Vector2(0.35, 0.35)
	patch.density_frequency = 0.09
	patch.ground_body_path = NodePath("../Ground")
	world.add_child(patch)
	await physics_frame
	await physics_frame
	for mode in [0, 1]:
		patch.scatter_type = mode
		patch.rebuild()
		await wait_frames(4)
		check(patch.generated_count > 50 and patch.generated_count <= patch.instance_count, "Both scatter types must generate a bounded noise-filtered layout")
		var mean_density := 0.0
		for y in 128:
			for x in 128:
				mean_density += patch._density_image.get_pixel(x, y).r / (128.0 * 128.0)
		var placement_density := 0.0
		for placement in patch._placements:
			var local_point: Vector3 = patch.to_local(placement.origin)
			var density: float = patch._sample_density(Vector2(local_point.x, local_point.z))
			check(density > 0.0, "Zero-density map regions must stay empty")
			placement_density += density / patch.generated_count
		check(placement_density > mean_density + 0.07, "Scatter must favor dense regions rather than fill sparse cells on retries")
		print("DENSITY mode=", mode, " count=", patch.generated_count, " map_mean=", mean_density, " placement_mean=", placement_density)
		var original_positions: Array[Transform3D] = patch._placements.duplicate()
		var original_choices: Array[int] = patch._instance_variants.duplicate()
		var original_pixels: PackedByteArray = patch._density_image.get_data()
		patch.rebuild()
		await wait_frames(4)
		check(original_positions == patch._placements and original_choices == patch._instance_variants,
			"Noise-filtered placement and model choices must reproduce with the same seeds")
		check(original_pixels == patch._density_image.get_data(), "Density preview must reproduce with the same noise seed")
		check(patch.get("density_preview") is ImageTexture, "The Inspector must expose the cached density preview")

	# Check map samples against actual FastNoiseLite Perlin output.
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = patch.density_seed
	noise.frequency = patch.density_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = patch.density_octaves
	for pixel in [Vector2i(19, 21), Vector2i(65, 105), Vector2i(117, 45)]:
		var local_point: Vector2 = (Vector2(pixel) / 127.0 - Vector2.ONE * 0.5) * patch.area_size
		var sample := noise.get_noise_2d(local_point.x, local_point.y) * 0.5 + 0.5
		var expected := smoothstep(patch.density_threshold, patch.density_threshold + patch.density_transition, sample)
		check(absf(patch._density_image.get_pixel(pixel.x, pixel.y).r - expected) < 0.005,
			"Cached density must sample Perlin noise, with the configured remapping")
	# Neighboring patches must sample a consistent world-space field.
	var neighbor: Node3D = load("res://scripts/scatter_patch.gd").new()
	neighbor.generate_on_start = false
	neighbor.area_size = patch.area_size
	neighbor.density_frequency = patch.density_frequency
	neighbor.position.x = 10.0
	world.add_child(neighbor)
	neighbor._build_density_map()
	check(absf(patch._sample_density(Vector2(5.0, 4.0)) - neighbor._sample_density(Vector2(-5.0, 4.0))) < 0.04,
		"Density samples must line up at the same world coordinate across patches")
	var previous_map: PackedByteArray = patch._density_image.get_data()
	patch.density_seed += 1
	patch.rebuild()
	await wait_frames(4)
	check(previous_map != patch._density_image.get_data(), "Changing the noise seed must change the density map")
	patch._density_image.save_png("res://.godot/scatter-density-preview.png")
	patch.density_threshold = 1.0
	patch.rebuild()
	await wait_frames(4)
	check(patch.generated_count == 0 and patch._renderers.is_empty(), "A fully black density map must generate no geometry or colliders")
	patch.density_strength = 0.0
	patch.rebuild()
	await wait_frames(4)
	check(patch.generated_count == patch.instance_count, "Zero noise strength must restore uniform placement")
	var uniform_positions: Array[Transform3D] = patch._placements.duplicate()
	patch.density_strength = 1.0
	patch.density_enabled = false
	patch.rebuild()
	await wait_frames(4)
	check(uniform_positions == patch._placements, "Disabling noise must exactly match zero-strength placement")
	check(is_equal_approx(patch._density_image.get_pixel(64, 64).r, 1.0), "Uniform scatter must show a white density preview")
	print("SCATTER DENSITY failed=", failed)
	world.queue_free()
	await process_frame
	quit(1 if failed else 0)


func wait_frames(count: int) -> void:
	for frame in count:
		await physics_frame


func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
