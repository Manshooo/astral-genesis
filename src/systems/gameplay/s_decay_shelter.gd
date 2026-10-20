# res://src/systems/gameplay/s_decay_shelter.gd
# Группа "gameplay". Убежище от распада: пока душа в зоне (C_Sheltered), запас восполняется. Отдельная система: S_Lifespan душу в убежище не выбирает
# (with_none), «тикает или копится» решает выборка. Восполняются ОБА кармана (душа и надетое тело) — иначе отдыхать пришлось бы без тела. Вики: [[Захват тела]].
class_name S_DecayShelter
extends System


## C_Dead исключён, как в S_Lifespan: мёртвая душа не поднимется, пока сцена смерти не встала.
func query() -> QueryBuilder:
	return q.with_all([C_Lifespan, C_Sheltered]).with_none([C_Dead])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var shelter := entity.get_component(C_Sheltered) as C_Sheltered
		var gain := shelter.refill_rate * delta
		var life := entity.get_component(C_Lifespan) as C_Lifespan
		life.current = _refill(life.current, gain, life.effective_max(entity))
		var decay := entity.get_component(C_BodyDecay) as C_BodyDecay
		if decay:
			decay.remaining = _refill(decay.remaining, gain, decay.effective_maximum(entity))


## Доливает до максимума, излишек (остаток тела от добровольного выхода) не срезает — убежище его замораживает.
static func _refill(current: float, gain: float, maximum: float) -> float:
	if current >= maximum:
		return current
	return minf(current + gain, maximum)
