@tool
extends Node

# Must match MAX_MARKERS in desertfloor.gdshader.
const MAX_MARKERS := 32
var _material: ShaderMaterial
var _warned_limit := false

func _process(_delta: float) -> void:
	var terrain := get_parent() as MeshInstance3D
	if terrain == null or terrain.mesh == null:
		return
	var current := terrain.get_active_material(0) as ShaderMaterial
	if current == null:
		return
	if current != _material:
		_material = current.duplicate() as ShaderMaterial
		terrain.set_surface_override_material(0, _material)
	var positions := PackedVector4Array()
	var colors := PackedColorArray()
	var effects := PackedVector4Array()
	for node in get_tree().get_nodes_in_group(&"terrain_target_markers"):
		var marker := node as terrain_target_marker
		if marker == null or marker.terrain != terrain or not marker.is_visible_in_tree():
			continue
		if positions.size() == MAX_MARKERS:
			if not _warned_limit:
				push_warning("Terrain target renderer supports up to 32 visible targets per terrain.")
				_warned_limit = true
			break
		var center := marker.global_position
		positions.append(Vector4(center.x, center.z, marker.radius, minf(marker.ring_width, marker.radius)))
		colors.append(marker.display_color())
		effects.append(Vector4(marker.capture_pulse, marker.capture_progress, 0.0, 0.0))
	var count := positions.size()
	positions.resize(MAX_MARKERS)
	colors.resize(MAX_MARKERS)
	effects.resize(MAX_MARKERS)
	_material.set_shader_parameter(&"marker_count", count)
	_material.set_shader_parameter(&"marker_positions", positions)
	_material.set_shader_parameter(&"marker_colors", colors)
	_material.set_shader_parameter(&"marker_effects", effects)

func _exit_tree() -> void:
	if is_instance_valid(_material):
		_material.set_shader_parameter(&"marker_count", 0)
