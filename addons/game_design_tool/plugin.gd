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
## Исключение, которое сюда НЕ поехало, — Room Wizard: он работает поверх
## сцены комнаты, открытой в обычном 3D-редакторе, а главный экран её прячет.
## Живёт отдельным тонким доком (DOCK_SLOT_RIGHT_UL), который слушает
## scene_changed — этот сигнал есть только у EditorPlugin, обычный Control
## подписаться на него сам не может.
@tool
extends EditorPlugin

const MainScreen := preload("res://addons/game_design_tool/main_screen.gd")
const RoomWizard := preload("res://addons/game_design_tool/dock/room_wizard.gd")

var _main_screen: Control
var _room_wizard: Control


func _enter_tree() -> void:
	_main_screen = MainScreen.new()
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	# Редактор сам покажет вкладку через _make_visible, когда её выберут; до тех
	# пор экран обязан быть скрыт, иначе он наложится на активный 2D/3D.
	_make_visible(false)

	_room_wizard = RoomWizard.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _room_wizard)
	scene_changed.connect(_room_wizard.refresh_for_scene)
	# scene_changed бьёт только по ПОСЛЕДУЮЩИМ переключениям — сцену, уже
	# открытую на момент загрузки плагина, он не покажет сам.
	_room_wizard.refresh_for_scene(EditorInterface.get_edited_scene_root())


func _exit_tree() -> void:
	if _main_screen:
		_main_screen.queue_free()
		_main_screen = null
	if _room_wizard:
		remove_control_from_docks(_room_wizard)
		_room_wizard.queue_free()
		_room_wizard = null


func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return "Геймдизайн"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon(&"Node", &"EditorIcons")


func _make_visible(visible: bool) -> void:
	if _main_screen:
		_main_screen.visible = visible
