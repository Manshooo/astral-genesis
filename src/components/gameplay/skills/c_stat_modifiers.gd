class_name C_StatModifiers
extends Component
## Слой модификаторов души: «база + модификаторы» вместо присваивания полей. Механика читает ПОСЧИТАННЫЙ
## стат — база аргументом of(), база НИКОГДА не переписывается (эффект можно снять, скиллы складываются).
## Свёртка (base + Σflat) * Πmult не зависит от порядка. Модификаторы — по ИСТОЧНИКАМ; set_source идемпотентен.
## Живёт на душе, не экспортируется (производное из SkillManager).


## Каталог статов — из него RS_StatModifier рисует выпадающий список (опечатка не доживает до рантайма).
const CAPTURE_RANGE := &"capture_range"        ## C_BodySnatch.capture_range, м
const CAPTURE_CHANCE := &"capture_chance"      ## C_BodySnatch.capture_success_chance, 0..1
const SOUL_LIFESPAN := &"soul_lifespan"        ## C_Lifespan.max_duration, с
const BODY_DECAY := &"body_decay"              ## C_BodyDecay.maximum — объём кармана тела, с
const BODY_HEALTH := &"body_health"            ## C_Health.maximum надетого тела
const WALK_SPEED := &"walk_speed"              ## C_Walk.speed, м/с
const JUMP_VELOCITY := &"jump_velocity"        ## C_Jump.velocity, м/с
## C_Sprint.speed_multiplier — «бегай быстрее» и «ходи быстрее» разные перки; сам бег — источником в WALK_SPEED (S_Sprint).
const SPRINT_MULTIPLIER := &"sprint_multiplier"
## Доля остатка тела при ДОБРОВОЛЬНОМ выходе (база 1.0).
const LEAVE_BODY_GAIN := &"leave_body_gain"
const OVERFLOW_LEAK := &"overflow_leak"        ## RS_GameConfig.lifespan_overflow_leak
const DEATH_KEEP := &"death_keep"              ## RS_GameConfig.lifespan_death_fraction
## Доля номинала эссенции из находок и тайников (база — essence_gain_base, навык поднимает до 1.0); касание Архитектора не множит.
const ESSENCE_GAIN := &"essence_gain"

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
	ESSENCE_GAIN,
]

## источник → {"flat": {стат: сумма}, "mult": {стат: произведение}}; по источникам — чтобы снять один целиком.
var _sources: Dictionary = {}
## Свёртка всех источников — кэш для value(), пересчитывается в _refold().
var _flat: Dictionary = {}
var _mult: Dictionary = {}


## Эффективное значение стата; терпима к отсутствию компонента — у врага модификаторов нет, база и есть ответ.
static func of(entity: Entity, stat: StringName, base: float) -> float:
	if entity == null:
		return base
	var mods := entity.get_component(C_StatModifiers) as C_StatModifiers
	return mods.value(stat, base) if mods else base


func value(stat: StringName, base: float) -> float:
	return RS_StatModifier.resolve(stat, base, _flat, _mult)


## Заменить вклад одного источника целиком; словари приходят уже свёрнутыми по рангу.
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


## Словари ПЕРЕСОБИРАЮТСЯ и присваиваются, не правятся на месте: GECS делает компонентам shallow duplicate().
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
