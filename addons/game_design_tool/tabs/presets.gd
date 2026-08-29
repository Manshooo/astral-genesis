## res://addons/game_design_tool/tabs/presets.gd
## Вкладка «Генератор» единого редактора геймдизайна: таблица пресетов и словарь
## тегов слева, карточка выделенного — справа.
##
## Что она закрывает:
##   1. веса/slot_count/тип пресетов разбросаны по .tres рядом со своими сценами
##      (src/levels/procedural/rooms/) — здесь они в одной таблице и правятся
##      на месте;
##   2. теги правились строкой через запятую в ячейке таблицы — опечатка тихо
##      создавала новый тег вместо использования существующего. Тег теперь
##      только выбирается чекбоксом: печатать нечего, опечатка невозможна;
##   3. ЧТО тег значит, прочитать было негде вовсе — список тегов нигде не
##      хранился, все три инструмента собирали его обходом preset.tags. Отсюда
##      словарь (RS_RoomTagCatalog, data/room_tag_catalog.tres): у тега
##      появились имя и описание, а у инструмента — способ отличить настоящий
##      тег от опечатки (нет в словаре → «нет описания», и видно, что он
##      одинокий);
##   4. нет обратной связи «что реально выберется» и рассинхрон «заявленные
##      слоты ↔ сцена» — «Прогнать сиды» и «Проверить сцены», без изменений.
##
## ПОЧЕМУ master-detail, а не облако чекбоксов под таблицей, как было раньше:
## описание тега длиннее его ключа, и в HFlowContainer его можно показать разве
## что тултипом — то есть тому, кто УЖЕ знает, какой тег ищет. В карточке
## описание стоит прямо под чекбоксом и читается до клика, ради чего всё и
## затевалось.
##
## ПОЧЕМУ словарь — вторая таблица здесь же, а не отдельная вкладка: цикл работы
## («выделил пресет → навесил тег») ходит между ними постоянно, и уводить
## описания за переключатель вкладок значило бы вернуть ту же проблему другим
## способом. Правая панель показывает то, что выделено ПОСЛЕДНИМ — пресет или
## тег; выделения в двух таблицах независимы, поэтому возврат к пресету стоит
## одного клика.
##
## Проверка стороны двери идёт через RS_RoomLayout — тем же правилом, которым
## RS_LayerPlan раскладывает слой, иначе инструмент проверял бы не то, что делает
## игра.
@tool
extends VBoxContainer

## Заголовок вкладки в TabContainer — тот берёт его из имени узла (см. _init).
const TAB_TITLE := "Генератор"

const LIBRARY_PATH := "res://data/room_preset_library.tres"
## Запасной путь словаря: обычно он приходит из библиотеки (tag_catalog), но с
## библиотекой без словаря инструмент должен продолжать работать, а не молчать.
const TAG_CATALOG_PATH := "res://data/room_tag_catalog.tres"
## Только для «Новый пресет» — заготовки БЕЗ сцены, планируешь пресет раньше,
## чем нарисована комната. Готовые пресеты (у которых уже есть scene) лежат
## РЯДОМ со своей сценой в src/levels/procedural/rooms/, тем же именем — это
## соглашение, на которое опирается Room Wizard (см. [[Единый редактор
## геймдизайна]]); data/room/ ему не нужен, он ищет .tres по пути сцены.
const PRESET_DIR := "res://data/room"

const COL_NAME := 0
const COL_SLOTS := 1
const COL_ACTUAL := 2
const COL_WEIGHT := 3
const COL_TYPE := 4
const COL_TAGS := 5

const TAG_COL_NAME := 0
const TAG_COL_USES := 1

## Ширина, от которой переносящиеся подписи считают свою минимальную высоту.
## Без неё Label с autowrap меряет себя по минимальной ШИРИНЕ (до первой
## раскладки это ~17 px) и запрашивает сотни пикселей высоты — та же грабля,
## что когда-то разложила правую панель (см. [[Редакторские инструменты]]).
const WRAP_WIDTH := 240

var _library: RS_RoomPresetLibrary
## Словарь тегов. null — библиотека без словаря: описаний нет, всё остальное
## работает ровно как до его появления.
var _tag_catalog: RS_RoomTagCatalog

var _tree: Tree
var _tag_tree: Tree
var _report: RichTextLabel
var _seeds_spin: SpinBox
var _status: Label
var _filter_edit: LineEdit
var _filter_chip: Button
var _new_tag_edit: LineEdit

