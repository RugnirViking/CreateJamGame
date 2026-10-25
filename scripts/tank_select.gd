extends Control

const DESIGN_SIZE := Vector2(1280, 720)

@onready var interface: Control = $Interface
@onready var tank_name: Label = $Interface/TankName

@export var pulse_min_scale := 1.5
@export var pulse_max_scale := 3.0
@export var pulse_period := 1.0
@export var preview_turn_speed := 0.2
@export_color_no_alpha var preview_background_color := Color.BLACK:
	set(value):
		preview_background_color = value
		if is_node_ready():
			_apply_preview_background()

var selected_index := 0
var _previews: Array[Node3D] = []
var _stats: Array[Dictionary] = []
var _deploying := false
var _elapsed := 0.0
var _pulse_elapsed := 0.0


func _ready() -> void:
	MenuMusic.play_if_stopped()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	selected_index = wrapi(int(get_tree().get_meta("selected_tank_index", 0)), 0, TankCatalog.TANKS.size())
	get_viewport().size_changed.connect(_fit_interface)
	_fit_interface()
	_apply_preview_background()
	for i in TankCatalog.TANKS.size():
		var data := TankCatalog.read_tank(i)
		var world := interface.get_node("Tank%d/Preview/Viewport/World" % i) as Node3D
		var camera := world.get_node("Camera") as Camera3D
		camera.look_at(Vector3.ZERO)
		var holder := Node3D.new()
		holder.name = "Model"
		var model := data.preview as Node3D
		holder.add_child(model)
		_set_preview_layers(model)
		var bounds: Array[AABB] = []
		_collect_bounds(model, Transform3D.IDENTITY, bounds)
		var combined := bounds[0]
		for bound in bounds:
			combined = combined.merge(bound)
		model.position -= combined.get_center()
		# Frame the full rotation at the largest pulse without clipping the square.
		camera.size = maxf(Vector2(combined.size.x, combined.size.z).length(), combined.size.y) * pulse_max_scale * 1.08
		world.add_child(holder)
		_previews.append(holder)
		data.erase("preview")
		_stats.append(data)
		var button := interface.get_node("Tank%d/Select" % i) as Button
		button.pressed.connect(_select.bind(i))
		button.tooltip_text = TankCatalog.TANKS[i].name
	$Interface/Deploy.pressed.connect(_deploy)
	_select(selected_index)
	$Interface/Deploy.grab_focus()


func _apply_preview_background() -> void:
	for i in TankCatalog.TANKS.size():
		var world_environment := interface.get_node("Tank%d/Preview/Viewport/World/Environment" % i) as WorldEnvironment
		var environment := world_environment.environment.duplicate() as Environment
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = preview_background_color
		world_environment.environment = environment


func _fit_interface() -> void:
	var available := get_viewport_rect().size
	var factor := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	interface.scale = Vector2.ONE * factor
	interface.position = (available - DESIGN_SIZE * factor) * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	_pulse_elapsed += delta
	for i in _previews.size():
		_previews[i].rotation.y = _elapsed * preview_turn_speed
		var multiplier := pulse_min_scale
		if i == selected_index:
			multiplier = pulse_scale_at(_pulse_elapsed)
		_previews[i].scale = Vector3.ONE * multiplier


func pulse_scale_at(seconds: float) -> float:
	var phase := seconds / maxf(pulse_period, 0.001)
	return lerpf(pulse_min_scale, pulse_max_scale, (1.0 - cos(TAU * phase)) * 0.5)


func _collect_bounds(node: Node3D, parent_pose: Transform3D, bounds: Array[AABB]) -> void:
	var pose := parent_pose * node.transform
	if node is MeshInstance3D:
		bounds.append(pose * node.get_aabb())
	for child in node.get_children():
		if child is Node3D:
			_collect_bounds(child, pose, bounds)


func _input(event: InputEvent) -> void:
	if _deploying or event.is_echo():
		return
	var viewport := get_viewport()
	if event.is_action_pressed("ui_left") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_A):
		_navigate(-1)
	elif event.is_action_pressed("ui_right") or (event is InputEventKey and event.pressed and event.physical_keycode == KEY_D):
		_navigate(1)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("return_action"):
		_back()
	else:
		return
	viewport.set_input_as_handled()


func _navigate(direction: int) -> void:
	_select(wrapi(selected_index + direction, 0, TankCatalog.TANKS.size()))


func _select(index: int) -> void:
	if _deploying:
		return
	selected_index = index
	get_tree().set_meta("selected_tank_index", index)
	tank_name.text = TankCatalog.TANKS[index].name
	var data: Dictionary = _stats[index]
	_value("Forward", "%.1f km/h" % (data.forward_speed * 3.6))
	_value("Reverse", "%.1f km/h" % (data.reverse_speed * 3.6))
	_value("Power", String.num(data.engine_power, 2))
	_value("Traverse", "%s°/s" % String.num(data.turret_traverse, 2))
	_value("Elevation", "%s°/s" % String.num(data.gun_elevation, 2))
	_value("Arc", "%s° to %s°" % [String.num(data.min_elevation, 2), String.num(data.max_elevation, 2)])
	_value("HP", "%d HP" % data.max_hp)
	_value("Reload", "%s s" % String.num(data.reload_time, 2))
	_pulse_elapsed = 0.0
	for i in _previews.size():
		_previews[i].scale = Vector3.ONE * pulse_min_scale
		var button := interface.get_node("Tank%d/Select" % i) as Button
		button.set_pressed_no_signal(i == index)


func _value(row: String, value: String) -> void:
	interface.get_node("Stats/%s/Value" % row).text = value


func _set_preview_layers(node: Node) -> void:
	if node is MeshInstance3D:
		node.layers = 1
	for child in node.get_children():
		_set_preview_layers(child)


func _back() -> void:
	if _deploying:
		return
	get_tree().set_meta("skip_menu_intro", true)
	get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")


func _deploy() -> void:
	if _deploying:
		return
	_deploying = true
	get_tree().set_meta("selected_player_scene", TankCatalog.TANKS[selected_index].path)
	$Interface/Deploy.disabled = true
	$Interface/Deploy.text = "DEPLOYING…"
	# Paint feedback before the level's terrain and scatter load.
	await get_tree().process_frame
	MenuMusic.stop()
	get_tree().change_scene_to_file("res://scenes/main.tscn")
