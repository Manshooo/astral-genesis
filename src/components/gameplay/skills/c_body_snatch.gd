class_name C_BodySnatch
extends Component

@export var capture_range: float = 2.0
@export var capture_success_chance: float = 0.5
## Звук удавшегося захвата — разовое событие byProd ([[Звук]]).
@export var capture_event: String = "event:/sfx/capture"

## Транзиентный запрос захвата на кадр: ставит E_Player, сбрасывает S_BodySnatch. Не экспортируется.
var capture_requested := false

## Транзиентный запрос ПОКИНУТЬ тело (leave_body): ввод ставит флаг, решает S_BodySnatch. Только
## добровольный выход отдаёт игроку остаток запаса тела (O_ExpelFromBody.expel).
var leave_requested := false
