# res://src/components/input/c_playerInput.gd
class_name C_PlayerInput
extends Component

# Направление движения от клавиатуры. Заполняет S_PlayerInput.
@export var move_direction := Vector3.ZERO
@export var jump_pressed := false
@export var mouse_captured := true
@export var mouse_delta := Vector2.ZERO
