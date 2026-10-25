extends Node3D

const MIN_ZOOM := 0.4
const MAX_ZOOM := 3.0
# Ten percent above the fastest configured player tanks (6 m/s).
const SPEED_FOV_LIMIT := 6.6

@export_range(0.0, 360.0, 1.0) var turret_traverse_speed := 60.0 # Degrees per second.
@export_range(0.0, 180.0, 1.0) var gun_elevation_speed := 30.0 # Degrees per second.
@export_range(-90.0, 0.0, 1.0) var min_gun_elevation := -15.0
@export_range(0.0, 90.0, 1.0) var max_gun_elevation := 45.0
@export var aim_distance := 1000.0
@export_flags_3d_physics var aim_collision_mask: int = 1
@export_range(0.01, 1.0, 0.01) var sniper_mouse_sensitivity := 0.12 # Degrees per pixel.
@export_range(10.0, 70.0, 1.0) var sniper_fov := 35.0
@export var sniper_camera_offset := Vector3(0.0, 0.08, 0.0)
@export_group("Sniper Stabilization")
@export_range(1.0, 40.0, 0.5) var sniper_horizontal_response := 20.0
@export_range(1.0, 40.0, 0.5) var sniper_vertical_response := 6.0
@export_range(1.0, 40.0, 0.5) var sniper_hull_rotation_response := 5.0

@onready var tank: playertank_tracks = $"../vehicle"
@onready var turret: Node3D = tank.turret
@onready var gun_elevation: Node3D = tank.gun_elevation
@onready var muzzle: Marker3D = tank.muzzle
@onready var crosshair: TextureRect = $"../AimHUD/Crosshair"
@onready var camera: Camera3D = $"3dpersoncam"
@onready var sniper_camera: Camera3D = $"../vehicle/snipercam"
@onready var sniper_hud: Control = $"../AimHUD/SniperHUD"
@onready var camera_offset: Vector3 = camera.position
@onready var rot_max_speed: float = 0.8;
@onready var rot_acc: float = 0.8;

@onready var speed_zoom_mult: float = 0.04;
@onready var speed_fov_mult: float = 0.18;
@onready var speed_rot_speed_mult: float = 0.08;

var zoom_amount := 1.0
var rot_speed: float = 0.8;
var tank_rotation: Vector3
var aim_point := Vector3.ZERO
var gun_aim_point := Vector3.ZERO
var has_aim_point := false
var sniper_mode := false
var sniper_yaw := 0.0
var sniper_pitch := 0.0
var _previous_mouse_mode := Input.MOUSE_MODE_VISIBLE
var _previous_mouse_position := Vector2.ZERO
var _sniper_hull_basis := Basis.IDENTITY
var _sniper_mount_offset := Vector3.ZERO

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	global_position = tank.global_position;
	tank_rotation = tank.rotation
	sniper_camera.top_level = true
	_sniper_mount_offset = tank.to_local(gun_elevation.global_position)
	
func _unhandled_input(event: InputEvent) -> void:
	if tank.you_win.visible and event.is_action_pressed("next_level"):
		return
	if tank.destroyed:
		return
	if sniper_mode and event.is_action_pressed("return_action"):
		zoom_amount = MIN_ZOOM + 0.1
		_set_sniper_mode(false)
		get_viewport().set_input_as_handled()
		return
	if sniper_mode and event is InputEventMouseMotion:
		# Captured mode keeps the cursor centered; use unscaled physical movement.
		_apply_sniper_mouse(event.screen_relative)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("zoom_in"):
		zoom_amount -= 0.1;
	elif event.is_action_pressed("zoom_out"):
		zoom_amount += 0.1;
	else:
		return
	zoom_amount = clampf(zoom_amount, MIN_ZOOM, MAX_ZOOM)
	_set_sniper_mode(zoom_amount <= MIN_ZOOM + 0.0001)
	get_viewport().set_input_as_handled()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	global_position = tank.global_position;
	camera.position = camera_offset * zoom_amount * (1+speed_zoom_mult*tank.linear_velocity.length());
	var fov_speed := minf(tank.linear_velocity.length(), SPEED_FOV_LIMIT)
	camera.fov = 75 + (1+speed_fov_mult*fov_speed)*30

	tank_rotation = tank.rotation;
	
	var yRot = rotation.y;
	var targetYRot = tank_rotation.y;
	if tank.throttle<0:
		targetYRot = tank_rotation.y+PI;
	
	# Temporarily double the rotation limit when more than a quarter-turn behind.
	var angle_gap := absf(wrapf(targetYRot - yRot, -PI, PI))
	rot_speed = rot_max_speed * (2.0 if angle_gap > PI / 2.0 else 1.0)

	rotation.y = rotate_toward(yRot, targetYRot, rot_speed * delta * (1+speed_rot_speed_mult*tank.linear_velocity.length()))
	if sniper_mode:
		_sync_sniper_camera(delta)
	sniper_hud.update_aim(turret.rotation.y, -gun_elevation.rotation.z)
	_update_crosshair()


