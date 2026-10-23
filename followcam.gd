extends Node3D

@onready var tank: Node3D = $"../vehicle"
@onready var camera: Node3D = $"3dpersoncam"
@onready var camera_offset: Vector3 = camera.position
@onready var rot_max_speed: float = 0.8;
@onready var rot_acc: float = 0.8;


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
	camera.position = camera_offset * zoom_amount;
	tank_rotation = tank.rotation;
	
	var yRot = rotation.y;
	var targetYRot = tank_rotation.y;
	
	rotation.y = rotate_toward(yRot, targetYRot, rot_speed * delta)
