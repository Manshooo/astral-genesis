## res://addons/game_design_tool/tabs/presets.gd
## Вкладка «Генератор» единого редактора геймдизайна. Закрывает четыре боли
## правки генерации:
##   1. веса/slot_count пресетов разбросаны по data/room/*.tres — здесь они
##      в одной таблице и правятся на месте; теги — отдельным облаком под
##      таблицей (см. ниже, почему не прямо в ячейке);
##   2. теги правились строкой через запятую в ячейке таблицы — опечатка тихо
##      создавала новый тег вместо использования существующего, и не было
##      способа увидеть, какие теги вообще есть в проекте. Облако тегов под
##      таблицей — чекбоксы по всем тегам библиотеки: выделил пресет, кликнул
##      нужные, опечатка невозможна в принципе, потому что не печатаешь;
##   3. новый пресет — это был поход в FileSystem создавать `.tres` руками и
##      прописывать путь к сцене. «Новый пресет» делает пустой ресурс, кладёт
##      в библиотеку и открывает в инспекторе (сцену/остальные поля — там,
##      Room Wizard, который снимет и этот шаг, ещё не сделан);
##   4. нет обратной связи «что реально выберется» и рассинхрон «заявленные
##      слоты ↔ сцена» — «Прогнать сиды» и «Проверить сцены», без изменений.
##
## Проверка стороны двери идёт через RS_RoomLayout — тем же правилом, которым
## RS_LayerPlan раскладывает слой, иначе инструмент проверял бы не то, что делает
## игра.
@tool
extends VBoxContainer

## Заголовок вкладки в TabContainer — тот берёт его из имени узла (см. _init).
const TAB_TITLE := "Генератор"

const LIBRARY_PATH := "res://data/room_preset_library.tres"
const PRESET_DIR := "res://data/room"

const COL_NAME := 0
const COL_SLOTS := 1
const COL_ACTUAL := 2
const COL_WEIGHT := 3
const COL_TAGS := 4

var _library: RS_RoomPresetLibrary
var _tree: Tree
var _report: RichTextLabel
var _seeds_spin: SpinBox
var _status: Label
## Путь .tres пресета -> сколько дверей реально в его сцене (считаем при обновлении).
var _actual_doors: Dictionary = {}

## Облако тегов: все теги, встречающиеся хоть у одного пресета библиотеки
## (включая fallback), не только у выделенного — иначе увидеть «что вообще
## есть» было бы негде, а именно это и было половиной проблемы.
var _known_tags: Array[StringName] = []
var _tag_flow: HFlowContainer
var _tag_section_label: Label
var _new_tag_edit: LineEdit

var _new_preset_dialog: ConfirmationDialog
var _new_preset_edit: LineEdit


func _init() -> void:
	name = TAB_TITLE  # TabContainer берёт заголовок вкладки из имени узла
	_build_ui()


## Таблицу наполняем не на старте редактора, а когда вкладку впервые открыли:
## _refresh инстанцирует ВСЕ сцены комнат (считает двери), и делать это ради
## вкладки, которую могут не открыть ни разу за сессию, незачем.
func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if _library == null and is_visible_in_tree():
		_refresh()


