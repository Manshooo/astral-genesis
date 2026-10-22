# res://src/systems/gameplay/s_regeneration.gd
# Группа "gameplay". Регенерация: по C_Regeneration.requested возвращает долю эффективного максимума HP равномерно за seconds. Лечит только сущность с прочностью —
# без тела применить не дал S_Abilities (C_Regeneration.refusal). Вики: [[Захват тела]] §«Способности и слоты».
class_name S_Regeneration
extends System


func query() -> QueryBuilder:
	return q.with_all([C_Regeneration, C_Health])


func deps() -> Dictionary[int, Array]:
	return {Runs.After: [S_Abilities]}


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var regen := entity.get_component(C_Regeneration) as C_Regeneration
		var health := entity.get_component(C_Health) as C_Health
		var maximum := health.effective_maximum(entity)
		if regen.requested:
			regen.requested = false
			regen.heal_left = maximum * regen.share
			regen.time_left = maxf(regen.seconds, 0.001)
		if regen.time_left <= 0.0:
			continue
		var step := regen.heal_left * minf(delta / regen.time_left, 1.0)
		health.current = minf(health.current + step, maximum)
		regen.heal_left -= step
		regen.time_left -= delta
