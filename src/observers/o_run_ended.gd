# res://src/observers/o_run_ended.gd
# Наблюдатель конца забега по СМЕРТИ. S_Lifespan шлёт "run_ended" (+ вешает C_Dead),
# когда запас распада БФЖ иссяк в развоплощён. Здесь передаём управление
# RunManager.die(): фиксация смерти в сейве, снос забега, экран смерти.
#
# Отложенно (call_deferred): die() сносит комнату и меняет сцену — делать это в
# середине прохода ECS по сущностям нельзя (ср. O_ExpelFromBody).
class_name O_RunEnded
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).on_event(&"run_ended")


func each(_event: Variant, _entity: Entity, _payload: Variant = null) -> void:
	RunManager.die.call_deferred()
