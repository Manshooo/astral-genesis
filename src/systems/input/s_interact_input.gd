class_name S_InteractInput
extends System

func query() -> QueryBuilder:
	return q.with_all([C_Interactable, C_Highlighted])

# interact() зовём ОТЛОЖЕННО (call_deferred): действие двери сносит комнату и спавнит новую, A_FinishRun меняет сцену, а структурные правки в process() запрещены (правило v9; ср. O_RunEnded).
func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		return
	if Input.is_action_just_pressed("interact"):
		var target = entities[0]
		var inter := target.get_component(C_Interactable) as C_Interactable
		# Механизм требует тела, а БФЖ бестелесен — нажатие не проходит; почему подсвечен, игрок читает в подсказке («Нужно тело»).
		if inter and inter.requires_body and not E_Player.is_embodied():
			return
		assert(target.has_method("interact"), "Сущность '%s' имеет компонент C_Interactable, но не реализует функцию interact()" % target.name)
		target.interact.call_deferred()
