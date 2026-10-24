extends MultiMeshInstance3D

# Small surface-aligned tread stamps work in the Compatibility renderer too.
@export_range(64, 16384, 64) var max_marks := 8192
@export var tread_width := 0.14
@export var tread_length := 0.168
@export var stamp_spacing := 0.15
@export var surface_offset := 0.004
@export var track_color := Color(0.16, 0.12, 0.075, 0.55)
@export var tread_texture: Texture2D = preload("res://art/textures/treadstransparent.png")

@onready var tank: playertank_tracks = $"../vehicle"

var mark_count := 0
var _next_mark := 0
var _wheels: Array[VehicleWheel3D] = []
var _last_points := PackedVector3Array()
var _last_bodies: Array[Node3D] = []
var _connected: Array[bool] = []


func _ready() -> void:
	# Marks are stored in world space and stay behind when the player moves.
	top_level = true
	global_transform = Transform3D.IDENTITY
	_wheels.assign(tank.wheels)
	_last_points.resize(_wheels.size())
	_last_bodies.resize(_wheels.size())
	_connected.resize(_wheels.size())
	var material := ShaderMaterial.new()
	material.shader = preload("res://scripts/shaders/ground_tracks.gdshader")
	material.set_shader_parameter("tread_texture", tread_texture)
	material.set_shader_parameter("track_color", track_color)
	var quad := QuadMesh.new()
	quad.size = Vector2(tread_width, tread_length)
	quad.material = material
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = max_marks
	multimesh.visible_instance_count = 0
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(_delta: float) -> void:
	var forward := -tank.global_basis.x.normalized()
	for i in _wheels.size():
		var wheel := _wheels[i]
		if not wheel.is_in_contact():
			_break_trail(i)
			continue
		var body := wheel.get_contact_body() as StaticBody3D
		var point := wheel.get_contact_point()
		var normal := wheel.get_contact_normal().normalized()
		# Cached wheel contacts can survive one tick after a flip or teleport.
		var reach := wheel.wheel_radius + wheel.wheel_rest_length + wheel.suspension_travel + 0.1
		if body == null or normal.dot(Vector3.UP) < 0.15 or point.distance_to(wheel.global_position) > reach:
			_break_trail(i)
			continue
		_record_contact(i, point, normal, body, forward)


func _break_trail(index: int) -> void:
	_connected[index] = false
	_last_bodies[index] = null


func _record_contact(index: int, point: Vector3, normal: Vector3, body: Node3D, forward: Vector3) -> void:
	var difference := point - _last_points[index]
	# Never draw a connecting strip across a jump, a new surface, or a teleport.
	if not _connected[index] or _last_bodies[index] != body or difference.length() > 0.75:
		_last_points[index] = point
		_last_bodies[index] = body
		_connected[index] = true
		_stamp_surface(point, normal, body, forward)
		return
	var distance := difference.slide(normal).length()
	if distance < stamp_spacing:
		return
	var start := _last_points[index]
	var steps := floori(distance / stamp_spacing)
	for step in range(1, steps + 1):
		var sample := start.lerp(point, float(step) * stamp_spacing / distance)
		_stamp_surface(sample, normal, body, forward)
	_last_points[index] = start.lerp(point, float(steps) * stamp_spacing / distance)


func _stamp_surface(point: Vector3, normal: Vector3, body: Node3D, forward: Vector3) -> void:
	# Verify each interpolated stamp touches the same surface; gaps stay unmarked.
	var query := PhysicsRayQueryParameters3D.create(
		point + normal * 0.08, point - normal * 0.08, tank.collision_mask, [tank.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or hit.get("collider") != body:
		return
	var hit_normal: Vector3 = hit["normal"]
	var along := forward.slide(hit_normal).normalized()
	if along.length_squared() < 0.001:
		return
	var across := along.cross(hit_normal).normalized()
	var position: Vector3 = hit["position"] + hit_normal * surface_offset
	# Local XY lies on the ground; the quad's +Z faces the surface normal.
	multimesh.set_instance_transform(_next_mark, Transform3D(Basis(across, along, hit_normal), position))
	_next_mark = (_next_mark + 1) % max_marks
	mark_count = mini(mark_count + 1, max_marks)
	multimesh.visible_instance_count = mark_count
