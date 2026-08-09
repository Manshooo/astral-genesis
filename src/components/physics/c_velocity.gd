# res://src/components/physics/c_velocity.gd
# Чистые данные: кто угодно пишет сюда, S_Movement применяет к телу.
# Сегодня пишет один S_PlayerMovement — ИИ у тел нет.
class_name C_Velocity
extends Component

@export var velocity := Vector3.ZERO
