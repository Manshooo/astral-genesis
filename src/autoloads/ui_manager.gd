# Единый стек UI-экранов: пауза, настройки, дерево навыков, карта. Вики: [[Конвенции проекта]].
extends Node
## Все экраны идут через один стек, поэтому Esc закрывает верхний.

const PAUSE_MENU_SCENE = preload("res://src/ui/pause_menu/pause_menu.tscn")
const SKILL_TREE_SCENE = preload("res://src/ui/skill_tree/skill_tree_ui.tscn")
const COMPLEX_MAP_SCENE = preload("res://src/ui/map/complex_map_screen.tscn")
const BANK_CHOICE_SCENE = preload("res://src/ui/bank_choice/bank_choice_screen.tscn")

## Включать из игровой сцены: влияет на автопаузу по Esc и возврат курсора в захват.
var enabled: bool = false

## Каждый элемент стека:
## { "screen": Control, "return_to": Control|null, "paused": bool, "on_close": Callable }
var _stack: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("map") and not event.is_echo():
		_toggle_complex_map()
		return
	if event.is_action_pressed("map_mini") and not event.is_echo():
		_toggle_mini_map()
		return
	if not event.is_action_pressed("pause_game") or event.is_echo():
		return
	if not _stack.is_empty():
		close_top()
		get_viewport().set_input_as_handled()
	elif enabled:
		_open_pause_menu()
		get_viewport().set_input_as_handled()


## Поглощённая способность не влезла в полный банк — спросить игрока. Поллинг, а не событие: поглощение идёт отложенно из выхода (O_ExpelFromBody),
## а поверх открытого экрана выбор подождёт, пока стек опустеет.
func _process(_delta: float) -> void:
	if not enabled or not _stack.is_empty():
		return
	var player := E_Player.find()
	var loadout := player.get_component(C_AbilityLoadout) as C_AbilityLoadout if player else null
	if loadout == null or loadout.pending.is_empty():
		return
	var screen: UI_BankChoiceScreen = BANK_CHOICE_SCENE.instantiate()
	push_screen(screen, true, null, screen.on_closed)
	screen.setup(player, loadout)


func _open_pause_menu() -> void:
	push_screen(PAUSE_MENU_SCENE.instantiate(), true)

func _any_paused() -> bool:
	for entry in _stack:
		if entry.paused:
			return true
	return false

## Показывает экран поверх стека. [param pause] — пауза SceneTree, [param return_to] — что показать
## при пустом стеке, [param on_close] — колбэк после закрытия ИМЕННО этого экрана.
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


## Закрывает верхний экран стека.
func close_top() -> void:
	if _stack.is_empty():
		return
	var entry = _stack.pop_back()
	_dismiss(entry.screen)

	if entry.get("on_close") and entry.on_close.is_valid():
		entry.on_close.call()

	if not _stack.is_empty():
		_stack.back().screen.show()
	else:
		if entry.return_to and is_instance_valid(entry.return_to):
			entry.return_to.show()
		if entry.paused:
			get_tree().paused = _any_paused()
		if enabled:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Есть ли открытый экран — для UI_MenuBackdrop: поверх экрана мир уже заволочен.
func has_screens() -> bool:
	return not _stack.is_empty()


## Убирает снятый со стека экран; «Отголосок» гаснет (play_exit), остальные сразу. Стек уже прежний:
## гаснущий экран — картинка, а не состояние.
func _dismiss(screen: Control) -> void:
	if screen.has_method(&"play_exit"):
		screen.play_exit()
	else:
		screen.queue_free()


## Без угасания: зовут перед сменой сцены.
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


# Дерево навыков — экран в общем стеке


func open_skill_tree(skill_manager, tree_data: RS_SkillTree) -> void:
	for entry in _stack:
		if entry.screen is SkillTreeUI:
			return

	var skill_ui: SkillTreeUI = SKILL_TREE_SCENE.instantiate()
	push_blocking_screen(skill_ui)
	skill_ui.setup(skill_manager, tree_data)


## Экран поверх идущей игры: ввод игрока блокируется (курсор нужен экрану), паузы нет. Блок снимает колбэк закрытия.
func push_blocking_screen(screen: Control) -> void:
	_set_player_input_blocked(true)
	push_screen(screen, false, null, func(): _set_player_input_blocked(false))


