class_name C_Walk
extends C_BodyTrait
## Умение ходить по земле и скорость этого тела. Нет компонента = не ходит (призрак летит, S_Flight).

## Клипы, без которых анимированное тело с этой способностью не обходится (dev/body_clips_check).
const CLIPS: Array[StringName] = [&"idle", &"walk"]

## Скорость по горизонтали, м/с; абсолютная.
@export var speed: float = 4.5
