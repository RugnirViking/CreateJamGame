@tool
extends Node3D

enum ScatterType { SOLID, CRUSHABLE }

const LOD_MESH_LIBRARY = preload("res://art/models/scatter_lod_meshes.res")
const COLLISION_CELL_SIZE := 16.0

@export var scatter_type := ScatterType.SOLID
@export var source_scenes: Array[PackedScene] = []
# Accept previously saved single-source overrides without exposing another field.
@export_storage var source_scene: PackedScene
@export_range(0, 20000, 1) var instance_count := 60
@export var area_size := Vector2(30.0, 30.0)
@export var scatter_seed := 7331
@export var minimum_spacing := 1.2
@export var center_clearance := 4.0
@export var scale_range := Vector2(0.75, 1.25)
@export_range(0.0, 80.0, 1.0) var maximum_slope := 35.0
@export var align_to_ground := true
@export var ray_height := 100.0
@export var ray_depth := 200.0
@export_flags_3d_physics var ground_collision_mask: int = 1
@export_node_path("StaticBody3D") var ground_body_path: NodePath
@export var generate_on_start := true
@export_range(0.0, 2.0, 0.05) var flatten_duration := 0.2

@export_group("Distance LOD")
@export var lod_enabled := true
@export_range(8.0, 128.0, 1.0, "suffix:m") var render_chunk_size := 64.0
@export_range(0.0, 200.0, 1.0, "suffix:m") var full_detail_distance := 30.0
@export_range(0.01, 2.0, 0.01) var mesh_lod_bias := 0.35
@export_range(0.0, 1000.0, 5.0, "or_greater", "suffix:m") var draw_distance := 240.0
@export_range(0.0, 200.0, 1.0, "or_greater", "suffix:m") var shadow_distance := 45.0

@export_group("Nearby Collision")
@export var collision_distance_enabled := true
@export_range(1.0, 100.0, 0.5, "or_greater", "suffix:m") var collision_distance := 12.0
@export_range(0.0, 20.0, 0.5, "suffix:m") var collision_hysteresis := 3.0
@export_range(0.02, 1.0, 0.01, "suffix:s") var collision_update_interval := 0.1
# Leave empty to follow the node in the player group.
@export_node_path("Node3D") var collision_target_path: NodePath

@export_group("Density Noise")
@export var density_enabled := true
@export var density_seed := 7331
@export_range(0.001, 1.0, 0.001) var density_frequency := 0.05
@export_range(1, 8, 1) var density_octaves := 3
@export var density_offset := Vector2.ZERO
@export_range(0.0, 1.0, 0.05) var density_strength := 1.0
@export_range(0.0, 1.0, 0.05) var density_threshold := 0.35
@export_range(0.0, 1.0, 0.05) var density_transition := 0.3
@export_group("")

@export_tool_button("Rebuild scatter") var rebuild_button: Callable = rebuild
@export_tool_button("Clear scatter") var clear_button: Callable = clear_scatter

var generated_count := 0
var _pending_build := false
var _generated: Node3D
var _variants: Array[Dictionary] = []
var _source_choices: Array[int] = []
var _instance_variants: Array[int] = []
var _instance_slots: Array[int] = []
var _instance_batches: Array[int] = []
var _visual_batches: Array[Dictionary] = []
var _visual_timer := 0.0
var _renderers: Array[MultiMeshInstance3D] = []
var _placements: Array[Transform3D] = []
var _colliders: Array[CollisionObject3D] = []
var _flattened: Array[bool] = []
var _flatten_tweens: Array[Tween] = []
var _density_image: Image
var _density_preview: ImageTexture
var _collision_cells: Dictionary = {}
var _collision_bounds: Array[AABB] = []
var _active_colliders: Dictionary = {}
var _collision_target: Node3D
var _collision_timer := 0.0


func _get_property_list() -> Array[Dictionary]:
	return [{"name": "density_preview", "type": TYPE_OBJECT,
		"hint": PROPERTY_HINT_RESOURCE_TYPE, "hint_string": "Texture2D",
		"usage": PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY}]


