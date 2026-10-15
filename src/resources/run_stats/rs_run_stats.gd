## res://src/resources/run_stats/rs_run_stats.gd
## Итоги ОДНОГО забега: что игрок успел, прежде чем распасться.
##
## ПОЧЕМУ СЛОВАРЬ ПОКАЗАТЕЛЕЙ, А НЕ ПОЛЯ. Набор показателей открыт и будет
## пополняться — артефакты, способности, нажатые в каждом теле, чем именно нанесён
## урон. Поле на каждый показатель означало бы, что «добавить строку в сводку» —
## это правка ресурса, экрана и сейва разом. Со словарём новый показатель стоит
## ключа здесь и строки в `data/run_stat_catalog.tres`; ни этот файл, ни экран не
## меняются.
##
## ПОЧЕМУ РЕСУРС, А НЕ ПЕРЕМЕННЫЕ В АВТОЛОАДЕ. Те же данные нужны истории забегов
## на доске в хабе (v0.7.0) — там они лежат сохранёнными на несколько забегов
## назад. И уже сейчас статистика едет в сейве рядом с прогрессом забега
## (`RS_WorldSave.run_stats`): без этого «выход в меню» посреди забега обнулял бы
## всё, что игрок успел.
class_name RS_RunStats
extends Resource

## Ключи показателей. Строка сводки ссылается на ключ, а не на поле, поэтому
## новый показатель — это константа здесь и строка в каталоге.
const TIME := &"time"  ## секунды забега, без пауз
const ROOMS := &"rooms"  ## сколько РАЗНЫХ комнат посещено
const BODIES := &"bodies"  ## сколько тел занято
const DAMAGE_TAKEN := &"damage_taken"
const DAMAGE_DEALT := &"damage_dealt"
const SKILL_POINTS := &"skill_points"  ## очки души за этот забег — сумма по источникам ниже
const ESSENCE := &"essence"  ## эссенция за этот забег — сумма по источникам ниже

## Источники очков души и эссенции (разбивка, §7 карточки «Игровой цикл»). Без
## разбивки график прогрессии не сверить: итог «получено 140» не говорит, откуда
## оно, а баланс как раз и решает, сколько брать откуда. Пишутся через [method
## credit], который сам растит и итог своей валюты.
const POINTS_ABSORB := &"points_absorb"  ## захват тела (поглощение сознания)
const POINTS_CLEAN_EXIT := &"points_clean_exit"  ## «чистый выход» из выжатого тела
const ESSENCE_ARCHITECT := &"essence_architect"  ## касание Архитектора
## Находки в комнатах. Пишет следующая волна (источники эссенции); ключ и запись
## заведены сейчас, чтобы строка сводки и API уже были на месте.
const ESSENCE_PICKUP := &"essence_pickup"

## Источник -> итог его валюты. Одно место, где сказано, какая валюта у источника:
## новый источник без записи здесь не попадёт ни в один итог, и тихо.
const SOURCE_TOTALS := {
	POINTS_ABSORB: SKILL_POINTS,
	POINTS_CLEAN_EXIT: SKILL_POINTS,
	ESSENCE_ARCHITECT: ESSENCE,
	ESSENCE_PICKUP: ESSENCE,
}

## Чем кончился забег. Смерть показывает экран итогов, побег (`finish_run`) —
## экран концовки (src/ui/ending/), который читает тот же снимок, коротко.
const OUTCOME_DEATH := &"death"
const OUTCOME_ESCAPE := &"escape"

## Накопленные числа по ключам выше. Отсутствие ключа читается как ноль (см.
## [method value]) — показатель, который в этом забеге ни разу не случился, не
## обязан заводить запись.
@export var counters: Dictionary[StringName, float] = {}

## Занятые тела в порядке захвата. Отдельно от счётчика `BODIES`, потому что это
## не число, а подробность: какие именно тела и что игрок в них делал.
@export var bodies: Array[RS_RunBody] = []

@export var outcome: StringName = &""

## Сколько метров уже зачтено дистанционным условиям навыков по каждой клетке
## этого забега: "<глубина>:<x>:<y>:<z>" -> метры. Лежит с забегом, а не в
## навыках: клетка «новая» только в пределах забега, и загрузка не должна
## отдавать посещённые клетки заново. Ключ строкой — Dictionary с Vector-ключами
## в .tres хрупок, а строка переживает любой формат сейва.
@export var cell_credit: Dictionary = {}


func add(key: StringName, amount: float) -> void:
	counters[key] = counters.get(key, 0.0) + amount


## Показатель, который не копится, а ЗНАЕТСЯ целиком (комнаты считает сейв —
## заводить рядом второй счётчик значило бы разъехаться с ним при первом же
## возврате в уже посещённую комнату).
func put(key: StringName, amount: float) -> void:
	counters[key] = amount


func value(key: StringName) -> float:
	return counters.get(key, 0.0)


## Записывает захват тела: и подробностью в [member bodies], и числом в счётчике.
## Обе записи делает одна функция — разъехаться им негде.
func note_body(scene_path: String, name_key: StringName) -> RS_RunBody:
	var record := RS_RunBody.new()
	record.scene_path = scene_path
	record.name_key = name_key
	record.taken_at = value(TIME)
	bodies.append(record)
	add(BODIES, 1.0)
	return record


## Тело, в котором игрок находится сейчас, — последнее занятое. Задел под
## показатели, которые копятся ПО ТЕЛУ (сколько способностей нажато и каких,
## какие артефакты работали): их пишут в `RS_RunBody.counters` этой записи.
## null — забег идёт призраком, писать некуда.
func current_body() -> RS_RunBody:
	return bodies.back() if not bodies.is_empty() else null


## Записать в разбивку [param amount] от источника [param source] и в итог его
## валюты. Только запись: сами очки и эссенцию выдают менеджеры навыков
## (RunStats.award_soul_points / award_essence), чтобы запись и выдача не жили
## двумя независимыми вызовами у каждого источника.
func credit(source: StringName, amount: float) -> void:
	if amount <= 0.0 or not SOURCE_TOTALS.has(source):
		return
	add(source, amount)
	add(SOURCE_TOTALS[source], amount)


## Сколько раз вид (сцена тела) уже захвачен в этом забеге — для множителей
## повторов. Считается по записям тел: они лежат в сейве забега, поэтому
## загрузка продолжает счёт, а не начинает его заново.
func captures_of_kind(scene_path: String) -> int:
	var count := 0
	for body in bodies:
		if body != null and body.scene_path == scene_path:
			count += 1
	return count


## Зачесть шаг длиной [param step] метров, сделанный по клетке [param cell_key].
## Возвращает, сколько метров реально засчитано. Клетка даёт не больше своей
## стороны [param cell_budget]: ходить кругами по одной клетке (в колбе, у двери)
## «километры» не наберёт, а пройденная целиком клетка в этом забеге больше не
## даёт ничего. Это и есть «только по новым клеткам».
func credit_cell_distance(cell_key: String, step: float, cell_budget: float) -> float:
	var used := float(cell_credit.get(cell_key, 0.0))
	var granted := clampf(minf(step, cell_budget - used), 0.0, step)
	if granted > 0.0:
		cell_credit[cell_key] = used + granted
	return granted


static func cell_key(depth: int, cell: Vector3i) -> String:
	return "%d:%d:%d:%d" % [depth, cell.x, cell.y, cell.z]
