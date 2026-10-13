# res://src/systems/gameplay/s_decay_shelter.gd
# Группа: "gameplay". Убежище от распада: пока душа стоит в зоне (C_Sheltered),
# её запас не убывает, а восполняется.
#
# Отдельная система, а не ветка в S_Lifespan: S_Lifespan душу в убежище просто
# не выбирает (with_none C_Sheltered), так что «тикает или копится» решает
# выборка, а не флаг внутри тика, — так же, как карман тела решается наличием
# C_BodyDecay.
#
# Восполняются ОБА кармана: и собственный запас души, и карман надетого тела.
# Убежище лечит саму душу, в чём бы она ни пришла: иначе игрок, зашедший в хаб
# в теле, выходил бы из него с той же полупустой душой, с какой вошёл, и чтобы
# отдохнуть по-настоящему, тело пришлось бы бросать у порога.
class_name S_DecayShelter
extends System


## C_Dead исключён по той же причине, что в S_Lifespan: объявленная мёртвой
## душа не должна подняться обратно, пока сцена смерти ещё не встала.
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


## Доливает до максимума, но излишек сверх него не срезает: излишек — остаток
## тела, принесённый добровольным выходом (O_ExpelFromBody), и убежище его
## замораживает, а не отнимает. Срезать его здесь значило бы наказывать за то,
## что игрок зашёл в хаб.
static func _refill(current: float, gain: float, maximum: float) -> float:
	if current >= maximum:
		return current
	return minf(current + gain, maximum)
