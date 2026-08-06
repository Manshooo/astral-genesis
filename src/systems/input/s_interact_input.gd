class_name S_InteractInput
extends System

func query() -> QueryBuilder:
	return q.with_all([C_Interactable, C_Highlighted])

# interact() зовём ОТЛОЖЕННО: действие двери (A_TravelThroughDoor) сносит текущую
# комнату и спавнит новую, A_FinishRun и вовсе меняет сцену. С GECS v9 системы
# обходят массивы архетипов zero-copy (System.safe_iteration = false по умолчанию),
# поэтому сносить/добавлять сущности прямо в process() нельзя — часть сущностей
# пропускается через swap-remove, а add_component на новых дверях роняет push_error
# в debug_mode. call_deferred уводит всё это за пределы прохода ECS (ср. O_RunEnded,
# O_ExpelFromBody).
func process(entities: Array[Entity], _components: Array, _delta: float) -> void:
	if entities.is_empty():
		return
	if Input.is_action_just_pressed("interact"):
		var target = entities[0]
		var inter := target.get_component(C_Interactable) as C_Interactable
		# Механизм требует тела, а БФЖ бестелесен — нажатие просто не проходит.
		# Почему объект вообще подсвечен и что не так, игрок читает в подсказке
		# (hud_prompt показывает «Нужно тело»), поэтому тишина тут не молчание.
		if inter and inter.requires_body and not _player_embodied():
			return
		assert(target.has_method("interact"), "Сущность '%s' имеет компонент C_Interactable, но не реализует функцию interact()" % target.name)
		target.interact.call_deferred()


func _player_embodied() -> bool:
	var player := ECS.world.query.with_all([C_PlayerInput]).execute_one()
	return player != null and player.has_component(C_Embodied)
