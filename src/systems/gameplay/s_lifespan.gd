# res://src/systems/gameplay/s_lifespan.gd
# Группа: "gameplay". Тикает распад БФЖ. Развоплощённая душа тает с полной
# скоростью, во плоти — замедленно (C_Lifespan.embodied_rate): тело снимает
# давление времени, но не отменяет его, иначе после первого же захвата забег
# перестаёт торопить. Полный запас возвращает сам момент вселения
# (S_BodySnatch._embody), так что охота за телами и остаётся способом выжить.
#
# Истечение запаса — настоящая смерть в любом состоянии: событие "run_ended" +
# тег C_Dead, чтобы распад не объявлялся повторно каждый кадр. На "run_ended"
# подписан O_RunEnded → RunManager.die() (запись смерти в сейв, снос забега,
# экран смерти).
class_name S_Lifespan
extends System


## Любая душа с запасом жизни, ещё не объявленная мёртвой. C_Embodied больше НЕ
## исключает сущность из выборки — он только замедляет тик (см. process).
## Враги/тела без C_Lifespan сюда не попадают.
func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var life := entity.get_component(C_Lifespan) as C_Lifespan
		var rate := life.embodied_rate if entity.has_component(C_Embodied) else 1.0
		if rate <= 0.0:
			continue
		life.current -= delta * rate
		if life.current <= 0.0:
			life.current = 0.0
			cmd.add_component(entity, C_Dead.new())
			ECS.world.emit_event(&"run_ended", entity)
