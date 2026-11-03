class_name C_FirstPersonMotion
extends C_BodyTrait
## Как камера носителя следует за головой ЭТОГО тела: где голова облика стоя, на рыси, в беге и в укусе, плюс качка в
## такт шагу. Без этого камера стоит у маркера Eyes, а голова в галопе уходит на метр вниз и вперёд — взгляд упирался
## бы в собственную спину. Пишет S_FirstPersonMotion; характеристика тела, едет на душу при захвате. Вики: [[Захват тела]].

## Где голова облика (точка между глаз) относительно базы глаз, м, в осях тела (−Z — вперёд): стоя и на шаге,
## в среднем по циклу рыси и бега, в пике выпада укуса. Меряет арт по кости головы в клипах.
@export var stand_head: Vector3 = Vector3.ZERO
@export var trot_head: Vector3 = Vector3.ZERO
@export var run_head: Vector3 = Vector3.ZERO
@export var bite_head: Vector3 = Vector3.ZERO

## Качка на шаге и рыси, м: x — вниз, y — вбок.
@export var walk_bob: Vector2 = Vector2(0.03, 0.01)

## Сколько раз камера проседает за цикл клипа walk и trot (у шага — на каждую ногу, у рыси — на каждую опору).
@export var walk_bounces: int = 2

## Где в цикле walk и trot (доля от первого кадра) голова облика ниже всего — туда же ляжет просадка камеры.
@export_range(0.0, 1.0) var walk_low: float = 0.0
@export_range(0.0, 1.0) var trot_low: float = 0.0

## Качка на бегу, м: x — вниз, y — вбок. Слабее, чем ход головы в клипе: сильная качка на бегу укачивает.
@export var run_bob: Vector2 = Vector2(0.025, 0.0)

## Сколько раз камера проседает за цикл клипа run (галоп — один толчок).
@export var run_bounces: int = 1

## То же для run.
@export_range(0.0, 1.0) var run_low: float = 0.0

## Крен на бегу, градусы; 0 — без крена.
@export var run_roll: float = 0.0

## Укус: насколько камера клюёт вниз (градусы), сколько длится выпад (с, как клип attack) и на какой его доле
## голова дальше всего.
@export var bite_dip: float = 4.0
@export var bite_time: float = 0.45
@export_range(0.05, 0.95) var bite_peak: float = 0.64

## Состояние между тиками: вес каждого аллюра (0..1, по нему и качка, и голова), остаток рывка, перезарядка удара.
var walk_weight: float = 0.0
var trot_weight: float = 0.0
var run_weight: float = 0.0
var bite_left: float = 0.0
var last_cooldown: float = 0.0
