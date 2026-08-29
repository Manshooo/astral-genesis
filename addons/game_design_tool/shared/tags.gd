## res://addons/game_design_tool/shared/tags.gd
## GDT_Tags — работа со структурными тегами комнат: нормализация ключа, сбор
## словарного запаса проекта, заведение тега в словаре.
##
## Раньше это лежало ТРЕМЯ копиями — в обеих вкладках и в доке Room Wizard, —
## и копии были оправданы тем, что «инструменты самодостаточны, общих утилит не
## заводим ради пяти строк». Пяти строк давно нет: с появлением словаря тегов
## (RS_RoomTagCatalog) копия выросла до ~90 строк каждая, и три из них должны
## соблюдать один инвариант — «каждый тег пресетов есть в словаре», тот самый,
## на котором держится отличие настоящего тега от опечатки. Инвариант, живущий
## в трёх местах, — это инвариант, который отвалится в одном из них незаметно.
##
## Только статика — состояния нет, вызывающий держит свои library/catalog.
@tool
extends RefCounted

const Library := preload("res://addons/game_design_tool/shared/library.gd")


## Тег в стиле уже существующих (vertical_hub, floor_hub, level_exit): нижний
## регистр, слова через «_», без пунктуации.
##
## ASCII намеренно, в отличие от GDT_Fs.slug: теги — это ключи
## RS_LevelNode.tags/RS_RoomPreset.tags, а не текст для игрока, и кириллица в
## них не нужна. Имена файлов — другой случай, там кириллица допускается.
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


## Все теги проекта: ключи словаря ПЛЮС теги, реально стоящие у пресетов.
##
## Второе слагаемое обязательно и именно оно ловит опечатки: тег, которому не
## написали описания, всё равно работает (словарь ОПИСАТЕЛЬНЫЙ, подбор комнаты
## в него не заглядывает), и спрятать его значило бы врать про содержимое
## библиотеки. Первое — тоже: заведённый, но ещё никем не носимый тег иначе не
## показался бы в облаке, и завести его было бы негде, кроме как опечаткой.
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


## Заводит тег в словаре и сохраняет его. Зовётся В МОМЕНТ, когда тег вешают на
## пресет, а не когда для него написали описание: инвариант «каждый тег
## пресетов есть в словаре» держит dev/room_tags_check, и только на нём и
## работает отличие настоящего тега от опечатки.
##
## Возвращает false, если словаря нет или тег в нём уже был — вызывающему это
## нужно, чтобы не рапортовать о заведении там, где ничего не произошло.
static func register(catalog: RS_RoomTagCatalog, tag: StringName) -> bool:
	if catalog == null or tag == &"" or catalog.has_id(tag):
		return false
	catalog.add_id(tag)
	save_catalog(catalog)
	return true


## Сохраняет словарь. Путь берём у самого ресурса, а не константой: словарь
## может быть назначен библиотеке из любого места проекта, и записать его по
## TAG_CATALOG_PATH значило бы создать второй файл рядом с настоящим.
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
