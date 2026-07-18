class_name A_TravelThroughDoor
extends RS_InteractionAction
## Действие двери: уводит игрока в соседний узел графа, записанный в C_DoorPortal
## этой двери (штампует RunManager при спавне). Учитывает замок.
## Назначается на дверь-Entity через E_InteractableObject.actions в редакторе.

func execute(entity: Entity, _interactor: Node = null) -> void:
	var portal := entity.get_component(C_DoorPortal) as C_DoorPortal
	if portal == null or portal.target_node_id == &"":
		push_warning("A_TravelThroughDoor: у двери '%s' нет C_DoorPortal с целью" % entity.name)
		return

	if portal.is_locked():
		# TODO: заменить на игровой фидбэк (звук/подсказка), когда появится
		# инвентарь ключей. Сейчас ключей нет нигде, поэтому заперто = закрыто.
		print("Дверь заперта: нужен '%s'" % portal.locked_by)
		return

	RunManager.travel_to(portal.target_node_id)
