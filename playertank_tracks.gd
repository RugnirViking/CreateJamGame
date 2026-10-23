class_name playertank_tracks
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
@export var righting_strength := 0.1

var wheels: Array[VehicleWheel3D] = []
var wheel_sides: Array[float] = []
var wheel_grip: Array[float] = []
var track_half_width := 0.0
var previous_speed := 0.0
var throttle: float = 0.0
var flip_text_offset: Vector3
var flip_tank_flag: bool

@onready var engine_sound: AudioStreamPlayer = $EngineSound
@onready var impact_sound: AudioStreamPlayer = $ImpactSound
@onready var flip_text: Label3D = $"../followcam/fliptext"


@onready var left_track_particles: CPUParticles3D = $left_track_particles
@onready var right_track_particles: CPUParticles3D = $right_track_particles

func _ready() -> void:
	for child in get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
			wheel_sides.append(signf(child.position.z))
			wheel_grip.append(child.wheel_friction_slip)
			track_half_width = maxf(track_half_width, absf(child.position.z))
			child.use_as_steering = false
			child.steering = 0.0
	flip_text_offset=flip_text.position

func _integrate_forces(state):
	if flip_tank_flag:
		var t = state.transform
		t.origin += Vector3.UP * 1.0
		# Keep the tank's heading while removing pitch and roll.
		var heading_x: Vector3 = t.basis.x
		heading_x.y = 0.0
		if heading_x.length_squared() < 0.0001:
			heading_x = Vector3.UP.cross(t.basis.z)
		heading_x = heading_x.normalized()
		t.basis = Basis(heading_x, Vector3.UP, heading_x.cross(Vector3.UP))
		state.transform = t
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		flip_tank_flag = false
		print("Tank moved to: ", t.origin)

func _physics_process(delta: float) -> void:
	throttle = Input.get_axis(&"reverse", &"accelerate")
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
	var desired_pitch := 0.3 + effort
	engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, desired_pitch, 1.0 - exp(-5.0 * delta))
	
	if impact_sound.stream != null and absf(speed - previous_speed) > 1.0:
		impact_sound.play()
		Input.vibrate_handheld(100)
		for joypad in Input.get_connected_joypads():
			Input.start_joy_vibration(joypad, 0.0, 0.5, 0.1)
	previous_speed = speed
	left_track_particles.emitting=(speed>1.0 or turn<-0.1) && left_grounded
	right_track_particles.emitting=(speed>1.0 or turn>0.1) && right_grounded
	
	
	# constant righting force
	
	var up_vector = global_transform.basis.y
	var target_up = Vector3.UP
	
	# Cross product finds the axis and amount of rotation needed to get back to upright
	var tilt_axis = up_vector.cross(target_up)
	
	# Apply torque proportional to the tilt
	apply_torque(tilt_axis * righting_strength)
	
	
	flip_text.visible=global_transform.basis.y.y < 0.2 && speed < 5
	
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flip_tank") and global_transform.basis.y.y < 0.2 and previous_speed < 5:
		flip_tank_flag = true
		sleeping = false
