## res://addons/game_design_tool/shared/tag_cloud.gd
## GDT_TagCloud — облако чекбоксов тегов пресета: по чекбоксу на каждый тег
## проекта, отмечены те, что стоят у показанного пресета.
##
## Тег ВЫБИРАЕТСЯ, а не печатается, и это главное свойство виджета: пока теги
## правились строкой через запятую, опечатка тихо создавала новый тег вместо
## использования существующего — комната после этого просто переставала
## подходить своим узлам, молча и не сразу.
##
## Используют боковая панель «Генератора мира» и док Room Wizard; описание тега
## в обоих показывается ТУЛТИПОМ, а не подписью под чипом — переносящаяся
## подпись раздула бы минимальную ширину панели (грабля №3 в [[Редакторские
## инструменты]], она про этот док буквально). Вкладка «Редактор пресетов»
## этот виджет не берёт намеренно: у неё master-detail и место под описание
## прямо под чекбоксом — ровно то, чего в узкой панели не сделать.
##
## Сохранением пресета виджет НЕ занимается: «Генератор мира» пишет ресурс на
## каждое переключение, а Room Wizard — только по кнопке «Сохранить», и решать
## это должен владелец, а не облако.
@tool
extends HFlowContainer

const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")

## Теги показанного пресета изменились чекбоксом или строкой «новый тег».
signal preset_changed

## Все теги проекта в алфавитном порядке — словарь плюс то, что реально стоит у
## пресетов (см. GDT_Tags.known_tags).
var known_tags: Array[StringName] = []

var _catalog: RS_RoomTagCatalog
var _preset: RS_RoomPreset
## Куда посылать за описанием тега, у которого его нет. У дока и у вкладки путь
## разный, поэтому текст задаёт владелец.
var _where_hint := ""


func _init(where_hint := "") -> void:
	_where_hint = where_hint


## Перечитывает словарный запас из библиотеки. Зовётся при смене выделения, а не
## один раз: библиотеку мог поправить соседний инструмент или инспектор.
func set_vocabulary(library: RS_RoomPresetLibrary) -> void:
	_catalog = Library.tag_catalog_of(library)
	known_tags = Tags.known_tags(library, _catalog)


## Показывает теги [param preset]; null очищает облако.
func show_for(preset: RS_RoomPreset) -> void:
	_preset = preset
	_rebuild()


## Заводит тег из введённой строки и вешает его на показанный пресет.
## Возвращает нормализованный ключ или &"" — вызывающему это нужно для статуса.
func add_new(text: String) -> StringName:
	var tag := Tags.tagify(text)
	if tag == &"" or _preset == null:
		return &""
	Tags.register(_catalog, tag)
	if not known_tags.has(tag):
		known_tags.append(tag)
		known_tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	Tags.toggle(_preset, tag, true)
	_rebuild()
	preset_changed.emit()
	return tag


## free(), не queue_free(): облако пересобирается на каждую смену выделения, и
## отложенное удаление копило бы старые чекбоксы поверх новых.
func _rebuild() -> void:
	for child: Node in get_children():
		child.free()
	if _preset == null:
		return
	for tag: StringName in known_tags:
		var chip := CheckBox.new()
		chip.text = String(tag)
		chip.button_pressed = _preset.tags.has(tag)
		chip.tooltip_text = Tags.description_or_hint(_catalog, tag, _where_hint)
		chip.toggled.connect(_on_chip_toggled.bind(tag))
		add_child(chip)


func _on_chip_toggled(pressed: bool, tag: StringName) -> void:
	if _preset == null:
		return
	Tags.toggle(_preset, tag, pressed)
	preset_changed.emit()
