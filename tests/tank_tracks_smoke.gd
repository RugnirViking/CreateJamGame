extends SceneTree

# godot --headless --path . --script tests/tank_tracks_smoke.gd
var tank: VehicleBody3D
var tick := 0
var failed := false
var pivot_start := Vector3.ZERO
var min_upright := 1.0
var max_speed := 0.0

func _initialize() -> void:
	var world: Node3D = load("res://main.tscn").instantiate()
	root.add_child(world)
	tank = world.get_node("playertank/vehicle")

func _physics_process(_delta: float) -> bool:
	tick += 1
	if tick == 120:
		report("settled")
		pivot_start = tank.global_position
		Input.action_press("turn_left")
	if tick == 240:
		report("pivot left")
		check(tank.angular_velocity.y > 0.3, "A must pivot left without throttle")
		check(horizontal_distance(pivot_start) < 0.2, "Left pivot must stay in place")
		check(left_wheel_force() < 0.0, "Left track must reverse during left pivot")
		Input.action_release("turn_left")
		Input.action_press("turn_right")
	if tick == 360:
		report("pivot right")
		check(tank.angular_velocity.y < -0.3, "D must pivot right without throttle")
		check(horizontal_distance(pivot_start) < 0.3, "Right pivot must stay in place")
		Input.action_release("turn_right")
	if tick == 480:
		report("pivot stopped")
		check(absf(tank.angular_velocity.y) < 0.1, "Releasing turn must stop rotation")
		Input.action_press("accelerate")
	if tick == 660:
		report("forward")
		check(tank.linear_velocity.dot(-tank.global_basis.x) > 0.5, "W must drive forward")
		Input.action_press("turn_left")
	if tick == 750:
		report("moving turn")
		check(tank.angular_velocity.y > 0.3, "W+A must turn left while driving")
		Input.action_release("accelerate")
		Input.action_press("reverse")
	if tick == 930:
		report("reverse turn")
		check(tank.linear_velocity.dot(-tank.global_basis.x) < -0.5, "S must drive backward")
		check(tank.angular_velocity.y > 0.3, "S+A must keep the same hull turn direction")
		Input.action_release("reverse")
		Input.action_release("turn_left")
	if tick == 1050:
		report("stopped")
		check(tank.linear_velocity.length() < 0.1, "Idle brake must stop translation")
		check(absf(tank.angular_velocity.y) < 0.1, "Idle must stop rotation")
		check(min_upright > 0.98, "Tank must stay upright")
		check(max_speed < 3.2, "Tank must respect its driving speed")
		# Steering assistance must never spin the tank while it is airborne.
		tank.global_position.y += 3.0
		tank.linear_velocity = Vector3.ZERO
		tank.angular_velocity = Vector3.ZERO
		Input.action_press("turn_left")
	if tick == 1053:
		# Allow cached wheel contacts to clear after the test teleport.
		tank.angular_velocity = Vector3.ZERO
	if tick == 1070:
		check(absf(tank.angular_velocity.y) < 0.01, "No steering torque while airborne")
		Input.action_release("turn_left")
		print("TRACKS min_upright=", min_upright, " max_speed=", max_speed, " failed=", failed)
		quit(1 if failed else 0)
	if tick < 1050:
		min_upright = minf(min_upright, tank.global_basis.y.dot(Vector3.UP))
		max_speed = maxf(max_speed, tank.linear_velocity.length())
	return false

func left_wheel_force() -> float:
	return tank.get_node("VehicleWheel3D").engine_force

func horizontal_distance(start: Vector3) -> float:
	var difference := tank.global_position - start
	return Vector2(difference.x, difference.z).length()

func report(phase: String) -> void:
	var contacts := 0
	for child in tank.get_children():
		if child is VehicleWheel3D and child.is_in_contact():
			contacts += 1
	print("TRACKS ", phase, " pos=", tank.global_position, " velocity=", tank.linear_velocity, " yaw=", tank.angular_velocity.y, " contacts=", contacts)
	check(contacts == 4, "Four grounded wheels during " + phase)

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)
