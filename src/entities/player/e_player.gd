# res://src/entities/player/e_player.gd
@tool
class_name E_Player
extends Entity

@onready var camera: Camera3D = $Camera3D

func define_components() -> Array:
	return [C_PlayerInput.new(), C_FPSCamera.new(), C_Health.new()]


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if has_component(C_UIBlocked):
		return  # не копим mouse look, пока открыт UI
		
	if event is InputEventMouseMotion:
		var inp := get_component(C_PlayerInput) as C_PlayerInput
		if inp:
			inp.mouse_delta += event.relative

	if event.is_action_pressed("jump") and not event.is_echo():
		var inp := get_component(C_PlayerInput) as C_PlayerInput
		if inp:
			inp.jump_pressed = true
