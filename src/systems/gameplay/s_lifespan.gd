# res://src/systems/gameplay/s_lifespan.gd
# Группа: "gameplay". Тикает распад БФЖ — ВСЕГДА в реальном времени, 1 с/с, в
# любом состоянии. Тело не замедляет ход времени, оно даёт ДРУГОЙ карман, из
# которого платится это время (см. C_Lifespan): иначе подпись «45 с» в HUD врала
# бы, потому что эти 45 секунд шли бы вдвое дольше.
#
# Два исхода, и они разные:
#   - кончился запас ТЕЛА (во плоти) — тело догорело, душу выбрасывает наружу;
#     это не смерть, забег продолжается призраком;
#   - кончился запас ДУШИ (развоплощён) — настоящая смерть: событие "run_ended" +
#     тег C_Dead, чтобы распад не объявлялся повторно каждый кадр. На "run_ended"
#     подписан O_RunEnded → RunManager.die().
class_name S_Lifespan
extends System


## Любая душа с запасом жизни, ещё не объявленная мёртвой. C_Embodied сущность из
## выборки НЕ исключает: во плоти распад тоже идёт, просто из другого кармана.
func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var life := entity.get_component(C_Lifespan) as C_Lifespan
		if entity.has_component(C_Embodied):
			_tick_body(entity, life, delta)
		else:
			_tick_soul(entity, life, delta)


## Во плоти расходуется запас ТЕЛА, собственный запас души ждёт нетронутым.
## Когда тело догорело — выбрасываем душу тем же путём, что и при гибели тела от
## урона: правило «сгорело — значит сгорело» одно на оба случая, и живёт оно в
## O_ExpelFromBody.
func _tick_body(entity: Entity, life: C_Lifespan, delta: float) -> void:
	life.body_current -= delta
	if life.body_current > 0.0:
		return
	life.body_current = 0.0
	# Отложенно: развоплощение снимает компоненты, а мы внутри прохода системы по
	# массивам архетипов (см. правило v9 в CLAUDE.md).
	O_ExpelFromBody.expel.call_deferred(entity, false)


## Развоплощён — расходуется собственный запас. Излишек, принесённый из тела,
## утекает быстрее: копить буфер и ходить с ним нельзя, его надо тратить.
func _tick_soul(entity: Entity, life: C_Lifespan, delta: float) -> void:
	var remaining := delta

	var overflow := life.overflow()
	if overflow > 0.0:
		var leak: float = GameConfig.config.lifespan_overflow_leak
		var burned := remaining * leak
		if burned < overflow:
			# Весь кадр ушёл на излишек, обычный запас не тронут.
			life.current -= burned
			return
		# Излишек кончился ВНУТРИ кадра: считаем, сколько времени на него ушло, и
		# остаток кадра тикаем обычным темпом. Иначе на высоком fps излишек
		# сгорал бы медленнее, чем на низком.
		life.current = life.max_duration
		remaining -= overflow / leak

	life.current -= remaining
	if life.current <= 0.0:
		life.current = 0.0
		cmd.add_component(entity, C_Dead.new())
		ECS.world.emit_event(&"run_ended", entity)
