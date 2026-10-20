# res://src/systems/gameplay/s_screen_message.gd
# Группа "gameplay". Гасит экранные сообщения по таймеру (C_ScreenMessage.remaining); рисует HUD (hud_message.gd), система про UI не знает.
class_name S_ScreenMessage
extends System


func query() -> QueryBuilder:
	return q.with_all([C_ScreenMessage])


func process(entities: Array[Entity], _components: Array, delta: float) -> void:
	for entity in entities:
		var msg := entity.get_component(C_ScreenMessage) as C_ScreenMessage
		msg.remaining -= delta
		if msg.remaining <= 0.0:
			# Снятие компонента — структурное: через cmd.
			cmd.remove_component(entity, C_ScreenMessage)
