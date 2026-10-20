## GDT_Tags — структурные теги комнат: нормализация ключа, словарный запас проекта, заведение тега в словаре.
## [[Редакторские инструменты]], раздел «shared/». Только статика.
@tool
extends RefCounted

const Library := preload("res://addons/game_design_tool/shared/library.gd")


## Нижний регистр, слова через «_». ASCII намеренно (в отличие от GDT_Fs.slug): теги — ключи RS_RoomPreset.tags.
static func tagify(text: String) -> StringName:
	var out := ""
	var prev_us := false
	for c in text.strip_edges().to_lower():
		if c == "_" or (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
			prev_us = false
		elif not prev_us and out != "":
			out += "_"
			prev_us = true
	out = out.rstrip("_")
	return StringName(out) if out != "" else &""


## Сколько пресетов носит каждый тег: тег -> число. Считается по тому же набору,
## что и known_tags, иначе счётчик расходился бы со списком.
static func uses(library: RS_RoomPresetLibrary) -> Dictionary:
	var counts := {}
	for preset: RS_RoomPreset in Library.vocabulary_presets(library):
		for tag: StringName in preset.tags:
			counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


## Ключи словаря ПЛЮС теги, реально стоящие у пресетов: второе ловит опечатки (тег без описания работает),
## первое показывает заведённый, но ещё не носимый тег.
static func known_tags(
	library: RS_RoomPresetLibrary, catalog: RS_RoomTagCatalog
) -> Array[StringName]:
	var seen := {}
	for preset: RS_RoomPreset in Library.vocabulary_presets(library):
		for tag: StringName in preset.tags:
			seen[tag] = true
	if catalog:
		for id: StringName in catalog.ids():
			seen[id] = true

	var out: Array[StringName] = []
	for tag: StringName in seen.keys():
		out.append(tag)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## Заводит тег в словаре в момент навешивания, не описания: на инварианте «каждый тег пресетов есть в словаре»
## (dev/room_tags_check) держится отличие тега от опечатки. false — словаря нет или тег уже был.
static func register(catalog: RS_RoomTagCatalog, tag: StringName) -> bool:
	if catalog == null or tag == &"" or catalog.has_id(tag):
		return false
	catalog.add_id(tag)
	save_catalog(catalog)
	return true


## Путь берём у самого ресурса: запись по TAG_CATALOG_PATH создала бы второй файл рядом с настоящим.
static func save_catalog(catalog: RS_RoomTagCatalog) -> Error:
	if catalog == null:
		return ERR_UNAVAILABLE
	var path := catalog.resource_path
	if path == "":
		path = Library.TAG_CATALOG_PATH
	return ResourceSaver.save(catalog, path)


## Описание тега для тултипа — или прямая просьба его завести: тег без описания
## неотличим от опечатки, и молчать об этом хуже, чем показать текст-подсказку.
## [param where] — куда идти писать описание; у дока и у вкладки путь разный.
static func description_or_hint(
	catalog: RS_RoomTagCatalog, tag: StringName, where: String
) -> String:
	if catalog == null:
		return ""
	var description := catalog.description_of(tag)
	if description != "":
		return description
	return "Нет описания. Заведи его в %s." % where


## Вешает или снимает тег с пресета. Ресурс НЕ сохраняется — сохранением и
## показом статуса распоряжается вызывающий, у каждого инструмента свой.
static func toggle(preset: RS_RoomPreset, tag: StringName, pressed: bool) -> void:
	if preset == null:
		return
	if pressed:
		if not preset.tags.has(tag):
			preset.tags.append(tag)
	else:
		preset.tags.erase(tag)
