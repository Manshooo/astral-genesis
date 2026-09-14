class_name C_BodySnatch
extends Component

@export var capture_range: float = 2.0
@export var capture_success_chance: float = 0.5

## Транзиентный запрос захвата на этот кадр: ставит E_Player по действию snatch_body,
## сбрасывает S_BodySnatch. Не экспортируется — живёт только в рантайме, в сцену не пишется.
var capture_requested := false

## Транзиентный запрос ПОКИНУТЬ тело (действие leave_body). Тем же приёмом, что и
## захват: ввод только ставит флаг, решение принимает S_BodySnatch.
##
## Добровольный выход — не удобство, а половина модели распада: только выйдя сам,
## игрок забирает остаток запаса тела себе (см. O_ExpelFromBody.expel).
var leave_requested := false
