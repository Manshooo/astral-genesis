## res://addons/game_design_tool/tabs/presets.gd
## Вкладка «Редактор пресетов» единого редактора геймдизайна: таблица пресетов и
## облако тегов слева, карточка выделенного — справа.
##
## Что она закрывает:
##   1. веса/slot_count/тип пресетов разбросаны по .tres рядом со своими сценами
##      (src/levels/procedural/rooms/) — здесь они в одной таблице и правятся
##      на месте;
##   2. теги правились строкой через запятую в ячейке таблицы — опечатка тихо
##      создавала новый тег вместо использования существующего. Тег теперь
##      только выбирается из списка известных: печатать нечего, опечатка
##      невозможна;
##   3. ЧТО тег значит, прочитать было негде вовсе — список тегов нигде не
##      хранился, все три инструмента собирали его обходом preset.tags. Отсюда
##      словарь (RS_RoomTagCatalog, data/room_tag_catalog.tres): у тега
##      появились имя и описание, а у инструмента — способ отличить настоящий
##      тег от опечатки (нет в словаре → «нет описания», и видно, что он
##      одинокий);
##   4. рассинхрон «заявленные слоты ↔ сцена» — «Проверка сцен».
##
## ПОЧЕМУ «Редактор пресетов», а не прежний «Генератор»: генератор здесь больше
## не запускается. «Прогнать сиды» уехал в «Генератор мира» — вопрос «что
## реально выпадает в забеге» про мир, а не про отдельный пресет, и отвечать на
## него правильно там, где этот мир видно. Здесь остались данные пресетов и
## сверка их со сценами.
##
## ПОЧЕМУ проверка — свёрнутая панель по кнопке-тумблеру, а не отчёт, постоянно
## висящий под таблицами: она устроена ровно как «Прогон сидов» в «Генераторе
## мира», и по той же причине. Отчёт нужен раз в несколько правок, а главное
## содержимое вкладки — таблицы и карточка; пустой RichTextLabel внизу отъедал
## у них высоту всё время, включая сессии, где проверку не запускают ни разу.
## Состояние тумблера переживает перезапуск редактора — иначе панель, открытая
## под разбор дверей, закрывалась бы сама на каждый перезапуск. Соотношения
## сплиттеров (список пресетов ↔ карточка, пресеты ↔ облако тегов, таблицы ↔
## панель проверки) — туда же, тем же GDT_EditorState: подвинутое рукой под
## свой монитор иначе съезжало бы на дефолт при каждом запуске редактора.
##
## ПОЧЕМУ master-detail, а не облако чекбоксов под таблицей, как было раньше:
## описание тега длиннее его ключа, и в HFlowContainer его можно показать разве
## что тултипом — то есть тому, кто УЖЕ знает, какой тег ищет. В карточке
## описание стоит прямо под чекбоксом и читается до клика, ради чего всё и
## затевалось. Поэтому вкладка НЕ берёт общий GDT_TagCloud (его берут узкие
## панели «Генератора мира» и Room Wizard): облако чипов — ровно та вёрстка,
## от которой здесь уходили.
##
## ПОЧЕМУ словарь — вторая таблица здесь же, а не отдельная вкладка: цикл работы
## («выделил пресет → навесил тег») ходит между ними постоянно, и уводить
## описания за переключатель вкладок значило бы вернуть ту же проблему другим
## способом. Правая панель показывает то, что выделено ПОСЛЕДНИМ — пресет или
## тег; выделения в двух таблицах независимы, поэтому возврат к пресету стоит
## одного клика.
##
## ПОЧЕМУ теги пресета в карточке — табличка навешанных + выпадающий список для
## добавления, а не чекбокс на каждый тег проекта: чекбоксов было бы по одному
## на КАЖДЫЙ тег библиотеки, а не только пресета, — при полусотне тегов карточка
## превращалась бы в длинный список, где смысл несёт меньшинство отмеченных
## строк. Табличка показывает только навешанные (снять — кнопкой ✕ в строке),
## добавление — тем же списком тегов проекта, но как источником, а не самоцелью.
## Описание — тултипом на строке и на пункте выпадающего списка, а не текстом
## под чекбоксом, как было: тултип не отъедает высоту у списка, который растёт
## вместе со словарём, а не только с числом отмеченных тегов.
##
## Проверка стороны двери идёт через RS_RoomLayout — тем же правилом, которым
## RS_LayerPlan раскладывает слой, иначе инструмент проверял бы не то, что делает
## игра.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Fs := preload("res://addons/game_design_tool/shared/fs.gd")
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const EditorState := preload("res://addons/game_design_tool/shared/editor_state.gd")

