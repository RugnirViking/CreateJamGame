class_name shell
extends Node3D

@export var velocity: float = 30.0
@export var lifetime: float = 10.0
@export_flags_3d_physics var collision_mask: int = 3

var shooter: PhysicsBody3D
var _age: float = 0.0

@onready var particles: GPUParticles3D = $shell/GPUParticles3D
@onready var explod: GPUParticles3D = $shell/explod
@onready var explosion_flash: GPUParticles3D = $ExplosionFlash

func _physics_process(delta: float) -> void:
	if !particles.emitting:
		particles.emitting=true;
	_age += delta
	if _age >= lifetime:
		_release_trail()
		queue_free()
		return

	# The barrel points along -X. Normalize so model scale does not slow the shell.
	var next_position := global_position - global_basis.x.normalized() * velocity * delta
	var query := PhysicsRayQueryParameters3D.create(global_position, next_position, collision_mask)
	if is_instance_valid(shooter):
		query.exclude = [shooter.get_rid()]
	query.hit_from_inside = true
	# Sweep the entire step so fast shells cannot skip through thin colliders.
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		global_position = hit["position"]
		_release_trail()
		_start_burst(explod, hit["position"])
		_start_burst(explosion_flash, hit["position"])
		queue_free()
		return
	global_position = next_position


func _release_trail() -> void:
	particles.reparent(get_tree().current_scene, true)
	particles.emitting = false
	_schedule_cleanup(particles)


func _start_burst(emitter: GPUParticles3D, impact_position: Vector3) -> void:
	# Preserve the tank's model scale, but let smoke rise in world space.
	var effect_scale := global_basis.get_scale()
	emitter.reparent(get_tree().current_scene, true)
	emitter.global_transform = Transform3D(Basis.from_scale(effect_scale), impact_position)
	emitter.local_coords = false
	emitter.restart()
	emitter.emitting = true
	_schedule_cleanup(emitter)


func _schedule_cleanup(emitter: GPUParticles3D) -> void:
	# The scene tree owns the timer; deleting this shell cannot cancel cleanup.
	var duration := emitter.lifetime / maxf(emitter.speed_scale, 0.01) + 0.1
	get_tree().create_timer(duration).timeout.connect(emitter.queue_free)