func _get(property: StringName) -> Variant:
	if property == &"density_preview":
		return _density_preview
	return null


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group(&"scatter_patches")
	set_notify_transform(true)
	set_physics_process(false)
	set_process(false)
	if generate_on_start:
		rebuild()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and is_node_ready() and Engine.is_editor_hint():
		rebuild()


func _get_configuration_warnings() -> PackedStringArray:
	for source in _get_sources():
		if source != null:
			return PackedStringArray()
	return PackedStringArray(["Add visual scenes to Source Scenes. Each placement randomly chooses one; meshes are rendered with MultiMesh."])


func _get_sources() -> Array[PackedScene]:
	var sources: Array[PackedScene] = source_scenes.duplicate()
	if sources.is_empty() and source_scene != null:
		sources.append(source_scene)
	return sources


func rebuild() -> void:
	# Run surface queries in a physics callback, including editor tool rebuilds.
	_pending_build = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if _pending_build:
		_pending_build = false
		_generate()
	elif not Engine.is_editor_hint() and collision_distance_enabled:
		_collision_timer -= delta
		if _collision_timer <= 0.0:
			_update_nearby_colliders()
			_collision_timer = collision_update_interval
	set_physics_process(not Engine.is_editor_hint() and collision_distance_enabled and generated_count > 0)


func _process(delta: float) -> void:
	_visual_timer -= delta
	if _visual_timer <= 0.0:
		_update_visual_lod()
		_visual_timer = 0.1


func clear_scatter() -> void:
	_pending_build = false
	set_physics_process(false)
	set_process(false)
	for tween in _flatten_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_flatten_tweens.clear()
	if is_instance_valid(_generated):
		remove_child(_generated)
		_generated.queue_free()
	_generated = null
	_variants.clear()
	_source_choices.clear()
	_instance_variants.clear()
	_instance_slots.clear()
	_instance_batches.clear()
	_visual_batches.clear()
	_visual_timer = 0.0
	_renderers.clear()
	_placements.clear()
	_colliders.clear()
	_collision_cells.clear()
	_collision_bounds.clear()
	_active_colliders.clear()
	_collision_target = null
	_collision_timer = 0.0
	_flattened.clear()
	generated_count = 0


func _collect_meshes(node: Node, parent_transform: Transform3D, parts: Array[Dictionary]) -> void:
	var local := parent_transform
	if node is Node3D:
		local *= node.transform
	if node is MeshInstance3D and node.mesh != null and node.visible:
		parts.append({"mesh": node.mesh, "transform": local, "material": node.material_override, "cast_shadow": node.cast_shadow})
	for child in node.get_children():
		_collect_meshes(child, local, parts)


func _prepare_variants() -> void:
	var cached_sources: Dictionary = {}
	for source in _get_sources():
		if source == null:
			continue
		var source_id := source.get_instance_id()
		if cached_sources.has(source_id):
			_source_choices.append(cached_sources[source_id])
			continue
		var parts: Array[Dictionary] = []
		var prototype := source.instantiate()
		_collect_meshes(prototype, Transform3D.IDENTITY, parts)
		prototype.free()
		if parts.is_empty():
			push_warning("Scatter source has no visible meshes: " + str(source.resource_path))
			continue
		var bounds := AABB()
		var first := true
		for part in parts:
			var part_bounds: AABB = part["transform"] * part["mesh"].get_aabb()
			bounds = part_bounds if first else bounds.merge(part_bounds)
			first = false
		# Each model has its own origin correction and box dimensions.
		for part in parts:
			var visual_transform: Transform3D = part["transform"]
			visual_transform.origin.y -= bounds.position.y
			part["transform"] = visual_transform
		var baked_meshes: Dictionary = LOD_MESH_LIBRARY.get_meta(&"meshes", {})
		for part_index in parts.size():
			parts[part_index]["lod_mesh"] = baked_meshes.get(source.resource_path + "#" + str(part_index), parts[part_index]["mesh"])
		bounds.position.y = 0.0
		cached_sources[source_id] = _variants.size()
		_source_choices.append(_variants.size())
		_variants.append({"parts": parts, "bounds": bounds, "indices": [], "renderers": []})