## Заголовок вкладки в TabContainer — тот берёт его из имени узла (см. _init).
const TAB_TITLE := "Редактор пресетов"

## Раздел проектных метаданных вкладки (см. GDT_EditorState) — состояние
## панели проверки и соотношения сплиттеров. Свой раздел, а не общий с
## «Генератором мира» (world_gen_tool): ключи там про сид и камеру, и общее имя
## означало бы, что переименование ключа в одной вкладке молча ломает другую.
const SETTINGS_SECTION := "presets_tool"

## Только для «Новый пресет» — заготовки БЕЗ сцены, планируешь пресет раньше,
## чем нарисована комната. Готовые пресеты (у которых уже есть scene) лежат
## РЯДОМ со своей сценой в src/levels/procedural/rooms/, тем же именем — это
## соглашение, на которое опирается Room Wizard (см. [[Единый редактор
## геймдизайна]]); data/room/ ему не нужен, он ищет .tres по пути сцены.
const PRESET_DIR := "res://data/room"

## Куда идти писать описание тега — текст тултипа-подсказки для тега без записи
## в словаре (см. GDT_Tags.description_or_hint). Тот же приём, что у world_gen.gd
## и Room Wizard, здесь просто указывает на соседнюю панель, а не на другую вкладку.
const TAG_HINT_WHERE := "облаке тегов слева"

const COL_NAME := 0
const COL_SLOTS := 1
const COL_ACTUAL := 2
const COL_WEIGHT := 3
const COL_TYPE := 4
const COL_TAGS := 5

const TAG_COL_NAME := 0
const TAG_COL_USES := 1

const COLOR_MISMATCH := Color(1, 0.45, 0.4)
const COLOR_MATCH := Color(0.6, 0.85, 0.6)
const COLOR_MUTED := Color(1, 1, 1, 0.7)
const COLOR_WARN := Color(1, 0.8, 0.45)

var _library: RS_RoomPresetLibrary
## Облако тегов. null — библиотека без словаря: описаний нет, всё остальное
## работает ровно как до его появления.
var _tag_catalog: RS_RoomTagCatalog

var _tree: Tree
var _tag_tree: Tree
## Проверка сцен: панель внизу, по умолчанию свёрнута, — тот же приём, что у
## «Прогона сидов» в «Генераторе мира» (см. шапку файла).
var _check_toggle: Button
var _check_panel: VBoxContainer
var _report: RichTextLabel
var _status: Label
var _filter_edit: LineEdit
var _filter_chip: Button
var _new_tag_edit: LineEdit

## Путь .tres пресета -> сколько дверей реально в его сцене (считаем при обновлении).
var _actual_doors: Dictionary = {}
## Тег -> сколько пресетов его носят. Считается там же, где _known_tags.
var _tag_uses: Dictionary = {}
## Все теги проекта — словарь плюс то, что реально стоит у пресетов
## (см. GDT_Tags.known_tags про то, почему второе слагаемое обязательно).
var _known_tags: Array[StringName] = []
## Варианты «Типа» по индексам — см. GDT_Library.type_ids.
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
## Табличка навешанных тегов — строка на тег, кнопка ✕ убирает.
var _p_tag_list: VBoxContainer
## Выпадающий список для добавления тега пресету — все известные теги МИНУС уже
## навешанные. Пересобирается вместе с табличкой: добавив тег, отдай его назад
## тому же списку, а не только уменьши табличку.
var _p_add_tag_option: OptionButton
## Кандидаты выпадающего списка в порядке его пунктов — оттуда обработчик кнопки
## «+» берёт StringName по индексу выделения (у OptionButton своих тегов нет).
var _p_add_tag_candidates: Array[StringName] = []

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
	if _library != null or not is_visible_in_tree():
		return
	# button_pressed сам зовёт _on_check_toggled — панель встаёт вместе с кнопкой.
	_check_toggle.button_pressed = EditorState.read(SETTINGS_SECTION, "check_panel", false)
	_refresh()


