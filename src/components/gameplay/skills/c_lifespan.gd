class_name C_Lifespan
extends Component
## СОБСТВЕННЫЙ запас души: сколько секунд она протянет без тела. Запас тела — отдельный C_BodyDecay;
## тикает карман, соответствующий состоянию. Остаток тела при выходе решает O_ExpelFromBody.
## Вики: [[Захват тела]] (модель запаса).

## Базовый запас души без тела, с. Прибавки скиллов — в C_StatModifiers (effective_max), база не переписывается.
@export var max_duration: float = 60.0
## Текущий запас; может превышать максимум — излишек утекает быстрее (S_Lifespan).
@export var current: float = 60.0


## Максимум с учётом модификаторов; душа аргументом — компонент владельца не ищет.
func effective_max(soul: Entity) -> float:
	return C_StatModifiers.of(soul, C_StatModifiers.SOUL_LIFESPAN, max_duration)


## Есть ли излишек сверх собственного максимума (принесённый из тела).
func overflow(soul: Entity) -> float:
	return maxf(current - effective_max(soul), 0.0)
