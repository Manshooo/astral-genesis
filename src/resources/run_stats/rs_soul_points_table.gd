## res://src/resources/run_stats/rs_soul_points_table.gd
## Сколько очков души стоит поглощённое сознание: шкала по классу тела и
## множители повторов (карточка «Игровой цикл — от и до» §4.1). Заменила награду
## за глубину: та росла за спуск вниз, прочь от выхода, а очки за поглощение
## действие, а не прохождение, и сами тянут вниз — сознание L5 стоит больше всех.
##
## Отдельный ресурс, а не поля RS_GameConfig: шкалу пересчитывает game-balance
## целиком, и числа не должны делить файл с физикой и лимитами. Лежит в
## data/soul_points_table.tres и грузится по пути (current), как кэш общих
## данных, — читают её RunStats и проверки, держать ссылку на неё в конфиге
## незачем.
##
## Порядок величин — десятки и сотни (эссенция — тысячи, решение 15.10). Числа
## черновые: считать их будет game-balance после прототипа.
class_name RS_SoulPointsTable
extends Resource

const PATH := "res://data/soul_points_table.tres"

## Очки за захват тела по классу: индекс — E_Body.body_class (L0..L5). L0 меньше
## всех, L5 больше всех.
@export var class_points: Array[int] = [10, 25, 60, 120, 250, 500]
## Множитель за ПЕРВЫЙ захват вида (сцены тела) в забеге.
@export var first_kind_multiplier: float = 2.0
## Множители повторных захватов того же вида: первый повтор, второй, … Дальше
## списка — ноль: фармить один и тот же труп бессмысленно.
@export var repeat_multipliers: Array[float] = [0.5, 0.25]
## «Чистый выход» (O_ExpelFromBody): сознание выжато до конца и усвоено целиком —
## бонус сверху шкалы захватов, поэтому на её же порядке величин.
@export var clean_exit_points: int = 15

static var _cached: RS_SoulPointsTable


## Таблица игры. Грузится в рантайме load(), а не preload: preload кастомного
## ресурса падает в debug/export-сборке (godotengine/godot#100100).
static func current() -> RS_SoulPointsTable:
	if _cached == null:
		_cached = load(PATH) as RS_SoulPointsTable
	if _cached == null:
		push_warning("RS_SoulPointsTable: нет %s — берутся числа по умолчанию" % PATH)
		_cached = RS_SoulPointsTable.new()
	return _cached


## Очки за захват тела класса [param body_class], если того же вида в этом забеге
## уже захватывали [param prior_same_kind] раз.
func points_for(body_class: int, prior_same_kind: int) -> int:
	if class_points.is_empty():
		return 0
	var base := class_points[clampi(body_class, 0, class_points.size() - 1)]
	return roundi(base * multiplier_for(prior_same_kind))


func multiplier_for(prior_same_kind: int) -> float:
	if prior_same_kind <= 0:
		return first_kind_multiplier
	if prior_same_kind > repeat_multipliers.size():
		return 0.0
	return repeat_multipliers[prior_same_kind - 1]
