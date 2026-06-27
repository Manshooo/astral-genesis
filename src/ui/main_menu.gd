# res://src/ui/main_menu.gd
extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://src/world/world.tscn")

func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu.tscn").instantiate()
	settings_menu.caller_node = self
	get_tree().root.add_child(settings_menu)
	hide()

func _on_exit_pressed() -> void:
	get_tree().quit()
