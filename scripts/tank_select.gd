extends Control

const DESIGN_SIZE := Vector2(1280, 720)
const ACCENT := Color("c7cf9e")

@onready var interface: Control = $Interface
@onready var showroom: Node3D = $Interface/Preview/Viewport/World
@onready var camera: Camera3D = $Interface/Preview/Viewport/World/Camera
@onready var tank_name: Label = $Interface/TankName
@onready var tank_type: Label = $Interface/TankType

var selected_index := 0
var _previews: Array[Node3D] = []
var _stats: Array[Dictionary] = []
var _carousel_tween: Tween
var _deploying := false
var _elapsed := 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	selected_index = wrapi(int(get_tree().get_meta("selected_tank_index", 0)), 0, TankCatalog.TANKS.size())
	get_viewport().size_changed.connect(_fit_interface)
	_fit_interface()
	camera.look_at(Vector3(0.0, 0.15, 0.0))
	showroom.get_node("Spotlight").look_at(Vector3.ZERO)
	for i in TankCatalog.TANKS.size():
		var data := TankCatalog.read_tank(i)
		var holder := Node3D.new()
		holder.name = "Preview%d" % i
		var model := data.preview as Node3D
		holder.add_child(model)
		_set_preview_layers(model)
		showroom.add_child(holder)
		_previews.append(holder)
		data.erase("preview")
		_stats.append(data)
	$Interface/Previous.pressed.connect(_navigate.bind(-1))
	$Interface/Next.pressed.connect(_navigate.bind(1))
	$Interface/Deploy.pressed.connect(_deploy)
	_select(selected_index, false)
	$Interface/Deploy.grab_focus()
	interface.modulate.a = 0.0
	create_tween().tween_property(interface, "modulate:a", 1.0, 0.35)


func _fit_interface() -> void:
	var available := get_viewport_rect().size
	var factor := minf(available.x / DESIGN_SIZE.x, available.y / DESIGN_SIZE.y)
	interface.scale = Vector2.ONE * factor
	interface.position = (available - DESIGN_SIZE * factor) * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	if not _previews.is_empty():
		_previews[selected_index].rotation.y = -0.12 + sin(_elapsed * 0.4) * 0.12


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


func _select(index: int, animate: bool = true) -> void:
	if _deploying:
		return
	selected_index = index
	get_tree().set_meta("selected_tank_index", index)
	tank_name.text = TankCatalog.TANKS[index].name
	tank_type.text = TankCatalog.TANKS[index].type
	var data: Dictionary = _stats[index]
	_value("Forward", "%.1f km/h" % (data.forward_speed * 3.6))
	_value("Reverse", "%.1f km/h" % (data.reverse_speed * 3.6))
	_value("Power", String.num(data.engine_power, 2))
	_value("Traverse", "%s°/s" % String.num(data.turret_traverse, 2))
	_value("Elevation", "%s°/s" % String.num(data.gun_elevation, 2))
	_value("Arc", "%s° to %s°" % [String.num(data.min_elevation, 2), String.num(data.max_elevation, 2)])
	_value("HP", "%d HP" % data.max_hp)
	_value("Reload", "%s s" % String.num(data.reload_time, 2))
	if _carousel_tween:
		_carousel_tween.kill()
	_carousel_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT) if animate else null
	for i in _previews.size():
		var relative := wrapi(i - index + 2, 0, 5) - 2
		var target := Vector3(relative * 3.4, 0.37 if relative == 0 else 0.04, -absf(relative) * 1.4)
		var size := 1.8 if relative == 0 else 1.05
		var preview := _previews[i]
		preview.visible = absi(relative) <= 1
		if animate:
			_carousel_tween.tween_property(preview, "position", target, 0.42)
			_carousel_tween.tween_property(preview, "scale", Vector3.ONE * size, 0.42)
		else:
			preview.position = target
			preview.scale = Vector3.ONE * size


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
	get_tree().change_scene_to_file("res://scenes/main.tscn")
