# res://src/autoloads/ui_manager.gd
extends Node
## Единая точка управления UI-экранами: пауза, настройки, дерево навыков и т.д.
## Все экраны идут через один стек, поэтому Esc всегда закрывает верхний экран —
## неважно, меню паузы это, настройки или дерево навыков.

const PAUSE_MENU_SCENE = preload("res://src/ui/pause_menu/pause_menu.tscn")
const SKILL_TREE_SCENE = preload("res://src/ui/skill_tree/skill_tree_ui.tscn")

## Включайте явно из игровой сцены — влияет только на автооткрытие паузы по Esc
## и на то, нужно ли возвращать курсор в захват, когда стек опустеет.
var enabled: bool = false

## Каждый элемент стека:
## { "screen": Control, "return_to": Control|null, "paused": bool, "on_close": Callable }
var _stack: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause_game") or event.is_echo():
		return
	if not _stack.is_empty():
		close_top()
		get_viewport().set_input_as_handled()
	elif enabled:
		_open_pause_menu()
		get_viewport().set_input_as_handled()


func _open_pause_menu() -> void:
	push_screen(PAUSE_MENU_SCENE.instantiate(), true)


## Показывает экран, помещая его на верх общего стека.
## [param pause] — ставит игру (SceneTree) на паузу, пока экран открыт (меню паузы).
## [param return_to] — экран, который нужно снова показать, когда стек опустеет.
## [param on_close] — необязательный колбэк, вызывается сразу после закрытия
##                    именно ЭТОГО экрана (например, снять C_UIBlocked с игрока).
func push_screen(
	screen: Control,
	pause: bool = false,
	return_to: Control = null,
	on_close: Callable = Callable(),
) -> void:
	if not _stack.is_empty():
		_stack.back().screen.hide()
	elif return_to:
		return_to.hide()

	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(screen)
	_stack.append(
		{
			"screen": screen,
			"return_to": return_to,
			"paused": pause,
			"on_close": on_close,
		}
	)

	if pause:
		get_tree().paused = true
	# Курсор всегда виден, пока на стеке есть хотя бы один экран
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Закрывает верхний экран стека. Всегда работает с ТЕМ, что реально открыто
## последним — неважно, пауза это, настройки или дерево навыков.
func close_top() -> void:
	if _stack.is_empty():
		return
	var entry = _stack.pop_back()
	entry.screen.queue_free()

	if entry.get("on_close") and entry.on_close.is_valid():
		entry.on_close.call()

	if not _stack.is_empty():
		_stack.back().screen.show()
	else:
		if entry.return_to and is_instance_valid(entry.return_to):
			entry.return_to.show()
		if entry.paused:
			get_tree().paused = false
		if enabled:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func close_all() -> void:
	var any_paused := false
	for entry in _stack:
		if is_instance_valid(entry.screen):
			entry.screen.queue_free()
		if entry.get("on_close") and entry.on_close.is_valid():
			entry.on_close.call()
		if entry.paused:
			any_paused = true
	_stack.clear()
	if any_paused:
		get_tree().paused = false
	if enabled:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# ---------------------------------------------------------------------------
# Дерево навыков — теперь тоже просто экран в общем стеке, а не отдельная ветка логики
# ---------------------------------------------------------------------------


func open_skill_tree(skill_manager, tree_data: RS_SkillTree) -> void:
	for entry in _stack:
		if entry.screen is SkillTreeUI:
			return

	var skill_ui: SkillTreeUI = SKILL_TREE_SCENE.instantiate()

	_set_player_input_blocked(true)
	
	push_screen(skill_ui, false, null, func(): _set_player_input_blocked(false))
	skill_ui.setup(skill_manager, tree_data)


func _set_player_input_blocked(blocked: bool) -> void:
	var player := _get_player_entity()
	if player == null:
		return
	if blocked:
		if not player.has_component(C_UIBlocked):
			player.add_component(C_UIBlocked.new())
			var inp := player.get_component(C_PlayerInput) as C_PlayerInput
			if inp:
				inp.mouse_delta = Vector2.ZERO
				inp.move_direction = Vector3.ZERO 
	else:
		player.remove_component(C_UIBlocked)


func _get_player_entity() -> Entity:
	return ECS.world.query.with_all([C_PlayerInput]).execute_one()
