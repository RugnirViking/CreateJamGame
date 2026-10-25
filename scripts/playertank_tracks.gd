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
@export var zeroing_acc := 2;
@export var max_targetness := 8.0;
@export var shell_scene: PackedScene
@export_range(0.1, 10.0, 0.1) var reload_duration := 1.5
@export_range(1, 100) var hits_to_destroy: int = 10
@export var low_health_color := Color(0.95, 0.18, 0.08)

var is_cat: bool:
	get:
		return get_meta("is_cat_tank", false)

@onready var active_model: Node3D = $Model
@onready var active_wreck: Node3D = $Wreck
@onready var turret: Node3D = $Model/TurretRotation
@onready var gun_elevation: Node3D = $Model/TurretRotation/GunElevation

var shell_hits: int = 0;
var targetness: float = max_targetness;
var wheels: Array[VehicleWheel3D] = []
var wheel_sides: Array[float] = []
var wheel_grip: Array[float] = []
var track_half_width := 0.0
var previous_speed := 0.0
var throttle: float = 0.0
var flip_text_offset: Vector3
var flip_tank_flag: bool
var destroyed: bool
var time_remaining: float = 180.0
var _health_bar_fill: StyleBoxFlat
var _full_health_color: Color
var _reload_remaining := 0.0
var _zeroing_warning_phase := 0.0
var _zeroing_started := false

@onready var engine_sound: AudioStreamPlayer = $EngineSound
@onready var impact_sound: AudioStreamPlayer = $ImpactSound
@onready var gunshot_sound: AudioStreamPlayer = $GunshotSound
@onready var catshot_sound: AudioStreamPlayer = $CatshotSound
@onready var gameovervoice_sound: AudioStreamPlayer = $ohnotryagain
@onready var win_fanfare: AudioStreamPlayer = $winfanfare
@onready var death_explosion_sound: AudioStreamPlayer = $deathexplosion
@onready var background_music: AudioStreamPlayer = $"../../BGMusic"
@onready var muzzle: Marker3D = $Model/TurretRotation/GunElevation/Muzzle
@onready var flip_text: Label3D = $"../followcam/fliptext"
@onready var sniper_flip_text: Label = $"../AimHUD/SniperHUD/FlipPrompt"
@onready var shell_fill: TextureProgressBar = $"../AimHUD/SniperHUD/Shell"
@onready var speed_label: Label = $"../AimHUD/HBoxContainer/SpeedLabel"
@onready var timer_label: Label = $"../AimHUD/HBoxContainer/TimerLabel"
@onready var vignetteShader: ColorRect = $"../AimHUD/VignetteShader"
@onready var heightmap: MeshInstance3D = $"../../heightmap"
@onready var health_bar: ProgressBar = $"../AimHUD/HealthBar"
@onready var health_label: Label = $"../AimHUD/HealthBar/HealthLabel"
@onready var game_over: Control = $"../AimHUD/GameOver"
@onready var death_reason: Label = $"../AimHUD/GameOver/Text/DeathReason"
@onready var zeroing_warning: Label = $"../AimHUD/ZeroingWarning"
@onready var you_win: Control = $"../AimHUD/YouWin"


@onready var left_track_particles: CPUParticles3D = $left_track_particles
@onready var right_track_particles: CPUParticles3D = $right_track_particles

func _ready() -> void:
	targetness = max_targetness
	shell_fill.step = 0.0
	shell_fill.value = shell_fill.max_value
	_update_timer_label()
	_connect_capture_targets.call_deferred()
	# Keep the editor's fill styling, with a private color for this player's HP.
	_health_bar_fill = health_bar.get_theme_stylebox("fill").duplicate() as StyleBoxFlat
	_full_health_color = _health_bar_fill.bg_color
	health_bar.add_theme_stylebox_override("fill", _health_bar_fill)
	_update_health_bar()
	for child in get_children():
		if child is VehicleWheel3D:
			wheels.append(child)
			wheel_sides.append(signf(child.position.z))
			wheel_grip.append(child.wheel_friction_slip)
			track_half_width = maxf(track_half_width, absf(child.position.z))
			child.use_as_steering = false
			child.steering = 0.0
	flip_text_offset=flip_text.position


