extends "res://dev/check_harness.gd"
## Проверка: номер сборки виден там, где его ищут по скриншоту бага, — в углу
## главного меню и в отладочном оверлее, — и это ровно config/version.
## Запускать: godot --headless dev/version_label_check.tscn
##
## Номер вписывает сборка (.github/scripts/set_version.sh), игра его только
## читает, поэтому ломается здесь тихо: подпись, оставшаяся с текстом из сцены
## или собранная не из того поля, выглядит как номер и врёт. Проверка
## подставляет номер не-релизной сборки, а не тот, что лежит в project.godot:
## его и показывают там, где номер нужен, — у сборок из коммитов.

const MAIN_MENU_SCENE := preload("res://src/ui/main_menu/main_menu.tscn")
const OVERLAY_SCENE := preload("res://dev/debug_overlay.tscn")
const VERSION_SETTING := "application/config/version"
## Вид, который даёт build_version.sh: «+» и точки обязаны доехать как есть.
const DEV_VERSION := "0.7.0-dev.33+fc91d3c"


func _ready() -> void:
	var original: String = ProjectSettings.get_setting(VERSION_SETTING)
	ProjectSettings.set_setting(VERSION_SETTING, DEV_VERSION)

	await _run()

	ProjectSettings.set_setting(VERSION_SETTING, original)
	_finish()


func _run() -> void:
	var expected := "v%s" % DEV_VERSION

	var menu: Control = MAIN_MENU_SCENE.instantiate()
	add_child(menu)
	var label: Label = menu.get_node("%Version")
	_check(
		"номер в углу главного меню — config/version",
		label.text == expected,
		"«%s», ожидалось «%s»" % [label.text, expected]
	)
	_check("номер в меню виден", label.visible and label.modulate.a > 0.0, "подпись скрыта")
	menu.queue_free()

	var overlay: CanvasLayer = OVERLAY_SCENE.instantiate()
	add_child(overlay)
	# Строку состояния оверлей собирает в _process, а process_frame приходит ДО
	# _process узлов в том же кадре: после одного ожидания в строке ещё «—».
	await get_tree().process_frame
	await get_tree().process_frame
	var status: Label = overlay.get_node("%Status")
	_check(
		"номер в строке состояния отладочного оверлея",
		status.text.contains(expected),
		"в строке нет «%s»: %s" % [expected, status.text.replace("\n", " / ")]
	)
	overlay.queue_free()
