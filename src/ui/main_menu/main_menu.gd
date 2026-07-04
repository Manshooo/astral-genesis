# res://src/ui/main_menu.gd
extends Control

const SETTINGS_MENU = preload("res://src/ui/settings_menu/settings_menu.tscn")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	PauseHandler.enabled = false

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://src/world/world.tscn")

func _on_settings_pressed() -> void:
	var settings_menu = SETTINGS_MENU.instantiate()
	settings_menu.caller_node = self
	get_tree().root.add_child(settings_menu)
	hide()

func _on_exit_pressed() -> void:
	get_tree().quit()
