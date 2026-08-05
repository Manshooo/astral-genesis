class_name A_TravelThroughDoor
extends RS_InteractionAction
## Действие двери: уводит игрока в соседний узел графа, записанный в C_DoorPortal
## этой двери (штампует RunManager при спавне). Учитывает замок и запечатанный
## проём — в обоих случаях даёт игроку экранное сообщение, а не тишину.
## Назначается на дверь-Entity через E_InteractableObject.actions в редакторе.

## Человекочитаемые имена ключей для сообщения. Инвентаря ключей ещё нет, так
## что locked_by пока всегда level_access_key.
const KEY_NAMES := {
	&"level_access_key": "ключ доступа к уровню",
}


func execute(entity: Entity, _interactor: Node = null) -> void:
	var portal := entity.get_component(C_DoorPortal) as C_DoorPortal
	if portal == null:
		push_warning("A_TravelThroughDoor: у двери '%s' нет C_DoorPortal" % entity.name)
		return

	# Пустая цель = запечатанный слот: у узла дверей больше, чем рёбер графа
	# (см. RunManager._seal_door). Дверь настоящая, но за ней ничего нет.
	if portal.target_node_id == &"":
		_notify("Прохода нет: проём заварен")
		return

	if portal.is_locked():
		# Ключей в игре ещё нет нигде, поэтому заперто = закрыто наглухо. Но
		# игрок теперь хотя бы знает, ЧТО нужно, а не смотрит в молчащую дверь.
		_notify("Заперто. Нужен %s" % KEY_NAMES.get(portal.locked_by, str(portal.locked_by)))
		return

	RunManager.travel_to(portal.target_node_id)


## Кладёт сообщение на игрока — рисует его hud_message.gd, гасит S_ScreenMessage.
## add/remove_component здесь безопасны: interact() зовётся из S_InteractInput
## через call_deferred, то есть уже ВНЕ прохода ECS по сущностям.
## Пересоздаём компонент, а не правим поля: прямая запись в поля миру не
## сигналится, и HUD не увидел бы новый текст.
func _notify(text: String) -> void:
	var player := ECS.world.query.with_all([C_PlayerInput]).execute_one()
	if player == null:
		return
	if player.has_component(C_ScreenMessage):
		player.remove_component(C_ScreenMessage)
	var message := C_ScreenMessage.new()
	message.text = text
	player.add_component(message)
