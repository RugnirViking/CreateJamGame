extends SceneTree

# Run with: godot --headless --path . --script tests/tank_physics_smoke.gd
var tank: VehicleBody3D
var tick := 0
var min_upright := 1.0
var max_speed := 0.0

func _initialize() -> void:
	var world: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(world)
	tank = world.get_node("playertank/vehicle")

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick == 120:
		report("settled")
		Input.action_press("accelerate")
	if tick == 300:
		report("straight")
		check(tank.linear_velocity.x < -0.5, "W must drive toward the front (-X)")
		Input.action_press("turn_left")
	if tick == 480:
		report("turn")
		check(tank.position.z > 0.5, "A must turn left while driving forward")
		Input.action_release("turn_left")
		Input.action_release("accelerate")
	if tick == 600:
		report("stopped")
		check(tank.linear_velocity.length() < 0.1, "Idle brake must stop the tank")
		Input.action_press("reverse")
	if tick == 780:
		report("reverse")
		Input.action_release("reverse")
		check(tank.linear_velocity.dot(-tank.global_basis.x) < -0.5, "S must drive backward")
		check(min_upright > 0.98, "Tank must remain upright through the driving sequence")
		check(max_speed < 3.2, "Tank must stay within its configured speed limits")
		print("PROBE min_upright=", min_upright, " max_speed=", max_speed)
		quit(1 if failed else 0)
	min_upright = minf(min_upright, tank.global_basis.y.dot(Vector3.UP))
	max_speed = maxf(max_speed, tank.linear_velocity.length())
	return false

func report(phase: String) -> void:
	var contacts := 0
	for child in tank.get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			contacts += 1
	print("PROBE ", phase, " position=", tank.position, " velocity=", tank.linear_velocity, " upright=", tank.global_basis.y.dot(Vector3.UP), " contacts=", contacts)
	check(contacts == 4, "All four wheels must contact the flat ground during " + phase)

var failed := false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