func _set_player_input_blocked(blocked: bool) -> void:
	var player := E_Player.find()
	if player == null:
		return
	if blocked:
		if not player.has_component(C_UIBlocked):
			player.add_component(C_UIBlocked.new())
			# Остальное держит S_PlayerInput, но до его прохода успеет физкадр — отпускаем удержание сразу.
			var inp := player.get_component(C_PlayerInput) as C_PlayerInput
			if inp:
				inp.release_held()
	else:
		player.remove_component(C_UIBlocked)


# Карта комплекса


## Та же клавиша закрывает; поверх чужого экрана не открывается — закрылась бы по Esc раньше него.
func _toggle_complex_map() -> void:
	if not _stack.is_empty():
		if _stack.back().screen is UI_ComplexMap:
			close_top()
			get_viewport().set_input_as_handled()
		return
	if not enabled:
		return
	get_viewport().set_input_as_handled()
	var level := ArchitectManager.map_level()
	if RunManager.current_graph and level > MapKnowledge.LEVEL_NONE and not full_map_by_key():
		_notify_player(tr("MAP_TERMINAL_ONLY"))
		return
	open_complex_map()


## Полная карта по клавише — только последний ранг «Карты комплекса»; до него карта — терминал в хабе.
func full_map_by_key() -> bool:
	return ArchitectManager.map_level() >= ArchitectStats.MAP_LEVEL_MAX


## Открывает карту (клавиша или терминал A_OpenComplexMap); без Архитектора — строка о связи.
## На паузе: карту изучают стоя, распад под ней превращал бы планирование в спешку.
func open_complex_map() -> void:
	for entry in _stack:
		if entry.screen is UI_ComplexMap:
			return
	if RunManager.current_graph == null:
		return
	var level := ArchitectManager.map_level()
	if level <= MapKnowledge.LEVEL_NONE:
		_notify_player(tr("MAP_NO_LINK"))
		return
	# Мини-карта обещает «[M] Вся карта» — переключение, а не слой поверх.
	var mini_map := _mini_map()
	if mini_map:
		mini_map.close()
	var screen: UI_ComplexMap = COMPLEX_MAP_SCENE.instantiate()
	push_screen(screen, true)
	screen.setup(
		RunManager.current_graph, level, RunManager.current_node_id,
		WorldSave.save.visited_node_ids, RunManager.plan_for_depth
	)


## Строка поверх HUD напрямую: и клавиша, и терминал приходят вне прохода систем.
func _notify_player(line: String) -> void:
	C_ScreenMessage.show_on(E_Player.find(), line)


## Мини-карта — узел HUD, не экран стека: Esc её не трогает. Без связи с Архитектором — строка.
## Поверх экрана не открывается.
func _toggle_mini_map() -> void:
	var mini_map := _mini_map()
	if mini_map == null or not _stack.is_empty() or not enabled:
		return
	get_viewport().set_input_as_handled()
	if mini_map.is_open:
		mini_map.close()
		return
	if RunManager.current_graph == null:
		return
	if ArchitectManager.map_level() <= MapKnowledge.LEVEL_NONE:
		_notify_player(tr("MAP_NO_LINK"))
		return
	mini_map.open()


func _mini_map() -> UI_MiniMap:
	return get_tree().get_first_node_in_group(UI_MiniMap.GROUP) as UI_MiniMap


# Затемнение экрана

## Шторка — прямой ребёнок root, не сцены: иначе мигнула бы миром при смене сцены. Снимает её
## уже НОВАЯ сцена (fade_from_black).
var _fade: ColorRect


## Гасит экран в чёрный за [param duration] и возвращает управление, когда погасло.
func fade_to_black(duration: float) -> void:
	_ensure_fade()
	_fade.color.a = 0.0
	_fade.show()
	# PROCESS_MODE_ALWAYS: гасить может понадобиться на паузе; твин считает время узла.
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, duration)
	await tween.finished


## Проявляет новую сцену; молча ничего не делает, если экран не гасили.
func fade_from_black(duration: float) -> void:
	if _fade == null or not _fade.visible:
		return
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 0.0, duration)
	await tween.finished
	_fade.hide()


func _ensure_fade() -> void:
	if is_instance_valid(_fade):
		return
	_fade = ColorRect.new()
	_fade.name = "FadeOverlay"
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Мышь сквозь шторку: иначе кнопки экрана итогов оказались бы под невидимой крышкой.
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.process_mode = Node.PROCESS_MODE_ALWAYS
	# Поверх всего, включая экраны стека.
	_fade.z_index = 128
	get_tree().root.add_child(_fade)
