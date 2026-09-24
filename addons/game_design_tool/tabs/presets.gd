## res://addons/game_design_tool/tabs/presets.gd
## Вкладка «Редактор пресетов» единого редактора геймдизайна: таблица пресетов и
## облако тегов слева, карточка выделенного — справа, проверка сцен — внизу.
##
## Что она закрывает:
##   1. веса/slot_count/тип пресетов разбросаны по .tres рядом со своими сценами
##      (src/levels/procedural/rooms/) — здесь они в одной таблице и правятся
##      на месте;
##   2. теги правились строкой через запятую — опечатка тихо создавала новый тег.
##      Тег теперь только выбирается из списка известных;
##   3. ЧТО тег значит, прочитать было негде — отсюда словарь (RS_RoomTagCatalog)
##      и карточка тега;
##   4. рассинхрон «заявленные слоты ↔ сцена» — «Проверка сцен».
##
## Сама вкладка — координатор: таблица пресетов, тулбар и «Новый пресет» живут
## здесь, остальное — панели в tabs/presets/ (карточки, облако тегов, проверка),
## которые делят общий контекст (tabs/presets/context.gd). Одним файлом вкладка
## доросла до 1300 строк, где пять панелей ходили в одни и те же поля напрямую;
## теперь правка идёт через контекст и историю редактора, а панели узнают о ней
## сигналом — тем же путём после правки и после Ctrl+Z.
##
## ПОЧЕМУ «Редактор пресетов», а не прежний «Генератор»: генератор здесь не
## запускается. «Прогнать сиды» живёт в «Генераторе мира» — вопрос «что реально
## выпадает» про мир, а не про отдельный пресет.
##
## ПОЧЕМУ проверка — свёрнутая панель по кнопке-тумблеру: отчёт нужен раз в
## несколько правок, а постоянно висящий пустой отчёт отъедал бы у таблиц высоту.
## Состояние тумблера и соотношения сплиттеров переживают перезапуск редактора
## (GDT_EditorState) — подвинутое рукой под свой монитор иначе съезжало бы.
##
## ПОЧЕМУ master-detail: описание тега длиннее ключа, и в облаке чипов его можно
## показать разве что тултипом. Правая панель показывает то, что выделено
## ПОСЛЕДНИМ — пресет или тег; выделения в двух таблицах независимы.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Fs := preload("res://addons/game_design_tool/shared/fs.gd")
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const EditorState := preload("res://addons/game_design_tool/shared/editor_state.gd")
const Context := preload("res://addons/game_design_tool/tabs/presets/context.gd")
const PresetCard := preload("res://addons/game_design_tool/tabs/presets/preset_card.gd")
const TagCard := preload("res://addons/game_design_tool/tabs/presets/tag_card.gd")
const TagList := preload("res://addons/game_design_tool/tabs/presets/tag_list.gd")
const SceneCheck := preload("res://addons/game_design_tool/tabs/presets/scene_check.gd")

## Заголовок вкладки в TabContainer — тот берёт его из имени узла (см. _init).
const TAB_TITLE := "Редактор пресетов"

## Раздел проектных метаданных вкладки (см. GDT_EditorState). Свой, а не общий с
## «Генератором мира»: общее имя означало бы, что переименование ключа в одной
## вкладке молча ломает другую.
const SETTINGS_SECTION := "presets_tool"

## Только для «Новый пресет» — заготовки БЕЗ сцены. Готовые пресеты лежат РЯДОМ
## со своей сценой, тем же именем — соглашение, на которое опирается Room Wizard.
const PRESET_DIR := "res://data/room"

const COL_NAME := 0
const COL_SLOTS := 1
const COL_ACTUAL := 2
const COL_WEIGHT := 3
const COL_TYPE := 4
const COL_TAGS := 5

const COLOR_MISMATCH := Color(1, 0.45, 0.4)

## Общее состояние панелей и единственный путь правки.
var ctx := Context.new()

var _tree: Tree
var _tag_list: TagList
var _preset_card: PresetCard
var _tag_card: TagCard
var _scene_check: SceneCheck
var _card_placeholder: Label
var _check_toggle: Button
var _status: Label
var _filter_edit: LineEdit
var _filter_chip: Button
var _new_preset_dialog: ConfirmationDialog
var _new_preset_edit: LineEdit

