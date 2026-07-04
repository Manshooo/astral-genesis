# res://src/ui/pause_handler.gd
# Autoload: PauseHandler
extends Node

const PAUSE_MENU_SCENE = preload("res://src/ui/pause_menu/pause_menu.tscn")

## Включайте это явно из игровой сцены (Main._ready()) и выключайте при выходе в меню.
## По умолчанию false — в главном меню Esc не должен открывать паузу игры.
var enabled: bool = false

var _pause_menu: Control = null

func _ready() -> void:
	# Автозагрузки по умолчанию следуют состоянию паузы дерева и перестанут получать
	# input, если поставить paused = true иначе. Нам нужно ловить Esc даже когда
	# дерево на паузе (чтобы снять её), поэтому — ALWAYS.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("pause_game") and not event.is_echo():
		if get_tree().paused:
			_close_pause()
		else:
			_open_pause()
		get_viewport().set_input_as_handled()

func _open_pause() -> void:
	if _pause_menu:
		return
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	get_tree().root.add_child(_pause_menu)
	get_tree().paused = true

func _close_pause() -> void:
	if _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
