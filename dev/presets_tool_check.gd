extends "res://dev/check_harness.gd"
## Проверка вкладки «Редактор пресетов» (addons/game_design_tool/tabs/presets*) на
## ВРЕМЕННОЙ библиотеке в user://: правки здесь пишутся на диск по-настоящему, и
## гонять их по данным проекта значило бы портить их каждым прогоном.
##
## Что ломается тихо и потому проверяется:
##   - переименование тега в уже занятое имя оставляло в словаре две записи с
##     одним id — вторая становилась невидимой, а validate() кнопка не звала;
##   - правка из таблицы или карточки обязана доехать до файла, а таблица и
##     карточка — показать её, а не прежнее значение;
##   - «В сцене» считается тем же кэшем RS_RoomLayout, что у рантайма;
##   - новый тег заводится в словаре в момент, когда его вешают.
##
## История редактора (GDT_Undo) вне работающего редактора не существует —
## Engine.is_editor_hint() ложно, — и правка здесь идёт прямым путём GDT_Undo:
## тем же набором «было → стало», только без записи в историю. Сам откат Ctrl+Z
## headless не проверить; его путь данных тот же, что у правки, плюс
## undo-свойства, которые GDT_Undo собирает из того же «было».
## Запускать: godot --headless dev/presets_tool_check.tscn

const PresetsTab := preload("res://addons/game_design_tool/tabs/presets.gd")
const DIR := "user://presets_tool_check"
const LIB_PATH := DIR + "/library.tres"
const TAGS_PATH := DIR + "/tags.tres"
## Однодверная сцена — счётчик «В сцене» обязан её посчитать.
const ONE_DOOR_SCENE := "res://src/levels/procedural/rooms/test_room.tscn"


func _ready() -> void:
	_make_library()
	var tab := PresetsTab.new()
	tab.ctx.library_path = LIB_PATH
	add_child(tab)
	await get_tree().process_frame

	_check_load(tab)
	_check_edit(tab)
	_check_new_tag(tab)
	await _check_rename_collision(tab)
	_check_forget(tab)
	_check_scene_check(tab)

	tab.queue_free()
	_cleanup()
	_finish()


## Три пресета, словарь из трёх тегов (у «alpha» есть описание, у «beta» нет).
func _make_library() -> void:
	_cleanup()
	DirAccess.make_dir_recursive_absolute(DIR)

	var catalog := RS_RoomTagCatalog.new()
	var alpha := catalog.add_id(&"alpha")
	alpha.description = "описание альфы"
	catalog.add_id(&"beta")
	catalog.add_id(&"gamma")
	_save(catalog, TAGS_PATH)

	var library := RS_RoomPresetLibrary.new()
	library.tag_catalog = load(TAGS_PATH)
	for spec: Array in [["one", [&"alpha"], true], ["two", [&"alpha", &"beta"], false]]:
		library.presets.append(_make_preset(spec[0], spec[1], spec[2]))
	library.fallback = _make_preset("spare", [], false)
	_save(library, LIB_PATH)


func _make_preset(id: String, tags: Array, with_scene: bool) -> RS_RoomPreset:
	var preset := RS_RoomPreset.new()
	preset.display_name = id
	for tag: StringName in tags:
		preset.tags.append(tag)
	preset.slot_count = 3
	if with_scene:
		preset.scene = load(ONE_DOOR_SCENE)
	var path := "%s/%s.tres" % [DIR, id]
	_save(preset, path)
	return load(path)


func _save(res: Resource, path: String) -> void:
	res.take_over_path(path)
	ResourceSaver.save(res, path)


## Файл, а не закэшированный объект: правка обязана доехать до диска.
func _on_disk(path: String) -> Resource:
	return ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)


func _cleanup() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(DIR)


func _preset(tab: Node, id: String) -> RS_RoomPreset:
	for preset: RS_RoomPreset in tab.ctx.library.presets + [tab.ctx.library.fallback]:
		if preset.display_name == id:
			return preset
	return null


func _check_load(tab: Node) -> void:
	_check("временная библиотека загрузилась", tab.ctx.library != null, LIB_PATH)
	var rows := 0
	var root: TreeItem = tab._tree.get_root()
	var item := root.get_first_child() if root else null
	while item:
		rows += 1
		item = item.get_next()
	_check("в таблице все пресеты и fallback", rows == 3, str(rows))
	var one := _preset(tab, "one")
	_check(
		"«В сцене» считает двери сцены",
		tab.ctx.actual_doors.get(one.resource_path, -9) == 1,
		str(tab.ctx.actual_doors)
	)
	_check(
		"пресет без сцены помечен как «нет сцены»",
		tab.ctx.actual_doors.get(_preset(tab, "two").resource_path, -9) == -1,
		str(tab.ctx.actual_doors)
	)


