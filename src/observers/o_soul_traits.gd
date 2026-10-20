# res://src/observers/o_soul_traits.gd
# Наблюдатель: во плоти возможности САМОЙ души (полёт, проход сквозь решётки) засыпают, при развоплощении просыпаются.
# Сидит на C_Embodied, как O_BodyVisual и O_BodyForm: воплощают душу два пути (захват и загрузка), правило в обоих разъехалось бы.
class_name O_SoulTraits
extends Observer


func query() -> QueryBuilder:
	return q.with_all([C_Embodied]).on_added().on_removed()


func each(event: Variant, entity: Entity, _payload: Variant = null) -> void:
	var player := entity as E_Player
	if player == null:
		return

	match event:
		Observer.Event.ADDED:
			for dormant in _worn(player):
				cmd.remove_component(player, dormant.get_script())
		Observer.Event.REMOVED:
			# СВЕЖИЕ КОПИИ из сцены души, не заначка: при пересадке тело→тело буфер коалесцирует remove+add, снятия можно не увидеть.
			for waking in player.soul_traits():
				cmd.add_component(player, waking)


## Возможности души, надетые сейчас; список заранее — снятие правит словарь components (как в O_ExpelFromBody.expel).
func _worn(player: E_Player) -> Array[Component]:
	var found: Array[Component] = []
	for component in player.components.values():
		if component is C_SoulTrait:
			found.append(component as Component)
	return found
