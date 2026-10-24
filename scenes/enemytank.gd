class_name enemytank_tracks
extends VehicleBody3D


@export_range(1, 100) var hits_to_destroy: int = 5

var shell_hits: int = 0
var destroyed: bool = false
var _health_bar: Sprite3D


func _ready() -> void:
	_darken_wreck($tankTOG2Destroyed)
	_health_bar = Sprite3D.new()
	_health_bar.name = "HealthBar"
	_health_bar.position = Vector3(0.25, 0.85, 0.0)
	_health_bar.pixel_size = 0.008
	_health_bar.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_health_bar.shaded = false
	_health_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_health_bar)
	_update_health_bar()


func _darken_wreck(node: Node) -> void:
	if node is MeshInstance3D:
		for surface in range(node.mesh.get_surface_count()):
			var source := node.get_active_material(surface) as BaseMaterial3D
			if source == null:
				continue
			# Isolate the tint so imported materials and intact tanks stay unchanged.
			var material := source.duplicate() as BaseMaterial3D
			material.albedo_color = Color(source.albedo_color.r * 0.5,
				source.albedo_color.g * 0.5, source.albedo_color.b * 0.5,
				source.albedo_color.a)
			node.set_surface_override_material(surface, material)
	for child in node.get_children():
		_darken_wreck(child)


func _update_health_bar() -> void:
	var remaining := clampf(1.0 - float(shell_hits) / hits_to_destroy, 0.0, 1.0)
	var image := Image.create(128, 16, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.04, 0.04, 0.04, 1.0))
	image.fill_rect(Rect2i(2, 2, 124, 12), Color(0.22, 0.08, 0.06, 1.0))
	if remaining > 0.0:
		var color := Color(0.2, 0.85, 0.25).lerp(Color(0.95, 0.18, 0.08), 1.0 - remaining)
		image.fill_rect(Rect2i(2, 2, roundi(124 * remaining), 12), color)
	_health_bar.texture = ImageTexture.create_from_image(image)
	_health_bar.visible = remaining > 0.0


func receive_shell_hit() -> void:
	if destroyed:
		return
	shell_hits += 1
	_update_health_bar()
	if shell_hits < hits_to_destroy:
		return
	destroyed = true
	$tank2.hide()
	$tankTOG2Destroyed.show()
	$EngineSound.stop()
	$left_track_particles.emitting = false
	$right_track_particles.emitting = false
	engine_force = 0.0
	brake = 100.0