#region Вёрстка
func _build_ui() -> void:
	add_child(_build_toolbar())

	# Вертикальный сплит: таблицы сверху, отчёт проверки снизу. Панель отчёта
	# скрыта — SplitContainer со скрытым вторым ребёнком отдаёт всю высоту
	# первому, поэтому свёрнутая проверка не отъедает у таблиц ничего.
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
	rows.add_child(_build_check_panel())

	_status = Ui.status_label()
	add_child(_status)

	_new_preset_dialog = Ui.text_dialog("Новый пресет — имя", _on_new_preset_confirmed)
	_new_preset_edit = Ui.dialog_edit(_new_preset_dialog)
	add_child(_new_preset_dialog)

	_rename_tag_dialog = Ui.text_dialog(
		"Переименовать тег во всех пресетах", _on_rename_tag_confirmed
	)
	_rename_tag_edit = Ui.dialog_edit(_rename_tag_dialog)
	add_child(_rename_tag_dialog)


func _build_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_child(Ui.button("Обновить", _refresh_pressed))
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


## Панель проверки. Кнопка запуска внутри неё обязательна — открытие панели само
## ничего не считает: проверка инстанцирует ВСЕ сцены комнат (двери считаются
## по-настоящему), и вешать это на разворот панели значило бы платить паузой за
## взгляд на прошлый отчёт. Ровно тем же соображением «Прогон сидов» не гоняется
## сам при открытии своей панели.
func _build_check_panel() -> Control:
	_check_panel = VBoxContainer.new()
	_check_panel.visible = false
	_check_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var run := Ui.button("Проверить сцены", _on_validate_pressed)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_check_panel.add_child(run)

	_report = Ui.report_label(140)
	_check_panel.add_child(_report)
	return _check_panel


func _on_check_toggled(pressed: bool) -> void:
	_check_panel.visible = pressed
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

	var tags_box := VBoxContainer.new()
	tags_box.add_child(Ui.section_label("Облако тегов"))
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
	new_tag_row.add_child(Ui.button("+ тег", _on_add_tag_pressed))
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

	_card_placeholder = Ui.wrap_label("Выдели пресет или тег слева — здесь будет карточка.")
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

	_p_title = Ui.section_label()
	card.add_child(_p_title)
	_p_scene = Ui.status_label()
	card.add_child(_p_scene)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	grid.add_child(Ui.label("Слоты"))
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

	grid.add_child(Ui.label("Вес"))
	_p_weight = SpinBox.new()
	_p_weight.min_value = 0.0
	_p_weight.max_value = 10.0
	_p_weight.step = 0.1
	_p_weight.value_changed.connect(_on_card_weight_changed)
	grid.add_child(_p_weight)

	grid.add_child(Ui.label("Тип"))
	_p_type = OptionButton.new()
	_p_type.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_type.item_selected.connect(_on_card_type_selected)
	grid.add_child(_p_type)
	card.add_child(grid)

	_p_type_desc = Ui.wrap_label("")
	_p_type_desc.modulate = COLOR_MUTED
	card.add_child(_p_type_desc)

	card.add_child(HSeparator.new())
	card.add_child(
		Ui.wrap_label(
			"Узел получит эту комнату, только если все теги узла есть здесь. Лишние теги не запрещены, но по специфичности уводят пресет от простых узлов."
		)
	)
	_p_tag_list = VBoxContainer.new()
	_p_tag_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(_p_tag_list)

	var add_row := HBoxContainer.new()
	_p_add_tag_option = OptionButton.new()
	_p_add_tag_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_add_tag_option.item_selected.connect(_on_add_tag_option_selected)
	add_row.add_child(_p_add_tag_option)
	add_row.add_child(Ui.button("+", _on_add_known_tag_pressed))
	card.add_child(add_row)
	return card


