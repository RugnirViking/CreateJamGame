extends Node3D

@onready var tank: playertank_tracks = $"../vehicle"
@onready var turret: Node3D = $"../vehicle/tank1/TurretRotation"
@onready var camera: Camera3D = $"3dpersoncam"
@onready var camera_offset: Vector3 = camera.position
@onready var rot_max_speed: float = 0.8;
@onready var rot_acc: float = 0.8;

@onready var speed_zoom_mult: float = 0.04;
@onready var speed_fov_mult: float = 0.18;
@onready var speed_rot_speed_mult: float = 0.08;

var zoom_amount := 1.0
var rot_speed: float = 0.8;
var tank_rotation: Vector3

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	global_position = tank.global_position;
	tank_rotation = tank.rotation
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		zoom_amount -= 0.1;
	if event.is_action_pressed("zoom_out"):
		zoom_amount += 0.1;
	zoom_amount = clampf(zoom_amount, 0.4, 3.0)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	global_position = tank.global_position;
	camera.position = camera_offset * zoom_amount * (1+speed_zoom_mult*tank.linear_velocity.length());
	camera.fov = 75 + (1+speed_fov_mult*tank.linear_velocity.length())*30

	tank_rotation = tank.rotation;
	
	var yRot = rotation.y;
	var targetYRot = tank_rotation.y;
	if tank.throttle<0:
		targetYRot = tank_rotation.y+PI;
	
	rotation.y = rotate_toward(yRot, targetYRot, rot_speed * delta * (1+speed_rot_speed_mult*tank.linear_velocity.length()))
	
	
	# 1. Get mouse position on the viewport
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()

	# 2. Build a ray from the camera
	var ray_origin: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = camera.project_ray_normal(mouse_pos)

	# 3. Create a horizontal plane at the character's height
	var plane: Plane = Plane(Vector3.UP, global_position.y)

	# 4. Find where the ray intersects the plane
	var intersection = plane.intersects_ray(ray_origin, ray_normal)
	
	if intersection != null:
		# Lock rotation to the Y-axis so the character doesn't tilt up or down
		var target_pos: Vector3 = Vector3(intersection.x, global_position.y, intersection.z)
		turret.look_at(target_pos, Vector3.UP)
		turret.rotation.y-=PI/2
		turret.rotation.x=0
		turret.rotation.z=0
	else:
		var max_distance: float = 1000.0
		var target_pos = ray_origin + (ray_normal * max_distance)
		
		turret.look_at(target_pos, Vector3.UP)
		turret.rotation.y-=PI/2
		turret.rotation.x=0
		turret.rotation.z=0