## Путь .tres пресета -> сколько дверей реально в его сцене (считаем при обновлении).
var _actual_doors: Dictionary = {}
## Тег -> сколько пресетов его носят. Считается там же, где _known_tags.
var _tag_uses: Dictionary = {}
## Все теги проекта: ключи словаря ПЛЮС теги, встречающиеся у пресетов. Второе
## слагаемое обязательно — тег, которому не написали описания, всё равно
## работает, и спрятать его значило бы врать про содержимое библиотеки.
var _known_tags: Array[StringName] = []
## Варианты «Типа» по индексам: [&""] + ключи каталога + типы, которые у
## пресетов стоят, но из каталога пропали. Последнее — не педантизм: молча
## подставить такому пресету «—» значило бы стереть авторскую правку.
var _type_ids: Array[StringName] = []
## Фильтр таблицы по тегу — ставится кнопкой из карточки тега, снимается чипом
## в тулбаре. Отдельно от текстового фильтра: «покажи всё с floor_hub» и «найди
## строку lab» — разные вопросы, и совмещать их в одном поле неудобно.
var _filter_tag: StringName = &""

#region Карточка
var _card_placeholder: Label
var _preset_card: VBoxContainer
var _p_title: Label
var _p_scene: Label
var _p_slots: SpinBox
var _p_actual: Label
var _p_weight: SpinBox
var _p_type: OptionButton
var _p_type_desc: Label
var _p_tag_list: VBoxContainer

var _tag_card: VBoxContainer
var _t_title: Label
var _t_uses: Label
var _t_name_edit: LineEdit
var _t_desc_edit: TextEdit
var _t_generator_note: Label
var _t_rename_btn: Button
var _t_used_by: Label

## Пресет и тег, которые сейчас показывает карточка. Держим отдельно от
## get_selected(), чтобы обработчики полей не искали их заново на каждый тик
## спинбокса.
var _editing_preset: RS_RoomPreset
var _editing_tag: StringName = &""

## Заполнение карточки двигает SpinBox/OptionButton — и те шлют свои сигналы
## так же, как от руки пользователя. Без этого флага открытие пресета тут же
## «сохраняло» его собственные значения обратно, а при переключении строки —
## значения предыдущего пресета в новый.
var _syncing := false
#endregion

var _new_preset_dialog: ConfirmationDialog
var _new_preset_edit: LineEdit
var _rename_tag_dialog: ConfirmationDialog
var _rename_tag_edit: LineEdit


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


#region Вёрстка
func _build_ui() -> void:
	add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.size_flags_stretch_ratio = 3.0  # таблицам места больше, чем отчёту внизу
	split.split_offset = 520
	split.add_child(_build_lists())
	split.add_child(_build_detail())
	add_child(split)

	add_child(HSeparator.new())

	var seeds_row := HBoxContainer.new()
	var seeds_label := Label.new()
	seeds_label.text = "Сидов:"
	seeds_row.add_child(seeds_label)
	_seeds_spin = SpinBox.new()
	_seeds_spin.min_value = 1
	_seeds_spin.max_value = 200
	_seeds_spin.value = 30
	seeds_row.add_child(_seeds_spin)
	var run := _button("Прогнать сиды", _on_preview_pressed)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seeds_row.add_child(run)
	add_child(seeds_row)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.selection_enabled = true
	_report.custom_minimum_size = Vector2(0, 96)
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_report)

	# Статус — строго ОДНА строка с многоточием, а не autowrap. Label с autowrap
	# считает минимальную высоту, перенося текст по минимальной ШИРИНЕ (до первой
	# раскладки это ~17 px), и требует под себя сотни пикселей. В доке это
	# разъезжало всю правую панель (см. [[Редакторские инструменты]]); на главном
	# экране так не ломается, но однострочный статус всё равно правильнее — иначе
	# длинный путь ресурса перекладывает вёрстку под собой. Полный текст — в подсказке.
	_status = _ellipsis_label()
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

	_rename_tag_dialog = ConfirmationDialog.new()
	_rename_tag_dialog.title = "Переименовать тег во всех пресетах"
	_rename_tag_edit = LineEdit.new()
	_rename_tag_edit.custom_minimum_size = Vector2(280, 0)
	_rename_tag_dialog.add_child(_rename_tag_edit)
	_rename_tag_dialog.register_text_enter(_rename_tag_edit)
	_rename_tag_dialog.confirmed.connect(_on_rename_tag_confirmed)
	add_child(_rename_tag_dialog)


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_child(_button("Обновить", _refresh_pressed))
	bar.add_child(_button("Новый пресет", _on_new_preset_pressed))
	bar.add_child(_button("Открыть сцену", _on_open_scene_pressed))
	bar.add_child(_button("Открыть в инспекторе", _on_edit_in_inspector_pressed))
	bar.add_child(_button("Проверить сцены", _on_validate_pressed))

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_filter_chip = _button("", _clear_tag_filter)
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


