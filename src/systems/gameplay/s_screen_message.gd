# res://src/systems/gameplay/s_screen_message.gd
# Группа: "gameplay". Гасит экранные сообщения по таймеру: тикает
# C_ScreenMessage.remaining и снимает компонент, когда время вышло.
# Рисует сообщение HUD (hud_message.gd) по сигналам мира — система про UI не знает.
class_name S_ScreenMessage
extends System


func query() -> QueryBuilder:
	return q.with_all([C_ScreenMessage])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var msg := entity.get_component(C_ScreenMessage) as C_ScreenMessage
		msg.remaining -= delta
		if msg.remaining <= 0.0:
			# Снятие компонента — структурное изменение: только через cmd,
			# иначе переезд архетипа пропустит соседей в этом же проходе.
			cmd.remove_component(entity, C_ScreenMessage)
