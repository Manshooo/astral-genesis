# res://src/autoloads/pause_handler.gd
extends Node

const PAUSE_MENU_SCENE = preload("res://src/ui/pause_menu/pause_menu.tscn")

## Включайте явно из игровой сцены — влияет только на автооткрытие паузы по Esc.
var enabled: bool = false

## Каждый элемент стека: { "screen": Control, "return_to": Control|null, "paused": bool }
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

func push_screen(screen: Control, pause: bool = false, return_to: Control = null) -> void:
	if not _stack.is_empty():
		_stack.back().screen.hide()
	elif return_to:
		return_to.hide()
	screen.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(screen)
	_stack.append({"screen": screen, "return_to": return_to, "paused": pause})
	if pause:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Закрывает верхний экран. Курсор возвращается в захват только если
## закрываемый экран сам ставил паузу (т.е. мы выходим обратно в геймплей).
func close_top() -> void:
	if _stack.is_empty():
		return
	var entry = _stack.pop_back()
	entry.screen.queue_free()
	if not _stack.is_empty():
		_stack.back().screen.show()
	else:
		if entry.return_to and is_instance_valid(entry.return_to):
			entry.return_to.show()
		if entry.paused:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func close_all() -> void:
	var any_paused := false
	for entry in _stack:
		if is_instance_valid(entry.screen):
			entry.screen.queue_free()
		if entry.paused:
			any_paused = true
	_stack.clear()
	if any_paused:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