## Левая колонка: таблица пресетов и словарь тегов. Разделитель между ними
## двигается — у одной библиотеки длиннее список комнат, у другой словарь.
func _build_lists() -> Control:
	var column := VSplitContainer.new()
	column.custom_minimum_size = Vector2(360, 0)
	column.split_offset = 240

	var presets_box := VBoxContainer.new()
	presets_box.add_child(_section_label("Пресеты комнат"))
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

	var tags_box := VBoxContainer.new()
	tags_box.add_child(_section_label("Словарь тегов"))
	_tag_tree = Tree.new()
	_tag_tree.columns = 2
	_tag_tree.column_titles_visible = true
	_tag_tree.hide_root = true
	_tag_tree.custom_minimum_size = Vector2(0, 72)
	_tag_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tag_tree.set_column_title(TAG_COL_NAME, "Тег")
	_tag_tree.set_column_title(TAG_COL_USES, "Пресетов")
	_tag_tree.set_column_expand(TAG_COL_USES, false)
	_tag_tree.set_column_custom_minimum_width(TAG_COL_USES, 72)
	_tag_tree.item_selected.connect(_on_tag_tree_selection_changed)
	tags_box.add_child(_tag_tree)

	var new_tag_row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег — Enter заводит и вешает на выделенный пресет"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _on_add_tag_pressed())
	new_tag_row.add_child(_new_tag_edit)
	new_tag_row.add_child(_button("+ тег", _on_add_tag_pressed))
	tags_box.add_child(new_tag_row)
	column.add_child(tags_box)
	return column


## Правая панель. В ScrollContainer, потому что высота карточки не ограничена
## сверху: тегов в словаре может стать втрое больше, а каждый занимает две
## строки (чекбокс и описание под ним).
func _build_detail() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(260, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_card_placeholder = _wrap_label("Выдели пресет или тег слева — здесь будет карточка.")
	box.add_child(_card_placeholder)
	_preset_card = _build_preset_card()
	box.add_child(_preset_card)
	_tag_card = _build_tag_card()
	box.add_child(_tag_card)
	return scroll


func _build_preset_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.visible = false
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_p_title = _section_label("")
	card.add_child(_p_title)
	_p_scene = _ellipsis_label()
	_p_scene.modulate = Color(1, 1, 1, 0.7)
	card.add_child(_p_scene)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	grid.add_child(_field_label("Слоты"))
	var slots_row := HBoxContainer.new()
	_p_slots = SpinBox.new()
	_p_slots.min_value = 0
	_p_slots.max_value = 12
	_p_slots.step = 1
	_p_slots.value_changed.connect(_on_card_slots_changed)
	slots_row.add_child(_p_slots)
	_p_actual = Label.new()
	slots_row.add_child(_p_actual)
	grid.add_child(slots_row)

	grid.add_child(_field_label("Вес"))
	_p_weight = SpinBox.new()
	_p_weight.min_value = 0.0
	_p_weight.max_value = 10.0
	_p_weight.step = 0.1
	_p_weight.value_changed.connect(_on_card_weight_changed)
	grid.add_child(_p_weight)

	grid.add_child(_field_label("Тип"))
	_p_type = OptionButton.new()
	_p_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_type.item_selected.connect(_on_card_type_selected)
	grid.add_child(_p_type)
	card.add_child(grid)

	_p_type_desc = _wrap_label("")
	_p_type_desc.modulate = Color(1, 1, 1, 0.7)
	card.add_child(_p_type_desc)

	card.add_child(HSeparator.new())
	var tags_head := _wrap_label(
		"Теги — ЖЁСТКИЙ фильтр: узел получит эту комнату, только если все теги"
		+ " узла есть здесь. Лишние теги не запрещены, но по специфичности уводят"
		+ " пресет от простых узлов."
	)
	card.add_child(tags_head)
	_p_tag_list = VBoxContainer.new()
	_p_tag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_p_tag_list)
	return card


func _build_tag_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.visible = false
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_t_title = _section_label("")
	card.add_child(_t_title)
	_t_uses = Label.new()
	_t_uses.modulate = Color(1, 1, 1, 0.7)
	card.add_child(_t_uses)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_field_label("Имя"))
	_t_name_edit = LineEdit.new()
	_t_name_edit.placeholder_text = "как показывать дизайнеру"
	_t_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_t_name_edit.focus_exited.connect(_flush_tag_edits)
	_t_name_edit.text_submitted.connect(func(_t: String) -> void: _flush_tag_edits())
	grid.add_child(_t_name_edit)
	card.add_child(grid)

	card.add_child(_field_label("Что тег значит"))
	_t_desc_edit = TextEdit.new()
	_t_desc_edit.custom_minimum_size = Vector2(0, 110)
	_t_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Сохраняем по уходу фокуса, а не на каждый символ: описание живёт в .tres,
	# и ResourceSaver на каждую букву переписывал бы файл словаря целиком.
	_t_desc_edit.focus_exited.connect(_flush_tag_edits)
	card.add_child(_t_desc_edit)

	_t_generator_note = _wrap_label(
		"Этот тег генератор ставит узлам сам, и его ключ захардкожен в"
		+ " RS_LevelGraph — переименование здесь сломало бы подбор молча."
	)
	_t_generator_note.modulate = Color(1, 0.8, 0.45)
	card.add_child(_t_generator_note)

	var buttons := HBoxContainer.new()
	buttons.add_child(_button("Показать пресеты с тегом", _on_filter_by_tag_pressed))
	_t_rename_btn = _button("Переименовать…", _on_rename_tag_pressed)
	buttons.add_child(_t_rename_btn)
	buttons.add_child(_button("Убрать из словаря", _on_forget_tag_pressed))
	card.add_child(buttons)

	_t_used_by = _wrap_label("")
	_t_used_by.modulate = Color(1, 1, 1, 0.7)
	card.add_child(_t_used_by)
	return card


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


