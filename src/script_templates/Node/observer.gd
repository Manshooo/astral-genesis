# meta-description: Наблюдатель GECS — реакция на добавление/снятие компонентов или событие мира.
# ЗАЧЕМ этот наблюдатель: <причина в одну-две фразы>.
#
# Колбэк может прийти посреди прохода системы (событие шлют из process()), поэтому
# структурные правки здесь — тоже через cmd, а если правка сносит комнату или
# сцену — через call_deferred (см. O_ExpelFromBody, O_RunEnded).
class_name _CLASS_
extends Observer


func query() -> QueryBuilder:
	return q.with_all([]).on_added().on_removed()


func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	match event:
		Observer.Event.ADDED:
			pass
		Observer.Event.REMOVED:
			pass
