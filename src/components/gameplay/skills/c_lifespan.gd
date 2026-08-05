class_name C_Lifespan
extends Component

@export var max_duration: float = 60.0
@export var current: float = 60.0
## Во сколько раз медленнее распад идёт ВО ПЛОТИ (есть C_Embodied). 1.0 — тело не
## помогает вовсе, 0.0 — полностью останавливает распад.
##
## Не ноль намеренно: тело должно снимать давление времени, но не отменять его,
## иначе после первого же захвата забег перестаёт торопить. Полный запас тело
## всё равно возвращает в момент вселения (S_BodySnatch._embody).
@export_range(0.0, 1.0) var embodied_rate: float = 0.5
