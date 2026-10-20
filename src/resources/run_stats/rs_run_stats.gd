## res://src/resources/run_stats/rs_run_stats.gd
## Итоги ОДНОГО забега. Показатели — СЛОВАРЬ ключей (набор открыт: новый показатель стоит ключа здесь и строки в каталоге), ресурс — а не
## автолоад: те же данные нужны истории забегов в хабе, и статистика едет в сейве (`RS_WorldSave.run_stats`), чтобы выход в меню не обнулял её.
## Вики: [[Цикл забега]] (Сводка забега).
class_name RS_RunStats
extends Resource

## Ключи показателей: строка сводки ссылается на ключ, а не на поле.
const TIME := &"time"  ## секунды забега, без пауз
const ROOMS := &"rooms"  ## сколько РАЗНЫХ комнат посещено
const BODIES := &"bodies"  ## сколько тел занято
const DAMAGE_TAKEN := &"damage_taken"
const DAMAGE_DEALT := &"damage_dealt"
const SKILL_POINTS := &"skill_points"  ## очки души за этот забег — сумма по источникам ниже
const ESSENCE := &"essence"  ## эссенция за этот забег — сумма по источникам ниже

## Источники очков души и эссенции (разбивка): итог не говорит, откуда он, а баланс решает, сколько брать откуда. Пишутся через credit().
const POINTS_ABSORB := &"points_absorb"  ## захват тела (поглощение сознания)
const POINTS_CLEAN_EXIT := &"points_clean_exit"  ## «чистый выход» из выжатого тела
const ESSENCE_ARCHITECT := &"essence_architect"  ## касание Архитектора
const ESSENCE_PICKUP := &"essence_pickup"  ## находка в комнате (LayerFinds)
const ESSENCE_CACHE := &"essence_cache"  ## тайник в тупике коридора (LayerFinds)

## Источник -> итог его валюты; источник без записи не попадёт ни в один итог, тихо.
const SOURCE_TOTALS := {
	POINTS_ABSORB: SKILL_POINTS,
	POINTS_CLEAN_EXIT: SKILL_POINTS,
	ESSENCE_ARCHITECT: ESSENCE,
	ESSENCE_PICKUP: ESSENCE,
	ESSENCE_CACHE: ESSENCE,
}

## Чем кончился забег: смерть показывает экран итогов, побег — экран концовки (тот же снимок).
const OUTCOME_DEATH := &"death"
const OUTCOME_ESCAPE := &"escape"

## Накопленные числа по ключам; отсутствие ключа — ноль (value).
@export var counters: Dictionary[StringName, float] = {}

## Занятые тела в порядке захвата — подробность, не число.
@export var bodies: Array[RS_RunBody] = []

@export var outcome: StringName = &""

## Метры, зачтённые дистанционным условиям навыков по клеткам забега ("<глубина>:<x>:<y>:<z>" -> м):
## клетка «новая» только в пределах забега. Ключ строкой — Dictionary с Vector-ключами в .tres хрупок.
@export var cell_credit: Dictionary = {}


func add(key: StringName, amount: float) -> void:
	counters[key] = counters.get(key, 0.0) + amount


## Показатель, который ЗНАЕТСЯ целиком (комнаты считает сейв — второй счётчик разъехался бы).
func put(key: StringName, amount: float) -> void:
	counters[key] = amount


func value(key: StringName) -> float:
	return counters.get(key, 0.0)


## Захват тела: подробностью в bodies и числом в счётчике одной функцией.
func note_body(scene_path: String, name_key: StringName) -> RS_RunBody:
	var record := RS_RunBody.new()
	record.scene_path = scene_path
	record.name_key = name_key
	record.taken_at = value(TIME)
	bodies.append(record)
	add(BODIES, 1.0)
	return record


## Тело игрока сейчас — последнее занятое; задел под показатели ПО ТЕЛУ. null — призрак.
func current_body() -> RS_RunBody:
	return bodies.back() if not bodies.is_empty() else null


## Записать в разбивку amount от source и в итог его валюты. Только запись: очки и эссенцию выдают RunStats.award_*.
func credit(source: StringName, amount: float) -> void:
	if amount <= 0.0 or not SOURCE_TOTALS.has(source):
		return
	add(source, amount)
	add(SOURCE_TOTALS[source], amount)


## Сколько раз вид уже захвачен в этом забеге (множители повторов); по записям тел — загрузка продолжает счёт.
func captures_of_kind(scene_path: String) -> int:
	var count := 0
	for body in bodies:
		if body != null and body.scene_path == scene_path:
			count += 1
	return count


## Зачесть шаг step м по клетке cell_id; возвращает засчитанное. Клетка даёт не больше cell_budget: кругами по одной «километры» не набрать.
func credit_cell_distance(cell_id: String, step: float, cell_budget: float) -> float:
	var used := float(cell_credit.get(cell_id, 0.0))
	var granted := clampf(minf(step, cell_budget - used), 0.0, step)
	if granted > 0.0:
		cell_credit[cell_id] = used + granted
	return granted


static func cell_key(depth: int, cell: Vector3i) -> String:
	return "%d:%d:%d:%d" % [depth, cell.x, cell.y, cell.z]