#region UI
func _build_ui() -> void:
	var title := Label.new()
	title.text = "Пресеты комнат"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_tree = Tree.new()
	_tree.columns = 5
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(0, 96)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.set_column_title(COL_NAME, "Пресет")
	_tree.set_column_title(COL_SLOTS, "Слоты")
	_tree.set_column_title(COL_ACTUAL, "В сцене")
	_tree.set_column_title(COL_WEIGHT, "Вес")
	_tree.set_column_title(COL_TAGS, "Теги")
	_tree.set_column_expand(COL_SLOTS, false)
	_tree.set_column_expand(COL_ACTUAL, false)
	_tree.set_column_expand(COL_WEIGHT, false)
	_tree.set_column_custom_minimum_width(COL_SLOTS, 56)
	_tree.set_column_custom_minimum_width(COL_ACTUAL, 64)
	_tree.set_column_custom_minimum_width(COL_WEIGHT, 56)
	_tree.item_edited.connect(_on_item_edited)
	_tree.item_selected.connect(_on_tree_selection_changed)
	add_child(_tree)

	_tag_section_label = Label.new()
	_tag_section_label.text = "Теги: выдели пресет в таблице"
	add_child(_tag_section_label)

	_tag_flow = HFlowContainer.new()
	add_child(_tag_flow)

	var new_tag_row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег — Enter добавляет и включает выделенному"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _on_add_tag_pressed())
	new_tag_row.add_child(_new_tag_edit)
	new_tag_row.add_child(_button("+ тег", _on_add_tag_pressed))
	add_child(new_tag_row)

	add_child(HSeparator.new())

	var row1 := HBoxContainer.new()
	row1.add_child(_button("Обновить", _refresh_pressed))
	row1.add_child(_button("Открыть сцену", _on_open_scene_pressed))
	row1.add_child(_button("Открыть в инспекторе", _on_edit_in_inspector_pressed))
	row1.add_child(_button("Новый пресет", _on_new_preset_pressed))
	add_child(row1)

	var row2 := HBoxContainer.new()
	var check := _button("Проверить сцены", _on_validate_pressed)
	check.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(check)
	add_child(row2)

	add_child(HSeparator.new())

	var row3 := HBoxContainer.new()
	var seeds_label := Label.new()
	seeds_label.text = "Сидов:"
	row3.add_child(seeds_label)
	_seeds_spin = SpinBox.new()
	_seeds_spin.min_value = 1
	_seeds_spin.max_value = 200
	_seeds_spin.value = 30
	row3.add_child(_seeds_spin)
	var run := _button("Прогнать сиды", _on_preview_pressed)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(run)
	add_child(row3)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.selection_enabled = true
	_report.custom_minimum_size = Vector2(0, 96)
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_report.size_flags_stretch_ratio = 2.0  # отчёту места больше, чем таблице
	add_child(_report)

	# Статус — строго ОДНА строка с многоточием, а не autowrap. Label с autowrap
	# считает минимальную высоту, перенося текст по минимальной ШИРИНЕ (до первой
	# раскладки это ~17 px), и требует под себя сотни пикселей. В доке это
	# разъезжало всю правую панель (см. [[Редакторские инструменты]]); на главном экране
	# так не ломается, но однострочный статус всё равно правильнее — иначе длинный
	# путь ресурса перекладывает вёрстку под собой. Полный текст — в подсказке.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	_new_preset_dialog = ConfirmationDialog.new()
	_new_preset_dialog.title = "Новый пресет — имя"
	_new_preset_edit = LineEdit.new()
	_new_preset_edit.custom_minimum_size = Vector2(280, 0)
	_new_preset_dialog.add_child(_new_preset_edit)
	_new_preset_dialog.register_text_enter(_new_preset_edit)
	_new_preset_dialog.confirmed.connect(_on_new_preset_confirmed)
	add_child(_new_preset_dialog)


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


## Строка статуса обрезается многоточием (см. про autowrap в _build_ui), поэтому
## целиком текст кладём в подсказку.
func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text
#endregion


#region Таблица пресетов
func _refresh_pressed() -> void:
	_refresh()
	_set_status("Обновлено.")


func _refresh() -> void:
	_library = ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary
	_tree.clear()
	_actual_doors.clear()
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + LIBRARY_PATH)
		_known_tags.clear()
		_on_tree_selection_changed()
		return

	var root := _tree.create_item()
	for preset: RS_RoomPreset in _library.presets:
		if preset == null:
			continue
		_add_row(root, preset, false)
	if _library.fallback:
		_add_row(root, _library.fallback, true)

	_collect_known_tags()
	_on_tree_selection_changed()  # таблица только что очищена — выделения нет

	_set_status(
		"%d пресетов + fallback. Слоты/вес — в таблице, теги — облаком ниже."
		% _library.presets.size()
	)


