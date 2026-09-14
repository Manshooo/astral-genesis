# res://src/components/physics/c_velocity.gd
# Чистые данные: кто угодно пишет сюда, S_Movement применяет к телу.
# Сегодня пишут системы возможностей игрока (S_Walk/S_Jump/S_Flight/S_Gravity)
# — ИИ у тел нет.
class_name C_Velocity
extends Component

@export var velocity := Vector3.ZERO
