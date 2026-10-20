class_name C_Jump
extends C_BodyTrait
## Умение прыгать и его сила у этого тела; нет компонента = прыгать нечем (тело не попадает в выборку S_Jump).

## Начальная скорость прыжка вверх, м/с. АБСОЛЮТНАЯ.
@export var velocity: float = 6.0

## Действие прыжка; резолвится из InputMap по имени (как C_Interactable.action_name).
@export var action_name: StringName = &"jump"