func _build_tag_card() -> VBoxContainer:
	var card := VBoxContainer.new()
	card.visible = false
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_t_title = Ui.section_label()
	card.add_child(_t_title)
	_t_uses = Label.new()
	_t_uses.modulate = COLOR_MUTED
	card.add_child(_t_uses)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(Ui.label("Имя"))
	_t_name_edit = LineEdit.new()
	_t_name_edit.placeholder_text = "как показывать дизайнеру"
	_t_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_t_name_edit.focus_exited.connect(_flush_tag_edits)
	_t_name_edit.text_submitted.connect(func(_t: String) -> void: _flush_tag_edits())
	grid.add_child(_t_name_edit)
	card.add_child(grid)

	card.add_child(Ui.label("Что тег значит"))
	_t_desc_edit = TextEdit.new()
	_t_desc_edit.custom_minimum_size = Vector2(0, 110)
	_t_desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	# Сохраняем по уходу фокуса, а не на каждый символ: описание живёт в .tres,
	# и ResourceSaver на каждую букву переписывал бы файл словаря целиком.
	_t_desc_edit.focus_exited.connect(_flush_tag_edits)
	card.add_child(_t_desc_edit)

	_t_generator_note = Ui.wrap_label(
		"Этот тег генератор ставит узлам сам, и его ключ захардкожен в"
		+ " RS_LevelGraph — переименование здесь сломало бы подбор молча."
	)
	_t_generator_note.modulate = COLOR_WARN
	card.add_child(_t_generator_note)

	var buttons := HBoxContainer.new()
	buttons.add_child(Ui.button("Показать пресеты с тегом", _on_filter_by_tag_pressed))
	_t_rename_btn = Ui.button("Переименовать…", _on_rename_tag_pressed)
	buttons.add_child(_t_rename_btn)
	buttons.add_child(Ui.button("Убрать из словаря", _on_forget_tag_pressed))
	card.add_child(buttons)

	_t_used_by = Ui.wrap_label("")
	_t_used_by.modulate = COLOR_MUTED
	card.add_child(_t_used_by)
	return card


func _set_status(text: String) -> void:
	Ui.set_status(_status, text)
#endregion


#region Таблица пресетов
func _refresh_pressed() -> void:
	_refresh()
	_set_status("Обновлено.")


func _refresh() -> void:
	_flush_tag_edits()
	_library = Library.load_library()
	_tree.clear()
	_actual_doors.clear()
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + Library.LIBRARY_PATH)
		# Словарь сбрасываем вместе с библиотекой: оставшись от прошлой удачной
		# загрузки, он принял бы правки описаний в ресурс, которого на экране
		# уже нет, и сохранил бы их молча.
		_tag_catalog = null
		_known_tags.clear()
		_tag_uses.clear()
		_rebuild_tag_tree()
		_show_nothing()
		return

	_tag_catalog = Library.tag_catalog_of(_library)
	_type_ids = Library.type_ids(_library)

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
		"" if _tag_catalog else " ⚠ облако тегов не назначено библиотеке. Описаний не будет."
	)
	_set_status(
		"%d пресетов + fallback. Теги и описания — в карточке справа.%s"
		% [_library.presets.size(), catalog_note]
	)