func _build_density_map() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.seed = density_seed
	noise.frequency = density_frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = density_octaves
	_density_image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for y in 128:
		for x in 128:
			var density := 1.0
			if density_enabled and density_strength > 0.0:
				var uv := Vector2(float(x), float(y)) / 127.0
				var local_point := (uv - Vector2.ONE * 0.5) * area_size
				var world_point := to_global(Vector3(local_point.x, 0.0, local_point.y))
				var value := clampf(noise.get_noise_2d(world_point.x + density_offset.x, world_point.z + density_offset.y) * 0.5 + 0.5, 0.0, 1.0)
				var upper_edge := minf(1.0, density_threshold + density_transition)
				var shaped := smoothstep(density_threshold, upper_edge, value) if upper_edge > density_threshold else (1.0 if value > density_threshold else 0.0)
				density = lerpf(1.0, shaped, density_strength)
			_density_image.set_pixel(x, y, Color(density, density, density, 1.0))
	if _density_preview == null:
		_density_preview = ImageTexture.create_from_image(_density_image)
	else:
		_density_preview.update(_density_image)
	notify_property_list_changed()


func _sample_density(local_point: Vector2) -> float:
	if not density_enabled or density_strength <= 0.0 or _density_image == null:
		return 1.0
	var pixel := ((local_point / area_size + Vector2.ONE * 0.5).clamp(Vector2.ZERO, Vector2.ONE)) * 127.0
	var x := floori(pixel.x)
	var y := floori(pixel.y)
	var next_x := mini(x + 1, 127)
	var next_y := mini(y + 1, 127)
	var top := lerpf(_density_image.get_pixel(x, y).r, _density_image.get_pixel(next_x, y).r, pixel.x - x)
	var bottom := lerpf(_density_image.get_pixel(x, next_y).r, _density_image.get_pixel(next_x, next_y).r, pixel.x - x)
	return lerpf(top, bottom, pixel.y - y)


func _has_space(point: Vector2, occupied: Dictionary) -> bool:
	if minimum_spacing <= 0.0:
		return true
	var cell := Vector2i(floori(point.x / minimum_spacing), floori(point.y / minimum_spacing))
	for y in range(-1, 2):
		for x in range(-1, 2):
			for neighbor: Vector2 in occupied.get(cell + Vector2i(x, y), []):
				if neighbor.distance_squared_to(point) < minimum_spacing * minimum_spacing:
					return false
	return true


func _occupy(point: Vector2, occupied: Dictionary) -> void:
	if minimum_spacing <= 0.0:
		return
	var cell := Vector2i(floori(point.x / minimum_spacing), floori(point.y / minimum_spacing))
	if not occupied.has(cell):
		occupied[cell] = []
	occupied[cell].append(point)


