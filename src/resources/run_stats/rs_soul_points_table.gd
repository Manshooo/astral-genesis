## res://src/resources/run_stats/rs_soul_points_table.gd
## Очки души за поглощённое сознание: шкала по классу тела и множители повторов (data/soul_points_table.tres). Отдельный ресурс —
## шкалу пересчитывает game-balance целиком; грузится по пути (current). Числа черновые: десятки и сотни, эссенция — тысячи.
class_name RS_SoulPointsTable
extends Resource

const PATH := "res://data/soul_points_table.tres"

## Очки за захват по классу: индекс — E_Body.body_class (L0..L5).
@export var class_points: Array[int] = [10, 25, 60, 120, 250, 500]
## Множитель за ПЕРВЫЙ захват вида в забеге.
@export var first_kind_multiplier: float = 2.0
## Множители повторных захватов того же вида; дальше списка — ноль (фармить труп бессмысленно).
@export var repeat_multipliers: Array[float] = [0.5, 0.25]
## «Чистый выход» (O_ExpelFromBody): бонус сверху шкалы захватов.
@export var clean_exit_points: int = 15

static var _cached: RS_SoulPointsTable


## Таблица игры; load() в рантайме, не preload (godotengine/godot#100100).
static func current() -> RS_SoulPointsTable:
	if _cached == null:
		_cached = load(PATH) as RS_SoulPointsTable
	if _cached == null:
		push_warning("RS_SoulPointsTable: нет %s — берутся числа по умолчанию" % PATH)
		_cached = RS_SoulPointsTable.new()
	return _cached


## Очки за захват тела класса body_class, если того же вида уже захватывали prior_same_kind раз.
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
