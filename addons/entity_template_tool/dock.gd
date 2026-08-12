## res://addons/entity_template_tool/dock.gd
## Окно управления шаблонами сущностей (RS_EntityTemplate):
##   - список шаблонов из res://data/entity_templates;
##   - Новый / Дублировать / Удалить / Переименовать;
##   - Редактировать — открывает шаблон в родном инспекторе Godot
##     (там же добавляются/настраиваются компоненты);
##   - Создать сущность — генерирует .tscn с корневым Entity из шаблона.
@tool
extends VBoxContainer

const TEMPLATE_DIR := "res://data/entity_templates"
const ENTITY_DIR := "res://src/entities"

var _list: ItemList
var _status: Label
var _paths: Array[String] = []  # индекс в списке -> путь .tres

var _name_dialog: ConfirmationDialog
var _name_edit: LineEdit
var _name_mode := ""  # "new" | "rename" | "create_entity"
var _delete_dialog: ConfirmationDialog
var _save_dialog: EditorFileDialog
var _pending_template: RS_EntityTemplate
var _pending_entity_name := ""  # имя корня будущей сущности


func _init() -> void:
	name = "Шаблоны"
	custom_minimum_size = Vector2(240, 0)
	_build_ui()


func _ready() -> void:
	_refresh()


#region UI
func _build_ui() -> void:
	add_child(_titled("Шаблоны сущностей"))

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.allow_reselect = true
	_list.item_activated.connect(_on_item_activated)
	_list.item_selected.connect(func(_i): _update_status())
	add_child(_list)

	var row1 := HBoxContainer.new()
	row1.add_child(_button("Новый", _on_new_pressed))
	row1.add_child(_button("Дублировать", _on_duplicate_pressed))
	row1.add_child(_button("Удалить", _on_delete_pressed))
	add_child(row1)

	var row2 := HBoxContainer.new()
	row2.add_child(_button("Переименовать", _on_rename_pressed))
	var edit_btn := _button("Редактировать", _on_edit_pressed)
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(edit_btn)
	add_child(row2)

	add_child(HSeparator.new())

	var create_btn := _button("Создать сущность из шаблона", _on_create_entity_pressed)
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(create_btn)

	# Статус — строго ОДНА строка с многоточием, а не autowrap. Label с autowrap
	# считает минимальную высоту, перенося текст по минимальной ШИРИНЕ (а она до
	# первой раскладки ~17 px), и требует под себя сотни пикселей. Эту минималку
	# редактор спрашивает у ВСЕХ вкладок дока сразу, ещё до открытия, — из-за неё
	# панели разъезжаются, пока вкладку не откроешь. Полный текст — в подсказке.
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	# Диалог ввода имени (для «Новый» и «Переименовать»).
	_name_dialog = ConfirmationDialog.new()
	_name_dialog.title = "Имя шаблона"
	_name_edit = LineEdit.new()
	_name_edit.custom_minimum_size = Vector2(280, 0)
	_name_dialog.add_child(_name_edit)
	_name_dialog.register_text_enter(_name_edit)
	_name_dialog.confirmed.connect(_on_name_confirmed)
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


