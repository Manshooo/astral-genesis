class_name C_BodyAnimation
extends C_BodyTrait
## Как тело анимирует движение: скорости, на которых записаны клипы, и порог перехода шага в бег. Параметры
## AnimationTree пишет S_BodyAnimation; характеристика тела — едет на душу при захвате вместе с обликом. Вики: [[Захват тела]].

## Метров за секунду, которые проходит клип walk при скорости 1 (метры за цикл / длина цикла): по ним клип
## подгоняется под фактический ход, root motion нет.
@export var walk_clip_speed: float = 1.0

## То же для run.
@export var run_clip_speed: float = 4.0

## То же для trot — рысь между шагом и бегом; 0 — у тела рыси нет, весь ход до бега идёт клипом walk.
@export var trot_clip_speed: float = 0.0

## С какой горизонтальной скорости, м/с, шаг переходит в рысь.
@export var trot_from_speed: float = 3.0

## С какой горизонтальной скорости, м/с, бежит тело без C_Sprint (враг); с C_Sprint бег — это нажатый бег.
@export var run_from_speed: float = 5.0

## Сколько секунд тело стоит, прежде чем почесаться или прислушаться (случайно в пределах).
@export var fidget_interval: Vector2 = Vector2(6.0, 14.0)

## Ниже этой скорости тело стоит.
const STILL_SPEED := 0.2

## Состояние между тиками: S_BodyAnimation узнаёт удар по сбросу перезарядки, попадание — по падению прочности.
var state: StringName = &"idle"
var last_cooldown: float = 0.0
var last_health: float = -1.0
var airborne: bool = false
var landing_left: float = 0.0
var fidget_left: float = -1.0
