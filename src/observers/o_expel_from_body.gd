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


func query() -> QueryBuilder:
	return q.with_all([C_Embodied]).on_event(&"entity_died")


func each(_event: Variant, entity: Entity, _payload: Variant = null) -> void:
	expel.call_deferred(entity, false)


## Развоплощение: снять «во плоти», здоровье и характеристики тела, а также тег
## смерти (тело умерло, но душа — нет). Облик снимается тоже — O_BodyVisual по
## снятию C_BodyVisual вернёт ригу его собственный вид.
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

	if soul.has_component(C_Dead):
		soul.remove_component(C_Dead)
	if soul.has_component(C_Health):
		soul.remove_component(C_Health)
	if soul.has_component(C_BodyStats):
		soul.remove_component(C_BodyStats)
	if soul.has_component(C_BodyVisual):
		soul.remove_component(C_BodyVisual)
	soul.remove_component(C_Embodied)
	ECS.world.emit_event(&"expelled_from_body", soul)


## Куда девается остаток запаса тела. Тут и живёт вся модель «распад как ресурс»:
##   - вышел сам — остаток тела ПРИБАВЛЯЕТСЯ к запасу души, и сумма может уйти
##     за собственный максимум. Излишек потом утекает быстрее (S_Lifespan), так
##     что накопить буфер и ходить с ним нельзя;
##   - тело погибло — не даёт ничего, а от запаса души остаётся малая доля
##     (GameConfig.lifespan_death_fraction). Гибель тела обязана быть больнее
##     добровольного выхода, иначе выходить «правильно» незачем.
static func _settle_lifespan(soul: Entity, voluntary: bool) -> void:
	var life := soul.get_component(C_Lifespan) as C_Lifespan
	if life == null:
		return

	if voluntary:
		life.current += life.body_current
	else:
		life.current = minf(
			life.current, life.max_duration * GameConfig.config.lifespan_death_fraction
		)

	life.body_current = 0.0
	life.body_max = 0.0
