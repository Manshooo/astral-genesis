# res://src/observers/o_run_ended.gd
# Наблюдатель конца забега по СМЕРТИ: S_Lifespan шлёт "run_ended" (+ C_Dead), когда стабильность души иссякла вне тела;
# передаём RunManager.die() отложенно (call_deferred): снос комнаты и смена сцены не в проходе ECS (ср. O_ExpelFromBody).
class_name O_RunEnded
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).on_event(&"run_ended")


func each(_event: Variant, _entity: Entity, _payload: Variant = null) -> void:
	RunManager.die.call_deferred()
