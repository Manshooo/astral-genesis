# res://src/ui/main_menu/main_menu.gd
extends Control

const WORLD_SCENE := "res://src/world/world.tscn"

@onready var load_button: Button = $Panel/MarginContainer/VBoxContainer2/VBoxContainer/Load

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	UIManager.enabled = false
	# Продолжать нечего, пока на диске нет сейва: WorldSave в этом случае держит
	# свежесгенерированную заготовку, а не сохранённое прохождение.
	load_button.disabled = not WorldSave.has_save_file

func _on_new_game_pressed() -> void:
	WorldSave.new_game()  # катим новый world_seed до загрузки мира
	get_tree().change_scene_to_file(WORLD_SCENE)

## Продолжить сохранённое прохождение. Ничего не катим и не грузим руками:
## WorldSave уже поднял сейв в _ready, а RunManager возьмёт из него и сид
## (world_seed + death_count), и узел, на котором игрок остановился.
func _on_load_pressed() -> void:
	get_tree().change_scene_to_file(WORLD_SCENE)

func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	UIManager.push_screen(settings_menu, false, self)

func _on_exit_pressed() -> void:
	get_tree().quit()