func _connect_capture_targets() -> void:
	for marker in get_tree().get_nodes_in_group(&"terrain_target_markers"):
		marker.captured.connect(_check_targets_captured)
	_check_targets_captured()


func _check_targets_captured() -> void:
	if destroyed or you_win.visible:
		return
	var targets := get_tree().get_nodes_in_group(&"terrain_target_markers")
	if targets.is_empty():
		return
	for marker in targets:
		if marker.state != terrain_target_marker.State.CAPTURED:
			return
	you_win.modulate.a = 0.0
	zeroing_warning.hide()
	you_win.show()
	win_fanfare.play()
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(you_win, "modulate:a", 1.0, 1.5)


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

func _process(_delta: float) -> void:
	if destroyed:
		# Follow a sliding wreck without inheriting its pitch or roll.
		for emitter: GPUParticles3D in [$explodeFire, $explodeSmoke, $dedSmoke]:
			emitter.global_position = global_position + Vector3.UP * 0.15


func _physics_process(delta: float) -> void:
	if destroyed:
		return
	_reload_remaining = maxf(_reload_remaining - delta, 0.0)
	shell_fill.value = lerpf(shell_fill.min_value, shell_fill.max_value, 1.0 - _reload_remaining / reload_duration)
	if not you_win.visible:
		time_remaining = maxf(time_remaining - delta, 0.0)
		_update_timer_label()
		if time_remaining <= 0.0:
			_trigger_game_over(false, "TIME")
			return
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
	var desired_pitch := 0.4 + effort
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
	sniper_flip_text.visible = flip_text.visible
	
	_update_zeroing(speed, delta)
	
	heightmap.set_instance_shader_parameter("player_x",global_position.x)
	heightmap.set_instance_shader_parameter("player_y",global_position.z)
	
	heightmap.set_instance_shader_parameter("color_target",Color(0.6,0.2,0.2,0.8-clampf(targetness/max_targetness,0,0.8)));
	
	heightmap.set_instance_shader_parameter("radius",clampf(targetness/max_targetness,0,1)*10);
	speed_label.text=str(speed*3.6).pad_decimals(2)+" KM/H"
	vignetteShader.set_instance_shader_parameter("alpha", 1-clampf(targetness/max_targetness,0,1))
	
	
	
func _update_zeroing(speed: float, delta: float) -> void:
	if not _zeroing_started or you_win.visible:
		zeroing_warning.hide()
		return
	var previous_targetness := targetness
	if speed < 1.0:
		targetness -= zeroing_acc * delta
	elif speed >= 3.0:
		targetness += zeroing_acc * delta
	targetness = clampf(targetness, 0.0, max_targetness)
	if targetness <= 0.0:
		_trigger_game_over(true, "ZEROED IN")
		return
	# Warn from the first shrink, including above half size, through imminent death.
	zeroing_warning.visible = targetness < previous_targetness
	if not zeroing_warning.visible:
		_zeroing_warning_phase = 0.0
		return
	var urgency := 1.0 - targetness / max_targetness
	_zeroing_warning_phase = fposmod(_zeroing_warning_phase + delta * lerpf(1.0, 5.0, urgency), 1.0)
	zeroing_warning.modulate = Color(1.0, 0.8, 0.25).lerp(Color(1.0, 0.12, 0.06), urgency)
	zeroing_warning.modulate.a = 1.0 if _zeroing_warning_phase < 0.6 else 0.15
	zeroing_warning.text = "MOVE NOW - IMPACT IMMINENT" if urgency >= 0.75 else "KEEP MOVING - ENEMY ZEROING IN"


