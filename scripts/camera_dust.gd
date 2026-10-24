extends MultiMeshInstance3D

# Adapted from Terrajet's scripts/fx/CaveDustField.gd: seeded billboard motes,
# recycled around the viewer. World positions replace progress along a track.
@export_range(1, 2000, 1) var particle_count := 1000
@export var field_half_size := Vector3(4.0, 2.5, 6.0)
@export var mote_size := 0.025
@export var dust_color := Color(0.88, 0.82, 0.67)

@onready var controller: Node3D = $"../followcam"
@onready var tank: VehicleBody3D = $"../vehicle"

var _rng := RandomNumberGenerator.new()
var _positions := PackedVector3Array()
var _sizes := PackedFloat32Array()
var _alphas := PackedFloat32Array()
var _last_camera: Camera3D


func _ready() -> void:
	top_level = true
	_rng.seed = 7331
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.no_depth_test = false
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * mote_size
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = quad
	multimesh.instance_count = particle_count
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(-field_half_size, field_half_size * 2.0)
	_positions.resize(particle_count)
	_sizes.resize(particle_count)
	_alphas.resize(particle_count)
	_reseed(controller.get_aim_camera())
	_update_particles(0.0)


func _reseed(view_camera: Camera3D) -> void:
	_last_camera = view_camera
	global_position = view_camera.global_position
	for i in particle_count:
		_positions[i] = global_position + Vector3(
			_rng.randf_range(-field_half_size.x, field_half_size.x),
			_rng.randf_range(-field_half_size.y, field_half_size.y),
			_rng.randf_range(-field_half_size.z, field_half_size.z))
		_sizes[i] = _rng.randf_range(0.45, 1.45)
		_alphas[i] = _rng.randf_range(0.6, 0.9)


func _process(delta: float) -> void:
	_update_particles(delta)


func _update_particles(delta: float) -> void:
	var view_camera: Camera3D = controller.get_aim_camera()
	if view_camera != _last_camera:
		_reseed(view_camera)
	global_position = view_camera.global_position
	var speed_ratio := clampf(tank.linear_velocity.length() / maxf(tank.max_forward_speed, 0.1), 0.0, 1.0)
	var intensity := lerpf(0.3, 1.0, speed_ratio)
	if controller.sniper_mode:
		intensity *= 0.25
	for i in particle_count:
		# Dust stays in the world as the camera moves through it. Wrapping supports
		# forward, reverse and sideways motion without building up new particles.
		var offset := _positions[i] + Vector3(0.025, 0.012, 0.015) * delta - global_position
		offset.x = wrapf(offset.x, -field_half_size.x, field_half_size.x)
		offset.y = wrapf(offset.y, -field_half_size.y, field_half_size.y)
		offset.z = wrapf(offset.z, -field_half_size.z, field_half_size.z)
		_positions[i] = global_position + offset
		var edge := (offset / field_half_size).abs()
		var fade := smoothstep(0.0, 0.2, 1.0 - maxf(edge.x, maxf(edge.y, edge.z)))
		fade *= smoothstep(0.25, 0.7, offset.length())
		var size := _sizes[i]
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), offset))
		multimesh.set_instance_color(i, Color(dust_color, _alphas[i] * fade * intensity))
