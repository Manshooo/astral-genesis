class_name C_EnemyAI
extends Component
## Простое поведение врага: вне радиуса аггро — стоит, увидев цель — бежит по
## прямой и бьёт в упор по кулдауну. Числа авторские, тюнятся в сцене
## конкретного врага — как C_Walk.speed у тел.
##
## Состояние — enum-поле здесь, а не россыпь тег-компонентов C_Idle/C_Chasing:
## так короче путь чтения (одна S_EnemyAI смотрит на одно поле) и нет риска
## навесить сразу два взаимоисключающих тега (см. «GECS и правила движка» про
## FSM в ECS).

enum State { IDLE, CHASING }

## Дистанция, с которой враг замечает воплощённого БФЖ.
@export var aggro_range: float = 10.0
## Дистанция, с которой враг бьёт вместо того, чтобы бежать дальше.
@export var attack_range: float = 1.8
@export var attack_damage: float = 15.0
## Пауза между ударами, с.
@export var attack_interval: float = 1.0

## Текущее состояние — читается HUD/будущими системами, пишет только S_EnemyAI.
@export var state: State = State.IDLE
## Сколько ещё ждать до следующего удара. 0 — можно бить прямо сейчас.
@export var attack_cooldown_left: float = 0.0
