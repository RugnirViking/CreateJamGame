extends Control

# The cactus's existing googly eyes face +Z, toward these portrait cameras.
const CACTUS := preload("res://art/models/cactus.glb")
const CAT := preload("res://art/models/cat_of_ages.glb")
const SWAY_SPEED := 3.2
const SWAY_ANGLE := 0.18
const CAT_FACING_YAW := PI * 0.5
const CAT_TWIRL_INTERVAL := 6.0
const CAT_TWIRL_DURATION := 1.1

var _dancers: Array[Node3D] = []
var _portraits: Array[SubViewportContainer] = []
var _phase := 0.0
var _dance_time := 0.0


func _ready() -> void:
	name = "DancingCactuses"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_FILL
	for index in range(2):
		_add_dancer(index)
	if get_tree().current_scene.get_meta("boss_mission", false):
		for index in range(2, 4):
			_add_dancer(index, true)
	visibility_changed.connect(_update_visibility)
	get_parent().resized.connect(_fit_overlay)
	resized.connect(_layout_portraits)
	get_parent().get_node("Text").item_rect_changed.connect(_layout_portraits.call_deferred)
	_update_visibility()
	_fit_overlay()
	_layout_portraits.call_deferred()


func _fit_overlay() -> void:
	# Keep the dancers on a full-screen overlay, independent of the text height.
	size = get_parent().size


func _add_dancer(index: int, is_cat: bool = false) -> void:
	var portrait := SubViewportContainer.new()
	if is_cat:
		portrait.name = "LeftCat" if index == 2 else "RightCat"
	else:
		portrait.name = "LeftCactus" if index == 0 else "RightCactus"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.stretch = true
	add_child(portrait)
	_portraits.append(portrait)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(300, 400)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	portrait.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-25, -25, 0)
	light.light_energy = 1.1
	viewport.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.position = Vector3(0, 4.8, 24)
	camera.current = true
	viewport.add_child(camera)
	var dancer := Node3D.new()
	dancer.name = "SwayPivot"
	viewport.add_child(dancer)
	if is_cat:
		var model := CAT.instantiate() as Node3D
		dancer.add_child(model)
		_fit_cat(model)
		# This imported cat faces -X; a quarter turn faces the portrait camera.
		dancer.rotation.y = CAT_FACING_YAW
	else:
		dancer.add_child(CACTUS.instantiate())
	_dancers.append(dancer)


func _fit_cat(model: Node3D) -> void:
	# Normalize the imported model's full transformed bounds, including its tail.
	var bounds := AABB()
	var first := true
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = model.global_transform.affine_inverse() * mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	if first:
		return
	var factor := minf(7.0 / maxf(bounds.size.y, 0.001), 5.0 / maxf(bounds.size.x, 0.001))
	model.scale *= factor
	# Put its feet at the sway pivot and center the cat in its portrait.
	model.position = -Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor


func _layout_portraits() -> void:
	var text := get_parent().get_node("Text") as Control
	var text_center := text.global_position + text.size * 0.5 - global_position
	var left_edge := text_center.x - text.size.x * 0.5
	var right_edge := text_center.x + text.size.x * 0.5
	var width := maxf(1.0, minf(left_edge, size.x - right_edge) - 24.0)
	var height := minf(size.y * 0.95, width * 1.8)
	var centers := [left_edge * 0.5, (right_edge + size.x) * 0.5]
	# With this camera, the model's base lies 90% down the portrait.
	# Anchor the actual cactus base just below the screen, not the portrait edge.
	var base_y := size.y + 12.0
	for index in range(2):
		_portraits[index].size = Vector2(width, height)
		_portraits[index].position = Vector2(centers[index] - width * 0.5, base_y - height * 0.9)
	# Extra boss-victory dancers occupy the middle, without resizing the cactuses.
	var cat_width := minf(size.x * 0.23, 320.0)
	var cat_height := minf(size.y * 0.65, cat_width * 1.8)
	for index in range(2, _portraits.size()):
		_portraits[index].size = Vector2(cat_width, cat_height)
		var center_x := size.x * (0.36 if index == 2 else 0.64)
		_portraits[index].position = Vector2(center_x - cat_width * 0.5, size.y - 32.0 - cat_height * 0.9)


func _update_visibility() -> void:
	var celebrating := is_visible_in_tree()
	_phase = 0.0
	_dance_time = 0.0
	_process(0.0)
	set_process(celebrating)
	if celebrating:
		_fit_overlay()
		_layout_portraits.call_deferred()
	for portrait in _portraits:
		var viewport := portrait.get_child(0) as SubViewport
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if celebrating else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_phase += delta * SWAY_SPEED
	_dance_time += delta
	for index in range(_dancers.size()):
		# Opposite phases make the pair lean toward and away from each other.
		_dancers[index].rotation.z = sin(_phase + index * PI) * SWAY_ANGLE
		if index >= 2:
			var dancer := _dancers[index]
			dancer.rotation.y = CAT_FACING_YAW + sin(_phase * 0.6 + index * PI) * 0.08
			dancer.position.y = absf(sin(_phase * 1.5 + index * PI)) * 0.25
			# Stagger their jumps, returning to face us after each full twirl.
			var cycle := fposmod(_dance_time + (1.8 if index == 3 else 0.0), CAT_TWIRL_INTERVAL)
			var twirl_start := CAT_TWIRL_INTERVAL - CAT_TWIRL_DURATION
			if cycle >= twirl_start:
				var progress := (cycle - twirl_start) / CAT_TWIRL_DURATION
				var direction := 1.0 if index == 2 else -1.0
				dancer.rotation.y += direction * TAU * smoothstep(0.0, 1.0, progress)
				dancer.position.y += sin(progress * PI) * 1.3
