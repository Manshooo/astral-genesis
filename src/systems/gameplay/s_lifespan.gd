# res://src/systems/gameplay/s_lifespan.gd
# Группа: "gameplay". Тикает распад БФЖ, пока он РАЗВОПЛОЩЁН (нет C_Embodied).
# Во плоти распад на паузе — тело держит сознание. Истечение
# запаса в развоплощён — настоящая смерть: событие "run_ended" + тег C_Dead,
# чтобы распад не объявлялся повторно каждый кадр.
#
# TODO: на "run_ended" пока никто не подписан — обработчик конца забега (экран
# смерти / WorldSave.record_death / возврат в хаб) появится вместе с флоу смерти.
class_name S_Lifespan
extends System


## Только развоплощённая душа: есть C_Lifespan, нет тела (C_Embodied) и ещё не
## объявлена мёртвой (C_Dead). Враги/тела без C_Lifespan сюда не попадают.
func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).with_none([C_Embodied, C_Dead])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var life := entity.get_component(C_Lifespan) as C_Lifespan
		life.current -= delta
		if life.current <= 0.0:
			life.current = 0.0
			cmd.add_component(entity, C_Dead.new())
			ECS.world.emit_event(&"run_ended", entity)
