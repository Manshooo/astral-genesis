## Единый редактор геймдизайна: вкладка главного экрана плюс док Room Wizard.
## См. [[Редакторские инструменты]], [[Единый редактор геймдизайна]].
@tool
extends EditorPlugin

const MainScreen := preload("res://addons/game_design_tool/main_screen.gd")
const RoomWizard := preload("res://addons/game_design_tool/dock/room_wizard.gd")
# Иконка обязана быть 16×16 и с color="#e0e0e0" на <svg> (вики: «Иконка вкладки»).
const PLUGIN_ICON := preload("res://addons/game_design_tool/assets/gamedesign.svg")

var _main_screen: Control
var _room_wizard: Control


func _enter_tree() -> void:
	_main_screen = MainScreen.new()
	EditorInterface.get_editor_main_screen().add_child(_main_screen)
	# Пока вкладку не выбрали, экран скрыт — иначе наложится на 2D/3D.
	_make_visible(false)

	_room_wizard = RoomWizard.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _room_wizard)
	scene_changed.connect(_room_wizard.refresh_for_scene)
	# scene_changed не сообщит о сцене, уже открытой при загрузке плагина.
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
	return PLUGIN_ICON


func _make_visible(visible: bool) -> void:
	if _main_screen:
		_main_screen.visible = visible
