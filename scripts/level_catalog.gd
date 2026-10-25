extends RefCounted

static var progress_path := "user://mission_progress.cfg"

const LEVELS := [
	{"name": "NORTHWEST", "description": "Two enemy vehicles have been spotted in a nearby town. Go and occupy it, and DON'T STOP", "path": "res://scenes/levels/northwest.tscn"},
	{"name": "NORTHEAST", "description": "The enemy have stepped up their presence here. A fast driver will be needed to get in and out, FAST", "path": "res://scenes/levels/northeast.tscn"},
	{"name": "SOUTHWEST", "description": "WHAT DID I TELL YOU ABOUT STOPPING, GET OUT THERE", "path": "res://scenes/levels/southwest.tscn"},
	{"name": "SOUTHEAST", "description": "!! ?? miaw !!", "path": "res://scenes/levels/southeast.tscn"},
	{"name": "ORIGINAL MAP", "description": "Return to the original full battlefield.", "path": "res://scenes/main.tscn"},
	{"name": "CREDITS", "description": "Mission accomplished. Meet the people behind ZEROED IN.", "path": "res://scenes/credits.tscn"},
]

const CAMPAIGN_MISSION_COUNT := 4


static func bonus_unlocked() -> bool:
	for index in CAMPAIGN_MISSION_COUNT:
		if not is_completed(LEVELS[index].path):
			return false
	return true


static func is_unlocked(index: int) -> bool:
	return index >= 0 and index < LEVELS.size() and (index < CAMPAIGN_MISSION_COUNT or bonus_unlocked())


static func mark_completed(path: String) -> void:
	for level in LEVELS:
		if level.path == path:
			var progress := ConfigFile.new()
			progress.load(progress_path)
			progress.set_value("completed", path, true)
			var error := progress.save(progress_path)
			if error != OK:
				push_warning("Could not save mission completion: %s" % error_string(error))
			return


static func is_completed(path: String) -> bool:
	var progress := ConfigFile.new()
	if progress.load(progress_path) != OK:
		return false
	return bool(progress.get_value("completed", path, false))


static func reset_completion() -> Error:
	var progress := ConfigFile.new()
	progress.load(progress_path)
	if progress.has_section("completed"):
		progress.erase_section("completed")
	return progress.save(progress_path)


static func crop_quarter(image: Image, index: int) -> Image:
	# Share the center row/column so all four pieces retain every source cell.
	var half := Vector2i((image.get_width() - 1) / 2, (image.get_height() - 1) / 2)
	return image.get_region(Rect2i(Vector2i(index % 2, index / 2) * half, half + Vector2i.ONE))


static func quarter_image(index: int) -> Image:
	var texture := preload("res://art/textures/heightmap.jpg")
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	return crop_quarter(image, index) if index < CAMPAIGN_MISSION_COUNT else image


static func height_at(image: Image, point: Vector2) -> float:
	var pixel := point + Vector2(image.get_size() - Vector2i.ONE) * 0.5
	var x := clampi(int(pixel.x), 0, image.get_width() - 2)
	var z := clampi(int(pixel.y), 0, image.get_height() - 2)
	var weight := (pixel - Vector2(x, z)).clamp(Vector2.ZERO, Vector2.ONE)
	return lerpf(lerpf(image.get_pixel(x, z).r, image.get_pixel(x + 1, z).r, weight.x),
		lerpf(image.get_pixel(x, z + 1).r, image.get_pixel(x + 1, z + 1).r, weight.x), weight.y) * 20.0


static func preview_mesh(index: int) -> ArrayMesh:
	var image := quarter_image(index)
	var extent := Vector2(image.get_size() - Vector2i.ONE)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	const STEPS := 48
	for z in range(STEPS + 1):
		for x in range(STEPS + 1):
			var uv := Vector2(x, z) / float(STEPS)
			var point := (uv - Vector2.ONE * 0.5) * extent
			surface.set_uv(uv)
			surface.add_vertex(Vector3(point.x, height_at(image, point), point.y))
	for z in range(STEPS):
		for x in range(STEPS):
			var a := z * (STEPS + 1) + x
			for vertex in [a, a + 1, a + STEPS + 1, a + 1, a + STEPS + 2, a + STEPS + 1]:
				surface.add_index(vertex)
	surface.generate_normals()
	return surface.commit()
