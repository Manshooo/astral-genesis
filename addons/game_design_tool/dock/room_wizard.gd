## res://addons/game_design_tool/dock/room_wizard.gd
## Room Wizard — оборачивает открытую сцену комнаты в RS_RoomPreset без
## ручного похода в FileSystem: сейчас это создать `.tres`, прописать в нём
## `scene`, прописать путь руками в редакторе, потом ещё руками добавить в
## библиотеку. Здесь — форма и две кнопки.
##
## Тонкий док, не вкладка главного экрана: работает ПОВЕРХ сцены, открытой в
## обычном 3D-редакторе (EditorPlugin.scene_changed → scene_root), а главный
## экран эту сцену прячет — см. [[Единый редактор геймдизайна]].
##
## Три решения, записанные в карточке заранее:
##   - Существующий ресурс ищется СОГЛАШЕНИЕМ ИМЁН: <сцена>.tres рядом со
##     сценой, тот же файл. Не поиском по scene.resource_path в библиотеке —
##     тот надёжнее, но конвенция уже выбрана и должна быть одной на весь
##     редактор (её теперь соблюдают все 12 существующих пресетов).
##   - Библиотека — путь константой (GDT_Library.LIBRARY_PATH), она в проекте одна.
##   - Подписи полей — локальный словарь (FIELD_LABELS), не сырые @export-
##     имена и не трюк RS_EntityTemplate с _get_property_list.
##
## Форма НАСТОЯЩАЯ рефлексивная (get_property_list, не хардкод трёх полей):
## новое скалярное @export-поле в RS_RoomPreset появится в форме само, разве
## что без перевода в FIELD_LABELS — сырое имя лучше молчаливо потерянного
## поля. scene, tags и room_type — не в общем цикле: первым распоряжается сам
## Wizard (он и есть источник scene), у остальных своя вёрстка.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Fs := preload("res://addons/game_design_tool/shared/fs.gd")
const Tags := preload("res://addons/game_design_tool/shared/tags.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const TagCloud := preload("res://addons/game_design_tool/shared/tag_cloud.gd")

## Поля scene, tags и room_type — своя вёрстка ниже, в общий рефлексивный цикл
## не идут. Тип — выпадающий список: он у комнаты один и берётся из каталога,
## а рефлексивная форма нарисовала бы StringName нередактируемой строкой.
const CUSTOM_FIELDS := ["scene", "tags", "room_type"]
const FIELD_LABELS := {
	"display_name": "Название",
	"slot_count": "Слоты",
	"weight": "Вес",
}
## Границы спинбоксов ПОИМЕННО, а не одни на весь числовой тип. RS_RoomPreset
## не носит @export_range, поэтому из get_property_list границы не достать — и
## пока они задавались одним числом на TYPE_INT, любое новое целое поле молча
## получало бы диапазон slot_count (0..12) и обрезало бы авторское значение при
## первом же сохранении. Незнакомое поле получает широкий диапазон: показать
## значение как есть безопаснее, чем подрезать его под чужую шкалу.
const FIELD_RANGES := {
	"slot_count": {"min": 0.0, "max": 12.0, "step": 1.0},
	"weight": {"min": 0.0, "max": 10.0, "step": 0.1},
}
const DEFAULT_INT_RANGE := {"min": -99999.0, "max": 99999.0, "step": 1.0}
const DEFAULT_FLOAT_RANGE := {"min": -99999.0, "max": 99999.0, "step": 0.01}

## Куда идти писать описание тега — текст для тултипов облака.
const TAG_HINT_WHERE := "вкладке «Геймдизайн» → «Редактор пресетов» → облако тегов"

var _scene_path := ""
var _preset_path := ""
var _preset: RS_RoomPreset

var _scene_label: Label
var _form_box: VBoxContainer
var _field_controls: Dictionary = {}  # имя @export-поля -> Control формы

var _tag_cloud: TagCloud
var _new_tag_edit: LineEdit

## Ключи в порядке пунктов _type_option: [&""] + каталог.
var _type_ids: Array[StringName] = []
var _type_option: OptionButton

var _resource_status: Label
var _save_btn: Button
var _add_to_library_btn: Button
var _status: Label


func _init() -> void:
	name = "Мастер комнаты"
	custom_minimum_size = Vector2(260, 0)
	_build_ui()


#region UI
func _build_ui() -> void:
	var title := Label.new()
	title.text = "Room Wizard"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_scene_label = Ui.ellipsis_label()
	add_child(_scene_label)

	add_child(HSeparator.new())

	_form_box = VBoxContainer.new()
	add_child(_form_box)

	var type_row := HBoxContainer.new()
	var type_label := Ui.label("Тип:")
	type_label.custom_minimum_size = Vector2(64, 0)
	type_row.add_child(type_label)
	_type_option = OptionButton.new()
	_type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_type_option.tooltip_text = (
		"Что это за помещение. Отдельная ось от тегов: тегами узел фильтруется"
		+ " жёстко, типом — только предпочитается."
	)
	type_row.add_child(_type_option)
	add_child(type_row)

	add_child(Ui.label("Теги:"))
	_tag_cloud = TagCloud.new(TAG_HINT_WHERE)
	add_child(_tag_cloud)

	var new_tag_row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _on_add_tag_pressed())
	new_tag_row.add_child(_new_tag_edit)
	new_tag_row.add_child(Ui.button("+", _on_add_tag_pressed))
	add_child(new_tag_row)

	add_child(HSeparator.new())

	_resource_status = Ui.status_label()
	add_child(_resource_status)

	_save_btn = Ui.button("Сохранить как Room-ресурс", _on_save_pressed)
	add_child(_save_btn)

	_add_to_library_btn = Ui.button("Добавить в библиотеку", _on_add_to_library_pressed)
	add_child(_add_to_library_btn)

	_status = Ui.status_label()
	add_child(_status)

	_set_active(false)