func _physics_process(delta: float) -> void:
	var active_camera := get_aim_camera()
	var mouse_pos := get_viewport().get_visible_rect().size * 0.5 if sniper_mode else get_viewport().get_mouse_position()
	var ray_origin := active_camera.project_ray_origin(mouse_pos)
	var ray_direction := active_camera.project_ray_normal(mouse_pos)
	aim_point = _ray_target(ray_origin, ray_direction)
	has_aim_point = true
	# The gun follows the camera's ray at its mechanical traverse/elevation speeds.
	_aim_at(aim_point, delta)
	# This is the gun's current impact point, distinct from the mouse command.
	gun_aim_point = _ray_target(muzzle.global_position, -muzzle.global_basis.x.normalized())


func _ray_target(origin: Vector3, direction: Vector3) -> Vector3:
	var ray_end := origin + direction * aim_distance
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, aim_collision_mask, [tank.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("position", ray_end)


func _aim_at(target: Vector3, delta: float) -> void:
	# Work in the hull's frame so hills and hull rotation do not tilt the turret.
	var local_target := turret.get_parent_node_3d().to_local(target) - turret.position
	if Vector2(local_target.x, local_target.z).length_squared() > 0.000001:
		# The model's barrel points along local -X, rather than Godot's -Z.
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
		# Elevating a -X barrel means rotating around local -Z.
		gun_elevation.rotation.z = rotate_toward(
			gun_elevation.rotation.z, -pitch, deg_to_rad(gun_elevation_speed) * delta
		)


func _update_crosshair() -> void:
	var active_camera := get_aim_camera()
	crosshair.visible = has_aim_point and not active_camera.is_position_behind(gun_aim_point)
	if crosshair.visible:
		crosshair.position = active_camera.unproject_position(gun_aim_point) - crosshair.size * 0.5


func get_aim_camera() -> Camera3D:
	return sniper_camera if sniper_mode else camera


func _set_sniper_mode(enabled: bool) -> void:
	if sniper_mode == enabled:
		return
	sniper_mode = enabled
	has_aim_point = false
	crosshair.visible = false
	if enabled:
		sniper_yaw = turret.rotation.y
		sniper_pitch = -gun_elevation.rotation.z
		_previous_mouse_mode = Input.mouse_mode
		_previous_mouse_position = get_viewport().get_mouse_position()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_sync_sniper_camera(0.0, true)
		sniper_camera.make_current()
		sniper_hud.update_aim(turret.rotation.y, sniper_pitch)
	else:
		camera.make_current()
		Input.mouse_mode = _previous_mouse_mode
		if _previous_mouse_mode == Input.MOUSE_MODE_VISIBLE:
			Input.warp_mouse(_previous_mouse_position)


func _apply_sniper_mouse(relative: Vector2) -> void:
	var sensitivity := deg_to_rad(sniper_mouse_sensitivity)
	# Mouse deltas change the camera aim immediately; the gun follows in physics.
	sniper_yaw = wrapf(sniper_yaw - relative.x * sensitivity, -PI, PI)
	sniper_pitch = clampf(sniper_pitch - relative.y * sensitivity,
		deg_to_rad(min_gun_elevation), deg_to_rad(max_gun_elevation))
	_sync_sniper_camera(0.0)


func _sync_sniper_camera(delta: float, snap: bool = false) -> void:
	var hull_basis := tank.global_basis.orthonormalized()
	# A fixed hull mount prevents the camera drifting as the turret catches up.
	var target_position := tank.global_position + hull_basis * (_sniper_mount_offset + sniper_camera_offset)
	var position := sniper_camera.global_position
	# Initialize on entry and reset after teleports, without a fly-in from the old view.
	if snap or position.distance_squared_to(target_position) > 25.0:
		position = target_position
		_sniper_hull_basis = hull_basis
	else:
		var horizontal_weight := 1.0 - exp(-sniper_horizontal_response * delta)
		position.x = lerpf(position.x, target_position.x, horizontal_weight)
		position.z = lerpf(position.z, target_position.z, horizontal_weight)
		position.y = lerpf(position.y, target_position.y, 1.0 - exp(-sniper_vertical_response * delta))
		_sniper_hull_basis = _sniper_hull_basis.slerp(
			hull_basis, 1.0 - exp(-sniper_hull_rotation_response * delta))
	# Stabilize hull motion while keeping the FPS camera independent of the gun.
	var camera_aim := Basis(Vector3.UP, sniper_yaw) * Basis(Vector3.FORWARD, sniper_pitch)
	var stabilized_aim := _sniper_hull_basis * camera_aim
	var forward := -stabilized_aim.x.normalized()
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.999:
		up = forward.cross(stabilized_aim.z).normalized()
	sniper_camera.global_transform = Transform3D(
		Basis.looking_at(forward, up), position
	)
	sniper_camera.fov = sniper_fov


func _exit_tree() -> void:
	if sniper_mode:
		Input.mouse_mode = _previous_mouse_mode


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and sniper_mode:
		zoom_amount = MIN_ZOOM + 0.1
		_set_sniper_mode(false)