## Фильтр таблицы по тегу — ставится из карточки тега, снимается чипом в тулбаре.
## Отдельно от текстового: «покажи всё с vertical_hub» и «найди строку lab» —
## разные вопросы.
var _filter_tag := &""
## Библиотека хоть раз загружалась — ленивая первая загрузка (см. _ready).
var _loaded := false


func _init() -> void:
	name = TAB_TITLE  # TabContainer берёт заголовок вкладки из имени узла
	ctx.status.connect(_set_status)
	ctx.preset_changed.connect(_on_preset_changed)
	_build_ui()


## Таблицу наполняем, когда вкладку впервые открыли, а не на старте редактора:
## загрузка считает двери сцен всех комнат, и делать это ради вкладки, которую
## могут не открыть ни разу за сессию, незачем.
func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if _loaded or not is_visible_in_tree():
		return
	_loaded = true
	# button_pressed сам зовёт _on_check_toggled — панель встаёт вместе с кнопкой.
	_check_toggle.button_pressed = EditorState.read(SETTINGS_SECTION, "check_panel", false)
	refresh()


#region Вёрстка
func _build_ui() -> void:
	add_child(_build_toolbar())

	# Вертикальный сплит: таблицы сверху, отчёт проверки снизу. Скрытый второй
	# ребёнок SplitContainer отдаёт всю высоту первому.
	var rows := VSplitContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorState.bind_split(rows, SETTINGS_SECTION, "check_panel_split", 0)
	add_child(rows)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorState.bind_split(split, SETTINGS_SECTION, "lists_detail_split", 520)
	split.add_child(_build_lists())
	split.add_child(_build_detail())
	rows.add_child(split)
	_scene_check = SceneCheck.new(ctx)
	rows.add_child(_scene_check)

	_status = Ui.status_label()
	add_child(_status)

	_new_preset_dialog = Ui.text_dialog("Новый пресет — имя", _on_new_preset_confirmed)
	_new_preset_edit = Ui.dialog_edit(_new_preset_dialog)
	add_child(_new_preset_dialog)


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_child(Ui.button("Обновить", _on_refresh_pressed))
	bar.add_child(Ui.button("Новый пресет", _on_new_preset_pressed))
	bar.add_child(Ui.button("Открыть сцену", _on_open_scene_pressed))
	bar.add_child(Ui.button("Открыть в инспекторе", _on_edit_in_inspector_pressed))

	bar.add_child(VSeparator.new())
	_check_toggle = Button.new()
	_check_toggle.text = "Проверка сцен"
	_check_toggle.toggle_mode = true
	_check_toggle.tooltip_text = (
		"Сверка «заявленные слоты ↔ двери сцены» и разбор дверей: какая на какой стене"
	)
	_check_toggle.toggled.connect(_on_check_toggled)
	bar.add_child(_check_toggle)

	bar.add_child(Ui.spacer())

	_filter_chip = Ui.button("", _clear_tag_filter)
	_filter_chip.visible = false
	_filter_chip.tooltip_text = "Снять фильтр по тегу"
	bar.add_child(_filter_chip)

	_filter_edit = LineEdit.new()
	_filter_edit.placeholder_text = "фильтр: имя, тег, тип"
	_filter_edit.custom_minimum_size = Vector2(180, 0)
	_filter_edit.clear_button_enabled = true
	_filter_edit.text_changed.connect(func(_t: String) -> void: _apply_filter())
	bar.add_child(_filter_edit)
	return bar


func _on_check_toggled(pressed: bool) -> void:
	_scene_check.visible = pressed
	EditorState.write(SETTINGS_SECTION, "check_panel", pressed)


