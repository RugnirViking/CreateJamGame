extends Control

# The cactus's existing googly eyes face +Z, toward these portrait cameras.
const CACTUS := preload("res://art/models/cactus.glb")
const SWAY_SPEED := 3.2
const SWAY_ANGLE := 0.18

var _dancers: Array[Node3D] = []
var _portraits: Array[SubViewportContainer] = []
var _phase := 0.0


func _ready() -> void:
	name = "DancingCactuses"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_FILL
	size_flags_vertical = Control.SIZE_FILL
	for index in range(2):
		_add_dancer(index)
	visibility_changed.connect(_update_visibility)
	get_parent().resized.connect(_fit_overlay)
	resized.connect(_layout_portraits)
	get_parent().get_node("Text").item_rect_changed.connect(_layout_portraits.call_deferred)
	_update_visibility()
	_fit_overlay()
	_layout_portraits.call_deferred()


func _fit_overlay() -> void:
	# CenterContainer sizes children to their minimum size.
	custom_minimum_size = get_parent().size


func _add_dancer(index: int) -> void:
	var portrait := SubViewportContainer.new()
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
	dancer.add_child(CACTUS.instantiate())
	_dancers.append(dancer)


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


func _update_visibility() -> void:
	var celebrating := is_visible_in_tree()
	_phase = 0.0
	set_process(celebrating)
	if celebrating:
		_fit_overlay()
		_layout_portraits.call_deferred()
	for portrait in _portraits:
		var viewport := portrait.get_child(0) as SubViewport
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if celebrating else SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	_phase += delta * SWAY_SPEED
	for index in range(_dancers.size()):
		# Opposite phases make the pair lean toward and away from each other.
		_dancers[index].rotation.z = sin(_phase + index * PI) * SWAY_ANGLE
