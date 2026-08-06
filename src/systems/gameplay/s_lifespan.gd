# res://src/systems/gameplay/s_lifespan.gd
# Группа: "gameplay". Тикает распад БФЖ — ВСЕГДА в реальном времени, 1 с/с, в
# любом состоянии. Тело не замедляет ход времени, оно увеличивает сам запас
# (C_Lifespan.effective_max): иначе подпись «45 с» в HUD врала бы, потому что эти
# 45 секунд шли бы вдвое дольше.
#
# Истечение запаса — настоящая смерть в любом состоянии: событие "run_ended" +
# тег C_Dead, чтобы распад не объявлялся повторно каждый кадр. На "run_ended"
# подписан O_RunEnded → RunManager.die() (запись смерти в сейв, снос забега,
# экран смерти).
class_name S_Lifespan
extends System


## Любая душа с запасом жизни, ещё не объявленная мёртвой. C_Embodied сущность из
## выборки НЕ исключает: во плоти распад тоже идёт, просто запас больше.
func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var life := entity.get_component(C_Lifespan) as C_Lifespan
		life.current -= delta
		# Потолок — свойство СОСТОЯНИЯ, а не того, кто это состояние менял:
		# запас, набранный в теле, не может пережить выход из него, кто бы ни снял
		# C_Embodied. O_ExpelFromBody режет излишек сам, чтобы HUD не мигнул
		# переполненной шкалой, но правило держится здесь.
		# ВНИМАНИЕ: в v0.5.0 запас должен уметь ПРЕВЫШАТЬ максимум (и утекать
		# сверх него быстрее) — тогда этот clamp заменяется, а не удаляется.
		life.current = minf(life.current, life.effective_max(entity.has_component(C_Embodied)))
		if life.current <= 0.0:
			life.current = 0.0
			cmd.add_component(entity, C_Dead.new())
			ECS.world.emit_event(&"run_ended", entity)