func _generate() -> void:
	clear_scatter()
	if area_size.x <= 0.0 or area_size.y <= 0.0:
		return
	_build_density_map()
	if instance_count == 0:
		return
	_prepare_variants()
	if _variants.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = scatter_seed
	# Choosing models must not shift the existing seeded placement layout.
	var variant_rng := RandomNumberGenerator.new()
	variant_rng.seed = scatter_seed ^ 0x5CA77E
	var columns := maxi(1, ceili(sqrt(float(instance_count) * area_size.x / area_size.y)))
	var rows := maxi(1, ceili(float(instance_count) / columns))
	var cell_size := area_size / Vector2(columns, rows)
	var density_rng := RandomNumberGenerator.new()
	density_rng.seed = scatter_seed ^ 0xD3517
	var cell_density_rolls := PackedFloat32Array()
	cell_density_rolls.resize(columns * rows)
	for cell in cell_density_rolls.size():
		cell_density_rolls[cell] = density_rng.randf()
	var occupied: Dictionary = {}
	var ground_body := get_node_or_null(ground_body_path) if not ground_body_path.is_empty() else null
	var minimum_normal_y := cos(deg_to_rad(maximum_slope))
	# A jittered grid spreads the samples; distance rejection prevents clumps.
	for attempt in instance_count * 8:
		if _placements.size() >= instance_count:
			break
		var cell := attempt % (columns * rows)
		var local_point := Vector2(cell % columns, floori(float(cell) / columns))
		local_point = (local_point + Vector2(rng.randf_range(0.1, 0.9), rng.randf_range(0.1, 0.9))) * cell_size - area_size * 0.5
		if local_point.length() < center_clearance:
			continue
		# Keep the same probability roll across retries so sparse regions stay sparse.
		if _sample_density(local_point) <= cell_density_rolls[cell]:
			continue
		var sample := to_global(Vector3(local_point.x, 0.0, local_point.y))
		var query := PhysicsRayQueryParameters3D.create(
			sample + Vector3.UP * ray_height, sample - Vector3.UP * ray_depth, ground_collision_mask)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit["collider"] is StaticBody3D:
			continue
		if ground_body != null and hit["collider"] != ground_body:
			continue
		var normal: Vector3 = hit["normal"]
		if normal.y < minimum_normal_y:
			continue
		var position: Vector3 = hit["position"]
		if not _has_space(Vector2(position.x, position.z), occupied):
			continue
		var up := normal.normalized() if align_to_ground else Vector3.UP
		var right := Vector3.RIGHT.slide(up).normalized()
		var basis := Basis(right, up, right.cross(up)) * Basis(Vector3.UP, rng.randf_range(-PI, PI))
		var scale_factor := rng.randf_range(maxf(0.01, minf(scale_range.x, scale_range.y)), maxf(0.01, maxf(scale_range.x, scale_range.y)))
		_placements.append(Transform3D(basis.scaled(Vector3.ONE * scale_factor), position))
		_occupy(Vector2(position.x, position.z), occupied)
		var variant_index: int = _source_choices[variant_rng.randi_range(0, _source_choices.size() - 1)]
		var indices: Array = _variants[variant_index]["indices"]
		_instance_variants.append(variant_index)
		_instance_slots.append(indices.size())
		indices.append(_placements.size() - 1)
	generated_count = _placements.size()
	if generated_count == 0:
		return
	_generated = Node3D.new()
	_generated.name = "GeneratedScatter"
	_generated.top_level = true
	add_child(_generated, false, Node.INTERNAL_MODE_BACK)
	_generated.global_transform = Transform3D.IDENTITY
	_build_visual_batches()
	_flattened.resize(generated_count)
	_flatten_tweens.resize(generated_count)
	_colliders.resize(generated_count)
	for index in generated_count:
		_set_flatten_amount(0.0, index)
		_index_collision(index)
	set_process(lod_enabled)
	_update_visual_lod()
	# Editor previews only need the MultiMesh visuals, not thousands of physics nodes.
	if Engine.is_editor_hint():
		return
	if collision_distance_enabled:
		_update_nearby_colliders()
		_collision_timer = collision_update_interval
	else:
		for index in generated_count:
			_build_collider(index)


