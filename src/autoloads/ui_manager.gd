extends Node

var _skill_ui: Control = null

func open_skill_tree(skill_manager, tree_data: RS_SkillTree) -> void:
	if _skill_ui:
		return
	_skill_ui = preload("res://src/ui/skill_tree/skill_tree_ui.tscn").instantiate()
	_skill_ui.setup(skill_manager, tree_data)
	get_tree().root.add_child(_skill_ui)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_set_player_input_blocked(true)   # мир крутится, но игрок не двигается/не смотрит

func _on_close_pressed() -> void:
	_skill_ui.queue_free()
	_skill_ui = null
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_player_input_blocked(false)

func _set_player_input_blocked(blocked: bool) -> void:
	# добавляем/убираем маркер-компонент на игроке, который S_PlayerInput/S_FPSLook
	# учитывают через with_none — так мир (NPC, физика, таймеры) не тормозится,
	# блокируется только конкретно ввод игрока
	var player = _get_player_entity()
	if blocked:
		player.add_component(C_UIBlocked.new())
	else:
		player.remove_component(C_UIBlocked)
