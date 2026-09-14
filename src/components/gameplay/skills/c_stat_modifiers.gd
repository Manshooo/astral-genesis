class_name C_StatModifiers
extends Component
## Слой модификаторов души: «база + модификаторы» вместо присваивания полей.
##
## Механика читает не поле, а ПОСЧИТАННЫЙ стат: авторское число плюс то, что
## накопила душа. Где лежит авторское число, паттерну безразлично — поле
## компонента тела (C_Walk.speed), поле кармана (C_BodyDecay.maximum) или
## скаляр из RS_GameConfig (lifespan_death_fraction). Это и есть причина, по
## которой база передаётся в of() аргументом, а не ищется по реестру
## «стат → компонент → поле»: реестр покрыл бы только компоненты, а половина
## того, что просятся крутить скиллами, компонентами не является.
##
## База НИКОГДА не переписывается. Отсюда всё остальное: два скилла на один стат
## складываются, а не затирают друг друга; эффект можно снять (респек, конец
## забега, временный баф), потому что исходное число никуда не девалось.
##
## Свёртка: (base + Σflat) * Πmult. Порядок выдачи скиллов на результат не
## влияет — иначе «модификаторы как данные» не работали бы: выдать их можно из
## дерева перков, из награды за забег и из временного эффекта, и все три пути
## обязаны сходиться в одно число.
##
## Модификаторы сгруппированы по ИСТОЧНИКУ (&"skills", улучшения забега, баф).
## Источник перезаписывается целиком одним вызовом set_source, поэтому пересчёт
## идемпотентен: не нужно помнить, что источник давал в прошлый раз, и повторное
## применение не удваивает эффект.
##
## Компонент живёт на душе (E_Player.define_components) и НЕ экспортируется:
## это производное состояние, восстанавливаемое из SkillManager, а не то, что
## авторят в сцене.


## Каталог статов. Здесь он полностью — чтобы скилл можно было объявить ДАННЫМИ
## (.tres): RS_StatModifier рисует из этого списка выпадающий список в
## инспекторе, так что опечатка в имени стата не доживает до рантайма.
const CAPTURE_RANGE := &"capture_range"        ## C_BodySnatch.capture_range, м
const CAPTURE_CHANCE := &"capture_chance"      ## C_BodySnatch.capture_success_chance, 0..1
const SOUL_LIFESPAN := &"soul_lifespan"        ## C_Lifespan.max_duration, с
const BODY_DECAY := &"body_decay"              ## C_BodyDecay.maximum — объём кармана тела, с
const BODY_HEALTH := &"body_health"            ## C_Health.maximum надетого тела
const WALK_SPEED := &"walk_speed"              ## C_Walk.speed, м/с
const JUMP_VELOCITY := &"jump_velocity"        ## C_Jump.velocity, м/с
## C_Sprint.speed_multiplier — во сколько раз бег быстрее шага ЭТОГО тела.
## Сам бег кладётся в WALK_SPEED отдельным источником (см. S_Sprint), а этот
## стат крутит именно множитель: «бегай быстрее» и «ходи быстрее» — разные перки.
const SPRINT_MULTIPLIER := &"sprint_multiplier"
## Доля остатка тела, забираемая при ДОБРОВОЛЬНОМ выходе. База 1.0 — весь
## остаток; стат существует, чтобы «+10% к получаемому времени» был модификатором.
const LEAVE_BODY_GAIN := &"leave_body_gain"
const OVERFLOW_LEAK := &"overflow_leak"        ## RS_GameConfig.lifespan_overflow_leak
const DEATH_KEEP := &"death_keep"              ## RS_GameConfig.lifespan_death_fraction

const ALL: Array[StringName] = [
	CAPTURE_RANGE,
	CAPTURE_CHANCE,
	SOUL_LIFESPAN,
	BODY_DECAY,
	BODY_HEALTH,
	WALK_SPEED,
	JUMP_VELOCITY,
	SPRINT_MULTIPLIER,
	LEAVE_BODY_GAIN,
	OVERFLOW_LEAK,
	DEATH_KEEP,
]

## источник → {"flat": {стат: сумма}, "mult": {стат: произведение}}.
## Хранится ПО ИСТОЧНИКАМ, а не одной кучей, ровно ради возможности снять один
## источник целиком.
var _sources: Dictionary = {}
## Свёртка всех источников — то, что читает value(). Кэш, а не второй источник
## правды: пересчитывается в _refold() при каждой правке _sources.
var _flat: Dictionary = {}
var _mult: Dictionary = {}


## Эффективное значение стата для сущности. Статическая и терпимая к отсутствию
## компонента: читают её системы, которые ходят и по душе, и по обычным врагам
## (S_Health), а у врага никаких модификаторов нет и заводить их незачем — база
## и есть ответ.
static func of(entity: Entity, stat: StringName, base: float) -> float:
	if entity == null:
		return base
	var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
	return mods.value(stat, base) if mods else base


func value(stat: StringName, base: float) -> float:
	var flat: float = _flat.get(stat, 0.0)
	var mult: float = _mult.get(stat, 1.0)
	return (base + flat) * mult


## Заменить вклад одного источника целиком. Словари приходят уже свёрнутыми по
## рангу — считать ранги дело того, кто источник объявляет (O_ApplySkillEffects
## для дерева перков), а не этого компонента.
func set_source(source: StringName, flat: Dictionary, mult: Dictionary) -> void:
	var next := _sources.duplicate()
	next[source] = {"flat": flat.duplicate(), "mult": mult.duplicate()}
	_sources = next
	_refold()


func clear_source(source: StringName) -> void:
	if not _sources.has(source):
		return
	var next := _sources.duplicate()
	next.erase(source)
	_sources = next
	_refold()


## ВАЖНО: словари здесь ПЕРЕСОБИРАЮТСЯ и присваиваются, а не правятся на месте.
## GECS при add_entity делает компонентам shallow duplicate() (см. шапку
## Component), а Dictionary — ссылочный тип: правка на месте разошлась бы по
## всем копиям компонента разом. Присваивание нового словаря отвязывает копию.
func _refold() -> void:
	var flat := {}
	var mult := {}
	for entry in _sources.values():
		for stat in entry["flat"]:
			flat[stat] = flat.get(stat, 0.0) + entry["flat"][stat]
		for stat in entry["mult"]:
			mult[stat] = mult.get(stat, 1.0) * entry["mult"][stat]
	_flat = flat
	_mult = mult
