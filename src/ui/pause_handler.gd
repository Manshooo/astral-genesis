# res://src/ui/pause_handler.gd
# Autoload: PauseHandler
# Глобально слушает Escape и открывает/закрывает паузу
extends Node

const PAUSE_MENU_SCENE = preload("res://src/ui/pause_menu.tscn")

var _pause_menu: Control = null

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_just_pressed("ui_cancel"):  # Escape
		if get_tree().paused:
			_close_pause()
		else:
			_open_pause()

func _open_pause() -> void:
	if _pause_menu:
		return
	_pause_menu = PAUSE_MENU_SCENE.instantiate()
	get_tree().root.add_child(_pause_menu)

func _close_pause() -> void:
	if _pause_menu:
		_pause_menu.queue_free()
		_pause_menu = null
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
