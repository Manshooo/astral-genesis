class_name C_Health
extends Component
## Прочность. Число АВТОРСКОЕ: у тела оно из его сцены, у врага — из его.
## Прибавки души (C_StatModifiers) сюда не пишутся, а учитываются при чтении —
## см. effective_maximum.

@export var maximum := 100.0
@export var current := 100.0

func _init(max_health: float = 100.0):
	maximum = max_health
	current = max_health


## Потолок HP для конкретного носителя. Терпит сущность без модификаторов: у
## обычного врага их нет, и база — уже ответ.
func effective_maximum(carrier: Entity) -> float:
	return C_StatModifiers.of(carrier, C_StatModifiers.BODY_HEALTH, maximum)
