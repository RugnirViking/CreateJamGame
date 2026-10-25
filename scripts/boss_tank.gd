extends "res://scenes/enemytank.gd"

@export_group("Close-range Spin")
@export var spin_radius := 6.0
@export var camp_duration := 2.0
@export var spin_duration := 0.85
@export var spin_cooldown := 5.0
@export var knockback_speed := 14.0
@export var knockback_lift := 8.0

@onready var spin_sound: AudioStreamPlayer = $SpinSound

var _camp_elapsed := 0.0
var _spin_elapsed := 0.0
var _spin_cooldown := 0.0
var _spin_start_yaw := 0.0
var _spinning := false
var _knocked_back := false


func is_spin_attacking() -> bool:
	return _spinning


func _physics_process(delta: float) -> void:
	if destroyed or not is_instance_valid(playertank) or playertank.destroyed or playertank.you_win.visible:
		_camp_elapsed = 0.0
		if _spinning:
			turret.rotation.y = wrapf(_spin_start_yaw, -PI, PI)
			_spinning = false
		return
	if _spinning:
		_advance_spin(delta)
		return
	_spin_cooldown = maxf(0.0, _spin_cooldown - delta)
	if _spin_cooldown <= 0.0 and _player_in_reach(spin_radius):
		_camp_elapsed += delta
	else:
		# Time spent outside the danger zone earns the grace period back.
		_camp_elapsed = maxf(0.0, _camp_elapsed - delta)
	if _camp_elapsed >= camp_duration:
		_camp_elapsed = 0.0
		_spin_elapsed = 0.0
		_spin_start_yaw = turret.rotation.y
		_spinning = true
		_knocked_back = false
		spin_sound.play()
		return
	super._physics_process(delta)


func _player_in_reach(radius: float) -> bool:
	var offset := playertank.global_position - global_position
	return Vector2(offset.x, offset.z).length_squared() <= radius * radius and absf(offset.y) <= 3.0


func _advance_spin(delta: float) -> void:
	_spin_elapsed = minf(_spin_elapsed + delta, spin_duration)
	turret.rotation.y = _spin_start_yaw + TAU * 2.0 * (_spin_elapsed / spin_duration)
	# The first complete revolution is the warning; kick as the second begins.
	if not _knocked_back and _spin_elapsed >= spin_duration * 0.5:
		_knocked_back = true
		if _player_in_reach(spin_radius):
			var away := playertank.global_position - global_position
			away.y = 0.0
			if away.length_squared() < 0.0001:
				away = global_basis.x
				away.y = 0.0
			away = away.normalized()
			playertank.sleeping = false
			# An impulse scaled by mass launches every selectable tank equally.
			playertank.apply_central_impulse((away * knockback_speed + Vector3.UP * knockback_lift) * playertank.mass)
	if _spin_elapsed >= spin_duration:
		turret.rotation.y = wrapf(_spin_start_yaw, -PI, PI)
		_spinning = false
		_spin_cooldown = spin_cooldown
