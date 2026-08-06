# res://src/ui/pause_menu.gd
extends Control

const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"
## Сколько держать отметку «Сохранено» на кнопке, прежде чем вернуть исходный текст.
const SAVED_HINT_SECONDS := 1.5

@onready var save_button: Button = $Panel/MarginContainer/VBoxContainer/Save

func _on_continue_pressed() -> void:
	UIManager.close_top()

## Ручное сохранение. Прогресс и так пишется на каждой смене комнаты, но распад
## тикает непрерывно — эта кнопка фиксирует запас на текущий момент.
## Отклик обязателен: без него кнопка выглядит сломанной (сохранение молча
## успевает пройти между кадрами).
func _on_save_pressed() -> void:
	if not RunManager.save_progress():
		_flash_save_button("Сохранять нечего")
		return
	_flash_save_button("Сохранено")

func _on_settings_pressed() -> void:
	var settings_menu = load("res://src/ui/settings_menu/settings_menu.tscn").instantiate()
	UIManager.push_screen(settings_menu)

func _on_exit_to_menu_pressed() -> void:
	# Забег не заканчиваем — только фиксируем точку и отпускаем мир: сцена сейчас
	# уйдёт, а RunManager (autoload) её переживёт и не должен остаться со ссылками
	# на убитые комнаты.
	RunManager.leave_to_menu()
	UIManager.close_all()
	UIManager.enabled = false
	get_tree().change_scene_to_file(MENU_SCENE)


## Подменяет подпись кнопки на время, затем возвращает исходную.
## Таймер с process_always: игра на паузе, обычный бы не тикал.
func _flash_save_button(text: String) -> void:
	var original := save_button.text
	if save_button.disabled:
		return  # отметка уже висит — не наслаиваем
	save_button.text = text
	save_button.disabled = true
	await get_tree().create_timer(SAVED_HINT_SECONDS, true).timeout
	if not is_instance_valid(save_button):
		return  # меню успели закрыть
	save_button.text = original
	save_button.disabled = false