func _add_row(root: TreeItem, preset: RS_RoomPreset, is_fallback: bool) -> void:
	var item := _tree.create_item(root)
	item.set_text(COL_NAME, Library.label_of(preset) + (" (fallback)" if is_fallback else ""))
	item.set_tooltip_text(COL_NAME, preset.resource_path)
	item.set_metadata(COL_NAME, preset.resource_path)

	item.set_cell_mode(COL_SLOTS, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(COL_SLOTS, 0, 12, 1)
	item.set_range(COL_SLOTS, preset.slot_count)
	item.set_editable(COL_SLOTS, true)

	var actual := _count_doors(preset)
	_actual_doors[preset.resource_path] = actual
	item.set_text(COL_ACTUAL, "нет сцены" if actual < 0 else str(actual))
	_mark_slot_mismatch(item, preset)

	item.set_cell_mode(COL_WEIGHT, TreeItem.CELL_MODE_RANGE)
	item.set_range_config(COL_WEIGHT, 0.0, 10.0, 0.1)
	item.set_range(COL_WEIGHT, preset.weight)
	item.set_editable(COL_WEIGHT, true)

	# Выпадающий список, а не свободный текст и не облако: тип у комнаты РОВНО
	# ОДИН (это ответ на вопрос «что это за помещение», а не набор способностей),
	# и множество вариантов задано каталогом — печатать тут нечего.
	item.set_cell_mode(COL_TYPE, TreeItem.CELL_MODE_RANGE)
	item.set_text(COL_TYPE, ",".join(Library.type_labels(_library, _type_ids, true)))
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


## Красит «В сцене» красным, если заявленные слоты разошлись с дверьми сцены.
## Генератор верит slot_count, а рёбра раздаются по реальным дверям — расхождение
## тихо ломает раздачу. Правится в двух местах (ячейка и карточка), поэтому
## правило одно на оба: разъехавшись, они спорили бы о цвете одной строки.
func _mark_slot_mismatch(item: TreeItem, preset: RS_RoomPreset) -> void:
	if item == null:
		return
	var actual: int = _actual_doors.get(preset.resource_path, -1)
	if actual < 0 or actual == preset.slot_count:
		item.clear_custom_color(COL_ACTUAL)
	else:
		item.set_custom_color(COL_ACTUAL, COLOR_MISMATCH)


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
			_mark_slot_mismatch(item, preset)
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
	var err := Library.save_preset(preset)
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


## Строка редактируемого пресета — три обработчика карточки начинались с неё.
func _editing_row() -> TreeItem:
	if _editing_preset == null:
		return null
	return _row_for(_editing_preset.resource_path)


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
	# Отчитываемся и когда фильтр снят: иначе «Показано 3 из 12» оставалось
	# висеть над полной таблицей и врало ровно после того, как фильтр убрали.
	if shown < total:
		_set_status("Показано %d из %d пресетов." % [shown, total])
	else:
		_set_status("Показаны все %d пресетов." % total)


func _haystack(preset: RS_RoomPreset) -> String:
	var type_label := (
		_library.type_catalog.label_of(preset.room_type)
		if _library and _library.type_catalog
		else String(preset.room_type)
	)
	return (
		"%s %s %s %s"
		% [
			Library.label_of(preset),
			preset.resource_path.get_file(),
			" ".join(preset.tags),
			type_label,
		]
	).to_lower()


func _clear_tag_filter() -> void:
	_filter_tag = &""
	_apply_filter()


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
	_p_title.text = Library.label_of(preset)
	_p_title.tooltip_text = preset.resource_path
	var scene_path := preset.scene.resource_path if preset.scene else ""
	_p_scene.text = scene_path.get_file() if scene_path != "" else "сцена не назначена"
	_p_scene.tooltip_text = scene_path
	_p_slots.value = preset.slot_count
	_update_actual_label(preset)
	_p_weight.value = preset.weight

	_p_type.clear()
	for text: String in Library.type_labels(_library, _type_ids):
		_p_type.add_item(text)
	_p_type.select(_type_index(preset.room_type))
	_syncing = false

	_update_type_desc(preset.room_type)
	_rebuild_tag_table(preset)


## «В сцене N» рядом со слотами: тот же рассинхрон, что подсвечен красным в
## таблице, но здесь его видно в момент правки — а правят слоты именно здесь.
func _update_actual_label(preset: RS_RoomPreset) -> void:
	var actual: int = _actual_doors.get(preset.resource_path, -1)
	if actual < 0:
		_p_actual.text = "в сцене: —"
		_p_actual.modulate = COLOR_MUTED
	elif actual == preset.slot_count:
		_p_actual.text = "в сцене: %d ✓" % actual
		_p_actual.modulate = COLOR_MATCH
	else:
		_p_actual.text = "в сцене: %d ⚠" % actual
		_p_actual.modulate = COLOR_MISMATCH


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
	var item := _editing_row()
	if item:
		item.set_range(COL_SLOTS, _editing_preset.slot_count)
		_mark_slot_mismatch(item, _editing_preset)
	_update_actual_label(_editing_preset)


func _on_card_weight_changed(value: float) -> void:
	if _syncing or _editing_preset == null:
		return
	_editing_preset.weight = value
	if not _save_preset(_editing_preset):
		return
	var item := _editing_row()
	if item:
		item.set_range(COL_WEIGHT, value)


func _on_card_type_selected(index: int) -> void:
	if _syncing or _editing_preset == null:
		return
	_editing_preset.room_type = _type_ids[index] if index < _type_ids.size() else &""
	if not _save_preset(_editing_preset):
		return
	var item := _editing_row()
	if item:
		item.set_range(COL_TYPE, index)
	_update_type_desc(_editing_preset.room_type)


## Табличка навешанных тегов: строка на тег (имя + кнопка ✕), под ней — выпадающий
## список для добавления. Порядок строк — алфавитный, чтобы снятие/добавление не
## переставляло уже показанные теги местами.
func _rebuild_tag_table(preset: RS_RoomPreset) -> void:
	# free(), не queue_free(): перестройка идёт на каждую смену выделения, и
	# отложенное удаление копило бы старые строки поверх новых.
	for child: Node in _p_tag_list.get_children():
		child.free()

	var assigned: Array[StringName] = preset.tags.duplicate()
	assigned.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))

	if assigned.is_empty():
		_p_tag_list.add_child(Ui.wrap_label("Тегов нет — добавь ниже."))
	for tag: StringName in assigned:
		_p_tag_list.add_child(_build_tag_row(tag))

	_rebuild_add_tag_option(assigned)


