# res://src/observers/o_expel_from_body.gd
# Наблюдатель: смерть ЗАХВАЧЕННОГО тела выбрасывает БФЖ обратно в призрака, а не
# завершает забег. Слушает событие "entity_died" (шлёт S_Health при HP<=0) для
# сущностей с C_Embodied — то есть только для воплощённой души, обычные враги без
# C_Embodied сюда не попадают.
#
# Порядок кадра (важно): S_Health вешает C_Dead ОТЛОЖЕННО (через свой командный
# буфер) и СИНХРОННО шлёт "entity_died". Снимать C_Health/C_Embodied прямо здесь
# нельзя — снятие произошло бы ДО применения C_Dead, и душа залипла бы мёртвой.
# Поэтому развоплощение откладываем через call_deferred: оно выполнится после того,
# как все командные буферы кадра применятся, и снимаем в т.ч. сам C_Dead.
class_name O_ExpelFromBody
extends Observer

## Порог выжатости тела, с которого добровольный выход даёт очко навыка (см.
## _settle_lifespan) — «дошёл до предела», а не «попробовал и вышел». Тело к
## этому моменту уже поглощено безвозвратно (S_BodySnatch._embody), так что
## фармить одно и то же тело повторным входом-выходом архитектурно нельзя —
## порог нужен только затем, чтобы награда отражала риск, а не сам факт выхода.
const _GRACEFUL_EXIT_DECAY_THRESHOLD := 0.5
const _GRACEFUL_EXIT_REWARD := 1


func query() -> QueryBuilder:
	return q.with_all([C_Embodied]).on_event(&"entity_died")


func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
	expel.call_deferred(entity, false)


## Развоплощение: снять «во плоти» и все характеристики тела (C_BodyTrait +
## C_Health), а также тег смерти (тело умерло, но душа — нет). Облик и форма
## снимаются тоже — O_BodyVisual и O_BodyForm по снятию своих компонентов вернут
## ригу его собственный вид и призрачный габарит.
##
## Статическая и с явным [param voluntary], потому что вызывают её ТРИ разных
## пути и правило распада у них разное:
##   - гибель тела от урона (этот наблюдатель) — voluntary = false;
##   - у тела вышло время (S_Lifespan) — voluntary = false, «сгорело — значит
##     сгорело» одинаково в обоих случаях;
##   - игрок вышел сам (S_BodySnatch) — voluntary = true.
## Держать логику в одном месте важнее, чем сэкономить параметр: разъехавшись,
## эти три пути дали бы три разных модели распада.
static func expel(soul: Entity, voluntary: bool) -> void:
	if not is_instance_valid(soul):
		return
	if not soul.has_component(C_Embodied):
		return  # уже вышли другим путём в этом же кадре

	_settle_lifespan(soul, voluntary)

	# Снимаем ВСЕ характеристики тела, не перечисляя их: что надел захват
	# (C_BodyTrait + C_Health), то и снимается — симметрия с S_BodySnatch._embody
	# держится сама, а не поддерживается вручную в двух списках.
	# Собираем список заранее: remove_component правит тот самый словарь.
	var worn: Array = []
	for component in soul.components.values():
		if component is C_BodyTrait or component is C_Health:
			worn.append(component)
	for component in worn:
		soul.remove_component(component)

	if soul.has_component(C_Dead):
		soul.remove_component(C_Dead)
	if soul.has_component(C_BodyVisual):
		soul.remove_component(C_BodyVisual)
	# Габарит и уровень глаз возвращает O_BodyForm по снятию — как и облик.
	if soul.has_component(C_BodyForm):
		soul.remove_component(C_BodyForm)
	soul.remove_component(C_Embodied)
	ECS.world.emit_event(&"expelled_from_body", soul)


## Куда девается остаток запаса тела. Тут и живёт вся модель «распад как ресурс»:
##   - вышел сам — остаток тела ПРИБАВЛЯЕТСЯ к запасу души, и сумма может уйти
##     за собственный максимум. Излишек потом утекает быстрее (S_Lifespan), так
##     что накопить буфер и ходить с ним нельзя;
##   - тело погибло — не даёт ничего, а от запаса души остаётся малая доля
##     (GameConfig.lifespan_death_fraction). Гибель тела обязана быть больнее
##     добровольного выхода, иначе выходить «правильно» незачем.
## Сам карман (C_BodyDecay) обнулять не нужно — он уходит вместе с телом, его
## снимает общий проход по трейтам выше.
static func _settle_lifespan(soul: Entity, voluntary: bool) -> void:
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	if life == null:
		return

	if voluntary:
		var decay := soul.get_component(C_BodyDecay) as C_BodyDecay
		if decay:
			# База 1.0 — забираем весь остаток. Стат существует, чтобы «+10% к
			# получаемому времени после выхода» был модификатором, а не правкой
			# этой формулы.
			var gain := C_StatModifiers.of(soul, C_StatModifiers.LEAVE_BODY_GAIN, 1.0)
			life.current += decay.remaining * gain

			var used_fraction := 1.0 - decay.remaining / decay.effective_maximum(soul)
			if used_fraction >= _GRACEFUL_EXIT_DECAY_THRESHOLD:
				SkillManager.add_skill_points(_GRACEFUL_EXIT_REWARD)
	else:
		var keep := C_StatModifiers.of(
			soul, C_StatModifiers.DEATH_KEEP, GameConfig.config.lifespan_death_fraction
		)
		life.current = minf(life.current, life.effective_max(soul) * keep)
