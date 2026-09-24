## res://addons/game_design_tool/tabs/presets/context.gd
## Общее состояние вкладки «Редактор пресетов» — то, что делят её панели:
## библиотека, словарь тегов, словарный запас, счётчики дверей — и ЕДИНСТВЕННЫЙ
## путь правки пресетов и словаря.
##
## Вкладка была одним файлом на 1300 строк: таблица, две карточки, облако тегов,
## диалоги и проверка сцен ходили в одни и те же поля напрямую. Разнесённые по
## панелям, они договариваются через этот объект: правку делает контекст (через
## историю редактора, GDT_Undo), а панели узнают о ней сигналом и перерисовывают
## своё. Сигнал приходит и после Ctrl+Z — панели не отличают правку от отката, и
## отдельного пути «перерисуй после отмены» нет ни у одной.
@tool
extends RefCounted

const Library := preload("res://addons/game_design_tool/shared/library.gd")
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Undo := preload("res://addons/game_design_tool/shared/undo.gd")

## Строка для строки статуса вкладки.
signal status(text: String)
## Поля пресета поменялись — правкой или откатом.
signal preset_changed(preset: RS_RoomPreset)
## Поменялся набор тегов проекта или словарь (завели, переименовали, забыли,
## описали) — панелям пересобрать списки тегов.
signal vocabulary_changed
## Библиотека перечитана целиком — панелям начать с чистого листа.
signal library_reloaded

## Откуда брать библиотеку. Путь проекта; проверки подменяют его временной
## копией, чтобы правки не писались в настоящие данные.
var library_path := Library.LIBRARY_PATH

var library: RS_RoomPresetLibrary
## Словарь тегов. null — библиотека без словаря: описаний нет, остальное работает.
var tag_catalog: RS_RoomTagCatalog
## Все теги проекта — словарь плюс то, что реально стоит у пресетов.
var known_tags: Array[StringName] = []
## Тег -> сколько пресетов его носят.
var tag_uses: Dictionary = {}
## Варианты «Типа» по индексам — см. GDT_Library.type_ids.
var type_ids: Array[StringName] = []
## Путь .tres пресета -> сколько дверей реально в его сцене; -1 — сцены нет.
var actual_doors: Dictionary = {}


## Перечитать библиотеку. Кэш сцен комнат сбрасываем: дизайнер мог поправить
## дверь в сцене, и без сброса счётчик «В сцене» показывал бы старую геометрию
## (тот же приём, что у «Пересобрать» в «Генераторе мира»).
func reload() -> bool:
	RS_RoomLayout.clear_scene_cache()
	library = Library.load_library(library_path)
	actual_doors.clear()
	if library == null:
		tag_catalog = null
		known_tags.clear()
		tag_uses.clear()
		type_ids.clear()
		library_reloaded.emit()
		return false
	tag_catalog = Library.tag_catalog_of(library)
	type_ids = Library.type_ids(library)
	for preset: RS_RoomPreset in Library.vocabulary_presets(library):
		actual_doors[preset.resource_path] = _count_doors(preset)
	collect_vocabulary()
	library_reloaded.emit()
	return true


func collect_vocabulary() -> void:
	tag_uses = Tags.uses(library)
	known_tags = Tags.known_tags(library, tag_catalog)


## Словарь поменяли мимо edit_* (тег заведён GDT_Tags.register) — пересчитать и
## сказать панелям.
func notify_vocabulary() -> void:
	collect_vocabulary()
	vocabulary_changed.emit()


## Сколько дверей с C_DoorSlot в сцене пресета. Через кэш RS_RoomLayout — тем же
## правилом и тем же кэшем, что рантайм и «Генератор мира»; раньше вкладка
## инстанцировала каждую сцену сама, по разу на обновление таблицы.
func _count_doors(preset: RS_RoomPreset) -> int:
	if preset.scene == null:
		return -1
	return RS_RoomLayout.door_count_of_scene(preset.scene.resource_path)


func type_index(id: StringName) -> int:
	var index := type_ids.find(id)
	return index if index >= 0 else 0


func type_at(index: int) -> StringName:
	return type_ids[index] if index >= 0 and index < type_ids.size() else &""


func set_status(text: String) -> void:
	status.emit(text)


# ---------------------------------------------------------------------------
# Правки. Все — через историю редактора; сигналы шлёт _after_*, который зовётся
# и после правки, и после отката.
# ---------------------------------------------------------------------------


## Правка полей одного пресета. [param changes] — {свойство: [было, стало]}.
## [param merge] — для спинбоксов: тики одного перетаскивания становятся одним
## шагом истории, а не сотней.
func edit_preset(action: String, preset: RS_RoomPreset, changes: Dictionary, merge := false) -> bool:
	var err := Undo.commit(action, preset, changes, _after_preset_edit.bind(preset), merge)
	return _report(err, "Сохранено: " + preset.resource_path.get_file())


## Правка нескольких ресурсов одним шагом (теги по всем пресетам, словарь).
func edit_many(action: String, edits: Array, done_text: String) -> bool:
	var err := Undo.commit_many(action, edits, _after_bulk_edit)
	return _report(err, done_text)


## Одна правка в составе edit_many: пресет или запись словаря (та сохраняется
## каталогом, в который встроена).
func preset_edit(preset: RS_RoomPreset, changes: Dictionary) -> Object:
	return Undo.Edit.new(preset, changes)


func catalog_edit(target: Object, changes: Dictionary) -> Object:
	return Undo.Edit.new(target, changes, _catalog_file())


## Файл словаря: у каталога без собственного пути (встроен в библиотеку) это
## сама библиотека — писать надо её.
func _catalog_file() -> Resource:
	if tag_catalog == null:
		return null
	if tag_catalog.resource_path != "" and not tag_catalog.resource_path.contains("::"):
		return tag_catalog
	return library


func _report(err: Error, done_text: String) -> bool:
	if err != OK:
		set_status("⚠ Не удалось сохранить (код %d)" % err)
		return false
	set_status(done_text)
	return true


func _after_preset_edit(preset: RS_RoomPreset) -> void:
	collect_vocabulary()
	preset_changed.emit(preset)
	vocabulary_changed.emit()


func _after_bulk_edit() -> void:
	collect_vocabulary()
	for preset: RS_RoomPreset in Library.vocabulary_presets(library):
		preset_changed.emit(preset)
	vocabulary_changed.emit()