## Одна строка таблички: имя тега (тултип — описание из словаря либо просьба
## его завести) и кнопка ✕, снимающая тег с пресета.
func _build_tag_row(tag: StringName) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var known := _tag_catalog != null and _tag_catalog.has_id(tag)
	var name_label := Ui.ellipsis_label(String(tag) if not known else _tag_catalog.label_of(tag))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = Tags.description_or_hint(_tag_catalog, tag, TAG_HINT_WHERE)
	if not known:
		name_label.modulate = COLOR_WARN
	row.add_child(name_label)

	row.add_child(Ui.button("✕", _on_remove_tag_pressed.bind(tag)))
	return row


## Кандидаты выпадающего списка — известные теги минус уже навешанные: список
## только предлагает то, чего у пресета ещё нет, иначе «+» либо ничего не менял
## бы (тег уже стоит), либо требовал сперва найти его в уже длинном списке.
func _rebuild_add_tag_option(assigned: Array[StringName]) -> void:
	_p_add_tag_option.clear()
	_p_add_tag_candidates.clear()
	for tag: StringName in _known_tags:
		if assigned.has(tag):
			continue
		_p_add_tag_candidates.append(tag)
		var known := _tag_catalog != null and _tag_catalog.has_id(tag)
		_p_add_tag_option.add_item(String(tag) if not known else _tag_catalog.label_of(tag))
		var idx := _p_add_tag_option.item_count - 1
		_p_add_tag_option.set_item_tooltip(idx, Tags.description_or_hint(_tag_catalog, tag, TAG_HINT_WHERE))

	var has_candidates := not _p_add_tag_candidates.is_empty()
	_p_add_tag_option.disabled = not has_candidates
	_p_add_tag_option.tooltip_text = (
		"" if not has_candidates else _p_add_tag_option.get_item_tooltip(0)
	)
	if not has_candidates:
		_p_add_tag_option.add_item("— все известные теги уже здесь —")


## Наведение на СВЁРНУТУЮ кнопку списка тоже должно показывать описание — иначе
## тултип был бы виден только в развёрнутом попапе, а не там, где взгляд обычно
## первым и падает.
func _on_add_tag_option_selected(index: int) -> void:
	if index >= 0 and index < _p_add_tag_option.item_count:
		_p_add_tag_option.tooltip_text = _p_add_tag_option.get_item_tooltip(index)


func _on_add_known_tag_pressed() -> void:
	if _editing_preset == null or _p_add_tag_candidates.is_empty():
		return
	var index := _p_add_tag_option.selected
	if index < 0 or index >= _p_add_tag_candidates.size():
		return
	_apply_tag_change(_p_add_tag_candidates[index], true)


func _on_remove_tag_pressed(tag: StringName) -> void:
	_apply_tag_change(tag, false)


func _apply_tag_change(tag: StringName, pressed: bool) -> void:
	if _editing_preset == null:
		return
	Tags.toggle(_editing_preset, tag, pressed)
	if not _save_preset(_editing_preset):
		return
	var item := _editing_row()
	if item:
		item.set_text(COL_TAGS, ", ".join(_editing_preset.tags))
	_collect_known_tags()
	_rebuild_tag_tree()
	# call_deferred, а не напрямую: сюда приходят и от кнопки ✕ ВНУТРИ самой
	# таблички — прямой вызов освобождал бы строку, пока её же сигнал pressed
	# ещё обрабатывается («Object was freed... while a signal is being emitted»).
	# Одна отложенная пересборка, а не двойной рендер со старыми и новыми
	# строками разом: free() внутри неё по-прежнему безусловный.
	_rebuild_tag_table.call_deferred(_editing_preset)
#endregion


#region Облако тегов
func _collect_known_tags() -> void:
	_tag_uses = Tags.uses(_library)
	_known_tags = Tags.known_tags(_library, _tag_catalog)


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
			item.set_custom_color(TAG_COL_NAME, COLOR_WARN)
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
	_t_used_by.text = _presets_with_tag_text(tag)


func _presets_with_tag_text(tag: StringName) -> String:
	var names: Array[String] = []
	for preset: RS_RoomPreset in Library.vocabulary_presets(_library):
		if preset.tags.has(tag):
			names.append(Library.label_of(preset))
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
		_set_status("⚠ Облако тегов не назначено библиотеке. Описания сохранять некуда.")
		return false
	var err := Tags.save_catalog(_tag_catalog)
	if err != OK:
		_set_status("⚠ Не удалось сохранить словарь (код %d)" % err)
		return false
	_set_status("Словарь сохранён.")
	return true


