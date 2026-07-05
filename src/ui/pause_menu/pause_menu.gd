# res://src/ui/pause_menu.gd
extends Control

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func _on_continue_pressed() -> void:  # Continue
	_close()

func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	settings_menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	settings_menu.caller_node = self
	get_tree().root.add_child(settings_menu)
	hide()

func _on_exit_to_menu_pressed() -> void:
	get_tree().paused = false
	PauseHandler.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().change_scene_to_file("res://src/levels/L_menu_map.tscn")

func _close() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	queue_free()
