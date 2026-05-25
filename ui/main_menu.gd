extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_new_game_pressed() -> void:
	get_tree().change_scene_to_file("res://world/world.tscn")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _on_exit_pressed() -> void:
	get_tree().quit()
