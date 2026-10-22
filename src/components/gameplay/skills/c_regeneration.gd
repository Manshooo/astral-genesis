class_name C_Regeneration
extends C_Ability
## Регенерация: возвращает долю максимума HP за несколько секунд. Числа черновые (решение 22.10 —
## 30 % за 5 с, откат 20 с у Гончей), баланс — game-balance. Исполняет S_Regeneration.

## Доля эффективного максимума HP за одно применение.
@export_range(0.0, 1.0, 0.01) var share: float = 0.3

## За сколько секунд доля возвращается.
@export var seconds: float = 5.0

## Сколько HP ещё вернуть и за сколько секунд; 0 — не лечит.
var heal_left := 0.0
var time_left := 0.0


## Лечить нечего без тела, а целое тело — лишний откат.
func refusal(owner: Entity) -> String:
	var health := owner.get_component(C_Health) as C_Health if owner else null
	if health == null:
		return "HUD_MSG_ABILITY_NEEDS_BODY"
	if health.current >= health.effective_maximum(owner):
		return "HUD_MSG_HEALTH_FULL"
	return ""
