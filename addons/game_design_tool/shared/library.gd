## GDT_Library — доступ к библиотеке пресетов: путь, подпись пресета, пресет по сцене узла, типы помещений.
## [[Редакторские инструменты]], раздел «shared/». Только статика.
@tool
extends RefCounted

const LIBRARY_PATH := "res://data/room_preset_library.tres"
## Запасной путь словаря тегов, если у библиотеки его нет.
const TAG_CATALOG_PATH := "res://data/room_tag_catalog.tres"

## Границы правки слотов и веса — одни на все инструменты (RS_RoomPreset своих @export_range не носит).
const SLOT_RANGE := {"min": 0.0, "max": 12.0, "step": 1.0}
const WEIGHT_RANGE := {"min": 0.0, "max": 10.0, "step": 0.1}


## CACHE_MODE_REPLACE: инструмент перечитывает библиотеку после своих правок, кэш показал бы старое.
## [param path] — для проверок на временной копии.
static func load_library(path := LIBRARY_PATH) -> RS_RoomPresetLibrary:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary


## Спинбокс по границам SLOT_RANGE/WEIGHT_RANGE.
static func configure_spin(spin: SpinBox, bounds: Dictionary) -> void:
	spin.min_value = bounds["min"]
	spin.max_value = bounds["max"]
	spin.step = bounds["step"]


## Ячейка Tree в режиме диапазона по тем же границам.
static func configure_range_cell(item: TreeItem, column: int, bounds: Dictionary) -> void:
	item.set_cell_mode(column, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(column, bounds["min"], bounds["max"], bounds["step"])


static func tag_catalog_of(library: RS_RoomPresetLibrary) -> RS_RoomTagCatalog:
	if library and library.tag_catalog:
		return library.tag_catalog
	return ResourceLoader.load(TAG_CATALOG_PATH) as RS_RoomTagCatalog


## Повторяет RS_RoomPresetLibrary._preset_label намеренно: тот приватный и живёт на рантайм-стороне.
static func label_of(preset: RS_RoomPreset) -> String:
	if preset == null:
		return ""
	if preset.display_name != "":
		return preset.display_name
	return preset.resource_path.get_file().get_basename()


## Словарный запас: пул автоподбора плюс fallback. Хаб не входит — он выдаётся в обход отбора.
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


## Пресет по пути сцены (обратной ссылки в данных нет); хаб проверяется наравне с остальными.
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


## «Нет типа», каталог В ПОРЯДКЕ ОБЪЯВЛЕНИЯ (он же порядок розыгрыша), затем типы, неизвестные каталогу:
## выбросить их значило бы молча стереть авторскую правку первым же сохранением.
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


## [param comma_safe] убирает запятые: в CELL_MODE_RANGE ячейки Tree они разделитель значений.
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


## Код ошибки отдаётся вызывающему — у каждого инструмента своя строка статуса.
static func save_preset(preset: RS_RoomPreset) -> Error:
	return ResourceSaver.save(preset, preset.resource_path)
