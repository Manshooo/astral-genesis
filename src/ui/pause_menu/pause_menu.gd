# res://src/ui/pause_menu.gd
extends Control

func _on_continue_pressed() -> void:
	PauseHandler.close_top()

func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	PauseHandler.push_screen(settings_menu)

func _on_exit_to_menu_pressed() -> void:
	PauseHandler.close_all()
	PauseHandler.enabled = false
	get_tree().change_scene_to_file("res://src/levels/L_menu_map.tscn")