func _build_visual_batches() -> void:
	_instance_batches.resize(generated_count)
	for variant in _variants:
		var cells: Dictionary = {}
		for index: int in variant["indices"]:
			var point := _placements[index].origin
			var cell := Vector2i(floori(point.x / maxf(1.0, render_chunk_size)), floori(point.z / maxf(1.0, render_chunk_size))) if lod_enabled else Vector2i.ZERO
			if not cells.has(cell):
				cells[cell] = []
			cells[cell].append(index)
		for indices: Array in cells.values():
			var bounds: AABB = _placements[indices[0]] * variant["bounds"]
			for index: int in indices:
				bounds = bounds.merge(_placements[index] * variant["bounds"])
			var origin := bounds.get_center() if lod_enabled else Vector3.ZERO
			var batch := {"bounds": bounds, "origin": origin, "indices": indices, "parts": variant["parts"], "renderers": []}
			for slot in indices.size():
				_instance_batches[indices[slot]] = _visual_batches.size()
				_instance_slots[indices[slot]] = slot
			_visual_batches.append(batch)
			for part in variant["parts"]:
				var renderer := MultiMeshInstance3D.new()
				renderer.name = "ScatterMesh%d" % _renderers.size()
				renderer.position = origin
				renderer.multimesh = MultiMesh.new()
				renderer.multimesh.transform_format = MultiMesh.TRANSFORM_3D
				renderer.multimesh.mesh = part["lod_mesh"] if lod_enabled else part["mesh"]
				renderer.multimesh.instance_count = indices.size()
				# Includes the small horizontal expansion when a prop is flattened.
				var model_bounds: AABB = variant["bounds"]
				var padding := maxf(model_bounds.size.x, model_bounds.size.z) * maxf(scale_range.x, scale_range.y) * 0.3
				renderer.multimesh.custom_aabb = AABB(bounds.position - origin, bounds.size).grow(padding)
				renderer.material_override = part["material"]
				renderer.cast_shadow = part["cast_shadow"]
				renderer.lod_bias = mesh_lod_bias if lod_enabled else 1.0
				_generated.add_child(renderer)
				_renderers.append(renderer)
				variant["renderers"].append(renderer)
				batch["renderers"].append(renderer)


func _update_visual_lod() -> void:
	if not lod_enabled:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	# Native mesh LOD is screen-size based and follows camera FOV automatically.
	# Extend the final visibility cutoff as well when entering sniper zoom.
	var zoom_scale := maxf(1.0, tan(deg_to_rad(70.0) * 0.5) / tan(deg_to_rad(maxf(camera.fov, 1.0)) * 0.5))
	for batch in _visual_batches:
		var bounds: AABB = batch["bounds"]
		var distance := camera.global_position.distance_to(camera.global_position.clamp(bounds.position, bounds.end))
		var near := distance <= full_detail_distance * zoom_scale
		var shadows_in_range := distance <= shadow_distance and shadow_distance > 0.0
		for part_index in batch["renderers"].size():
			var renderer: MultiMeshInstance3D = batch["renderers"][part_index]
			var part: Dictionary = batch["parts"][part_index]
			var shadow_mode: int = part["cast_shadow"] if shadows_in_range else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var mesh: Mesh = part["mesh"] if near else part["lod_mesh"]
			if renderer.multimesh.mesh != mesh:
				renderer.multimesh.mesh = mesh
			renderer.lod_bias = 1.0 if near else mesh_lod_bias
			renderer.visibility_range_end = draw_distance * zoom_scale if draw_distance > 0.0 else 0.0
			if renderer.cast_shadow != shadow_mode:
				renderer.cast_shadow = shadow_mode


func _collision_cell(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / COLLISION_CELL_SIZE), floori(point.z / COLLISION_CELL_SIZE))


func _index_collision(index: int) -> void:
	var bounds: AABB = _variants[_instance_variants[index]]["bounds"]
	var placement := _placements[index]
	# Match the collider's minimum box size, including large or offset models.
	var scale_factor := placement.basis.get_scale().x
	var size := (bounds.size * scale_factor).max(Vector3.ONE * 0.05)
	var center := bounds.get_center() * scale_factor
	var world_bounds := Transform3D(placement.basis.orthonormalized(), placement.origin) * AABB(center - size * 0.5, size)
	_collision_bounds.append(world_bounds)
	var first := _collision_cell(world_bounds.position)
	var last := _collision_cell(world_bounds.end)
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var cell := Vector2i(x, y)
			if not _collision_cells.has(cell):
				_collision_cells[cell] = []
			_collision_cells[cell].append(index)


func _within_collision_distance(index: int, point: Vector3, distance: float) -> bool:
	var bounds := _collision_bounds[index]
	var closest := point.clamp(bounds.position, bounds.end)
	return point.distance_squared_to(closest) <= distance * distance


