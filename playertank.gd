
extends VehicleBody3D

const STEER_SPEED := 1.5
const STEER_LIMIT := 0.4

@export var engine_force_value := 25.0
@export var max_forward_speed := 3.0
@export var max_reverse_speed := 1.8
@export var brake_strength := 5.0
@export var idle_brake := 1.5

var previous_speed := 0.0

@onready var engine_sound: AudioStreamPlayer = $EngineSound
@onready var impact_sound: AudioStreamPlayer = $ImpactSound

func _physics_process(delta: float) -> void:
	# The tank model faces -X; the wheel rolling axes are aligned with it.
	var forward_speed := linear_velocity.dot(-global_basis.x)
	var throttle := Input.get_axis(&"reverse", &"accelerate")
	var steer_target := Input.get_axis(&"turn_right", &"turn_left") * STEER_LIMIT
	steering = move_toward(steering, steer_target, STEER_SPEED * delta)

	engine_force = 0.0
	brake = 0.0
	if is_zero_approx(throttle):
		brake = idle_brake
	elif throttle * forward_speed < -0.1:
		# Slow down before applying drive in the opposite direction.
		brake = brake_strength * absf(throttle)
	elif throttle > 0.0 and forward_speed < max_forward_speed:
		engine_force = throttle * engine_force_value
	elif throttle < 0.0 and forward_speed > -max_reverse_speed:
		engine_force = throttle * engine_force_value

	var speed := linear_velocity.length()
	var desired_pitch := 0.8 + speed / maxf(max_forward_speed, 0.1)
	engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, desired_pitch, 1.0 - exp(-5.0 * delta))
	if impact_sound.stream != null and absf(speed - previous_speed) > 1.0:
		impact_sound.play()
		Input.vibrate_handheld(100)
		for joypad in Input.get_connected_joypads():
			Input.start_joy_vibration(joypad, 0.0, 0.5, 0.1)
	previous_speed = speed
