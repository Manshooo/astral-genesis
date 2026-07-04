# res://src/systems/input/s_playerInput.gd
class_name S_PlayerInput
extends System 

func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput]).iterate([C_PlayerInput])

func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var jump := Input.is_action_just_pressed("jump")
	var move_dir := Vector3(input_dir.x, 0.0, input_dir.y).normalized() if input_dir != Vector2.ZERO else Vector3.ZERO
	
	var toggle_mouse := Input.is_action_just_pressed("capture_mouse")

	var input_comps: Array = components[0]
	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		inp.move_direction = move_dir
		
		inp.jump_pressed = jump
		print("jump_pressed (input)")
		
		if toggle_mouse:
			inp.mouse_captured = !inp.mouse_captured
			
		if inp.mouse_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
