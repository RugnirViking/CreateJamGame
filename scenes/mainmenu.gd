extends Control

@export var duration: float = 2.0 
@export var title_rise: float = 150.0
@export var title_rise_duration: float = 0.8
@export var button_fade_duration: float = 0.45
@onready var titleLabel : Label = $Title
@onready var crosshair : TextureRect = $CrosshairNobg
@onready var boom_sound: AudioStreamPlayer = $AudioStreamPlayer
@onready var title_theme: AudioStreamPlayer = $titlemusic
@onready var menu_buttons: VBoxContainer = $MenuButtons
@onready var controls_dialog: AcceptDialog = $ControlsDialog
@onready var menu_camera: Camera3D = $Camera3D
@onready var turret: Node3D = $enemytank/tank2/TurretRotation
@onready var gun_elevation: Node3D = $enemytank/tank2/TurretRotation/Cube_004/GunElevation


func _process(delta: float) -> void:
	_aim_at_mouse(get_viewport().get_mouse_position(), delta)


func _aim_at_mouse(mouse_position: Vector2, delta: float) -> void:
	# Put the cursor's target in front of the tank so it turns toward the screen.
	var plane_origin := turret.global_position.lerp(menu_camera.global_position, 0.5)
	var aim_plane := Plane(menu_camera.global_basis.z, plane_origin)
	var intersection: Variant = aim_plane.intersects_ray(
		menu_camera.project_ray_origin(mouse_position),
		menu_camera.project_ray_normal(mouse_position)
	)
	if intersection == null:
		return
	var target: Vector3 = intersection
	var local_target := turret.get_parent_node_3d().to_local(target) - turret.position
	if Vector2(local_target.x, local_target.z).length_squared() > 0.000001:
		# The tank model's barrel points along local -X.
		var target_yaw := atan2(local_target.z, -local_target.x)
		turret.rotation.y = rotate_toward(turret.rotation.y, target_yaw, deg_to_rad(180.0) * delta)
	var gun_target := gun_elevation.get_parent_node_3d().to_local(target) - gun_elevation.position
	if gun_target.length_squared() > 0.000001:
		var pitch := atan2(gun_target.y, Vector2(gun_target.x, gun_target.z).length())
		gun_elevation.rotation.z = rotate_toward(gun_elevation.rotation.z, -pitch, deg_to_rad(90.0) * delta)


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	titleLabel.visible_characters = 0
	crosshair.visible = false
	for button: Button in menu_buttons.get_children():
		button.modulate.a = 0.0
		button.disabled = true
	$MenuButtons/Play.pressed.connect(_on_play_pressed)
	$MenuButtons/Controls.pressed.connect(controls_dialog.popup_centered)
	$MenuButtons/Quit.pressed.connect(get_tree().quit)
	if get_tree().get_meta("skip_menu_intro", false):
		get_tree().remove_meta("skip_menu_intro")
		titleLabel.visible_characters = -1
		crosshair.visible = true
		titleLabel.position.y -= title_rise
		crosshair.position.y -= title_rise
		for button: Button in menu_buttons.get_children():
			button.modulate.a = 1.0
			button.disabled = false
		$MenuButtons/Play.grab_focus()
		title_theme.play()
		return
	# Let each boom finish while later letters play their own sound.
	boom_sound.max_polyphony = titleLabel.get_total_character_count() + 1
	
	# Create a tween to animate visible_characters up to the total character count
	var tween = create_tween()
	tween.tween_method(
		_reveal_characters,
		0,
		titleLabel.get_total_character_count(), 
		duration
	)
	await tween.finished
	await get_tree().create_timer(0.5).timeout
	crosshair.visible = true
	boom_sound.play()
	title_theme.play()
	await _show_menu()


func _show_menu() -> void:
	var rise_tween := create_tween().set_parallel(true)
	rise_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	rise_tween.tween_property(titleLabel, "position:y", titleLabel.position.y - title_rise, title_rise_duration)
	rise_tween.tween_property(crosshair, "position:y", crosshair.position.y - title_rise, title_rise_duration)
	await rise_tween.finished

	var fade_tween := create_tween()
	for button: Button in menu_buttons.get_children():
		fade_tween.tween_property(button, "modulate:a", 1.0, button_fade_duration)
	await fade_tween.finished
	for button: Button in menu_buttons.get_children():
		button.disabled = false
	$MenuButtons/Play.grab_focus()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _reveal_characters(character_count: int) -> void:
	for character_index in range(titleLabel.visible_characters, character_count):
		if not titleLabel.text[character_index].strip_edges().is_empty():
			boom_sound.play()
	titleLabel.visible_characters = character_count
