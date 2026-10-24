extends SceneTree

const Marker = preload("res://scripts/terrain_target_marker.gd")
const Renderer = preload("res://scripts/terrain_target_renderer.gd")

class Indicator:
	extends Node3D
	var chevron_target: Node3D

var failures := 0
var captures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var indicator := Indicator.new()
	world.add_child(indicator)
	var player := Node3D.new()
	indicator.add_child(player)
	player.add_to_group(&"player")
	var terrain := MeshInstance3D.new()
	terrain.mesh = PlaneMesh.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://scenes/desertfloor.gdshader")
	terrain.set_surface_override_material(0, material)
	world.add_child(terrain)
	var renderer := Renderer.new()
	terrain.add_child(renderer)
	renderer.set_process(false)
	var first := Marker.new()
	first.state = Marker.State.ACTIVE
	first.terrain = terrain
	world.add_child(first)
	first.set_process(false)
	var second := Marker.new()
	second.terrain = terrain
	second.state = Marker.State.INACTIVE
	second.position = Vector3(20.0, 0.0, 0.0)
	world.add_child(second)
	second.set_process(false)
	first.nextmarker = second
	# Reproduce assigning the stationary wrapper instead of the moving body.
	first.player = indicator
	indicator.chevron_target = first
	first.captured.connect(func(): captures += 1)

	player.position = Vector3(10.0, 0.0, 0.0)
	first._update_capture(5.0)
	_check(first.capture_progress == 0.0, "Outside range must not capture")
	player.position = Vector3(0.0, 30.0, 0.0)
	first._update_capture(1.0)
	_check(is_equal_approx(first.capture_progress, 0.25), "Capture uses XZ distance and configured duration")
	_check(first.capture_pulse > 0.0, "Capture pulses inside range")
	player.position.x = 10.0
	first._update_capture(1.0)
	_check(first.capture_progress == 0.0 and first.capture_pulse == 0.0, "Leaving range resets capture")
	second._update_capture(10.0)
	_check(second.state == Marker.State.INACTIVE, "Inactive markers cannot capture")
	player.position.x = 0.0
	first._update_capture(4.0)
	_check(first.state == Marker.State.CAPTURED and captures == 1, "Capture completes and signals once")
	_check(first.display_color() == first.captured_color, "Captured marker changes color")
	_check(second.state == Marker.State.ACTIVE, "Capture activates next target")
	_check(indicator.chevron_target == second, "Chevron switches to next target")
	first._update_capture(10.0)
	_check(captures == 1, "Captured markers cannot recapture")

	renderer._process(0.0)
	var drawn := terrain.get_active_material(0) as ShaderMaterial
	_check(drawn != material, "Terrain marker material is isolated")
	_check(drawn.get_shader_parameter(&"marker_count") == 2, "Draws multiple targets together")
	var colors: PackedColorArray = drawn.get_shader_parameter(&"marker_colors")
	_check(colors[0] == first.captured_color and colors[1] == second.color, "Preserves each target's state color")
	second.hide()
	renderer._process(0.0)
	_check(drawn.get_shader_parameter(&"marker_count") == 1, "Hidden targets are removed from rendering")
	second.show()
	player.position = Vector3(20.0, 0.0, 0.0)
	second._update_capture(4.0)
	_check(second.state == Marker.State.CAPTURED and indicator.chevron_target == null, "Final capture clears indicator target")
	first.free()
	_check(second.state == Marker.State.CAPTURED, "Removing a marker does not reactivate another")
	world.free()
	# Also verify the actual scene's sequence and automatic shared renderer.
	var main_scene := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await process_frame
	await process_frame
	_check(main_scene.get_node("FirstTarget").state == Marker.State.ACTIVE, "Scene starts with FirstTarget active")
	_check(main_scene.get_node("FirstTarget").nextmarker == main_scene.get_node("SecondTarget"), "First target keeps next-target link")
	_check(main_scene.get_node("SecondTarget").nextmarker == main_scene.get_node("ThirdTarget"), "Second target keeps next-target link")
	var scene_terrain := main_scene.get_node("heightmap") as MeshInstance3D
	_check(scene_terrain.has_node("TargetMarkers"), "Terrain creates its renderer automatically")
	_check(scene_terrain.get_active_material(0).get_shader_parameter("marker_count") == 3, "Actual scene renders all three targets")
	var scene_target := main_scene.get_node("FirstTarget") as terrain_target_marker
	var tank_body := main_scene.get_node("playertank/vehicle") as VehicleBody3D
	var wrapper := main_scene.get_node("playertank") as Node3D
	scene_target.player = wrapper
	tank_body.global_position = scene_target.global_position
	scene_target._update_capture(1.0)
	_check(scene_target.capture_progress > 0.0, "Actual tank captures with scene root assigned as Player")
	_check(wrapper.global_position.distance_to(tank_body.global_position) > 3.0, "Wrapper remains separate from moving body in regression")
	main_scene.free()
	if failures == 0:
		print("Terrain target checks passed.")
	quit(1 if failures else 0)