## Левая колонка: таблица пресетов и облако тегов. Разделитель между ними
## двигается — у одной библиотеки длиннее список комнат, у другой словарь.
func _build_lists() -> Control:
	var column := VSplitContainer.new()
	column.custom_minimum_size = Vector2(360, 0)
	EditorState.bind_split(column, SETTINGS_SECTION, "presets_tags_split", 240)

	var presets_box := VBoxContainer.new()
	presets_box.add_child(Ui.section_label("Пресеты комнат"))
	_tree = Tree.new()
	_tree.columns = 6
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.custom_minimum_size = Vector2(0, 96)
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.set_column_title(COL_NAME, "Пресет")
	_tree.set_column_title(COL_SLOTS, "Слоты")
	_tree.set_column_title(COL_ACTUAL, "В сцене")
	_tree.set_column_title(COL_WEIGHT, "Вес")
	_tree.set_column_title(COL_TYPE, "Тип")
	_tree.set_column_title(COL_TAGS, "Теги")
	_tree.set_column_expand(COL_SLOTS, false)
	_tree.set_column_expand(COL_ACTUAL, false)
	_tree.set_column_expand(COL_WEIGHT, false)
	_tree.set_column_custom_minimum_width(COL_SLOTS, 56)
	_tree.set_column_custom_minimum_width(COL_ACTUAL, 64)
	_tree.set_column_custom_minimum_width(COL_WEIGHT, 56)
	_tree.set_column_custom_minimum_width(COL_TYPE, 120)
	_tree.item_edited.connect(_on_item_edited)
	_tree.item_selected.connect(_on_tree_selection_changed)
	presets_box.add_child(_tree)
	column.add_child(presets_box)

	_tag_list = TagList.new(ctx)
	_tag_list.tag_selected.connect(_on_tag_selected)
	_tag_list.new_tag_requested.connect(_on_new_tag_requested)
	column.add_child(_tag_list)
	return column


## Правая панель. В ScrollContainer: высота карточки сверху не ограничена — тегов
## в словаре может стать втрое больше.
func _build_detail() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_card_placeholder = Ui.wrap_label("Выдели пресет или тег слева — здесь будет карточка.")
	box.add_child(_card_placeholder)
	_preset_card = PresetCard.new(ctx)
	box.add_child(_preset_card)
	_tag_card = TagCard.new(ctx)
	_tag_card.filter_requested.connect(_on_filter_by_tag)
	_tag_card.tag_renamed.connect(_on_tag_renamed)
	_tag_card.forgotten.connect(_show_nothing)
	box.add_child(_tag_card)
	return scroll


func _set_status(text: String) -> void:
	Ui.set_status(_status, text)
#endregion


#region Таблица пресетов
func _on_refresh_pressed() -> void:
	refresh()
	_set_status("Обновлено.")


func refresh() -> void:
	_tag_card.flush_edits()
	_tree.clear()
	if not ctx.reload():
		_set_status("⚠ Не удалось загрузить " + ctx.library_path)
		_show_nothing()
		return

	var root := _tree.create_item()
	for preset: RS_RoomPreset in ctx.library.presets:
		if preset != null:
			_add_row(root, preset, false)
	if ctx.library.fallback:
		_add_row(root, ctx.library.fallback, true)

	_apply_filter()
	_show_nothing()  # таблица только что очищена — выделения нет

	var catalog_note := (
		"" if ctx.tag_catalog else " ⚠ облако тегов не назначено библиотеке. Описаний не будет."
	)
	_set_status(
		"%d пресетов + fallback. Теги и описания — в карточке справа.%s"
		% [ctx.library.presets.size(), catalog_note]
	)


func _add_row(root: TreeItem, preset: RS_RoomPreset, is_fallback: bool) -> void:
	var item := _tree.create_item(root)
	item.set_text(COL_NAME, Library.label_of(preset) + (" (fallback)" if is_fallback else ""))
	item.set_tooltip_text(COL_NAME, preset.resource_path)
	item.set_metadata(COL_NAME, preset.resource_path)

	Library.configure_range_cell(item, COL_SLOTS, Library.SLOT_RANGE)
	item.set_editable(COL_SLOTS, true)
	var actual: int = ctx.actual_doors.get(preset.resource_path, -1)
	item.set_text(COL_ACTUAL, "нет сцены" if actual < 0 else str(actual))
	Library.configure_range_cell(item, COL_WEIGHT, Library.WEIGHT_RANGE)
	item.set_editable(COL_WEIGHT, true)

	# Выпадающий список, а не свободный текст: тип у комнаты РОВНО ОДИН, и
	# множество вариантов задано каталогом — печатать тут нечего.
	item.set_cell_mode(COL_TYPE, TreeItem.CELL_MODE_RANGE)
	item.set_text(COL_TYPE, ",".join(Library.type_labels(ctx.library, ctx.type_ids, true)))
	item.set_editable(COL_TYPE, true)
	item.set_tooltip_text(
		COL_TYPE,
		"Что это за помещение. ОТДЕЛЬНАЯ ось от тегов: тегами узел фильтруется"
		+ " жёстко, типом — только предпочитается.",
	)
	# Read-only здесь: правка — в карточке справа (см. шапку про опечатки).
	item.set_tooltip_text(COL_TAGS, "Правятся в карточке справа — выдели строку.")
	_fill_row(item, preset)


