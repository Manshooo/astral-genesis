## res://addons/game_design_tool/plugin.gd
## Единый редактор геймдизайна — вкладка главного экрана рядом с «2D» / «3D» /
## «Script».
##
## Почему главный экран, а не док и не отдельное окно: инструменты этой игры —
## это широкие таблицы и (следующим шагом) 3D-вьюпорт генератора, а правая
## панель под них тесная. Отдельное окно рассматривалось и отвергнуто: его
## главный аргумент — обойти ловушку «минимальный размер док спрашивает у ВСЕХ
## вкладок сразу» (см. [[Редакторские инструменты]]), но у главного экрана этой ловушки
## нет точно так же, а площади он даёт больше, чем окно.
##
## Исключение, которое сюда НЕ поедет, — будущий Room Wizard: он работает поверх
## сцены комнаты, открытой в обычном 3D-редакторе, а главный экран её прячет.
## Ему остаётся отдельный тонкий док.
@tool
extends EditorPlugin

const MainScreen := preload("res://addons/game_design_tool/main_screen.gd")

var _main_screen: Control


func _enter_tree() -> void:
	_main_screen = MainScreen.new()
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	# Редактор сам покажет вкладку через _make_visible, когда её выберут; до тех
	# пор экран обязан быть скрыт, иначе он наложится на активный 2D/3D.
	_make_visible(false)


func _exit_tree() -> void:
	if _main_screen:
		_main_screen.queue_free()
		_main_screen = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Геймдизайн"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Node", &"EditorIcons")


func _make_visible(visible: bool) -> void:
	if _main_screen:
		_main_screen.visible = visible
