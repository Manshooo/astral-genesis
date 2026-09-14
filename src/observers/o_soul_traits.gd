# res://src/observers/o_soul_traits.gd
# Наблюдатель: во плоти возможности САМОЙ души засыпают, при развоплощении
# просыпаются. Полёт и проход сквозь решётки принадлежат БФЖ, а не телу, — но
# пока он носит тело, летать и просачиваться ему нечем.
#
# Сидит на C_Embodied, а не вызывается из захвата, ровно по той причине, по
# которой на нём же сидят O_BodyVisual и O_BodyForm: воплощают душу ДВА пути —
# S_BodySnatch при захвате и RunManager._restore_embodiment при загрузке, — и
# правило, расписанное в обоих, разъезжается молча. Один раз этим уже обожглись:
# облик садился по верному офсету после загрузки и по чужому после захвата
# именно потому, что пути разошлись.
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
			# СВЕЖИЕ КОПИИ из сцены души, а не заначка, снятая при вселении.
			# Заначка пережила бы обычный выход, но не пересадку тело→тело: там
			# буфер коалесцирует remove+add C_Embodied в один переезд архетипа, и
			# снятия наблюдатель может не увидеть вовсе — заначка осталась бы
			# пустой, а душа навсегда без полёта. Нечего хранить — нечему и
			# потеряться.
			for waking in player.soul_traits():
				cmd.add_component(player, waking)


## Возможности души, надетые на неё прямо сейчас.
##
## Собираем список ЗАРАНЕЕ, отдельным проходом: снятие правит тот самый словарь
## components, по которому мы бы шли (та же осторожность, что в
## O_ExpelFromBody.expel).
func _worn(player: E_Player) -> Array[Component]:
	var found: Array[Component] = []
	for component in player.components.values():
		if component is C_SoulTrait:
			found.append(component as Component)
	return found
