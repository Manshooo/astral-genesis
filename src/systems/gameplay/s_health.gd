# res://src/systems/gameplay/s_health.gd
# Группа: "gameplay".
# Базовая система здоровья. Следит за C_Health у ВСЕХ сущностей (игрок, враги,
# захваченные тела) и делает ровно две вещи:
#   1. Держит current в пределах [0, maximum] — защита от переотхила/ухода в минус.
#   2. Когда HP падает до нуля, ОДИН раз объявляет о смерти: вешает тег C_Dead и
#      шлёт событие "entity_died" (GECS emit_event -> Observer.on_event).
#      Событие несёт саму сущность, поэтому наблюдатели могут фильтровать, чью
#      именно смерть обрабатывать (напр. только игрока: with_all([C_PlayerInput])).
#
# Чего система намеренно НЕ делает:
#   - не наносит урон (это дело боевых систем — они меняют C_Health.current);
#   - не удаляет тело из мира и не решает, что значит смерть для конкретной
#     сущности. На "entity_died" подписываются те, кому это важно: игрок
#     (конец забега / перенос сознания), враг (дроп лута), и т.д.
class_name S_Health
extends System


## Только живые сущности со здоровьем. C_Dead исключает уже обработанные трупы,
## поэтому смерть гарантированно объявляется единожды.
func query() -> QueryBuilder:
	return q.with_all([C_Health]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	for entity in entities:
		var health := entity.get_component(C_Health) as C_Health
		health.current = clampf(health.current, 0.0, health.effective_maximum(entity))

		if health.current <= 0.0:
			cmd.add_component(entity, C_Dead.new())
			ECS.world.emit_event(&"entity_died", entity)
