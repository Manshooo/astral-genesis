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
##   - Библиотека — путь константой, она в проекте одна.
##   - Подписи полей — локальный словарь (FIELD_LABELS), не сырые @export-
##     имена и не трюк RS_EntityTemplate с _get_property_list.
##
## Форма НАСТОЯЩАЯ рефлексивная (get_property_list, не хардкод трёх полей):
## новое скалярное @export-поле в RS_RoomPreset появится в форме само, разве
## что без перевода в FIELD_LABELS — сырое имя лучше молчаливо потерянного
## поля. scene и tags — не в общем цикле: первым распоряжается сам Wizard
## (он и есть источник scene), у второго своя вёрстка (облако чекбоксов, тот
## же приём, что у вкладки «Генератор» — presets.gd, — опечатка в
## существующем теге тогда невозможна структурно).
@tool
extends VBoxContainer

const LIBRARY_PATH := "res://data/room_preset_library.tres"

## Поля scene, tags и room_type — своя вёрстка ниже, в общий рефлексивный цикл
## не идут. Тип — выпадающий список: он у комнаты один и берётся из каталога,
## а рефлексивная форма нарисовала бы StringName нередактируемой строкой.
const CUSTOM_FIELDS := ["scene", "tags", "room_type"]
const FIELD_LABELS := {
	"display_name": "Название",
	"slot_count": "Слоты",
	"weight": "Вес",
}

var _scene_path := ""
var _preset_path := ""
var _preset: RS_RoomPreset

var _scene_label: Label
var _form_box: VBoxContainer
var _field_controls: Dictionary = {}  # имя @export-поля -> Control формы

var _known_tags: Array[StringName] = []
## Словарь тегов из библиотеки. В доке описание показывается ТОЛЬКО тултипом:
## переносящаяся подпись под каждым чипом раздула бы минимальную ширину панели
## (грабля №3 в [[Редакторские инструменты]] — она про этот док буквально).
## Читать описания глазами — во вкладке «Генератор», там для этого карточка.
var _tag_catalog: RS_RoomTagCatalog
var _tag_flow: HFlowContainer
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

	_scene_label = Label.new()
	_scene_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_scene_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_scene_label)

	add_child(HSeparator.new())

	_form_box = VBoxContainer.new()
	add_child(_form_box)

	var type_row := HBoxContainer.new()
	var type_label := _label("Тип:")
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

	add_child(_label("Теги:"))
	_tag_flow = HFlowContainer.new()
	add_child(_tag_flow)

	var new_tag_row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _on_add_tag_pressed())
	new_tag_row.add_child(_new_tag_edit)
	new_tag_row.add_child(_button("+", _on_add_tag_pressed))
	add_child(new_tag_row)

	add_child(HSeparator.new())

	# Статус ресурса — строго ОДНА строка, тот же приём, что у остальных
	# вкладок редактора (см. [[Редакторские инструменты]]): длинный путь иначе
	# перекладывает вёрстку под собой.
	_resource_status = Label.new()
	_resource_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_resource_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_resource_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_resource_status)

	_save_btn = _button("Сохранить как Room-ресурс", _on_save_pressed)
	add_child(_save_btn)

	_add_to_library_btn = _button("Добавить в библиотеку", _on_add_to_library_pressed)
	add_child(_add_to_library_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)

	_set_active(false)


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


func _set_status(text: String) -> void:
	_status.text = text
	_status.tooltip_text = text
#endregion


#region Реакция на смену сцены
## Зовёт EditorPlugin на scene_changed (см. plugin.gd) — этот узел сам не
## подписан на редактор, у обычного Control нет доступа к такому сигналу.
func refresh_for_scene(scene_root: Node) -> void:
	_preset = null
	_field_controls.clear()

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

	_collect_known_tags()
	_rebuild_type_options()
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
	_tag_flow.visible = active
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
## же принцип, что у оверлеев «Генератора мира» и облака тегов «Генератора»
## (presets.gd) — отложенное удаление копило бы старые контролы поверх новых
## при быстром переключении вкладок сцены в редакторе.
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

	_rebuild_tag_chips()


func _add_field_row(prop: Dictionary) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = FIELD_LABELS.get(prop.name, prop.name)
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
			var spin := SpinBox.new()
			spin.min_value = 0
			spin.max_value = 12
			spin.step = 1
			spin.value = _preset.get(prop.name)
			spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			control = spin
		TYPE_FLOAT:
			var spin_f := SpinBox.new()
			spin_f.min_value = 0.0
			spin_f.max_value = 10.0
			spin_f.step = 0.1
			spin_f.value = _preset.get(prop.name)
			spin_f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			control = spin_f
		_:
			# Тип, который форма ещё не умеет рисовать — появится, когда в
			# RS_RoomPreset заведут поле такого типа. Честно показать
			# значение текстом лучше, чем молча сделать вид, что поля нет.
			var raw := Label.new()
			raw.text = str(_preset.get(prop.name))
			control = raw

	row.add_child(control)
	_form_box.add_child(row)
	_field_controls[prop.name] = control


## Список типов помещений из каталога библиотеки. Тип, который у пресета уже
## стоит, но каталогу неизвестен, дописывается отдельным пунктом — иначе
## сохранение молча стёрло бы авторскую правку, подставив первый пункт.
func _rebuild_type_options() -> void:
	var library := ResourceLoader.load(LIBRARY_PATH) as RS_RoomPresetLibrary
	var catalog := library.type_catalog if library else null

	_type_ids = [&""]
	if catalog:
		_type_ids.append_array(catalog.ids())
	if _preset and _preset.room_type != &"" and not _type_ids.has(_preset.room_type):
		_type_ids.append(_preset.room_type)

	_type_option.clear()
	for id: StringName in _type_ids:
		var label := catalog.label_of(id) if catalog else ("—" if id == &"" else String(id))
		if id != &"" and (catalog == null or catalog.by_id(id) == null):
			label += " (нет в каталоге)"
		_type_option.add_item(label)

	var index := _type_ids.find(_preset.room_type) if _preset else 0
	_type_option.select(index if index >= 0 else 0)


