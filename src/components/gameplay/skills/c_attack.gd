class_name C_Attack
extends C_BodyTrait
## Ближний удар тела и его сила у ЭТОГО тела (числа в сцене; механика одна на всех — S_Attack).
## Нет компонента = бить нечем. C_BodyTrait, чтобы удар ехал с телом при захвате. Враг бьёт через C_EnemyAI.
## Вики: [[Захват тела]].

## Урон за удар, абсолютный.
@export var damage: float = 10.0

## Дальность удара от глаз, м (луч идёт из камеры).
@export var reach: float = 2.0

## Пауза между ударами, с.
@export var interval: float = 0.8

## Действие удара; резолвится из InputMap по имени, как C_Jump.action_name.
@export var action_name: StringName = &"attack"

## Сколько ждать до следующего удара, с. Рабочее состояние (без @export); 0 — можно бить.
var cooldown_left := 0.0
