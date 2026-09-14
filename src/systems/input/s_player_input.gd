# res://src/systems/input/s_player_input.gd
class_name S_PlayerInput
extends System 

func query() -> QueryBuilder:
	return q.with_all([C_PlayerInput]).iterate([C_PlayerInput]).with_none([C_UIBlocked])

func process(entities: Array[Entity], components: Array, _delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir := Vector3(input_dir.x, 0.0, input_dir.y).normalized() if input_dir != Vector2.ZERO else Vector3.ZERO

	var input_comps: Array = components[0]
	for i in entities.size():
		var inp := input_comps[i] as C_PlayerInput
		inp.move_direction = move_dir
