class_name C_Sprint
extends C_BodyTrait
## Умение бежать и его сила у этого тела; нет компонента = бежать нечем (ползун). Единственное число —
## МНОЖИТЕЛЬ (исключение из «абсолютных» в C_BodyTrait): бег во столько раз быстрее шага ЭТОГО тела, и перк
## на ходьбу действует на бег.
@export var speed_multiplier: float = 1.7

## Действие бега; резолвится из InputMap по имени (как C_Jump.action_name).
@export var action_name: StringName = &"sprint"

## Бежим ли ПРЯМО СЕЙЧАС. Рабочее состояние (не @export): модификатор ставится и снимается по фронту (S_Sprint).
var active := false