func _input(event: InputEvent) -> void:
	if _zeroing_started or destroyed or you_win.visible:
		return
	for action in [&"accelerate", &"reverse", &"turn_left", &"turn_right", &"shoot", &"flip_tank", &"zoom_in", &"zoom_out"]:
		if event.is_action_pressed(action):
			_zeroing_started = true
			return


func _unhandled_input(event: InputEvent) -> void:
	if you_win.visible and event.is_action_pressed("next_level"):
		# Reserve the action until another level is available.
		get_viewport().set_input_as_handled()
		return
	if destroyed:
		if event.is_action_pressed("return_action"):
			get_viewport().set_input_as_handled()
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_tree().set_meta("skip_menu_intro", true)
			get_tree().change_scene_to_file("res://scenes/mainmenu.tscn")
		return
	if event.is_action_pressed("flip_tank") and global_transform.basis.y.y < 0.2 and previous_speed < 5:
		flip_tank_flag = true
		sleeping = false
	if event.is_action_pressed("shoot"):
		_spawn_shell()
			
		

func _spawn_shell() -> void:
	if shell_scene == null or _reload_remaining > 0.0:
		return
	var shell := shell_scene.instantiate() as Node3D
	shell.set("shooter", self)
	get_tree().current_scene.add_child(shell)
	# Match the barrel's position, aim, and model scale without following the tank.
	shell.global_transform = muzzle.global_transform
	_reload_remaining = reload_duration
	shell_fill.value = shell_fill.min_value
	if is_cat:
		catshot_sound.play()
	else:
		gunshot_sound.play()
	

func receive_shell_hit() -> void:
	if destroyed or you_win.visible:
		return
	shell_hits += 1
	_update_health_bar()
	if shell_hits < hits_to_destroy:
		return
	_trigger_game_over(true, "0HP")


func _trigger_game_over(show_wreck: bool, reason: String) -> void:
	if destroyed or you_win.visible:
		return
	destroyed = true
	zeroing_warning.hide()
	_start_death_effects()
	flip_tank_flag = false
	flip_text.hide()
	sniper_flip_text.hide()
	death_reason.text = reason
	game_over.modulate.a = 0.0
	game_over.show()
	create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).tween_property(game_over, "modulate:a", 1.0, 1.5)
	if show_wreck:
		active_model.hide()
		active_wreck.show()
	
	$EngineSound.stop()
	$left_track_particles.emitting = false
	$right_track_particles.emitting = false
	engine_force = 0.0
	brake = 100.0
	throttle = 0.0
	for wheel in wheels:
		wheel.engine_force = 0.0
		wheel.brake = 100.0
	background_music.volume_linear *= 0.2
	death_explosion_sound.play()
	await get_tree().create_timer(0.5).timeout
	gameovervoice_sound.play()



func _start_death_effects() -> void:
	for emitter: GPUParticles3D in [$explodeFire, $explodeSmoke, $dedSmoke]:
		# Keep the plume upright even when the destroyed tank has rolled over.
		var origin := global_position + Vector3.UP * 0.15
		emitter.top_level = true
		emitter.global_transform = Transform3D(Basis.IDENTITY, origin)
		# Carry existing smoke with the emitter as well as spawning at the hull.
		emitter.local_coords = true
		emitter.show()
		emitter.restart()
		emitter.emitting = true


func _update_timer_label() -> void:
	var seconds := ceili(time_remaining)
	timer_label.text = "%02d:%02d" % [floori(seconds / 60.0), seconds % 60]


func _update_health_bar() -> void:
	var maximum := maxi(hits_to_destroy, 1)
	var current := clampi(maximum - shell_hits, 0, maximum)
	health_bar.max_value = maximum
	health_bar.value = current
	_health_bar_fill.bg_color = _full_health_color.lerp(low_health_color, 1.0 - float(current) / maximum)
	health_label.text = "HP %d / %d" % [current, maximum]
