class_name A_TravelThroughDoor
extends RS_InteractionAction
## Переход по ребру графа в узел из C_DoorPortal (штампует RunManager). Замок и «пустой» выход дают экранное сообщение;
## что значит «пройти», решает RunManager.use_door. База и для A_UsePortal (переопределяет тексты). Вики: [[Взаимодействие]].

## Ключи перевода имён ключей; инвентаря нет, locked_by пока всегда level_access_key.
const KEY_NAMES := {
	&"level_access_key": "ITEM_LEVEL_ACCESS_KEY",
}


func execute(entity: Entity, _interactor: Node = null) -> void:
	var portal := entity.get_component(C_DoorPortal) as C_DoorPortal
	if portal == null:
		push_warning("%s: у «%s» нет C_DoorPortal" % [_class_label(), entity.name])
		return

	# Пустая цель = выход «заглушён»: у узла интерактивов больше, чем рёбер (LayerStreamer._seal_door).
	if portal.target_node_id == &"":
		_notify(_sealed_message())
		return

	if portal.locked_by == C_DoorPortal.ENTRY_SEAL:
		_notify(tr("HUD_MSG_ENTRY_SEALED"))
		return
	if portal.is_locked():
		# Ключей в игре нет: заперто = наглухо, но игрок знает, ЧТО нужно.
		_notify(_locked_message(portal.locked_by))
		return

	RunManager.use_door(entity, portal.target_node_id)


# --- Тексты: переопределяются наследниками (портал говорит по-своему) --------


func _sealed_message() -> String:
	return tr("HUD_MSG_SEALED")


func _locked_message(key: StringName) -> String:
	# tr() до подстановки: перевод узнаёт только строку-шаблон.
	return tr("HUD_MSG_LOCKED_NEEDS") % _key_name(key)


func _class_label() -> String:
	return "A_TravelThroughDoor"


func _key_name(key: StringName) -> String:
	return tr(KEY_NAMES.get(key, str(key)))


## Строка игроку: прямая правка законна — interact() идёт через call_deferred, вне прохода ECS.
func _notify(line: String) -> void:
	C_ScreenMessage.show_on(E_Player.find(), line)
