## res://addons/game_design_tool/tabs/templates.gd
## Вкладка «Шаблоны» единого редактора геймдизайна — управление шаблонами
## сущностей (RS_EntityTemplate):
##   - список шаблонов из res://data/entity_templates;
##   - Новый / Дублировать / Удалить / Переименовать;
##   - Редактировать — открывает шаблон в родном инспекторе Godot
##     (там же добавляются/настраиваются компоненты);
##   - Создать сущность — генерирует .tscn с корневым Entity из шаблона.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Fs := preload("res://addons/game_design_tool/shared/fs.gd")

## Заголовок вкладки в TabContainer — тот берёт его из имени узла (см. _init).
const TAB_TITLE := "Шаблоны"

const TEMPLATE_DIR := "res://data/entity_templates"
const ENTITY_DIR := "res://src/entities"

## Зачем диалогу имени режим: окно ввода одно на три операции, а «ОК» в них
## значит разное. Enum, а не строка: режим «create_entity» с опечаткой
## проваливался бы во все ветки мимо и молча не делал ничего.
enum NameMode { NEW, RENAME, CREATE_ENTITY }

var _list: ItemList
var _status: Label
var _paths: Array[String] = []  # индекс в списке -> путь .tres
var _loaded := false  # список уже собран (см. _on_visibility_changed)

var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_mode := NameMode.NEW
var _delete_dialog: ConfirmationDialog
var _save_dialog: EditorFileDialog
var _pending_template: RS_EntityTemplate
var _pending_entity_name := ""  # имя корня будущей сущности


func _init() -> void:
	name = TAB_TITLE  # TabContainer берёт заголовок вкладки из имени узла
	_build_ui()


## Список наполняем при первом показе вкладки, а не в _ready: все вкладки
## строятся разом на старте редактора, и лезть в файловую систему ради вкладки,
## которую могут ни разу не открыть, незачем.
func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if not _loaded and is_visible_in_tree():
		_loaded = true
		_refresh()


#region UI
func _build_ui() -> void:
	var title := Ui.label("Шаблоны сущностей")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_activated.connect(_on_item_activated)
	_list.item_selected.connect(func(_i: int) -> void: _update_status())
	add_child(_list)

	var row1 := HBoxContainer.new()
	row1.add_child(Ui.button("Новый", _on_new_pressed))
	row1.add_child(Ui.button("Дублировать", _on_duplicate_pressed))
	row1.add_child(Ui.button("Удалить", _on_delete_pressed))
	add_child(row1)

	var row2 := HBoxContainer.new()
	row2.add_child(Ui.button("Переименовать", _on_rename_pressed))
	var edit_btn := Ui.button("Редактировать", _on_edit_pressed)
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(edit_btn)
	add_child(row2)

	add_child(HSeparator.new())

	var create_btn := Ui.button("Создать сущность из шаблона", _on_create_entity_pressed)
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(create_btn)

	_status = Ui.status_label()
	add_child(_status)

	# Диалог ввода имени — один на «Новый», «Переименовать» и «Создать сущность»
	# (различаются режимом, см. NameMode).
	_name_dialog = Ui.text_dialog("Имя шаблона", _on_name_confirmed)
	_name_edit = Ui.dialog_edit(_name_dialog)
	add_child(_name_dialog)

	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Удалить шаблон?"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)

	_save_dialog = EditorFileDialog.new()
	_save_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_save_dialog.clear_filters()
	_save_dialog.add_filter("*.tscn", "Сцена сущности")
	_save_dialog.file_selected.connect(_on_entity_path_chosen)
	add_child(_save_dialog)


func _set_status(text: String) -> void:
	Ui.set_status(_status, text)


func _warn(text: String) -> void:
	_set_status("⚠ " + text)


## Открывает диалог имени в заданном режиме — три операции звали его тремя
## одинаковыми пятистрочиями, различавшимися заголовком и подставленным текстом.
func _ask_name(mode: NameMode, title: String, preset_text: String) -> void:
	_name_mode = mode
	Ui.popup_text_dialog(_name_dialog, title, preset_text)
#endregion


#region Список
func _refresh(select_path := "") -> void:
	_list.clear()
	_paths.clear()

	var dir := DirAccess.open(TEMPLATE_DIR)
	if dir != null:
		for file in dir.get_files():
			if not file.ends_with(".tres"):
				continue
			var path := TEMPLATE_DIR + "/" + file
			var tmpl := ResourceLoader.load(path) as RS_EntityTemplate
			if tmpl == null:
				continue  # чужой .tres — молча пропускаем
			var label: String = tmpl.display_name if tmpl.display_name != "" else file.get_basename()
			# Считаем компоненты вместе с теми, что уже лежат в базовой сцене:
			# у шаблона с укомплектованной сценой (напр. «Тело») собственный
			# список пуст, и «(0 комп.)» читалось бы как «шаблон пустой».
			var idx := _list.add_item("%s  (%d комп.)" % [label, tmpl.component_count()])
			_list.set_item_tooltip(idx, path)
			_paths.append(path)

	if select_path != "":
		var i := _paths.find(select_path)
		if i != -1:
			_list.select(i)
	_update_status()