## Переносит значения из формы в _preset. Зовётся перед сохранением, а не
## держит _preset синхронизированным на каждое нажатие клавиши — дешевле и
## ничего не теряет, потому что сохраняем мы только по кнопке.
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
## Тот же сбор, что у presets.gd._collect_known_tags — своя копия, а не общий
## код: вкладка и док самодостаточны (см. [[Единый редактор геймдизайна]]).
func _collect_known_tags() -> void:
	var library := ResourceLoader.load(LIBRARY_PATH) as RS_RoomPresetLibrary
	_tag_catalog = library.tag_catalog if library else null
	var seen := {}
	if library:
		for p: RS_RoomPreset in library.presets:
			if p == null:
				continue
			for tag: StringName in p.tags:
				seen[tag] = true
		if library.fallback:
			for tag: StringName in library.fallback.tags:
				seen[tag] = true
	# Теги из словаря — тоже: заведённый, но ещё никем не носимый тег иначе не
	# показался бы в облаке, и завести его было бы негде, кроме как опечаткой.
	if _tag_catalog:
		for id: StringName in _tag_catalog.ids():
			seen[id] = true

	var result: Array[StringName] = []
	for tag: StringName in seen.keys():
		result.append(tag)
	result.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_known_tags = result


func _rebuild_tag_chips() -> void:
	for child: Node in _tag_flow.get_children():
		child.free()
	if _preset == null:
		return
	for tag: StringName in _known_tags:
		var chip := CheckBox.new()
		chip.text = String(tag)
		chip.button_pressed = _preset.tags.has(tag)
		chip.tooltip_text = _tag_tooltip(tag)
		chip.toggled.connect(_on_tag_chip_toggled.bind(tag))
		_tag_flow.add_child(chip)


## Описание тега из словаря — или прямая просьба его завести: тег без описания
## неотличим от опечатки, и молчать об этом хуже, чем показать пустой тултип.
func _tag_tooltip(tag: StringName) -> String:
	if _tag_catalog == null:
		return ""
	var description := _tag_catalog.description_of(tag)
	if description != "":
		return description
	return "Нет описания. Заведи его во вкладке «Геймдизайн» → «Генератор» → словарь тегов."


func _on_tag_chip_toggled(pressed: bool, tag: StringName) -> void:
	if pressed:
		if not _preset.tags.has(tag):
			_preset.tags.append(tag)
	elif _preset.tags.has(tag):
		_preset.tags.erase(tag)


func _on_add_tag_pressed() -> void:
	var tag := _tagify(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag == &"":
		return
	if not _known_tags.has(tag):
		_known_tags.append(tag)
		_known_tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_register_tag(tag)
	if not _preset.tags.has(tag):
		_preset.tags.append(tag)
	_rebuild_tag_chips()


## Новый тег заводится в словаре СРАЗУ, а не когда для него напишут описание:
## инвариант «каждый тег пресетов есть в словаре» держит dev/room_tags_check и
## только на нём и работает отличие настоящего тега от опечатки. Описание
## пишется во вкладке «Генератор» — здесь для него нет места.
func _register_tag(tag: StringName) -> void:
	if _tag_catalog == null or _tag_catalog.has_id(tag):
		return
	_tag_catalog.add_id(tag)
	var path := _tag_catalog.resource_path
	if path != "":
		ResourceSaver.save(_tag_catalog, path)


## Тот же приём, что в presets.gd — теги ASCII-идентификаторов, кириллица не
## нужна (не текст для игрока, ключ RS_LevelNode.tags/RS_RoomPreset.tags).
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


#region Сохранение
func _on_save_pressed() -> void:
	if _preset == null or _scene_path == "":
		return
	_apply_form_to_preset()
	_preset.scene = ResourceLoader.load(_scene_path, "", ResourceLoader.CACHE_MODE_REPLACE) as PackedScene
	if not ResourceLoader.exists(_preset_path):
		_preset.take_over_path(_preset_path)
	var err := ResourceSaver.save(_preset, _preset_path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	_rescan_filesystem()
	_resource_status.text = "Сохранён: " + _preset_path.get_file()
	_add_to_library_btn.disabled = false
	_set_status("Сохранено: " + _preset_path.get_file())


func _on_add_to_library_pressed() -> void:
	if _preset == null or not ResourceLoader.exists(_preset_path):
		_set_status("⚠ Сначала сохрани ресурс.")
		return
	var library := ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary
	if library == null:
		_set_status("⚠ Не удалось загрузить библиотеку.")
		return
	for existing: RS_RoomPreset in library.presets:
		if existing and existing.resource_path == _preset_path:
			_set_status("Уже в библиотеке: " + _preset_path.get_file())
			return

	library.presets.append(_preset)
	var err := ResourceSaver.save(library, LIBRARY_PATH)
	if err != OK:
		_set_status("⚠ Не удалось сохранить библиотеку (код %d)" % err)
		return
	_rescan_filesystem()
	_set_status("Добавлен в библиотеку: " + _preset_path.get_file())


func _rescan_filesystem() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs != null:
		fs.scan()
#endregion