## Правка из карточки: доезжает до файла, строка таблицы показывает новое.
func _check_edit(tab: Node) -> void:
	var one := _preset(tab, "one")
	tab._show_preset(one)
	tab._preset_card._slots.value = 1
	var saved := _on_disk(one.resource_path) as RS_RoomPreset
	_check("слоты из карточки записаны в файл", saved.slot_count == 1, str(saved.slot_count))
	var row: TreeItem = tab._row_for(one.resource_path)
	_check(
		"строка таблицы показывает правку карточки",
		int(row.get_range(PresetsTab.COL_SLOTS)) == 1,
		str(row.get_range(PresetsTab.COL_SLOTS))
	)


## Новый тег: заводится в словаре и вешается на показанный пресет.
func _check_new_tag(tab: Node) -> void:
	var one := _preset(tab, "one")
	tab._show_preset(one)
	tab._on_new_tag_requested("Delta Room")
	var catalog := _on_disk(TAGS_PATH) as RS_RoomTagCatalog
	_check("новый тег заведён в словаре", catalog.has_id(&"delta_room"), str(catalog.ids()))
	var saved := _on_disk(one.resource_path) as RS_RoomPreset
	_check("и повешен на пресет", saved.tags.has(&"delta_room"), str(saved.tags))


## Переименование в занятое имя — слияние, а не дубль.
func _check_rename_collision(tab: Node) -> void:
	tab._on_tag_selected(&"alpha")
	tab._tag_card._rename_edit.text = "beta"
	tab._tag_card._on_rename_confirmed()
	await get_tree().process_frame

	var catalog := _on_disk(TAGS_PATH) as RS_RoomTagCatalog
	var betas := 0
	for entry: RS_RoomTag in catalog.tags:
		betas += 1 if entry.id == &"beta" else 0
	_check("после слияния запись «beta» в словаре одна", betas == 1, str(catalog.ids()))
	_check("запись «alpha» ушла", not catalog.has_id(&"alpha"), str(catalog.ids()))
	_check("словарь валиден", catalog.validate().is_empty(), ", ".join(catalog.validate()))
	_check(
		"описание пустой «beta» взято у «alpha»",
		catalog.description_of(&"beta") == "описание альфы",
		catalog.description_of(&"beta")
	)
	var two := _on_disk(_preset(tab, "two").resource_path) as RS_RoomPreset
	_check(
		"у пресета с обоими тегами «beta» не задвоилась",
		two.tags.count(&"beta") == 1 and not two.tags.has(&"alpha"),
		str(two.tags)
	)
	var one := _on_disk(_preset(tab, "one").resource_path) as RS_RoomPreset
	_check("у пресета только с «alpha» стала «beta»", one.tags.has(&"beta"), str(one.tags))
	_check("карточка переключилась на новое имя", tab._tag_card.tag == &"beta", str(tab._tag_card.tag))

	# Обычное переименование — в свободное имя.
	tab._tag_card._rename_edit.text = "epsilon"
	tab._tag_card._on_rename_confirmed()
	catalog = _on_disk(TAGS_PATH) as RS_RoomTagCatalog
	_check(
		"переименование в свободное имя меняет id записи",
		catalog.has_id(&"epsilon") and not catalog.has_id(&"beta"),
		str(catalog.ids())
	)


## «Убрать из словаря» снимает описание, а не тег с пресетов.
func _check_forget(tab: Node) -> void:
	tab._on_tag_selected(&"epsilon")
	tab._tag_card._on_forget_pressed()
	var catalog := _on_disk(TAGS_PATH) as RS_RoomTagCatalog
	_check("тег убран из словаря", not catalog.has_id(&"epsilon"), str(catalog.ids()))
	var two := _on_disk(_preset(tab, "two").resource_path) as RS_RoomPreset
	_check("но остался у пресета", two.tags.has(&"epsilon"), str(two.tags))
	_check("карточка тега закрыта", not tab._tag_card.visible, "")


func _check_scene_check(tab: Node) -> void:
	tab._scene_check.run_check()
	var text: String = tab._scene_check.report_text()
	_check(
		"проверка сцен разобрала дверь однодверной комнаты",
		text.contains("one") and text.contains("стена"),
		text.left(200)
	)
