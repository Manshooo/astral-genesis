# res://src/systems/input/s_player_input.gd
# Группа: "input". Опрос УДЕРЖИВАЕМОГО ввода (направление, бег) в C_PlayerInput;
# фронты нажатий ставит E_Player._input, взгляд копит он же.
#
# Две выборки, и вторая — не для симметрии. Пока открыт блокирующий экран
# (C_UIBlocked), опрашивать клавиатуру нельзя, но и оставить компонент как есть
# тоже: последнее направление и зажатый бег остались бы в нём, и тело поехало бы
# само, пока игрок щёлкает по дереву навыков. Системы движения C_UIBlocked
# намеренно не фильтруют — выпавшее из S_Walk тело сохранило бы старую скорость
# и тем более поехало бы. Поэтому «под блоком ничего не нажато» держит источник
# ввода, а не каждый его потребитель.
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
	# Удержание, а не нажатие: бег длится ровно столько, сколько держат клавишу.
	# Спрашиваем здесь, вместе с направлением, чтобы весь удерживаемый ввод
	# читался в одном месте — системе бега остаётся только его последствие.
	var sprint := Input.is_action_pressed("sprint")

	for entity in entities:
		var inp := entity.get_component(C_PlayerInput) as C_PlayerInput
		inp.move_direction = move_dir
		inp.sprint_held = sprint


func _hold_neutral(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		(entity.get_component(C_PlayerInput) as C_PlayerInput).release_held()
