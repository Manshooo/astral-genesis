extends Control

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_continue_pressed() -> void:
	get_tree().free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
func _on_exit_pressed() -> void:
	get_tree().quit()
