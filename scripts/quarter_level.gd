extends "res://scripts/gameplay_tank_spawn.gd"

const Levels = preload("res://scripts/level_catalog.gd")

@export_range(0, 3) var quadrant: int = 0


func _enter_tree() -> void:
	get_node("heightmap").quadrant = quadrant
	var image := Levels.quarter_image(quadrant)
	super._enter_tree()
	# Prevent driving off the finite heightmap. Each piece keeps its original scale.
	var half := Vector2(image.get_size() - Vector2i.ONE) * 0.5
	for side in [-1.0, 1.0]:
		_add_boundary(Vector3(side * (half.x + 1.0), 15, 0), Vector3(2, 80, half.y * 2 + 4))
		_add_boundary(Vector3(0, 15, side * (half.y + 1.0)), Vector3(half.x * 2 + 4, 80, 2))


func _add_boundary(center: Vector3, dimensions: Vector3) -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = dimensions
	collision.shape = box
	collision.position = center
	add_child(collision)
