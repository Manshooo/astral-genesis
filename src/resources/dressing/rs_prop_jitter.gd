## Как пропу с PropJitter позволено отойти от нарисованного места (data/chair_jitter.tres): сдвиг, поворот, шанс
## быть отодвинутым назад и шанс пропасть. Лицо пропа — +Z, отодвигается он назад. Вики: [[Расстановка пропов в комнатах]].
class_name RS_PropJitter
extends Resource

## Смещение по полу (м) и поворот (градусы) в обе стороны.
@export var offset := 0.1
@export var turn := 12.0
## Отодвинут назад от того, к чему стоит лицом, и довёрнут.
@export_range(0.0, 1.0) var pushed_chance := 0.25
@export var push_distance := 0.35
@export var push_turn := 25.0
@export_range(0.0, 1.0) var missing_chance := 0.1
