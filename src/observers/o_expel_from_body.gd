# res://src/observers/o_expel_from_body.gd
# Наблюдатель: смерть ЗАХВАЧЕННОГО тела выбрасывает БФЖ обратно в призрака, а не
# завершает забег (см. ADR-0002). Слушает событие "entity_died" (шлёт S_Health при
# HP<=0) для сущностей с C_Embodied — то есть только для воплощённой души, обычные
# враги без C_Embodied сюда не попадают.
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
	_expel.call_deferred(entity)


## Развоплощение: снять «во плоти» и здоровье тела, а также тег смерти (тело
## умерло, но душа — нет). C_Lifespan остаётся и снова начинает тикать —
## S_Lifespan матчит развоплощённую душу по with_none([C_Embodied]).
func _expel(soul: Entity) -> void:
	if not is_instance_valid(soul):
		return
	if soul.has_component(C_Dead):
		soul.remove_component(C_Dead)
	if soul.has_component(C_Health):
		soul.remove_component(C_Health)
	if soul.has_component(C_Embodied):
		soul.remove_component(C_Embodied)
	ECS.world.emit_event(&"expelled_from_body", soul)
