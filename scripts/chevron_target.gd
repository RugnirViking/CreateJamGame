extends Node3D

@export var chevron_target: Node3D

@onready var _pivot: Node3D = $followcam/chevronpivot
@onready var _rest_basis: Basis = _pivot.basis

func _process(_delta: float) -> void:
	_pivot.visible = is_instance_valid(chevron_target)
	if not is_instance_valid(chevron_target):
		return
	var direction := _pivot.get_parent_node_3d().to_local(chevron_target.global_position) - _pivot.position
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		return
	# The strip extends along local -Y; retain its authored flat orientation.
	var rest_forward := -_rest_basis.y
	rest_forward.y = 0.0
	var yaw := rest_forward.signed_angle_to(direction, Vector3.UP)
	_pivot.basis = Basis(Vector3.UP, yaw) * _rest_basis