func _set_status(text: String) -> void:
	Ui.set_status(_status, text)
#endregion


#region Реакция на смену сцены
## Зовёт EditorPlugin на scene_changed (см. plugin.gd) — этот узел сам не
## подписан на редактор, у обычного Control нет доступа к такому сигналу.
func refresh_for_scene(scene_root: Node) -> void:
	_preset = null
	_field_controls.clear()
	_tag_cloud.show_for(null)

	if scene_root == null:
		_scene_label.text = "Сцена не открыта"
		_set_active(false)
		return

	var scene_path := scene_root.scene_file_path
	if scene_path == "":
		_scene_label.text = "Сцена не сохранена — сохрани и открой снова"
		_set_active(false)
		return

	_scene_path = scene_path
	_scene_label.text = scene_path.get_file()
	_scene_label.tooltip_text = scene_path
	# Соглашение имён: Room-ресурс — <сцена>.tres рядом со сценой, тот же файл.
	_preset_path = scene_path.get_basename() + ".tres"

	if ResourceLoader.exists(_preset_path):
		_preset = ResourceLoader.load(_preset_path, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPreset
		_resource_status.text = "Уже существует: " + _preset_path.get_file()
	else:
		_preset = RS_RoomPreset.new()
		_preset.display_name = scene_path.get_file().get_basename()
		_resource_status.text = "Будет создан: " + _preset_path.get_file()

	var library := Library.load_library()
	_tag_cloud.set_vocabulary(library)
	_tag_cloud.show_for(_preset)
	_rebuild_type_options(library)
	_build_form()
	_set_active(true)


## Хаб — исключение из общего правила: «Сохранить как Room-ресурс» ему нужен
## как любой другой сцене (Room Wizard — единственный путь дать hub.tscn его
## RS_RoomPreset), а вот «Добавить в библиотеку» — нет и не должен. Библиотека
## отдаёт его RS_LevelGraph.HUB_ROOM_SCENE в обход отбора (домашний узел
## получает хаб принудительно, не через select_preset); попади его пресет в
## presets — пустые tags и slot_count=1 сделали бы hub кандидатом-победителем
## для ЛЮБОГО непомеченного узла-тупика графа (см. RS_RoomPresetLibrary.hub).
func _set_active(active: bool) -> void:
	_form_box.visible = active
	_tag_cloud.visible = active
	_type_option.disabled = not active
	_save_btn.disabled = not active
	# _scene_path не сбрасывается в false-ветках refresh_for_scene (там кнопка
	# и так выключена через not active) — is_hub смотрим только пока active,
	# иначе подсказка о хабе могла бы остаться от предыдущей сцены.
	var is_hub := active and _scene_path == RS_LevelGraph.HUB_ROOM_SCENE
	_add_to_library_btn.disabled = not active or not ResourceLoader.exists(_preset_path) or is_hub
	_add_to_library_btn.tooltip_text = (
		"Хаб — не для общего пула, генератор ставит его домашнему узлу напрямую"
		if is_hub
		else ""
	)
#endregion


#region Рефлексивная форма
## free(), не queue_free(): форма пересобирается на каждую смену сцены — тот
## же принцип, что у оверлеев «Генератора мира» и облака тегов — отложенное
## удаление копило бы старые контролы поверх новых при быстром переключении
## вкладок сцены в редакторе.
func _build_form() -> void:
	for child: Node in _form_box.get_children():
		child.free()
	_field_controls.clear()

	for prop: Dictionary in _preset.get_property_list():
		# И SCRIPT_VARIABLE (объявлено в этом скрипте, не в базовом Resource —
		# иначе в форму попали бы resource_local_to_scene и подобное), И
		# EDITOR (реально @export, а не служебное поле).
		if not (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		if CUSTOM_FIELDS.has(prop.name):
			continue
		_add_field_row(prop)


func _add_field_row(prop: Dictionary) -> void:
	var row := HBoxContainer.new()
	var label := Ui.label(FIELD_LABELS.get(prop.name, prop.name))
	label.custom_minimum_size = Vector2(64, 0)
	row.add_child(label)

	var control: Control
	match prop.type:
		TYPE_STRING:
			var edit := LineEdit.new()
			edit.text = _preset.get(prop.name)
			edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			control = edit
		TYPE_INT:
			control = _spin_for(prop.name, DEFAULT_INT_RANGE)
		TYPE_FLOAT:
			control = _spin_for(prop.name, DEFAULT_FLOAT_RANGE)
		_:
			# Тип, который форма ещё не умеет рисовать — появится, когда в
			# RS_RoomPreset заведут поле такого типа. Честно показать
			# значение текстом лучше, чем молча сделать вид, что поля нет.
			control = Ui.label(str(_preset.get(prop.name)))

	row.add_child(control)
	_form_box.add_child(row)
	_field_controls[prop.name] = control


func _spin_for(field_name: String, default_range: Dictionary) -> SpinBox:
	var limits: Dictionary = FIELD_RANGES.get(field_name, default_range)
	var spin := SpinBox.new()
	spin.min_value = limits["min"]
	spin.max_value = limits["max"]
	spin.step = limits["step"]
	spin.value = _preset.get(field_name)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spin


## Список типов помещений из каталога библиотеки. Тип, который у пресета уже
## стоит, но каталогу неизвестен, дописывается отдельным пунктом — иначе
## сохранение молча стёрло бы авторскую правку, подставив первый пункт.
func _rebuild_type_options(library: RS_RoomPresetLibrary) -> void:
	_type_ids = Library.type_ids(library, _preset)
	_type_option.clear()
	for text: String in Library.type_labels(library, _type_ids):
		_type_option.add_item(text)

	var index := _type_ids.find(_preset.room_type) if _preset else 0
	_type_option.select(index if index >= 0 else 0)


## Переносит значения из формы в _preset. Зовётся перед сохранением, а не
## держит _preset синхронизированным на каждое нажатие клавиши — дешевле и
## ничего не теряет, потому что сохраняем мы только по кнопке.
##
## Теги в этом переносе не участвуют: облако пишет их прямо в _preset (см.
## GDT_TagCloud — сохранением оно не занимается, а правкой в памяти да).
func _apply_form_to_preset() -> void:
	# get_selected(), а не get_selected_id(): id совпадает с индексом только пока
	# его никто не задал явно, а _type_ids индексируется именно позицией пункта.
	var selected := _type_option.get_selected()
	_preset.room_type = (
		_type_ids[selected] if selected >= 0 and selected < _type_ids.size() else &""
	)
	for field_name: String in _field_controls:
		var control: Control = _field_controls[field_name]
		if control is LineEdit:
			_preset.set(field_name, (control as LineEdit).text)
		elif control is SpinBox:
			_preset.set(field_name, (control as SpinBox).value)
#endregion


#region Облако тегов
func _on_add_tag_pressed() -> void:
	var tag := _tag_cloud.add_new(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag != &"":
		_set_status("Тег «%s» повешен — сохрани ресурс, чтобы записать." % tag)
#endregion


#region Сохранение
func _on_save_pressed() -> void:
	if _preset == null or _scene_path == "":
		return
	_apply_form_to_preset()
	_preset.scene = ResourceLoader.load(_scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	var err := (
		Library.save_preset(_preset)
		if ResourceLoader.exists(_preset_path)
		else Fs.save_new(_preset, _preset_path)
	)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	Fs.rescan()
	_resource_status.text = "Сохранён: " + _preset_path.get_file()
	_add_to_library_btn.disabled = _scene_path == RS_LevelGraph.HUB_ROOM_SCENE
	_set_status("Сохранено: " + _preset_path.get_file())


func _on_add_to_library_pressed() -> void:
	if _preset == null or not ResourceLoader.exists(_preset_path):
		_set_status("⚠ Сначала сохрани ресурс.")
		return
	var library := Library.load_library()
	if library == null:
		_set_status("⚠ Не удалось загрузить библиотеку.")
		return
	for existing: RS_RoomPreset in library.presets:
		if existing and existing.resource_path == _preset_path:
			_set_status("Уже в библиотеке: " + _preset_path.get_file())
			return

	library.presets.append(_preset)
	var err := ResourceSaver.save(library, Library.LIBRARY_PATH)
	if err != OK:
		_set_status("⚠ Не удалось сохранить библиотеку (код %d)" % err)
		return
	Fs.rescan()
	_set_status("Добавлен в библиотеку: " + _preset_path.get_file())
#endregion
