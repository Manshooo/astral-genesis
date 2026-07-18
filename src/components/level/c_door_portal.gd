class_name C_DoorPortal
extends Component
## Рантайм-связь двери с ребром графа. Штампуется RunManager при
## спавне комнаты по RS_LevelConnection выбранного узла — руками не заполняется.
## Пустой target_node_id = проём запечатан (никуда не ведёт).
@export var target_node_id: StringName = &""
## Копия RS_LevelConnection.locked_by: непусто = дверь заперта до наличия ключа.
@export var locked_by: StringName = &""


func is_locked() -> bool:
	return locked_by != &""
