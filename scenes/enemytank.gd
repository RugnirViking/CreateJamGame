class_name enemytank_tracks
extends VehicleBody3D


@export_range(1, 100) var hits_to_destroy: int = 5
@export_range(0.0, 360.0, 1.0) var turret_traverse_speed := 30.0 # Degrees per second; player uses 60.
@export_range(0.0, 180.0, 1.0) var gun_elevation_speed := 15.0 # Degrees per second; player uses 30.
@export_range(-90.0, 0.0, 1.0) var min_gun_elevation := -15.0
@export_range(0.0, 90.0, 1.0) var max_gun_elevation := 45.0
@export var shell_scene: PackedScene = preload("res://scenes/shell.tscn")
@export_range(0.1, 10.0, 0.1) var fire_interval := 1.5
@export_range(0.0, 180.0, 0.1) var fire_angle_degrees := 10.0

@export_group("Scene References")
@export_node_path("Node3D") var model_path := NodePath("Model")
@export_node_path("Node3D") var wreck_path := NodePath("Wreck")
@export_node_path("Node3D") var turret_path := NodePath("Model/TurretRotation")
@export_node_path("Node3D") var gun_elevation_path := NodePath("Model/TurretRotation/GunElevation")

@onready var active_model: Node3D = get_node(model_path)
@onready var active_wreck: Node3D = get_node(wreck_path)
@onready var turret: Node3D = get_node(turret_path)
@onready var gun_elevation: Node3D = get_node(gun_elevation_path)
@onready var muzzle: Marker3D = gun_elevation.get_node("Muzzle")

@onready var playertank: playertank_tracks = get_tree().current_scene.get_node_or_null("playertank/vehicle") as playertank_tracks

var shell_hits: int = 0
var destroyed: bool = false
var _health_bar: Sprite3D
var _fire_cooldown := 0.0


func _ready() -> void:
	_darken_wreck(active_wreck)
	_health_bar = Sprite3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = Vector3(0.25, 0.85, 0.0)
	_health_bar.pixel_size = 0.008
	_health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar.shaded = false
	_health_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_health_bar)
	_update_health_bar()


func _physics_process(delta: float) -> void:
	if destroyed or not is_instance_valid(playertank):
		return
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	# Aim at the player's hull center, slightly above its vehicle origin.
	var target := playertank.to_global(Vector3(0.0, 0.25, 0.0))
	# Aim in the hull's frame so tracking also works on slopes.
	var local_target := turret.get_parent_node_3d().to_local(target) - turret.position
	if Vector2(local_target.x, local_target.z).length_squared() > 0.000001:
		# Like the player's tank, this barrel faces local -X.
		var target_yaw := atan2(local_target.z, -local_target.x)
		turret.rotation.y = rotate_toward(
			turret.rotation.y, target_yaw, deg_to_rad(turret_traverse_speed) * delta
		)

	var gun_target := gun_elevation.get_parent_node_3d().to_local(target) - gun_elevation.position
	if gun_target.length_squared() > 0.000001:
		var horizontal_distance := Vector2(gun_target.x, gun_target.z).length()
		var pitch := clampf(
			atan2(gun_target.y, horizontal_distance),
			deg_to_rad(min_gun_elevation), deg_to_rad(max_gun_elevation)
		)
		gun_elevation.rotation.z = rotate_toward(
			gun_elevation.rotation.z, -pitch, deg_to_rad(gun_elevation_speed) * delta
		)

	# Check the actual barrel direction in 3D, including elevation.
	var to_player := target - muzzle.global_position
	if _fire_cooldown <= 0.0 and to_player.length_squared() > 0.000001:
		var barrel_forward := -muzzle.global_basis.x.normalized()
		if barrel_forward.dot(to_player.normalized()) >= cos(deg_to_rad(fire_angle_degrees)):
			_spawn_shell()


func _spawn_shell() -> void:
	if shell_scene == null:
		return
	var projectile := shell_scene.instantiate() as Node3D
	projectile.set("shooter", self)
	get_tree().current_scene.add_child(projectile)
	projectile.global_transform = muzzle.global_transform
	_fire_cooldown = fire_interval


func _darken_wreck(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var source := node.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			# Isolate the tint so imported materials and intact tanks stay unchanged.
			var material := source.duplicate() as BaseMaterial3D
			material.albedo_color = Color(source.albedo_color.r * 0.5,
				source.albedo_color.g * 0.5, source.albedo_color.b * 0.5,
				source.albedo_color.a)
			node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_darken_wreck(child)


func _update_health_bar() -> void:
	var remaining := clampf(1.0 - float(shell_hits) / hits_to_destroy, 0.0, 1.0)
	var image := Image.create(128, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.04, 0.04, 0.04, 1.0))
	image.fill_rect(Rect2i(2, 2, 124, 12), Color(0.22, 0.08, 0.06, 1.0))
	if remaining > 0.0:
		var color := Color(0.2, 0.85, 0.25).lerp(Color(0.95, 0.18, 0.08), 1.0 - remaining)
		image.fill_rect(Rect2i(2, 2, roundi(124 * remaining), 12), color)
	_health_bar.texture = ImageTexture.create_from_image(image)
	_health_bar.visible = remaining > 0.0


func receive_shell_hit() -> void:
	if destroyed:
		return
	shell_hits += 1
	_update_health_bar()
	if shell_hits < hits_to_destroy:
		return
	destroyed = true
	active_model.hide()
	active_wreck.show()
	$EngineSound.stop()
	$left_track_particles.emitting = false
	$right_track_particles.emitting = false
	engine_force = 0.0
	brake = 100.0
