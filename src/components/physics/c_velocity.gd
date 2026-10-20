# res://src/components/physics/c_velocity.gd
# Чистые данные: пишут системы возможностей (S_Walk/S_Jump/S_Flight/S_Gravity), применяет S_Movement.
class_name C_Velocity
extends Component

@export var velocity := Vector3.ZERO
