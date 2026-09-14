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
const SKILL_POINTS := &"skill_points"  ## награда за этот забег

## Чем кончился забег. Пока экран итогов один — на смерть; побег (`finish_run`)
## забег тоже завершает, и когда у победы появится свой экран, ей понадобится
## ровно этот же снимок, только с другим заголовком.
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
