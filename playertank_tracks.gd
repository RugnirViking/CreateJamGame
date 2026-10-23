extends VehicleBody3D

# The model faces -X, so its left track is on local +Z.
@export var engine_force_value := 25.0
@export var max_forward_speed := 3.0
@export var max_reverse_speed := 1.8
@export var max_turn_speed := 1.5 # Radians per second; also applies when reversing.
@export var drive_response := 3.0
@export var turn_response := 2.0
@export var idle_brake := 1.5
@export var turning_grip := 0.5

var wheels: Array[VehicleWheel3D] = []
var wheel_sides: Array[float] = []
var wheel_grip: Array[float] = []
var track_half_width := 0.0
var previous_speed := 0.0

@onready var engine_sound: AudioStreamPlayer = $EngineSound
@onready var impact_sound: AudioStreamPlayer = $ImpactSound

func _ready() -> void:
	for child in get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
			wheel_sides.append(signf(child.position.z))
			wheel_grip.append(child.wheel_friction_slip)
			track_half_width = maxf(track_half_width, absf(child.position.z))
			child.use_as_steering = false
			child.steering = 0.0

func _physics_process(delta: float) -> void:
	var throttle := Input.get_axis(&"reverse", &"accelerate")
	var turn := Input.get_axis(&"turn_right", &"turn_left")
	var forward := -global_basis.x.normalized()
	var up := global_basis.y.normalized()
	var target_speed := throttle * (max_forward_speed if throttle >= 0.0 else max_reverse_speed)
	var target_yaw := turn * max_turn_speed
	var yaw_speed := angular_velocity.dot(up)
	var turning := clampf(maxf(absf(turn), absf(yaw_speed) / maxf(max_turn_speed, 0.01)), 0.0, 1.0)
	var left_grounded := false
	var right_grounded := false
	# Per-wheel drive replaces VehicleBody3D's shared engine/brake/steering.
	engine_force = 0.0
	brake = 0.0
	steering = 0.0
	if not is_zero_approx(throttle) or not is_zero_approx(turn):
		sleeping = false

	for i in wheels.size():
		var wheel := wheels[i]
		var side := wheel_sides[i]
		var offset := wheel.global_position - global_position
		var wheel_speed := (linear_velocity + angular_velocity.cross(offset)).dot(forward)
		# Opposite track velocities give a pivot; unequal velocities give a moving turn.
		var track_speed := target_speed - side * target_yaw * track_half_width
		var force := (track_speed - wheel_speed) * drive_response * mass / maxf(wheels.size(), 1)
		var force_limit := engine_force_value * mass / 100.0
		wheel.engine_force = clampf(force, -force_limit, force_limit)
		wheel.brake = 0.0
		if is_zero_approx(throttle) and is_zero_approx(turn):
			wheel.engine_force = 0.0
			wheel.brake = idle_brake * mass / 100.0
		wheel.wheel_friction_slip = lerpf(wheel_grip[i], turning_grip, turning)
		if wheel.is_in_contact():
			left_grounded = left_grounded or side > 0.0
			right_grounded = right_grounded or side < 0.0

	# VehicleWheel3D models tires: their sideways grip resists track skidding.
	# A grounded yaw assist lets both tracks scrub sideways without rotating the transform.
	if left_grounded and right_grounded:
		var yaw_torque := clampf((target_yaw - yaw_speed) * turn_response, -3.0, 3.0) * mass
		apply_torque(up * yaw_torque)

	var speed := linear_velocity.length()
	var effort := maxf(speed / maxf(max_forward_speed, 0.1), absf(turn) * 0.5)
	var desired_pitch := 0.8 + effort
	engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, desired_pitch, 1.0 - exp(-5.0 * delta))
	if impact_sound.stream != null and absf(speed - previous_speed) > 1.0:
		impact_sound.play()
		Input.vibrate_handheld(100)
		for joypad in Input.get_connected_joypads():
			Input.start_joy_vibration(joypad, 0.0, 0.5, 0.1)
	previous_speed = speed
