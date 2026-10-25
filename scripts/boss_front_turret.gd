extends Node3D

@export_range(-180.0, 180.0, 1.0) var min_yaw_degrees := -25.0
@export_range(-180.0, 180.0, 1.0) var max_yaw_degrees := 110.0
@export_range(0.1, 10.0, 0.1) var fire_interval := 2.2
@export_range(0.0, 10.0, 0.1) var initial_fire_delay := 0.0

@onready var boss: enemytank_tracks = get_node("../../..")
@onready var gun: Node3D = $Cube_004/GunElevation
@onready var muzzle: Marker3D = $Cube_004/GunElevation/Muzzle

var _cooldown := 0.0


func _ready() -> void:
	_cooldown = initial_fire_delay


func _physics_process(delta: float) -> void:
	if boss.destroyed or boss.is_spin_attacking() or not is_instance_valid(boss.playertank):
		return
	if boss.playertank.destroyed or boss.playertank.you_win.visible:
		return
	_cooldown = maxf(0.0, _cooldown - delta)
	var target := boss.playertank.to_global(Vector3(0.0, 0.25, 0.0))
	# The mount's frame stays fixed to the hull, including on sloping terrain.
	var local_target := get_parent_node_3d().to_local(target) - position
	var yaw := atan2(local_target.z, -local_target.x)
	var min_yaw := deg_to_rad(min_yaw_degrees)
	var max_yaw := deg_to_rad(max_yaw_degrees)
	rotation.y = rotate_toward(rotation.y, clampf(yaw, min_yaw, max_yaw),
		deg_to_rad(boss.turret_traverse_speed) * delta)
	var gun_target := gun.get_parent_node_3d().to_local(target) - gun.position
	var pitch := atan2(gun_target.y, Vector2(gun_target.x, gun_target.z).length())
	gun.rotation.z = rotate_toward(gun.rotation.z,
		-clampf(pitch, deg_to_rad(boss.min_gun_elevation), deg_to_rad(boss.max_gun_elevation)),
		deg_to_rad(boss.gun_elevation_speed) * delta)
	# Enforce the arc independently of aiming tolerance at the traverse stops.
	if yaw < min_yaw or yaw > max_yaw or _cooldown > 0.0:
		return
	var to_target := target - muzzle.global_position
	if to_target.length_squared() < 0.000001 or to_target.length() > boss.max_range:
		return
	if -muzzle.global_basis.x.normalized().dot(to_target.normalized()) < cos(deg_to_rad(boss.fire_angle_degrees)):
		return
	if boss.shell_scene == null:
		return
	var projectile := boss.shell_scene.instantiate() as Node3D
	projectile.set("shooter", boss)
	get_tree().current_scene.add_child(projectile)
	projectile.global_transform = muzzle.global_transform
	_cooldown = fire_interval