func _selected_path() -> String:
	var sel := _list.get_selected_items()
	if sel.is_empty():
		return ""
	return _paths[sel[0]]


func _selected_template() -> RS_EntityTemplate:
	var path := _selected_path()
	if path == "":
		return null
	return ResourceLoader.load(path) as RS_EntityTemplate


## Возвращает выделенный шаблон, а если его нет — жалуется и отдаёт null.
## Четыре кнопки начинались одной и той же трёхстрочной проверкой.
func _require_selection() -> RS_EntityTemplate:
	var tmpl := _selected_template()
	if tmpl == null:
		_warn("Сначала выбери шаблон.")
	return tmpl


func _update_status() -> void:
	if _paths.is_empty():
		_set_status("Нет шаблонов. Жми «Новый».")
	elif _selected_path() == "":
		_set_status("%d шаблонов. Выбери один." % _paths.size())
	else:
		_set_status(_selected_path().get_file())
#endregion


#region Действия
func _on_item_activated(_index: int) -> void:
	_on_edit_pressed()


func _on_new_pressed() -> void:
	_ask_name(NameMode.NEW, "Новый шаблон — имя", "Новая сущность")


func _on_rename_pressed() -> void:
	var tmpl := _require_selection()
	if tmpl == null:
		return
	_ask_name(NameMode.RENAME, "Переименовать шаблон", tmpl.display_name)


func _on_name_confirmed() -> void:
	var entered := _name_edit.text.strip_edges()
	if entered == "":
		_warn("Пустое имя.")
		return

	match _name_mode:
		NameMode.NEW:
			var tmpl := RS_EntityTemplate.new()
			tmpl.display_name = entered
			var path := Fs.unique_path(TEMPLATE_DIR, Fs.slug(entered, "entity_template"))
			if _save_template(tmpl, path):
				_refresh(path)
				_edit_resource(path)
				_set_status("Создан: " + path.get_file())
		NameMode.RENAME:
			var path := _selected_path()
			var tmpl := ResourceLoader.load(path) as RS_EntityTemplate
			if tmpl == null:
				return
			tmpl.display_name = entered
			if _save_template(tmpl, path):
				_refresh(path)
		NameMode.CREATE_ENTITY:
			# Имя → корень сцены; файл — то же имя в snake_case (папку выбираем в диалоге).
			_pending_entity_name = entered
			_save_dialog.current_dir = ENTITY_DIR
			_save_dialog.current_file = Fs.slug(entered) + ".tscn"
			_save_dialog.popup_centered_ratio(0.6)


func _on_duplicate_pressed() -> void:
	var src := _require_selection()
	if src == null:
		return
	var copy := src.duplicate(true) as RS_EntityTemplate
	copy.display_name = src.display_name + " (копия)"
	var base := _selected_path().get_file().get_basename()
	var path := Fs.unique_path(TEMPLATE_DIR, base + "_copy")
	if _save_template(copy, path):
		_refresh(path)
		_set_status("Дубликат: " + path.get_file())


func _on_delete_pressed() -> void:
	var path := _selected_path()
	if path == "":
		_warn("Сначала выбери шаблон.")
		return
	_delete_dialog.dialog_text = "Удалить файл «%s»?" % path.get_file()
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	var path := _selected_path()
	if path == "":
		return
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		_warn("Не удалось удалить (код %d)." % err)
		return
	Fs.rescan()
	_refresh()
	_set_status("Удалён: " + path.get_file())


func _on_edit_pressed() -> void:
	var tmpl := _require_selection()
	if tmpl == null:
		return
	EditorInterface.edit_resource(tmpl)
	_set_status("Открыт в инспекторе → правь компоненты.")


func _on_create_entity_pressed() -> void:
	var tmpl := _require_selection()
	if tmpl == null:
		return
	_pending_template = tmpl
	_ask_name(NameMode.CREATE_ENTITY, "Имя сущности (имя корня сцены)", tmpl.display_name)


func _on_entity_path_chosen(path: String) -> void:
	if _pending_template == null:
		return
	var root := _pending_template.build_entity(_pending_entity_name)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, path)
	root.free()
	_pending_template = null
	_pending_entity_name = ""

	if err != OK:
		_warn("Не удалось сохранить сцену (код %d)." % err)
		return
	Fs.rescan()
	EditorInterface.open_scene_from_path(path)
	_set_status("Создана сущность: " + path.get_file())
#endregion


#region Утилиты
func _save_template(res: Resource, path: String) -> bool:
	var err := Fs.save_new(res, path)
	if err != OK:
		_warn("Ошибка сохранения (код %d)." % err)
		return false
	return true


func _edit_resource(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res != null:
		EditorInterface.edit_resource(res)
#endregion
