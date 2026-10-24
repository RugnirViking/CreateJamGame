@tool
class_name terrain_target_marker
extends Node3D

signal captured
signal activated

enum State { INACTIVE, ACTIVE, CAPTURED }

@export var terrain: MeshInstance3D
@export var state: State = State.INACTIVE
@export var nextmarker: terrain_target_marker
## Accepts the moving player body or its scene root. Empty uses the player group.
@export var player: Node3D

@export_group("Appearance")
@export_range(0.1, 50.0, 0.1) var radius: float = 3.0
@export_range(0.01, 5.0, 0.01) var ring_width: float = 0.15
## Active color. Alpha sets fill opacity; the ring remains solid.
@export var color: Color = Color(1.0, 0.8, 0.1, 0.18)
@export var inactive_color: Color = Color(0.45, 0.48, 0.52, 0.08)
@export var captured_color: Color = Color(0.2, 0.85, 0.4, 0.22)

@export_group("Capture")
## Horizontal distance, independent of target height above the terrain.
@export_range(0.1, 50.0, 0.1) var capture_distance: float = 3.0
@export_range(0.1, 30.0, 0.1) var capture_duration: float = 4.0
@export_range(0.2, 10.0, 0.1) var pulse_period: float = 2.0

var capture_progress: float = 0.0
var capture_pulse: float = 0.0
var _capture_elapsed: float = 0.0

func _enter_tree() -> void:
	add_to_group(&"terrain_target_markers")

func _process(delta: float) -> void:
	if not Engine.is_editor_hint():
		_update_capture(delta)

func _update_capture(delta: float) -> void:
	if state != State.ACTIVE or not is_visible_in_tree():
		_reset_progress()
		return
	var player_body := _resolve_player_body()
	if not is_instance_valid(player_body):
		_reset_progress()
		return
	var offset := player_body.global_position - global_position
	if Vector2(offset.x, offset.z).length_squared() > capture_distance * capture_distance:
		_reset_progress()
		return
	_capture_elapsed += delta
	capture_progress = clampf(_capture_elapsed / maxf(capture_duration, 0.1), 0.0, 1.0)
	var fade_in := smoothstep(0.0, 0.6, _capture_elapsed)
	capture_pulse = (0.5 - 0.5 * cos(TAU * _capture_elapsed / maxf(pulse_period, 0.2))) * fade_in
	if capture_progress >= 1.0:
		_capture()

func activate() -> void:
	if state == State.CAPTURED:
		return
	state = State.ACTIVE
	_reset_progress()
	activated.emit()

func _resolve_player_body() -> Node3D:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group(&"player") as Node3D
	if not is_instance_valid(player):
		return null
	# The tank scene root stays at spawn while its VehicleBody3D moves.
	for node in get_tree().get_nodes_in_group(&"player"):
		if node is Node3D and (node == player or player.is_ancestor_of(node)):
			return node as Node3D
	return player

func display_color() -> Color:
	match state:
		State.INACTIVE:
			return inactive_color
		State.CAPTURED:
			return captured_color
	return color

func _capture() -> void:
	state = State.CAPTURED
	_reset_progress()
	var next_target: terrain_target_marker = null
	if is_instance_valid(nextmarker) and nextmarker != self and nextmarker.state != State.CAPTURED:
		next_target = nextmarker
		if not is_instance_valid(next_target.player):
			next_target.player = player
		next_target.activate()
	# Keep the assigned indicator following the objective sequence.
	var indicator: Node = _resolve_player_body()
	while is_instance_valid(indicator):
		if "chevron_target" in indicator and indicator.chevron_target == self:
			indicator.chevron_target = next_target
			break
		indicator = indicator.get_parent()
	captured.emit()

func _reset_progress() -> void:
	_capture_elapsed = 0.0
	capture_progress = 0.0
	capture_pulse = 0.0
