# res://src/components/physics/c_velocity.gd
# Чистые данные. Кто угодно пишет сюда — S_Movement применяет.
# Игрок:  S_PlayerMovement → C_Velocity → S_Movement
# NPC:    S_AIMovement     → C_Velocity → S_Movement
class_name C_Velocity
extends Component

@export var velocity := Vector3.ZERO
