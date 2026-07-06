# res://src/ui/main_menu.gd
extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PauseHandler.enabled = false

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://src/world/world.tscn")

func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	PauseHandler.push_screen(settings_menu, false, self)

func _on_exit_pressed() -> void:
	get_tree().quit()