func _titled(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


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
			var res := ResourceLoader.load(path)
			var tmpl := res as RS_EntityTemplate
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
	_name_mode = "new"
	_name_dialog.title = "Новый шаблон — имя"
	_name_edit.text = "Новая сущность"
	_name_dialog.popup_centered(Vector2i(340, 90))
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_rename_pressed() -> void:
	var tmpl := _selected_template()
	if tmpl == null:
		_warn("Сначала выбери шаблон.")
		return
	_name_mode = "rename"
	_name_dialog.title = "Переименовать шаблон"
	_name_edit.text = tmpl.display_name
	_name_dialog.popup_centered(Vector2i(340, 90))
	_name_edit.grab_focus()
	_name_edit.select_all()


func _on_name_confirmed() -> void:
	var entered := _name_edit.text.strip_edges()
	if entered == "":
		_warn("Пустое имя.")
		return

	if _name_mode == "new":
		var tmpl := RS_EntityTemplate.new()
		tmpl.display_name = entered
		var path := _unique_path(_snake(entered, "entity_template"))
		if _save_resource(tmpl, path):
			_refresh(path)
			_edit_resource(path)
			_set_status("Создан: " + path.get_file())
	elif _name_mode == "rename":
		var path := _selected_path()
		var tmpl := ResourceLoader.load(path) as RS_EntityTemplate
		if tmpl == null:
			return
		tmpl.display_name = entered
		if _save_resource(tmpl, path):
			_refresh(path)
	elif _name_mode == "create_entity":
		# Имя → корень сцены; файл — то же имя в snake_case (папку выбираем в диалоге).
		_pending_entity_name = entered
		_save_dialog.current_dir = ENTITY_DIR
		_save_dialog.current_file = _snake(entered) + ".tscn"
		_save_dialog.popup_centered_ratio(0.6)


func _on_duplicate_pressed() -> void:
	var src := _selected_template()
	if src == null:
		_warn("Сначала выбери шаблон.")
		return
	var copy := src.duplicate(true) as RS_EntityTemplate
	copy.display_name = src.display_name + " (копия)"
	var base := _selected_path().get_file().get_basename()
	var path := _unique_path(base + "_copy")
	if _save_resource(copy, path):
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
	_rescan_filesystem()
	_refresh()
	_set_status("Удалён: " + path.get_file())


func _on_edit_pressed() -> void:
	var tmpl := _selected_template()
	if tmpl == null:
		_warn("Сначала выбери шаблон.")
		return
	EditorInterface.edit_resource(tmpl)
	_set_status("Открыт в инспекторе → правь компоненты.")


func _on_create_entity_pressed() -> void:
	var tmpl := _selected_template()
	if tmpl == null:
		_warn("Сначала выбери шаблон.")
		return
	_pending_template = tmpl
	_name_mode = "create_entity"
	_name_dialog.title = "Имя сущности (имя корня сцены)"
	_name_edit.text = tmpl.display_name
	_name_dialog.popup_centered(Vector2i(340, 90))
	_name_edit.grab_focus()
	_name_edit.select_all()


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
	_rescan_filesystem()
	EditorInterface.open_scene_from_path(path)
	_set_status("Создана сущность: " + path.get_file())
#endregion


#region Утилиты
## snake_case: буквы (в т.ч. кириллица) и цифры сохраняются в нижнем регистре,
## любой разделитель/пунктуация → одно подчёркивание, края обрезаются.
func _snake(text: String, fallback := "entity") -> String:
	var out := ""
	var prev_us := false
	for c in text.strip_edges().to_lower():
		if _is_word_char(c):
			out += c
			prev_us = false
		elif not prev_us and out != "":
			out += "_"
			prev_us = true
	out = out.rstrip("_")
	return out if out != "" else fallback


## Буква (латиница/кириллица/…) отличается регистром upper≠lower; плюс цифры и «_».
func _is_word_char(c: String) -> bool:
	return c == "_" or (c >= "0" and c <= "9") or c.to_lower() != c.to_upper()


func _unique_path(base: String) -> String:
	_ensure_dir()
	var path := TEMPLATE_DIR + "/" + base + ".tres"
	var n := 2
	while FileAccess.file_exists(path):
		path = "%s/%s_%d.tres" % [TEMPLATE_DIR, base, n]
		n += 1
	return path


func _ensure_dir() -> void:
	if not DirAccess.dir_exists_absolute(TEMPLATE_DIR):
		DirAccess.make_dir_recursive_absolute(TEMPLATE_DIR)


func _save_resource(res: Resource, path: String) -> bool:
	res.take_over_path(path)
	var err := ResourceSaver.save(res, path)
	if err != OK:
		_warn("Ошибка сохранения (код %d)." % err)
		return false
	_rescan_filesystem()
	return true


func _edit_resource(path: String) -> void:
	var res := ResourceLoader.load(path)
	if res != null:
		EditorInterface.edit_resource(res)


func _rescan_filesystem() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()


func _warn(text: String) -> void:
	_set_status("⚠ " + text)
#endregion