func _update_nearby_colliders() -> void:
	if not is_instance_valid(_collision_target) or not _collision_target.is_inside_tree():
		_collision_target = get_node_or_null(collision_target_path) as Node3D if not collision_target_path.is_empty() else get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(_collision_target) or not _collision_target.is_inside_tree():
		for index: int in _active_colliders.keys():
			_release_collider(index)
		return
	var point := _collision_target.global_position
	# Keep existing boxes slightly farther away to avoid churn at the boundary.
	for index: int in _active_colliders.keys():
		if _flattened[index] or not _within_collision_distance(index, point, collision_distance + collision_hysteresis):
			_release_collider(index)
	var first := _collision_cell(point - Vector3.ONE * collision_distance)
	var last := _collision_cell(point + Vector3.ONE * collision_distance)
	var visited: Dictionary = {}
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for index: int in _collision_cells.get(Vector2i(x, y), []):
				if visited.has(index):
					continue
				visited[index] = true
				if not _flattened[index] and not _active_colliders.has(index) and _within_collision_distance(index, point, collision_distance):
					_build_collider(index)


func _release_collider(index: int) -> void:
	_colliders[index].queue_free()
	_colliders[index] = null
	_active_colliders.erase(index)


func _build_collider(index: int) -> void:
	var placement := _placements[index]
	var scale_factor := placement.basis.get_scale().x
	var bounds: AABB = _variants[_instance_variants[index]]["bounds"]
	var bounds_center := bounds.get_center() * scale_factor
	var shape := BoxShape3D.new()
	shape.size = (bounds.size * scale_factor).max(Vector3.ONE * 0.05)
	var collision := CollisionShape3D.new()
	collision.name = "BoxCollider"
	collision.shape = shape
	collision.position = bounds_center
	var body: CollisionObject3D
	if scatter_type == ScatterType.SOLID:
		body = StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 2
	else:
		var area := Area3D.new()
		area.collision_layer = 0
		area.collision_mask = 2
		area.monitorable = false
		area.body_entered.connect(_on_body_entered.bind(index))
		body = area
	body.name = "ScatterCollider%d" % index
	body.add_child(collision)
	_generated.add_child(body)
	body.transform = Transform3D(placement.basis.orthonormalized(), placement.origin)
	_colliders[index] = body
	_active_colliders[index] = true


func _on_body_entered(body: Node3D, index: int) -> void:
	if not Engine.is_editor_hint() and body.is_in_group(&"scatter_crushers"):
		flatten_instance(index)


func flatten_in_radius(impact_position: Vector3, radius: float) -> void:
	if scatter_type != ScatterType.CRUSHABLE or radius <= 0.0:
		return
	# Query the placement grid, including props without active nearby colliders.
	var first := _collision_cell(impact_position - Vector3.ONE * radius)
	var last := _collision_cell(impact_position + Vector3.ONE * radius)
	var visited: Dictionary = {}
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			for index: int in _collision_cells.get(Vector2i(x, y), []):
				if visited.has(index):
					continue
				visited[index] = true
				if not _flattened[index] and _within_collision_distance(index, impact_position, radius):
					flatten_instance(index)


func flatten_instance(index: int) -> void:
	if scatter_type != ScatterType.CRUSHABLE or index < 0 or index >= generated_count or _flattened[index]:
		return
	_flattened[index] = true
	if is_instance_valid(_colliders[index]):
		_colliders[index].set_deferred("monitoring", false)
		_colliders[index].get_node("BoxCollider").set_deferred("disabled", true)
	if flatten_duration <= 0.0:
		_set_flatten_amount(1.0, index)
	else:
		var tween := create_tween()
		_flatten_tweens[index] = tween
		tween.tween_method(_set_flatten_amount.bind(index), 0.0, 1.0, flatten_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _set_flatten_amount(amount: float, index: int) -> void:
	var squash := Transform3D(Basis.from_scale(Vector3.ONE.lerp(Vector3(1.25, 0.08, 1.25), amount)), Vector3.ZERO)
	var variant: Dictionary = _variants[_instance_variants[index]]
	var batch: Dictionary = _visual_batches[_instance_batches[index]]
	var renderers: Array = batch["renderers"]
	for part_index in renderers.size():
		renderers[part_index].multimesh.set_instance_transform(
			_instance_slots[index], (_placements[index] * squash * variant["parts"][part_index]["transform"]).translated(-batch["origin"]))