## Заголовок раздела. MOUSE_FILTER_STOP не косметика: Label по умолчанию
## пропускает мышь насквозь и тултип с полным текстом (путь ресурса, описание
## тега) не показывает вовсе — а обрезанной многоточием строке он и нужен.
func _section_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


func _field_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


## Однострочная подпись с многоточием — см. про autowrap в _build_ui и про
## mouse_filter в _section_label.
func _ellipsis_label() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l


## Переносящаяся подпись. custom_minimum_size.x обязателен: без него autowrap
## считает высоту по минимальной ширине и раздувает панель (см. _build_ui).
func _wrap_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(WRAP_WIDTH, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Строка статуса обрезается многоточием, поэтому целиком текст кладём в подсказку.
func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text
#endregion


#region Таблица пресетов
func _refresh_pressed() -> void:
	_refresh()
	_set_status("Обновлено.")


func _refresh() -> void:
	_flush_tag_edits()
	_library = ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary
	_tree.clear()
	_actual_doors.clear()
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + LIBRARY_PATH)
		_known_tags.clear()
		_tag_uses.clear()
		_rebuild_tag_tree()
		_show_nothing()
		return

	_tag_catalog = _library.tag_catalog
	if _tag_catalog == null:
		_tag_catalog = ResourceLoader.load(TAG_CATALOG_PATH) as RS_RoomTagCatalog

	_collect_type_ids()

	var root := _tree.create_item()
	for preset: RS_RoomPreset in _library.presets:
		if preset == null:
			continue
		_add_row(root, preset, false)
	if _library.fallback:
		_add_row(root, _library.fallback, true)

	_collect_known_tags()
	_rebuild_tag_tree()
	_apply_filter()
	_show_nothing()  # таблица только что очищена — выделения нет

	var catalog_note := (
		"" if _tag_catalog else " ⚠ словарь тегов не назначен библиотеке — описаний не будет."
	)
	_set_status(
		"%d пресетов + fallback. Теги и описания — в карточке справа.%s"
		% [_library.presets.size(), catalog_note]
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

	# Выпадающий список, а не свободный текст и не облако: тип у комнаты РОВНО
	# ОДИН (это ответ на вопрос «что это за помещение», а не набор способностей),
	# и множество вариантов задано каталогом — печатать тут нечего.
	item.set_cell_mode(COL_TYPE, TreeItem.CELL_MODE_RANGE)
	item.set_text(COL_TYPE, ",".join(_type_option_labels()))
	item.set_range(COL_TYPE, _type_index(preset.room_type))
	item.set_editable(COL_TYPE, true)
	item.set_tooltip_text(
		COL_TYPE,
		"Что это за помещение. ОТДЕЛЬНАЯ ось от тегов: тегами узел фильтруется"
		+ " жёстко, типом — только предпочитается.",
	)

	# Read-only здесь: правка — чекбоксами в карточке справа. Свободный текст
	# через запятую опечаткой тихо плодил новый тег вместо использования
	# существующего — ровно то, ради ухода от чего всё и переверстали.
	item.set_text(COL_TAGS, ", ".join(preset.tags))
	item.set_tooltip_text(COL_TAGS, "Правятся в карточке справа — выдели строку.")


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
		COL_TYPE:
			var index := int(item.get_range(COL_TYPE))
			preset.room_type = (
				_type_ids[index] if index >= 0 and index < _type_ids.size() else &""
			)
		_:
			return

	if not _save_preset(preset):
		return
	# Таблица и карточка правят одни и те же поля — после правки в ячейке
	# карточку надо перечитать, иначе следующий тик её спинбокса вернёт старое.
	if _editing_preset != null and _editing_preset.resource_path == path:
		_show_preset_card(preset)


func _save_preset(preset: RS_RoomPreset) -> bool:
	var err := ResourceSaver.save(preset, preset.resource_path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return false
	_set_status("Сохранено: " + preset.resource_path.get_file())
	return true


func _selected_preset() -> RS_RoomPreset:
	var item := _tree.get_selected()
	if item == null:
		return null
	return ResourceLoader.load(item.get_metadata(COL_NAME)) as RS_RoomPreset


func _row_for(path: String) -> TreeItem:
	var item := _tree.get_root()
	if item == null:
		return null
	item = item.get_first_child()
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


## Скрывает строки, не подходящие под фильтры. Строки не пересобираем: пересбор
## считает двери, инстанцируя ВСЕ сцены комнат, — на каждую букву в поле поиска
## это была бы заметная пауза.
func _apply_filter() -> void:
	var needle := _filter_edit.text.strip_edges().to_lower()
	var root := _tree.get_root()
	if root == null:
		return
	var item := root.get_first_child()
	var shown := 0
	var total := 0
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
	if shown < total:
		_set_status("Показано %d из %d пресетов." % [shown, total])


func _haystack(preset: RS_RoomPreset) -> String:
	var type_label := (
		_library.type_catalog.label_of(preset.room_type)
		if _library and _library.type_catalog
		else String(preset.room_type)
	)
	return (
		"%s %s %s %s"
		% [
			_label_of(preset),
			preset.resource_path.get_file(),
			" ".join(preset.tags),
			type_label,
		]
	).to_lower()


func _clear_tag_filter() -> void:
	_filter_tag = &""
	_apply_filter()
#endregion


#region Тип помещения
## Варианты списка: «нет типа», затем каталог в порядке объявления, затем типы,
## которые у пресетов стоят, но каталогу неизвестны. Порядок каталога не
## сортируем — он же задаёт порядок розыгрыша, и видеть его как есть полезнее,
## чем по алфавиту.
func _collect_type_ids() -> void:
	_type_ids = [&""]
	var catalog := _library.type_catalog if _library else null
	if catalog:
		_type_ids.append_array(catalog.ids())

	for preset: RS_RoomPreset in _library.presets:
		if preset and preset.room_type != &"" and not _type_ids.has(preset.room_type):
			_type_ids.append(preset.room_type)
	if _library.fallback and _library.fallback.room_type != &"":
		if not _type_ids.has(_library.fallback.room_type):
			_type_ids.append(_library.fallback.room_type)


## Подписи вариантов для ячейки-списка. Запятая — разделитель значений в
## Tree.set_text для CELL_MODE_RANGE, поэтому из подписей её выбрасываем: иначе
## одно имя развалилось бы на два пункта. В OptionButton карточки этого
## ограничения нет, но список берём тот же — разъехавшиеся подписи в двух
## редакторах одного поля путали бы сильнее, чем стоит сохранённая запятая.
func _type_option_labels() -> Array[String]:
	var catalog := _library.type_catalog if _library else null
	var out: Array[String] = []
	for id: StringName in _type_ids:
		var label := catalog.label_of(id) if catalog else ("—" if id == &"" else String(id))
		if not _type_ids.is_empty() and id != &"" and (catalog == null or catalog.by_id(id) == null):
			label += " (нет в каталоге)"
		out.append(label.replace(",", " "))
	return out


func _type_index(id: StringName) -> int:
	var index := _type_ids.find(id)
	return index if index >= 0 else 0
#endregion


#region Карточка пресета
func _on_tree_selection_changed() -> void:
	_show_preset_card(_selected_preset())


func _show_nothing() -> void:
	_editing_preset = null
	_editing_tag = &""
	_preset_card.visible = false
	_tag_card.visible = false
	_card_placeholder.visible = true


func _show_preset_card(preset: RS_RoomPreset) -> void:
	if preset == null:
		_show_nothing()
		return
	_editing_preset = preset
	_card_placeholder.visible = false
	_tag_card.visible = false
	_preset_card.visible = true

	_syncing = true
	_p_title.text = _label_of(preset)
	_p_title.tooltip_text = preset.resource_path
	var scene_path := preset.scene.resource_path if preset.scene else ""
	_p_scene.text = scene_path.get_file() if scene_path != "" else "сцена не назначена"
	_p_scene.tooltip_text = scene_path
	_p_slots.value = preset.slot_count
	_update_actual_label(preset)
	_p_weight.value = preset.weight

	_p_type.clear()
	for label: String in _type_option_labels():
		_p_type.add_item(label)
	_p_type.select(_type_index(preset.room_type))
	_syncing = false

	_update_type_desc(preset.room_type)
	_rebuild_tag_checkboxes(preset)


## «В сцене N» рядом со слотами: тот же рассинхрон, что подсвечен красным в
## таблице, но здесь его видно в момент правки — а правят слоты именно здесь.
func _update_actual_label(preset: RS_RoomPreset) -> void:
	var actual: int = _actual_doors.get(preset.resource_path, -1)
	if actual < 0:
		_p_actual.text = "в сцене: —"
		_p_actual.modulate = Color(1, 1, 1, 0.7)
	elif actual == preset.slot_count:
		_p_actual.text = "в сцене: %d ✓" % actual
		_p_actual.modulate = Color(0.6, 0.85, 0.6)
	else:
		_p_actual.text = "в сцене: %d ⚠" % actual
		_p_actual.modulate = Color(1, 0.45, 0.4)


func _update_type_desc(id: StringName) -> void:
	var catalog := _library.type_catalog if _library else null
	if id == &"":
		_p_type_desc.text = (
			"Без типа — безликое помещение. Тип ПРЕДПОЧИТАЕТСЯ, а не требуется:"
			+ " узел с типом возьмёт комнату без него, если типизированной нет."
		)
		return
	var description := catalog.description_of(id) if catalog else ""
	_p_type_desc.text = description if description != "" else "Описание типа не заполнено."


func _on_card_slots_changed(value: float) -> void:
	if _syncing or _editing_preset == null:
		return
	_editing_preset.slot_count = int(value)
	if not _save_preset(_editing_preset):
		return
	var item := _row_for(_editing_preset.resource_path)
	if item:
		item.set_range(COL_SLOTS, _editing_preset.slot_count)
		var actual: int = _actual_doors.get(_editing_preset.resource_path, -1)
		item.set_custom_color(COL_ACTUAL, Color(1, 0.45, 0.4))
		if actual < 0 or actual == _editing_preset.slot_count:
			item.clear_custom_color(COL_ACTUAL)
	_update_actual_label(_editing_preset)


func _on_card_weight_changed(value: float) -> void:
	if _syncing or _editing_preset == null:
		return
	_editing_preset.weight = value
	if not _save_preset(_editing_preset):
		return
	var item := _row_for(_editing_preset.resource_path)
	if item:
		item.set_range(COL_WEIGHT, value)


func _on_card_type_selected(index: int) -> void:
	if _syncing or _editing_preset == null:
		return
	_editing_preset.room_type = _type_ids[index] if index < _type_ids.size() else &""
	if not _save_preset(_editing_preset):
		return
	var item := _row_for(_editing_preset.resource_path)
	if item:
		item.set_range(COL_TYPE, index)
	_update_type_desc(_editing_preset.room_type)


## Список тегов карточки: чекбокс и описание ПОД ним. Порядок — алфавитный и
## не зависит от того, отмечен тег или нет: сортировка «свои сверху» переставляла
## бы строки прямо под курсором на каждый клик.
func _rebuild_tag_checkboxes(preset: RS_RoomPreset) -> void:
	# free(), не queue_free(): перестройка идёт на каждую смену выделения, и
	# отложенное удаление копило бы старые чекбоксы поверх новых.
	for child: Node in _p_tag_list.get_children():
		child.free()

	for tag: StringName in _known_tags:
		var known := _tag_catalog != null and _tag_catalog.has_id(tag)
		var chip := CheckBox.new()
		chip.text = String(tag) if not known else "%s — %s" % [tag, _tag_catalog.label_of(tag)]
		chip.button_pressed = preset.tags.has(tag)
		chip.toggled.connect(_on_tag_chip_toggled.bind(tag))
		_p_tag_list.add_child(chip)

		var description := _tag_catalog.description_of(tag) if _tag_catalog else ""
		var note := _wrap_label(
			description if description != "" else "Описания нет — выдели тег в словаре слева."
		)
		note.modulate = Color(1, 1, 1, 0.6) if description != "" else Color(1, 0.8, 0.45, 0.8)
		_p_tag_list.add_child(note)


func _on_tag_chip_toggled(pressed: bool, tag: StringName) -> void:
	if _editing_preset == null:
		return
	if pressed:
		if not _editing_preset.tags.has(tag):
			_editing_preset.tags.append(tag)
	elif _editing_preset.tags.has(tag):
		_editing_preset.tags.erase(tag)
	if not _save_preset(_editing_preset):
		return
	var item := _row_for(_editing_preset.resource_path)
	if item:
		item.set_text(COL_TAGS, ", ".join(_editing_preset.tags))
	_collect_known_tags()
	_rebuild_tag_tree()
#endregion


#region Словарь тегов
## Все теги проекта: ключи словаря плюс всё, что реально стоит у пресетов
## (включая fallback). Второе слагаемое и ловит опечатки: тег, которого нет в
## словаре, показывается со значком «одинокий» — раньше он выглядел в облаке
## ровно так же полноценно, как настоящий.
func _collect_known_tags() -> void:
	_tag_uses.clear()
	var presets := _library.presets + ([_library.fallback] if _library.fallback else [])
	for preset: RS_RoomPreset in presets:
		if preset == null:
			continue
		for tag: StringName in preset.tags:
			_tag_uses[tag] = int(_tag_uses.get(tag, 0)) + 1

	var seen := {}
	for tag: StringName in _tag_uses:
		seen[tag] = true
	if _tag_catalog:
		for id: StringName in _tag_catalog.ids():
			seen[id] = true

	var result: Array[StringName] = []
	for tag: StringName in seen.keys():
		result.append(tag)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_known_tags = result


## Сигналы дерева на время пересборки блокируем: восстановление выделения шлёт
## item_selected так же, как клик, и правая панель прыгала бы на карточку тега
## каждый раз, когда тег просто повесили на пресет чекбоксом.
func _rebuild_tag_tree() -> void:
	var previous := _editing_tag
	_tag_tree.set_block_signals(true)
	_tag_tree.clear()
	var root := _tag_tree.create_item()
	for tag: StringName in _known_tags:
		var item := _tag_tree.create_item(root)
		var known := _tag_catalog != null and _tag_catalog.has_id(tag)
		item.set_text(TAG_COL_NAME, String(tag) if known else "⚠ " + String(tag))
		item.set_metadata(TAG_COL_NAME, tag)
		if not known:
			item.set_custom_color(TAG_COL_NAME, Color(1, 0.8, 0.45))
			item.set_tooltip_text(
				TAG_COL_NAME,
				"Тега нет в словаре: описания у него нет, и никто не поручится, что это"
				+ " не опечатка в похожем теге.",
			)
		elif _tag_catalog.by_id(tag).description != "":
			item.set_tooltip_text(TAG_COL_NAME, _tag_catalog.description_of(tag))
		var uses := int(_tag_uses.get(tag, 0))
		item.set_text(TAG_COL_USES, str(uses))
		if uses == 0:
			# Описан, но не носится ни одной комнатой — не ошибка (тег могли
			# завести заранее), но повод не искать его в облаке зря.
			item.set_custom_color(TAG_COL_USES, Color(1, 1, 1, 0.5))
		if tag == previous:
			item.select(TAG_COL_NAME)
	_tag_tree.set_block_signals(false)


func _selected_tag() -> StringName:
	var item := _tag_tree.get_selected()
	if item == null:
		return &""
	return item.get_metadata(TAG_COL_NAME)


func _on_tag_tree_selection_changed() -> void:
	_flush_tag_edits()
	_show_tag_card(_selected_tag())


func _show_tag_card(tag: StringName) -> void:
	if tag == &"":
		_show_nothing()
		return
	_editing_tag = tag
	_card_placeholder.visible = false
	_preset_card.visible = false
	_tag_card.visible = true

	var entry: RS_RoomTag = _tag_catalog.by_id(tag) if _tag_catalog else null
	_t_title.text = String(tag)
	var uses := int(_tag_uses.get(tag, 0))
	_t_uses.text = "Носят пресетов: %d%s" % [uses, "" if entry else "   ⚠ нет в словаре"]
	_t_name_edit.text = entry.display_name if entry else ""
	_t_desc_edit.text = entry.description if entry else ""
	_t_name_edit.editable = _tag_catalog != null
	_t_desc_edit.editable = _tag_catalog != null
	_t_generator_note.visible = entry != null and entry.set_by_generator
	_t_rename_btn.disabled = entry != null and entry.set_by_generator
	_t_rename_btn.tooltip_text = (
		"Ключ захардкожен в RS_LevelGraph — переименовывать можно только вместе с кодом."
		if _t_rename_btn.disabled
		else ""
	)
	_t_used_by.text = "Стоит у: " + _presets_with_tag_text(tag)


func _presets_with_tag_text(tag: StringName) -> String:
	var names: Array[String] = []
	var presets := _library.presets + ([_library.fallback] if _library.fallback else [])
	for preset: RS_RoomPreset in presets:
		if preset and preset.tags.has(tag):
			names.append(_label_of(preset))
	return ", ".join(names) if not names.is_empty() else "— ни у одного пресета"


## Записывает правки имени/описания в словарь. Зовётся по уходу фокуса и перед
## любой сменой выделения: TextEdit не шлёт «готово», и без явного сброса
## описание терялось бы ровно в тот момент, когда пользователь кликает дальше.
func _flush_tag_edits() -> void:
	if _tag_catalog == null or _editing_tag == &"" or not _tag_card.visible:
		return
	var entry := _tag_catalog.by_id(_editing_tag)
	if entry == null:
		return
	if entry.display_name == _t_name_edit.text and entry.description == _t_desc_edit.text:
		return
	entry.display_name = _t_name_edit.text
	entry.description = _t_desc_edit.text
	_save_tag_catalog()


func _save_tag_catalog() -> bool:
	if _tag_catalog == null:
		_set_status("⚠ Словарь тегов не назначен библиотеке — описания сохранять некуда.")
		return false
	var path := _tag_catalog.resource_path
	if path == "":
		path = TAG_CATALOG_PATH
	var err := ResourceSaver.save(_tag_catalog, path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить словарь (код %d)" % err)
		return false
	_set_status("Словарь сохранён: " + path.get_file())
	return true


## Новый тег заводится СРАЗУ в словаре, а не в момент, когда для него написали
## описание: иначе он был бы неотличим от опечатки — а именно ради этого
## различия словарь и появился. Выделенному пресету тег тут же и вешается,
## потому что заводят его обычно для конкретной комнаты.
func _on_add_tag_pressed() -> void:
	var tag := _tagify(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag == &"":
		return
	if _tag_catalog and not _tag_catalog.has_id(tag):
		_tag_catalog.add_id(tag)
		_save_tag_catalog()

	var preset := _editing_preset
	if preset != null:
		if not preset.tags.has(tag):
			preset.tags.append(tag)
		if _save_preset(preset):
			var item := _row_for(preset.resource_path)
			if item:
				item.set_text(COL_TAGS, ", ".join(preset.tags))
		_collect_known_tags()
		_rebuild_tag_tree()
		_rebuild_tag_checkboxes(preset)
		_set_status("Тег «%s» заведён и повешен на «%s»." % [tag, _label_of(preset)])
		return

	_collect_known_tags()
	_rebuild_tag_tree()
	_set_status("Тег «%s» заведён в словаре — опиши его справа." % tag)


func _on_filter_by_tag_pressed() -> void:
	if _editing_tag == &"":
		return
	_filter_tag = _editing_tag
	_filter_edit.text = ""
	_apply_filter()


func _on_rename_tag_pressed() -> void:
	if _editing_tag == &"":
		return
	_rename_tag_edit.text = String(_editing_tag)
	_rename_tag_dialog.popup_centered(Vector2i(340, 90))
	_rename_tag_edit.grab_focus()
	_rename_tag_edit.select_all()


## Переименование идёт по ВСЕМ пресетам разом — вручную это правка десятка
## .tres, и пропущенный превращается в тихую опечатку, то есть в комнату,
## которая больше никуда не подходит.
func _on_rename_tag_confirmed() -> void:
	var old_tag := _editing_tag
	var new_tag := _tagify(_rename_tag_edit.text)
	if old_tag == &"" or new_tag == &"" or new_tag == old_tag:
		return
	var touched := 0
	var presets := _library.presets + ([_library.fallback] if _library.fallback else [])
	for preset: RS_RoomPreset in presets:
		if preset == null or not preset.tags.has(old_tag):
			continue
		preset.tags.erase(old_tag)
		if not preset.tags.has(new_tag):
			preset.tags.append(new_tag)
		if _save_preset(preset):
			touched += 1

	if _tag_catalog:
		var entry := _tag_catalog.by_id(old_tag)
		if entry:
			entry.id = new_tag
		else:
			_tag_catalog.add_id(new_tag)
		_save_tag_catalog()

	_editing_tag = new_tag
	_refresh()
	_show_tag_card(new_tag)
	_set_status("«%s» → «%s», пресетов затронуто: %d." % [old_tag, new_tag, touched])


## Убирает ОПИСАНИЕ, а не тег с пресетов: снять тег с комнаты — осознанное
## действие в её карточке, и делать это оптом из словаря опасно (пресет молча
## перестанет подходить своим узлам).
func _on_forget_tag_pressed() -> void:
	if _editing_tag == &"" or _tag_catalog == null:
		return
	var uses := int(_tag_uses.get(_editing_tag, 0))
	_tag_catalog.remove_id(_editing_tag)
	_save_tag_catalog()
	var tail := (
		"" if uses == 0 else " Сам тег остался у %d пресетов — снимай его в их карточках." % uses
	)
	var removed := _editing_tag
	_collect_known_tags()
	_rebuild_tag_tree()
	if _editing_preset:
		_rebuild_tag_checkboxes(_editing_preset)
	_show_nothing()
	_set_status("«%s» убран из словаря.%s" % [removed, tail])


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
	var item := _row_for(path)
	if item == null:
		return
	item.select(COL_NAME)
	_on_tree_selection_changed()


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
		+ "(node.tags ⊆ preset.tags) → специфичность (минимум лишних тегов) → "
		+ "тип помещения → вес. "
		+ "Тип — ПРЕДПОЧТЕНИЕ, а не фильтр: если в группе нет ни одного пресета "
		+ "загаданного узлу типа, группа идёт дальше целиком. "
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
