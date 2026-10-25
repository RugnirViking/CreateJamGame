extends "res://scripts/tank_select.gd"

const Levels = preload("res://scripts/level_catalog.gd")

var _tank_preview: Node3D


func _ready() -> void:
	MenuMusic.play_if_stopped()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	selected_index = wrapi(int(get_tree().get_meta("selected_level_index", 0)), 0, Levels.LEVELS.size())
	get_viewport().size_changed.connect(_fit_interface)
	_fit_interface()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.69, 0.62, 0.43)
	material.roughness = 1.0
	for i in Levels.LEVELS.size():
		var world := interface.get_node("Tank%d/Preview/Viewport/World" % i) as Node3D
		var camera := world.get_node("Camera") as Camera3D
		camera.position = Vector3(-170, 210, 250)
		camera.look_at(Vector3.ZERO)
		camera.size = 1000.0
		var holder := Node3D.new()
		holder.name = "Terrain"
		var terrain := MeshInstance3D.new()
		terrain.mesh = Levels.preview_mesh(i)
		terrain.material_override = material
		terrain.position.y = -10.0
		holder.add_child(terrain)
		world.add_child(holder)
		_previews.append(holder)
		var button := interface.get_node("Tank%d/Select" % i) as Button
		button.pressed.connect(_select.bind(i))
		button.tooltip_text = Levels.LEVELS[i].name
		var stamp := TextureRect.new()
		stamp.name = "CompletedStamp"
		stamp.texture = preload("res://art/textures/checkmark.png")
		stamp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stamp.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		stamp.position = Vector2(136, 12)
		stamp.size = Vector2(76, 76)
		stamp.modulate = Color(0.78039217, 0.8117647, 0.61960787, 1)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stamp.visible = Levels.is_completed(Levels.LEVELS[i].path)
		interface.get_node("Tank%d" % i).add_child(stamp)
	_build_tank_preview()
	$Interface/Deploy.pressed.connect(_deploy)
	_select(selected_index)
	$Interface/Deploy.grab_focus()


func _build_tank_preview() -> void:
	var index := wrapi(int(get_tree().get_meta("selected_tank_index", 0)), 0, TankCatalog.TANKS.size())
	var data := TankCatalog.read_tank(index)
	var model := data.preview as Node3D
	_tank_preview = Node3D.new()
	_tank_preview.name = "Model"
	_tank_preview.add_child(model)
	_set_preview_layers(model)
	var bounds: Array[AABB] = []
	_collect_bounds(model, Transform3D.IDENTITY, bounds)
	var combined := bounds[0]
	for bound in bounds:
		combined = combined.merge(bound)
	model.position -= combined.get_center()
	var world := $Interface/SelectedTank/Preview/Viewport/World
	world.add_child(_tank_preview)
	var camera := world.get_node("Camera") as Camera3D
	camera.look_at(Vector3.ZERO)
	camera.size = maxf(Vector2(combined.size.x, combined.size.z).length(), combined.size.y) * 1.2
	$Interface/SelectedTank.tooltip_text = TankCatalog.TANKS[index].name


func _process(delta: float) -> void:
	super._process(delta)
	_tank_preview.rotation.y = _elapsed * preview_turn_speed


func _navigate(direction: int) -> void:
	_select(wrapi(selected_index + direction, 0, Levels.LEVELS.size()))


func _select(index: int) -> void:
	if _deploying:
		return
	selected_index = index
	get_tree().set_meta("selected_level_index", index)
	tank_name.text = Levels.LEVELS[index].name
	$Interface/Stats/Description.text = Levels.LEVELS[index].description
	_pulse_elapsed = 0.0
	for i in _previews.size():
		_previews[i].scale = Vector3.ONE * pulse_min_scale
		var button := interface.get_node("Tank%d/Select" % i) as Button
		button.set_pressed_no_signal(i == index)


func _back() -> void:
	if not _deploying:
		get_tree().change_scene_to_file("res://scenes/tank_select.tscn")


func _deploy() -> void:
	if _deploying:
		return
	_deploying = true
	var tank_index := wrapi(int(get_tree().get_meta("selected_tank_index", 0)), 0, TankCatalog.TANKS.size())
	get_tree().set_meta("selected_player_scene", TankCatalog.TANKS[tank_index].path)
	$Interface/Deploy.disabled = true
	$Interface/Deploy.text = "DEPLOYING…"
	await get_tree().process_frame
	MenuMusic.stop()
	get_tree().change_scene_to_file(Levels.LEVELS[selected_index].path)
