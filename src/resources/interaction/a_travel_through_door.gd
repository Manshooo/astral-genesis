class_name A_TravelThroughDoor
extends RS_InteractionAction
## Переход по ребру графа: ведёт игрока в соседний узел, записанный в
## C_DoorPortal этого интерактива (штампует RunManager при спавне слоя).
## Учитывает замок и «пустой» выход — в обоих случаях даёт игроку экранное
## сообщение, а не тишину. Что именно значит «пройти», решает RunManager.use_door:
## дверь в коридор открывается на месте, портал и прежняя раскладка переносят.
##
## Базовый класс и для вертикального перехода: портал — та же дверь, только в
## другой слой (см. A_UsePortal, он лишь переопределяет тексты).
## Назначается на Entity через E_InteractableObject.actions в редакторе.

## Человекочитаемые имена ключей для сообщения. Инвентаря ключей ещё нет, так
## что locked_by пока всегда level_access_key.
const KEY_NAMES := {
	&"level_access_key": "ключ доступа к уровню",
}


func execute(entity: Entity, _interactor: Node = null) -> void:
	var portal := entity.get_component(C_DoorPortal) as C_DoorPortal
	if portal == null:
		push_warning("%s: у «%s» нет C_DoorPortal" % [_class_label(), entity.name])
		return

	# Пустая цель = выход «заглушён»: у узла интерактивов больше, чем рёбер графа
	# (см. RunManager._seal_door). Проём/портал настоящий, но за ним ничего нет.
	if portal.target_node_id == &"":
		_notify(_sealed_message())
		return

	if portal.is_locked():
		# Ключей в игре ещё нет нигде, поэтому заперто = закрыто наглухо. Но
		# игрок теперь хотя бы знает, ЧТО нужно, а не смотрит в молчащую дверь.
		_notify(_locked_message(portal.locked_by))
		return

	RunManager.use_door(entity, portal.target_node_id)


# --- Тексты: переопределяются наследниками (портал говорит по-своему) --------


func _sealed_message() -> String:
	return "Прохода нет: проём заварен"


func _locked_message(key: StringName) -> String:
	return "Заперто. Нужен %s" % _key_name(key)


func _class_label() -> String:
	return "A_TravelThroughDoor"


func _key_name(key: StringName) -> String:
	return KEY_NAMES.get(key, str(key))


## Строка игроку. Прямая правка, без буфера, законна: interact() зовётся из
## S_InteractInput через call_deferred, то есть уже ВНЕ прохода ECS.
func _notify(line: String) -> void:
	C_ScreenMessage.show_on(E_Player.find(), line)
