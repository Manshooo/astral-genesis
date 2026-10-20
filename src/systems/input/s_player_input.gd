# res://src/systems/input/s_player_input.gd
# Группа "input". Опрос УДЕРЖИВАЕМОГО ввода (направление, бег) в C_PlayerInput; фронты нажатий и взгляд — E_Player._input. Вторая выборка — под блокирующим экраном
# (C_UIBlocked): клавиатуру не опрашиваем, но и последнее направление оставлять нельзя — тело поехало бы. Системы движения C_UIBlocked не фильтруют, «ничего не нажато» держит источник.
class_name S_PlayerInput
extends System


func sub_systems() -> Array[Array]:
	return [
		[q.with_all([C_PlayerInput]).with_none([C_UIBlocked]), _read_input],
		[q.with_all([C_PlayerInput, C_UIBlocked]), _hold_neutral],
	]


func _read_input(entities: Array[Entity], _components: Array, _delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var move_dir := Vector3(input_dir.x, 0.0, input_dir.y).normalized() if input_dir != Vector2.ZERO else Vector3.ZERO
	# Удержание, а не нажатие: бег длится, пока держат клавишу; читаем вместе с направлением.
	var sprint := Input.is_action_pressed("sprint")

	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		inp.move_direction = move_dir
		inp.sprint_held = sprint


func _hold_neutral(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		(entity.get_component(C_PlayerInput) as C_PlayerInput).release_held()
