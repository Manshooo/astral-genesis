# res://src/systems/gameplay/s_lifespan.gd
# Группа "gameplay". Тикает стабильность души и распад тела — ВСЕГДА в реальном времени 1 с/с, кроме убежища (S_DecayShelter): тело даёт ДРУГОЙ карман, не
# замедляет время. Кончился запас ТЕЛА — душу выбрасывает наружу (не смерть); кончился запас ДУШИ — "run_ended" + C_Dead (O_RunEnded → RunManager.die()). Вики: [[Захват тела]].
class_name S_Lifespan
extends System


## Любая душа с запасом, не мёртвая; воплощённые не исключаются (из другого кармана). Души в убежище (C_Sheltered) — работа S_DecayShelter.
func query() -> QueryBuilder:
	return q.with_all([C_Lifespan]).with_none([C_Dead, C_Sheltered])


## Что тикает, решает НАЛИЧИЕ кармана тела (C_BodyDecay), не флаг «во плоти». Тело без него укрытия не даёт — время из запаса души.
func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var life := entity.get_component(C_Lifespan) as C_Lifespan
		var decay := entity.get_component(C_BodyDecay) as C_BodyDecay
		if decay:
			_tick_body(entity, decay, delta)
		else:
			_tick_soul(entity, life, delta)


## Во плоти тратится запас ТЕЛА; догорело — выбрасываем тем же путём, что при гибели от урона (O_ExpelFromBody).
func _tick_body(entity: Entity, decay: C_BodyDecay, delta: float) -> void:
	decay.remaining -= delta
	if decay.remaining > 0.0:
		return
	decay.remaining = 0.0
	# Отложенно: развоплощение снимает компоненты посреди прохода по архетипам (правило v9).
	O_ExpelFromBody.expel.call_deferred(entity, false)


## Развоплощён — тратится запас души; излишек из тела утекает быстрее.
func _tick_soul(entity: Entity, life: C_Lifespan, delta: float) -> void:
	var remaining := delta

	var overflow := life.overflow(entity)
	if overflow > 0.0:
		# Темп утечки — стат; снизу единица: излишек не утекает МЕДЛЕННЕЕ обычного (буфер был бы выгоднее), и защита деления: ноль давал бы бессмертие.
		var leak := maxf(
			C_StatModifiers.of(
				entity, C_StatModifiers.OVERFLOW_LEAK, GameConfig.config.lifespan_overflow_leak
			),
			1.0
		)
		var burned := remaining * leak
		if burned < overflow:
			# Весь кадр ушёл на излишек, обычный запас не тронут.
			life.current -= burned
			return
		# Излишек кончился ВНУТРИ кадра: остаток кадра — обычным темпом, иначе на высоком fps излишек сгорал бы медленнее.
		life.current = life.effective_max(entity)
		remaining -= overflow / leak

	life.current -= remaining
	if life.current <= 0.0:
		life.current = 0.0
		cmd.add_component(entity, C_Dead.new())
		ECS.world.emit_event(&"run_ended", entity)
