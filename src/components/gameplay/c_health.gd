class_name C_Health
extends Component
## Прочность; число авторское (из сцены тела или врага). Прибавки души (C_StatModifiers) учитываются при чтении — effective_maximum.

@export var maximum := 100.0
@export var current := 100.0

func _init(max_health: float = 100.0):
	maximum = max_health
	current = max_health


## Потолок HP для носителя; сущность без модификаторов терпит.
func effective_maximum(carrier: Entity) -> float:
	return C_StatModifiers.of(carrier, C_StatModifiers.BODY_HEALTH, maximum)