## Новый тег заводится СРАЗУ в словаре, а не в момент, когда для него написали
## описание: иначе он был бы неотличим от опечатки — а именно ради этого
## различия словарь и появился. Выделенному пресету тег тут же и вешается,
## потому что заводят его обычно для конкретной комнаты.
func _on_add_tag_pressed() -> void:
	var tag := Tags.tagify(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag == &"":
		return
	Tags.register(_tag_catalog, tag)

	var preset := _editing_preset
	if preset == null:
		_collect_known_tags()
		_rebuild_tag_tree()
		_set_status("Тег «%s» заведён в словаре — опиши его справа." % tag)
		return

	Tags.toggle(preset, tag, true)
	if _save_preset(preset):
		var item := _row_for(preset.resource_path)
		if item:
			item.set_text(COL_TAGS, ", ".join(preset.tags))
	_collect_known_tags()
	_rebuild_tag_tree()
	_rebuild_tag_table(preset)
	_set_status("Тег «%s» заведён и повешен на «%s»." % [tag, Library.label_of(preset)])


func _on_filter_by_tag_pressed() -> void:
	if _editing_tag == &"":
		return
	_filter_tag = _editing_tag
	_filter_edit.text = ""
	_apply_filter()


func _on_rename_tag_pressed() -> void:
	if _editing_tag == &"":
		return
	Ui.popup_text_dialog(
		_rename_tag_dialog, "Переименовать тег во всех пресетах", String(_editing_tag)
	)


## Переименование идёт по ВСЕМ пресетам разом — вручную это правка десятка
## .tres, и пропущенный превращается в тихую опечатку, то есть в комнату,
## которая больше никуда не подходит.
func _on_rename_tag_confirmed() -> void:
	var old_tag := _editing_tag
	var new_tag := Tags.tagify(_rename_tag_edit.text)
	if old_tag == &"" or new_tag == &"" or new_tag == old_tag:
		return
	var touched := 0
	for preset: RS_RoomPreset in Library.vocabulary_presets(_library):
		if not preset.tags.has(old_tag):
			continue
		Tags.toggle(preset, old_tag, false)
		Tags.toggle(preset, new_tag, true)
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
	var removed := _editing_tag
	_tag_catalog.remove_id(removed)
	_save_tag_catalog()
	var tail := (
		"" if uses == 0 else " Сам тег остался у %d пресетов — снимай его в их карточках." % uses
	)
	_collect_known_tags()
	_rebuild_tag_tree()
	if _editing_preset:
		_rebuild_tag_table(_editing_preset)
	_show_nothing()
	_set_status("«%s» убран из словаря.%s" % [removed, tail])
#endregion


#region Новый пресет
func _on_new_preset_pressed() -> void:
	if _library == null:
		_set_status("⚠ Библиотека не загружена.")
		return
	Ui.popup_text_dialog(_new_preset_dialog, "Новый пресет — имя", "Новый пресет")


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
	var path := Fs.unique_path(PRESET_DIR, Fs.slug(entered, "room_preset"))
	var err := Fs.save_new(preset, path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return

	_library.presets.append(preset)
	var lib_err := ResourceSaver.save(_library, Library.LIBRARY_PATH)
	if lib_err != OK:
		_set_status("⚠ Пресет создан, но библиотека не сохранилась (код %d)" % lib_err)
		return

	Fs.rescan()
	_refresh()
	_select_row(path)
	_set_status("Создан: " + path.get_file() + " — назначь сцену через «Открыть в инспекторе».")


func _select_row(path: String) -> void:
	var item := _row_for(path)
	if item == null:
		return
	item.select(COL_NAME)
	_on_tree_selection_changed()
#endregion


#region Проверка сцен
## Отчёт по каждому пресету в свёрнутую панель внизу: расхождения slot_count ↔
## сцена и разбор дверей — какая дверь на какой стене и что у неё в slot_id.
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

	var checked := Library.vocabulary_presets(_library)
	for preset: RS_RoomPreset in checked:
		lines.append("[b]%s[/b]" % Library.label_of(preset))
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
	_set_status("Проверено пресетов: %d" % checked.size())


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