func _add_row(root: TreeItem, preset: RS_RoomPreset, is_fallback: bool) -> void:
	var item := _tree.create_item(root)
	var label := _label_of(preset)
	item.set_text(COL_NAME, label + (" (fallback)" if is_fallback else ""))
	item.set_tooltip_text(COL_NAME, preset.resource_path)
	item.set_metadata(COL_NAME, preset.resource_path)

	item.set_cell_mode(COL_SLOTS, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(COL_SLOTS, 0, 12, 1)
	item.set_range(COL_SLOTS, preset.slot_count)
	item.set_editable(COL_SLOTS, true)

	var actual := _count_doors(preset)
	_actual_doors[preset.resource_path] = actual
	item.set_text(COL_ACTUAL, "нет сцены" if actual < 0 else str(actual))
	if actual >= 0 and actual != preset.slot_count:
		# Рассинхрон: генератор верит slot_count, а рёбра раздаются по реальным дверям.
		item.set_custom_color(COL_ACTUAL, Color(1, 0.45, 0.4))

	item.set_cell_mode(COL_WEIGHT, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(COL_WEIGHT, 0.0, 10.0, 0.1)
	item.set_range(COL_WEIGHT, preset.weight)
	item.set_editable(COL_WEIGHT, true)

	# Read-only здесь: правка — облаком тегов под таблицей (см. _rebuild_tag_chips).
	# Свободный текст через запятую опечаткой тихо плодил новый тег вместо
	# использования существующего — ровно то, ради ухода от чего облако и есть.
	item.set_text(COL_TAGS, ", ".join(preset.tags))
	item.set_tooltip_text(COL_TAGS, "Правится облаком тегов под таблицей — выдели строку.")


## Сколько дверей с C_DoorSlot реально в сцене пресета. -1 — сцена не назначена.
func _count_doors(preset: RS_RoomPreset) -> int:
	if preset.scene == null:
		return -1
	var room := preset.scene.instantiate()
	var count := RS_RoomLayout.door_entities(room).size()
	room.free()
	return count


func _on_item_edited() -> void:
	var item := _tree.get_edited()
	var column := _tree.get_edited_column()
	if item == null:
		return
	var path: String = item.get_metadata(COL_NAME)
	var preset := ResourceLoader.load(path) as RS_RoomPreset
	if preset == null:
		_set_status("⚠ Не найден пресет: " + path)
		return

	match column:
		COL_SLOTS:
			preset.slot_count = int(item.get_range(COL_SLOTS))
			var actual: int = _actual_doors.get(path, -1)
			item.set_custom_color(COL_ACTUAL, Color(1, 0.45, 0.4))
			if actual < 0 or actual == preset.slot_count:
				item.clear_custom_color(COL_ACTUAL)
		COL_WEIGHT:
			preset.weight = item.get_range(COL_WEIGHT)
		_:
			return

	var err := ResourceSaver.save(preset, path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	_set_status("Сохранено: " + path.get_file())


func _selected_preset() -> RS_RoomPreset:
	var item := _tree.get_selected()
	if item == null:
		return null
	return ResourceLoader.load(item.get_metadata(COL_NAME)) as RS_RoomPreset


func _on_open_scene_pressed() -> void:
	var preset := _selected_preset()
	if preset == null:
		_set_status("⚠ Сначала выбери пресет.")
		return
	if preset.scene == null:
		_set_status("⚠ У пресета не назначена сцена.")
		return
	EditorInterface.open_scene_from_path(preset.scene.resource_path)
	_set_status("Открыта " + preset.scene.resource_path.get_file())


func _on_edit_in_inspector_pressed() -> void:
	var preset := _selected_preset()
	if preset == null:
		_set_status("⚠ Сначала выбери пресет.")
		return
	EditorInterface.edit_resource(preset)
#endregion


#region Облако тегов
## Все теги хоть одного пресета библиотеки (включая fallback) — не только
## выделенного: облако должно показывать «что вообще есть в проекте», иначе
## не видно, что тег `vertical_hub` уже существует, и опечатка `verticalhub`
## тихо создаёт второй.
func _collect_known_tags() -> void:
	var seen := {}
	for preset: RS_RoomPreset in _library.presets:
		if preset == null:
			continue
		for tag: StringName in preset.tags:
			seen[tag] = true
	if _library.fallback:
		for tag: StringName in _library.fallback.tags:
			seen[tag] = true

	var result: Array[StringName] = []
	for tag: StringName in seen.keys():
		result.append(tag)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_known_tags = result


func _on_tree_selection_changed() -> void:
	var preset := _selected_preset()
	_tag_section_label.text = (
		"Теги «%s»:" % _label_of(preset) if preset else "Теги: выдели пресет в таблице"
	)
	_rebuild_tag_chips(preset)


## free(), не queue_free(): та же причина, что у оверлеев «Генератора мира» —
## перестройка идёт на каждую смену выделения, отложенное удаление копило бы
## старые чекбоксы поверх новых при быстром переключении строк.
func _rebuild_tag_chips(preset: RS_RoomPreset) -> void:
	for child: Node in _tag_flow.get_children():
		child.free()
	for tag: StringName in _known_tags:
		var chip := CheckBox.new()
		chip.text = String(tag)
		chip.button_pressed = preset != null and preset.tags.has(tag)
		chip.disabled = preset == null
		chip.toggled.connect(_on_tag_chip_toggled.bind(tag))
		_tag_flow.add_child(chip)


func _on_tag_chip_toggled(pressed: bool, tag: StringName) -> void:
	var preset := _selected_preset()
	if preset == null:
		return
	if pressed:
		if not preset.tags.has(tag):
			preset.tags.append(tag)
	elif preset.tags.has(tag):
		preset.tags.erase(tag)
	_save_tags(preset)


func _on_add_tag_pressed() -> void:
	var tag := _tagify(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag == &"":
		return
	if not _known_tags.has(tag):
		_known_tags.append(tag)
		_known_tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

	var preset := _selected_preset()
	if preset == null:
		_rebuild_tag_chips(null)
		_set_status("Тег «%s» добавлен в облако — станет доступен всем пресетам." % tag)
		return
	if not preset.tags.has(tag):
		preset.tags.append(tag)
	_save_tags(preset)


func _save_tags(preset: RS_RoomPreset) -> void:
	var err := ResourceSaver.save(preset, preset.resource_path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	var item := _tree.get_selected()
	if item:
		item.set_text(COL_TAGS, ", ".join(preset.tags))
	_rebuild_tag_chips(preset)
	_set_status("Сохранено: " + preset.resource_path.get_file())


## Тег в стиле уже существующих (vertical_hub, floor_hub, level_exit): нижний
## регистр, слова через «_», без пунктуации. Тегам ASCII-идентификаторов
## хватает — это ключи RS_LevelNode.tags/RS_RoomPreset.tags, не текст для
## игрока, поэтому кириллица здесь не нужна (в отличие от _filename_slug).
func _tagify(text: String) -> StringName:
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
#endregion


#region Новый пресет
func _on_new_preset_pressed() -> void:
	if _library == null:
		_set_status("⚠ Библиотека не загружена.")
		return
	_new_preset_edit.text = "Новый пресет"
	_new_preset_dialog.popup_centered(Vector2i(340, 90))
	_new_preset_edit.grab_focus()
	_new_preset_edit.select_all()


## Пустой RS_RoomPreset в библиотеке — не полноценный Room Wizard (тот снимал
## бы этот шаг целиком, назначая сцену сразу), а минимум, снимающий ручной
## поход в FileSystem. Сцену и остальные поля — «Открыть в инспекторе».
func _on_new_preset_confirmed() -> void:
	var entered := _new_preset_edit.text.strip_edges()
	if entered == "":
		_set_status("⚠ Пустое имя.")
		return

	var preset := RS_RoomPreset.new()
	preset.display_name = entered
	var path := _unique_preset_path(_filename_slug(entered))
	preset.take_over_path(path)
	var err := ResourceSaver.save(preset, path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return

	_library.presets.append(preset)
	var lib_err := ResourceSaver.save(_library, LIBRARY_PATH)
	if lib_err != OK:
		_set_status("⚠ Пресет создан, но библиотека не сохранилась (код %d)" % lib_err)
		return

	_rescan_filesystem()
	_refresh()
	_select_row(path)
	_set_status("Создан: " + path.get_file() + " — назначь сцену через «Открыть в инспекторе».")


func _select_row(path: String) -> void:
	var item := _tree.get_root()
	if item == null:
		return
	item = item.get_first_child()
	while item != null:
		if String(item.get_metadata(COL_NAME)) == path:
			item.select(COL_NAME)
			_on_tree_selection_changed()
			return
		item = item.get_next()


func _unique_preset_path(base: String) -> String:
	var path := PRESET_DIR + "/" + base + ".tres"
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.tres" % [PRESET_DIR, base, n]
		n += 1
	return path


## Имя файла из русского/любого display_name — тот же приём, что у вкладки
## «Шаблоны» (templates.gd._snake) для той же задачи, продублирован здесь
## умышленно: вкладки этого редактора самодостаточны, общих утилит не заводим
## ради пяти строк (см. [[Единый редактор геймдизайна]]).
func _filename_slug(text: String) -> String:
	var out := ""
	var prev_us := false
	for c in text.strip_edges().to_lower():
		if c == "_" or (c >= "0" and c <= "9") or c.to_lower() != c.to_upper():
			out += c
			prev_us = false
		elif not prev_us and out != "":
			out += "_"
			prev_us = true
	out = out.rstrip("_")
	return out if out != "" else "room_preset"


func _rescan_filesystem() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
#endregion


#region Проверка сцен
## Отчёт по каждому пресету: расхождения slot_count ↔ сцена и разбор дверей —
## какая дверь на какой стене и что у неё в slot_id.
##
## slot_id мы НЕ проставляем автоматически, хотя рекомендацию печатаем: у дверей,
## не перекрывших component_resources, C_DoorSlot приходит из complex_door.tscn и
## разделяется ВСЕМИ дверьми проекта — запись в него испортила бы все комнаты
## сразу. Плюс на раздачу рёбер slot_id больше не влияет (сторона берётся из
## геометрии), он остался ключом детерминированной сортировки.
func _on_validate_pressed() -> void:
	if _library == null:
		_refresh()
	if _library == null:
		return
	var lines: Array[String] = []
	var problems_total := 0

	for preset: RS_RoomPreset in _library.presets + ([_library.fallback] if _library.fallback else []):
		if preset == null:
			continue
		lines.append("[b]%s[/b]" % _label_of(preset))
		var problems := _library.validate_preset(preset)
		problems_total += problems.size()
		for problem in problems:
			lines.append("  [color=#ff7066]! %s[/color]" % problem)
		lines.append_array(_door_lines(preset))

	var head := (
		"[color=#7ad17a]Расхождений нет.[/color]"
		if problems_total == 0
		else "[color=#ff7066]Проблем: %d[/color]" % problems_total
	)
	_report.text = head + "\n" + "\n".join(lines)
	_set_status("Проверено пресетов: %d" % (_library.presets.size() + (1 if _library.fallback else 0)))


func _door_lines(preset: RS_RoomPreset) -> Array[String]:
	var lines: Array[String] = []
	if preset.scene == null:
		return lines
	var room := preset.scene.instantiate()
	for door in RS_RoomLayout.door_entities(room):
		var direction := RS_RoomLayout.door_direction(door as Node as Node3D, room)
		var slot_id := RS_RoomLayout.slot_id_of(door)
		var mark := "" if slot_id == direction else "   → по стене подошёл бы «%s»" % direction
		lines.append(
			"    %s: стена «%s», slot_id «%s»%s"
			% [door.name, direction, slot_id if slot_id != &"" else "—", mark]
		)
	room.free()
	return lines
#endregion


#region Предпросмотр выборки
## Гоняет генератор по N сидам и показывает, что реально выпало и почему остальные
## пресеты отсеялись. Выбор берём из настоящего прогона (room_scene_path), причины
## отсева — из RS_RoomPresetLibrary.explain_selection: жёсткие фильтры
## (вместимость/теги/специфичность) от rng не зависят, поэтому цифры честные.
func _on_preview_pressed() -> void:
	if _library == null:
		_refresh()
	if _library == null:
		return
	var seeds := int(_seeds_spin.value)
	var picks := {}  # label -> сколько раз реально выбран
	var reasons := {}  # label -> { причина: сколько раз }
	var degrees := {}  # число рёбер -> сколько узлов
	var nodes_total := 0

	for s in seeds:
		var graph := RS_LevelGraph.new().generate_run(s, _library)
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		for node: RS_LevelNode in graph.nodes.values():
			nodes_total += 1
			var degree: int = node.connections.size()
			degrees[degree] = degrees.get(degree, 0) + 1
			var picked := _label_for_scene(node.room_scene_path)
			picks[picked] = picks.get(picked, 0) + 1

			var explained: Dictionary = _library.explain_selection(node, rng)["reasons"]
			for label: String in explained:
				# Победителя броска у explain свой (у него отдельный rng), поэтому
				# «выбран» сливаем с «дошёл до весов»: таблица отсева говорит только
				# о ЖЁСТКИХ фильтрах, а они от rng не зависят. Кто реально выпал —
				# в таблице «Что выпало», она из настоящего прогона.
				var reason: String = explained[label]
				if reason == RS_RoomPresetLibrary.REASON_SELECTED:
					reason = RS_RoomPresetLibrary.REASON_CANDIDATE
				if not reasons.has(label):
					reasons[label] = {}
				reasons[label][reason] = reasons[label].get(reason, 0) + 1

	_report.text = _preview_report(seeds, nodes_total, picks, reasons, degrees)
	_set_status("Прогнано сидов: %d, узлов: %d" % [seeds, nodes_total])


func _preview_report(
	seeds: int, nodes_total: int, picks: Dictionary, reasons: Dictionary, degrees: Dictionary
) -> String:
	var out := "[b]Прогон %d сидов, %d узлов[/b]\n" % [seeds, nodes_total]

	out += "\n[b]Что выпало[/b]\n[code]"
	var picked_labels := picks.keys()
	picked_labels.sort_custom(func(a, b): return picks[a] > picks[b])
	for label: String in picked_labels:
		out += "%-24s %5d  %4.1f%%\n" % [label, picks[label], 100.0 * picks[label] / maxi(nodes_total, 1)]
	out += "[/code]"

	out += "\n[b]Почему отсеивались[/b] (по узлам всех сидов)\n[code]"
	var reason_labels := reasons.keys()
	reason_labels.sort()
	for label: String in reason_labels:
		var parts: Array[String] = []
		var by_reason: Dictionary = reasons[label]
		var keys := by_reason.keys()
		keys.sort()
		for reason: String in keys:
			parts.append("%s×%d" % [reason, by_reason[reason]])
		out += "%-24s %s\n" % [label, ", ".join(parts)]
	out += "[/code]"

	out += "\n[b]Степени узлов (сколько рёбер = сколько дверей нужно)[/b]\n[code]"
	var degree_keys := degrees.keys()
	degree_keys.sort()
	for degree: int in degree_keys:
		out += "рёбер %d: %5d узлов\n" % [degree, degrees[degree]]
	out += "[/code]"

	out += (
		"\n[i]Порядок отбора: вместимость (slot_count ≥ рёбер) → теги "
		+ "(node.tags ⊆ preset.tags) → специфичность (минимум лишних тегов) → вес. "
		+ "Вес применяется ПОСЛЕДНИМ: если конкуренты отсеялись раньше, правка веса "
		+ "не изменит ничего — сначала смотри на «вместимость» и «теги». "
		+ "«Дошёл до весов» — сколько раз пресет участвовал в броске; сколько раз он "
		+ "его выиграл, смотри в «Что выпало».[/i]"
	)
	return out


## Пресет по пути сцены — для колонки «что выпало». Сцены вне библиотеки (хаб,
## placeholder) показываем по имени файла.
func _label_for_scene(scene_path: String) -> String:
	for preset: RS_RoomPreset in _library.presets:
		if preset and preset.scene and preset.scene.resource_path == scene_path:
			return _label_of(preset)
	if _library.fallback and _library.fallback.scene \
			and _library.fallback.scene.resource_path == scene_path:
		return _label_of(_library.fallback) + " (fallback)"
	return scene_path.get_file().get_basename() + " (вне библиотеки)"


func _label_of(preset: RS_RoomPreset) -> String:
	if preset.display_name != "":
		return preset.display_name
	return preset.resource_path.get_file().get_basename()
#endregion