## Значения строки из пресета — и при постройке, и после правки или отката.
func _fill_row(item: TreeItem, preset: RS_RoomPreset) -> void:
	item.set_range(COL_SLOTS, preset.slot_count)
	item.set_range(COL_WEIGHT, preset.weight)
	item.set_range(COL_TYPE, ctx.type_index(preset.room_type))
	item.set_text(COL_TAGS, ", ".join(preset.tags))
	# «В сцене» красным, если заявленные слоты разошлись с дверьми сцены:
	# генератор верит slot_count, а рёбра раздаются по реальным дверям.
	var actual: int = ctx.actual_doors.get(preset.resource_path, -1)
	if actual < 0 or actual == preset.slot_count:
		item.clear_custom_color(COL_ACTUAL)
	else:
		item.set_custom_color(COL_ACTUAL, COLOR_MISMATCH)


func _on_preset_changed(preset: RS_RoomPreset) -> void:
	var item := _row_for(preset.resource_path)
	if item:
		_fill_row(item, preset)
	if _filter_tag != &"" or _filter_edit.text != "":
		_apply_filter()


func _on_item_edited() -> void:
	var item := _tree.get_edited()
	if item == null:
		return
	var preset := ResourceLoader.load(item.get_metadata(COL_NAME)) as RS_RoomPreset
	if preset == null:
		_set_status("⚠ Не найден пресет: " + str(item.get_metadata(COL_NAME)))
		return
	match _tree.get_edited_column():
		COL_SLOTS:
			ctx.edit_preset(
				"Слоты пресета", preset,
				{"slot_count": [preset.slot_count, int(item.get_range(COL_SLOTS))]}
			)
		COL_WEIGHT:
			ctx.edit_preset(
				"Вес пресета", preset, {"weight": [preset.weight, item.get_range(COL_WEIGHT)]}
			)
		COL_TYPE:
			ctx.edit_preset(
				"Тип пресета", preset,
				{"room_type": [preset.room_type, ctx.type_at(int(item.get_range(COL_TYPE)))]}
			)


func _selected_preset() -> RS_RoomPreset:
	var item := _tree.get_selected()
	if item == null:
		return null
	return ResourceLoader.load(item.get_metadata(COL_NAME)) as RS_RoomPreset


func _row_for(path: String) -> TreeItem:
	var root := _tree.get_root()
	var item := root.get_first_child() if root else null
	while item != null:
		if String(item.get_metadata(COL_NAME)) == path:
			return item
		item = item.get_next()
	return null


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


## Скрывает строки, не подходящие под фильтры. Строки не пересобираем — только
## прячем: на каждую букву в поле поиска этого хватает.
func _apply_filter() -> void:
	var needle := _filter_edit.text.strip_edges().to_lower()
	var root := _tree.get_root()
	if root == null:
		return
	var shown := 0
	var total := 0
	var item := root.get_first_child()
	while item != null:
		total += 1
		var preset := ResourceLoader.load(item.get_metadata(COL_NAME)) as RS_RoomPreset
		var matches := preset != null
		if matches and _filter_tag != &"":
			matches = preset.tags.has(_filter_tag)
		if matches and needle != "":
			matches = _haystack(preset).contains(needle)
		item.visible = matches
		shown += 1 if matches else 0
		item = item.get_next()

	_filter_chip.visible = _filter_tag != &""
	_filter_chip.text = "тег: %s  ✕" % _filter_tag
	# Отчитываемся и когда фильтр снят: иначе «Показано 3 из 12» висело бы над
	# полной таблицей и врало ровно после того, как фильтр убрали.
	if shown < total:
		_set_status("Показано %d из %d пресетов." % [shown, total])
	else:
		_set_status("Показаны все %d пресетов." % total)


