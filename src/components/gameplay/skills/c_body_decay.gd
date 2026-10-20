class_name C_BodyDecay
extends C_BodyTrait
## Карман распада ТЕЛА: сколько секунд душа проживёт в нём (свой запас души — C_Lifespan). Компонент,
## а не поля в C_Lifespan: наличие компонента и есть «есть тело». Запас — отдельное число, не формула
## от прочности. Вики: [[Захват тела]] (модель запаса).

## Секунд, что тело даёт целиком — авторское число; прибавки скиллов считает effective_maximum.
@export var maximum: float = 60.0

## Сколько осталось. Состояние: не @export, заполняется в on_worn и из сейва.
var remaining: float = 0.0


## Тело надето — карман открывается полным. Остаток прошлого тела сгорает при пересадке: иначе
## выгодно было бы прыгать по телам, копя чужое время, а добровольный выход обесценился.
func on_worn(soul: Entity) -> void:
	remaining = effective_maximum(soul)


## Сколько секунд тело даёт ЭТОЙ душе: авторское число плюс её модификаторы.
func effective_maximum(soul: Entity) -> float:
	return C_StatModifiers.of(soul, C_StatModifiers.BODY_DECAY, maximum)
