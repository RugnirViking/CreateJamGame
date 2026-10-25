extends CollisionShape3D

@onready var turret: Node3D = $"../Model/TurretRotation"

func _physics_process(_delta: float) -> void:
	# The shape dimensions are authored in vehicle units; follow traverse without
	# inheriting the imported model's 0.1 scale a second time.
	var pose := get_parent_node_3d().global_transform.affine_inverse() * turret.global_transform
	transform = Transform3D(pose.basis.orthonormalized(), pose.origin)
