## res://addons/game_design_tool/shared/library.gd
## GDT_Library — доступ к библиотеке пресетов: где она лежит, как назвать
## пресет, какой пресет стоит за сценой узла и какие бывают типы помещений.
##
## Три инструмента (вкладки «Редактор пресетов» и «Генератор мира», док Room
## Wizard) читают одну и ту же библиотеку, и каждый держал свой LIBRARY_PATH,
## свой label_of() и свой обход .presets. Расхождение это уже дало: поиск
## пресета по сцене существовал в «Генераторе мира» ДВАЖДЫ — _preset_for
## (боковая панель) знал про library.hub, а _label_for_scene (прогон сидов) —
## нет, и хаб в статистике отчитывался как «вне библиотеки». Здесь обход один,
## и разъехаться ему негде.
##
## Только статика — библиотека загружается по требованию, состояния тут нет.
@tool
extends RefCounted

const LIBRARY_PATH := "res://data/room_preset_library.tres"
## Запасной путь словаря тегов: обычно он приходит из библиотеки (tag_catalog),
## но с библиотекой без словаря инструмент должен продолжать работать, а не
## молчать.
const TAG_CATALOG_PATH := "res://data/room_tag_catalog.tres"


## CACHE_MODE_REPLACE, а не обычная загрузка: инструмент перечитывает библиотеку
## после того, как её мог поправить он сам или инспектор, и закэшированный
## экземпляр показывал бы состояние до правки.
static func load_library() -> RS_RoomPresetLibrary:
	return ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary


static func tag_catalog_of(library: RS_RoomPresetLibrary) -> RS_RoomTagCatalog:
	if library and library.tag_catalog:
		return library.tag_catalog
	return ResourceLoader.load(TAG_CATALOG_PATH) as RS_RoomTagCatalog


## Читаемое имя пресета для таблиц, карточек и отчётов. Повторяет
## RS_RoomPresetLibrary._preset_label намеренно: тот приватный и живёт на
## рантайм-стороне, а тянуть инструментальную подпись через игровой API значило
## бы сделать его публичным ради редактора.
static func label_of(preset: RS_RoomPreset) -> String:
	if preset == null:
		return ""
	if preset.display_name != "":
		return preset.display_name
	return preset.resource_path.get_file().get_basename()


## Пресеты, составляющие СЛОВАРНЫЙ ЗАПАС библиотеки: пул автоподбора плюс
## fallback. Хаб сюда не входит намеренно — он выдаётся домашнему узлу в обход
## отбора (RS_RoomPresetLibrary.hub), и его теги не часть общего набора.
static func vocabulary_presets(library: RS_RoomPresetLibrary) -> Array[RS_RoomPreset]:
	var out: Array[RS_RoomPreset] = []
	if library == null:
		return out
	for preset: RS_RoomPreset in library.presets:
		if preset != null:
			out.append(preset)
	if library.fallback:
		out.append(library.fallback)
	return out


## Пресет по пути сцены — обратной ссылки «узел → пресет» в данных нет.
## Хаб проверяется наравне с остальными: у него теперь свой RS_RoomPreset
## (hub.tres), просто вне пула автоподбора, и узнавать его нужно так же, как
## любой другой узел с пресетом.
static func preset_for_scene(library: RS_RoomPresetLibrary, scene_path: String) -> RS_RoomPreset:
	if library == null or scene_path == "":
		return null
	for preset: RS_RoomPreset in library.presets:
		if preset and preset.scene and preset.scene.resource_path == scene_path:
			return preset
	for special: RS_RoomPreset in [library.fallback, library.hub]:
		if special and special.scene and special.scene.resource_path == scene_path:
			return special
	return null


## Варианты «Типа»: «нет типа», затем каталог В ПОРЯДКЕ ОБЪЯВЛЕНИЯ, затем типы,
## которые у пресетов стоят, но каталогу неизвестны.
##
## Порядок каталога не сортируем — он же задаёт порядок розыгрыша, и видеть его
## как есть полезнее, чем по алфавиту. Неизвестные типы дописываем, а не
## выбрасываем: подставить такому пресету «—» значило бы стереть авторскую
## правку молча, первым же сохранением формы.
static func type_ids(library: RS_RoomPresetLibrary, extra: RS_RoomPreset = null) -> Array[StringName]:
	var ids: Array[StringName] = [&""]
	var catalog := library.type_catalog if library else null
	if catalog:
		ids.append_array(catalog.ids())

	var candidates := vocabulary_presets(library)
	if extra:
		candidates.append(extra)
	for preset: RS_RoomPreset in candidates:
		if preset.room_type != &"" and not ids.has(preset.room_type):
			ids.append(preset.room_type)
	return ids


## Подписи вариантов типа для [param ids].
##
## [param comma_safe] выбрасывает запятые: в ячейке Tree (CELL_MODE_RANGE) они —
## разделитель значений, и одно имя развалилось бы на два пункта. В OptionButton
## этого ограничения нет, но список берётся тот же — разъехавшиеся подписи в
## двух редакторах одного поля путали бы сильнее, чем стоит сохранённая запятая.
static func type_labels(
	library: RS_RoomPresetLibrary, ids: Array[StringName], comma_safe := false
) -> Array[String]:
	var catalog := library.type_catalog if library else null
	var out: Array[String] = []
	for id: StringName in ids:
		var text := catalog.label_of(id) if catalog else ("—" if id == &"" else String(id))
		if id != &"" and (catalog == null or catalog.by_id(id) == null):
			text += " (нет в каталоге)"
		out.append(text.replace(",", " ") if comma_safe else text)
	return out


## Сохраняет пресет по его собственному пути. Код ошибки отдаём вызывающему —
## показать его должен он, у каждого инструмента своя строка статуса.
static func save_preset(preset: RS_RoomPreset) -> Error:
	return ResourceSaver.save(preset, preset.resource_path)