func _haystack(preset: RS_RoomPreset) -> String:
	var catalog := ctx.library.type_catalog if ctx.library else null
	var type_label := catalog.label_of(preset.room_type) if catalog else String(preset.room_type)
	return (
		"%s %s %s %s"
		% [Library.label_of(preset), preset.resource_path.get_file(), " ".join(preset.tags), type_label]
	).to_lower()


func _on_filter_by_tag(tag: StringName) -> void:
	if tag == &"":
		return
	_filter_tag = tag
	_filter_edit.text = ""
	_apply_filter()


func _clear_tag_filter() -> void:
	_filter_tag = &""
	_apply_filter()
#endregion


#region Что показывает правая панель
func _on_tree_selection_changed() -> void:
	_show_preset(_selected_preset())


func _on_tag_selected(tag: StringName) -> void:
	_tag_card.flush_edits()
	if tag == &"":
		_show_nothing()
		return
	_preset_card.show_preset(null)
	_card_placeholder.visible = false
	_tag_card.show_tag(tag)


func _on_tag_renamed(new_tag: StringName) -> void:
	_tag_list.select_quietly(new_tag)
	_tag_card.show_tag(new_tag)


func _show_preset(preset: RS_RoomPreset) -> void:
	_tag_card.flush_edits()
	if preset == null:
		_show_nothing()
		return
	_tag_card.show_tag(&"")
	_card_placeholder.visible = false
	_preset_card.show_preset(preset)


func _show_nothing() -> void:
	_preset_card.show_preset(null)
	_tag_card.show_tag(&"")
	_card_placeholder.visible = true


## Новый тег заводится СРАЗУ в словаре, а не когда для него написали описание:
## иначе он был бы неотличим от опечатки — ради этого различия словарь и
## появился. Заведение в словаре — не шаг истории (Ctrl+Z снимет тег с пресета,
## но запись словаря останется): описанный заранее тег без носителей — не ошибка.
## Выделенному пресету тег тут же и вешается: заводят его обычно для комнаты.
func _on_new_tag_requested(text: String) -> void:
	var tag := Tags.tagify(text)
	if tag == &"":
		return
	Tags.register(ctx.tag_catalog, tag)
	var preset := _preset_card.preset
	if preset == null or preset.tags.has(tag):
		ctx.notify_vocabulary()
		_set_status("Тег «%s» заведён в словаре — опиши его справа." % tag)
		return
	var after: Array[StringName] = preset.tags.duplicate()
	after.append(tag)
	if ctx.edit_preset("Повесить тег", preset, {"tags": [preset.tags.duplicate(), after]}):
		_set_status("Тег «%s» заведён и повешен на «%s»." % [tag, Library.label_of(preset)])
#endregion


#region Новый пресет
func _on_new_preset_pressed() -> void:
	if ctx.library == null:
		_set_status("⚠ Библиотека не загружена.")
		return
	Ui.popup_text_dialog(_new_preset_dialog, "Новый пресет — имя", "Новый пресет")


## Пустой RS_RoomPreset в библиотеке — минимум, снимающий ручной поход в
## FileSystem; сцену и остальные поля — «Открыть в инспекторе». В историю
## редактора не идёт: это создание файла, а не правка, и «отменить» его значило
## бы удалять файл с диска — такое инструмент молча делать не должен.
func _on_new_preset_confirmed() -> void:
	var entered := _new_preset_edit.text.strip_edges()
	if entered == "":
		_set_status("⚠ Пустое имя.")
		return

	var preset := RS_RoomPreset.new()
	preset.display_name = entered
	var path := Fs.unique_path(PRESET_DIR, Fs.slug(entered, "room_preset"))
	var err := Fs.save_new(preset, path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return

	ctx.library.presets.append(preset)
	var lib_err := ResourceSaver.save(ctx.library, ctx.library_path)
	if lib_err != OK:
		_set_status("⚠ Пресет создан, но библиотека не сохранилась (код %d)" % lib_err)
		return

	Fs.rescan()
	refresh()
	var item := _row_for(path)
	if item:
		item.select(COL_NAME)
		_on_tree_selection_changed()
	_set_status("Создан: " + path.get_file() + " — назначь сцену через «Открыть в инспекторе».")
#endregion
