## res://addons/game_design_tool/tabs/world_gen.gd
## Вкладка «Генератор мира» единого редактора геймдизайна: 3D-превью текущего
## слоя комплекса. Прогоняет ТОТ ЖЕ генератор (RS_LevelGraph.generate_run) и ТУ
## ЖЕ раскладку (RS_LayerPlan.build), что и игра — см.
## [[world-generator-tool-spec]] и [[Цикл забега]]. Отрисовкой и пикингом
## занимается GDT_ViewportHost (viewport_host.gd); эта вкладка — панель
## управления и боковая панель узла вокруг него.
##
## Глубина слоя и набор оверлеев — РАЗНЫЕ ручки: глубина фильтрует область (что
## показываем), оверлеи — способ отрисовки (как показываем). Слово «слой» здесь
## не используется вовсе — оно занято глубиной комплекса (depth, L0..L4) в
## остальном проекте.
##
## Пересборка — только по явной кнопке. Генерация инстанцирует реальные сцены
## комнат (см. GDT_RoomsOverlay), автоперегенерация на каждое изменение сида
## пересобирала бы слой на каждый тик спинбокса.
@tool
extends VBoxContainer

const TAB_TITLE := "Генератор мира"
const LIBRARY_PATH := "res://data/room_preset_library.tres"

## EditorSettings.set_project_metadata — тот самый пробел из [[Единый редактор
## геймдизайна]] («Решено, но не реализовано» в MVP): сид/глубина/оверлеи/
## камера переживают перезапуск редактора. Метаданные ПРОЕКТА, не установки
## Godot — у другого проекта своя генерация, чужой сид тут бессмысленен.
const SETTINGS_SECTION := "world_gen_tool"

const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")

var _seed_spin: SpinBox
var _depth_option: OptionButton
var _visibility_menu: MenuButton
var _status: Label
var _host: ViewportHost
var _info_label: RichTextLabel
var _open_preset_btn: Button
var _open_scene_btn: Button

## Инлайн-редактор пресета выделенного узла (v3-стретч) — прямо здесь, без
## похода на вкладку «Генератор» или в инспектор. Виден, только когда у узла
## есть сцена, для которой в библиотеке нашёлся пресет (_preset_for).
var _preset_section: VBoxContainer
var _preset_label: Label
var _slot_spin: SpinBox
var _weight_spin: SpinBox
var _tag_flow: HFlowContainer
var _new_tag_edit: LineEdit
var _known_tags: Array[StringName] = []
## Словарь тегов из библиотеки. Здесь, как и в доке Room Wizard, описание живёт
## тултипом: секция узла — приложение к 3D-превью, и отдавать её половину под
## текст описаний неправильно. Читать их глазами — во вкладке «Генератор».
var _tag_catalog: RS_RoomTagCatalog
## Пресет, который сейчас редактируется секцией выше — держим отдельно от
## _selected_node_data().preset, чтобы обработчики полей не искали его заново
## на каждое изменение спинбокса.
var _editing_preset: RS_RoomPreset

var _graph: RS_LevelGraph
var _library: RS_RoomPresetLibrary
var _loaded := false


func _init() -> void:
	name = TAB_TITLE
	_build_ui()


## Первую генерацию откладываем до первого показа вкладки — как и «Генератор»,
## строить слой (реальные сцены комнат) ради вкладки, которую могут не открыть
## за сессию, незачем.
func _ready() -> void:
	visibility_changed.connect(_on_visibility_changed)
	_on_visibility_changed()


func _on_visibility_changed() -> void:
	if not _loaded and is_visible_in_tree():
		_loaded = true
		RS_RoomLayout.clear_scene_cache()
		_restore_state()


#region UI
func _build_ui() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	add_child(_build_toolbar())

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	_host = ViewportHost.new()
	_host.node_picked.connect(_on_node_picked)
	split.add_child(_host)
	split.add_child(_build_side_panel())
	split.split_offset = -320  # боковая панель у правого края, вьюпорту — остальное

	_status = Label.new()
	# Строго ОДНА строка с многоточием, а не autowrap — см. [[Редакторские
	# инструменты]]: длинный путь ресурса иначе перекладывает вёрстку под собой.
	_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.modulate = Color(1, 1, 1, 0.7)
	add_child(_status)


func _build_toolbar() -> Control:
	var row := HBoxContainer.new()

	row.add_child(_label("Сид:"))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 999999
	_seed_spin.step = 1
	_seed_spin.value = 0
	row.add_child(_seed_spin)
	row.add_child(_button("Случайный", _on_random_seed_pressed))
	row.add_child(_button("Пересобрать", _on_rebuild_pressed))

	row.add_child(VSeparator.new())

	row.add_child(_label("Глубина:"))
	_depth_option = OptionButton.new()
	for depth: int in RS_LevelGraph.DEPTHS:
		_depth_option.add_item("L%d" % depth, depth)
	_depth_option.select(_depth_option.get_item_index(RS_LevelGraph.HOME_DEPTH))
	_depth_option.item_selected.connect(_on_depth_selected)
	row.add_child(_depth_option)

	row.add_child(VSeparator.new())
	row.add_child(_build_visibility_menu())
	row.add_child(VSeparator.new())

	# Отдельная кнопка, а не побочный эффект СКМ: раньше камера «доезжала» до
	# осмысленного вида неявно при первой же орбите без выделения — из-за
	# устаревшей дистанции автокадрирования получался разброс, который
	# выглядел как «сброс в начало координат» (см. GDT_ViewportHost.
	# _orbit_pivot_hint). Явная кнопка предсказуема и не привязана к жесту.
	row.add_child(_button("Сбросить вид", _on_reset_view_pressed))

	return row


func _build_side_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)

	panel.add_child(_label("Узел"))

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.selection_enabled = true
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_info_label)

	panel.add_child(HSeparator.new())
	panel.add_child(_build_preset_section())
	panel.add_child(HSeparator.new())

	_open_preset_btn = _button("Открыть пресет", _on_open_preset_pressed)
	panel.add_child(_open_preset_btn)
	_open_scene_btn = _button("Открыть сцену", _on_open_scene_pressed)
	panel.add_child(_open_scene_btn)

	_clear_selection()
	return panel


## Слоты/вес/теги ПРЕСЕТА выделенного узла — редактируются прямо здесь, тем же
## приёмом (чекбоксы облака тегов, сохранение на каждое изменение), что и
## вкладка «Генератор» (presets.gd) и Room Wizard (dock/room_wizard.gd). Не то
## же самое, что «Теги узла» в _info_label выше: node_data.tags — структурные
## требования УЗЛА графа (их проставляет генератор), preset.tags — способности
## РЕСУРСА комнаты; путать их нельзя, поэтому секции визуально разделены.
func _build_preset_section() -> Control:
	_preset_section = VBoxContainer.new()

	_preset_label = Label.new()
	_preset_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_preset_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_preset_section.add_child(_preset_label)

	var slot_row := HBoxContainer.new()
	slot_row.add_child(_label("Слоты:"))
	_slot_spin = SpinBox.new()
	_slot_spin.min_value = 0
	_slot_spin.max_value = 12
	_slot_spin.step = 1
	_slot_spin.value_changed.connect(_on_slot_changed)
	slot_row.add_child(_slot_spin)
	_preset_section.add_child(slot_row)

	var weight_row := HBoxContainer.new()
	weight_row.add_child(_label("Вес:"))
	_weight_spin = SpinBox.new()
	_weight_spin.min_value = 0.0
	_weight_spin.max_value = 10.0
	_weight_spin.step = 0.1
	_weight_spin.value_changed.connect(_on_weight_changed)
	weight_row.add_child(_weight_spin)
	_preset_section.add_child(weight_row)

	_preset_section.add_child(_label("Теги пресета:"))
	_tag_flow = HFlowContainer.new()
	_preset_section.add_child(_tag_flow)

	var new_tag_row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _on_add_tag_pressed())
	new_tag_row.add_child(_new_tag_edit)
	new_tag_row.add_child(_button("+", _on_add_tag_pressed))
	_preset_section.add_child(new_tag_row)

	return _preset_section


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


func _on_reset_view_pressed() -> void:
	_host.frame_layer()


## Выпадающее меню, а не чекбоксы в ряд: чекбоксов уже три и будет больше
## («Двери» — заявленный, но пока не построенный четвёртый оверлей, см.
## overlay_registry.gd), а в панели инструментов место не резиновое. Пункты —
## циклом по реестру, тот же принцип, что и раньше: новый оверлей — строка в
## OverlayRegistry.OVERLAYS, а не правка этого кода.
func _build_visibility_menu() -> MenuButton:
	_visibility_menu = MenuButton.new()
	_visibility_menu.text = "Видимость"
	_visibility_menu.tooltip_text = "Переключает видимость отображаемых слоёв"

	var popup := _visibility_menu.get_popup()
	for i in OverlayRegistry.OVERLAYS.size():
		var overlay: Dictionary = OverlayRegistry.OVERLAYS[i]
		popup.add_check_item(overlay["title"], i)
		var idx := popup.get_item_index(i)
		popup.set_item_checked(idx, overlay["default_visible"])
		popup.set_item_tooltip(idx, overlay["tooltip"])
	popup.id_pressed.connect(_on_visibility_item_pressed)

	return _visibility_menu


## PopupMenu не переключает check-пункт сам — состояние ведём руками и тут же
## применяем к вьюпорту, тем же id, каким пункт заведён (порядковый номер в
## OverlayRegistry.OVERLAYS).
func _on_visibility_item_pressed(id: int) -> void:
	var popup := _visibility_menu.get_popup()
	var idx := popup.get_item_index(id)
	var new_state := not popup.is_item_checked(idx)
	popup.set_item_checked(idx, new_state)
	var overlay: Dictionary = OverlayRegistry.OVERLAYS[id]
	_host.set_overlay_visible(overlay["id"], new_state)
	_set_meta("overlay_" + String(overlay["id"]), new_state)
#endregion


#region Генерация
func _on_random_seed_pressed() -> void:
	_seed_spin.value = randi() % 1000000


func _on_rebuild_pressed() -> void:
	# Дизайнер мог поправить сцену комнаты (дверь, положение) с прошлой
	# пересборки — без сброса тул продолжит показывать старую раскладку
	# (см. RS_RoomLayout.clear_scene_cache).
	RS_RoomLayout.clear_scene_cache()
	_rebuild_graph()


## Восстанавливает сид/глубину/видимость оверлеев ДО генерации, камеру —
## ПОСЛЕ (см. дальше почему), и только тогда подписывается на camera_changed.
## Порядок важен: _rebuild_graph → _rebuild_layer → ViewportHost.show_layer
## сама кадрирует камеру на весь слой (frame_layer, см. viewport_host.gd) и
## эмитит camera_changed — подпишись раньше, и это автокадрирование тут же
## перезаписало бы в EditorSettings ЕЩЁ НЕ ПРИМЕНЁННУЮ сохранённую позицию,
## прежде чем restore_camera успеет её поставить.
func _restore_state() -> void:
	_seed_spin.value = _get_meta("seed", 0)

	var depth: int = _get_meta("depth", RS_LevelGraph.HOME_DEPTH)
	var depth_idx := _depth_option.get_item_index(depth)
	if depth_idx >= 0:
		_depth_option.select(depth_idx)

	var popup := _visibility_menu.get_popup()
	for i in OverlayRegistry.OVERLAYS.size():
		var overlay: Dictionary = OverlayRegistry.OVERLAYS[i]
		var visible_state: bool = _get_meta("overlay_" + String(overlay["id"]), overlay["default_visible"])
		popup.set_item_checked(popup.get_item_index(i), visible_state)
		_host.set_overlay_visible(overlay["id"], visible_state)

	_rebuild_graph()

	if _get_meta("camera_saved", false):
		var pos: Vector3 = _get_meta("camera_position", Vector3.ZERO)
		var rot: Vector3 = _get_meta("camera_rotation", Vector3.ZERO)
		_host.restore_camera(pos, rot)

	_host.camera_changed.connect(_on_camera_changed)


func _on_camera_changed() -> void:
	_set_meta("camera_position", _host.camera_position())
	_set_meta("camera_rotation", _host.camera_rotation_degrees())
	_set_meta("camera_saved", true)


## EditorSettings — редакторский API: за пределами настоящего работающего
## редактора (в т.ч. в headless-прогонах dev/world_gen_tool_check.gd, где
## Engine.is_editor_hint() ложно — это ИГРОВОЙ прогон сцены, не редактор)
## singleton не инициализирован и звать его незачем — состояние заведомо
## некому будет читать между сессиями редактора, которых не было. Тот же
## приём, каким e_body_crawler.gd отсекает физическую симуляцию в редакторе.
func _get_meta(key: String, default: Variant) -> Variant:
	if not Engine.is_editor_hint():
		return default
	# set_project_metadata/get_project_metadata — методы ЭКЗЕМПЛЯРА синглтона
	# (не статика класса EditorSettings) — только через EditorInterface.
	return EditorInterface.get_editor_settings().get_project_metadata(SETTINGS_SECTION, key, default)


func _set_meta(key: String, value: Variant) -> void:
	if not Engine.is_editor_hint():
		return
	EditorInterface.get_editor_settings().set_project_metadata(SETTINGS_SECTION, key, value)


func _rebuild_graph() -> void:
	_library = ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + LIBRARY_PATH)
		return
	var run_seed := int(_seed_spin.value)
	_graph = RS_LevelGraph.new().generate_run(run_seed, _library)
	_rebuild_layer()
	_set_status("Сид %d, узлов в графе: %d" % [run_seed, _graph.nodes.size()])
	_set_meta("seed", run_seed)


func _current_depth() -> int:
	var idx := _depth_option.selected
	if idx < 0:
		return RS_LevelGraph.HOME_DEPTH
	return _depth_option.get_item_id(idx)


func _on_depth_selected(_index: int) -> void:
	_rebuild_layer()
	_set_meta("depth", _current_depth())


func _rebuild_layer() -> void:
	if _graph == null:
		return
	var depth := _current_depth()
	var layer_nodes := _graph.get_nodes_by_depth(depth)
	var plan := RS_LayerPlan.build(layer_nodes)
	_host.show_layer(_graph, layer_nodes, plan, _preset_labels_for(layer_nodes))
	_clear_selection()


## node_id -> имя пресета, для оверлея «Подписи». Тот же поиск, что
## _preset_for уже делает для одного узла (инлайн-редактор) — здесь просто
## для всех узлов слоя разом, до того как их отрисует ViewportHost.
func _preset_labels_for(layer_nodes: Array[RS_LevelNode]) -> Dictionary:
	var labels := {}
	for node_data: RS_LevelNode in layer_nodes:
		var preset := _preset_for(node_data)
		labels[node_data.id] = _label_of(preset) if preset else ""
	return labels
#endregion


#region Выделение
func _on_node_picked(node_id: StringName) -> void:
	if node_id == &"" or _graph == null:
		_clear_selection()
		return
	var node_data := _graph.get_node_data(node_id)
	if node_data == null:
		_clear_selection()
		return
	_info_label.text = _node_report(node_data)
	_open_scene_btn.disabled = (
		node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path)
	)

	_editing_preset = _preset_for(node_data)
	_open_preset_btn.disabled = _editing_preset == null
	_preset_section.visible = _editing_preset != null
	if _editing_preset:
		_collect_known_tags()
		_fill_preset_section()


func _clear_selection() -> void:
	_info_label.text = "[i]Кликни по комнате во вьюпорте.[/i]"
	_open_preset_btn.disabled = true
	_open_scene_btn.disabled = true
	_editing_preset = null
	_preset_section.visible = false


func _node_report(node_data: RS_LevelNode) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % node_data.id)
	lines.append(
		"Глубина L%d, этаж %d, индекс %d"
		% [node_data.depth, node_data.floor_index, node_data.index_in_layer]
	)
	lines.append("Рёбер: %d" % node_data.connections.size())
	if not node_data.tags.is_empty():
		lines.append("Теги: " + ", ".join(node_data.tags))
	# Отдельной строкой от тегов — намеренно: это ДРУГАЯ ось подбора, и слитый
	# с тегами тип ровно тем и путал бы, чего разведение осей избегает.
	# После генерации здесь тип фактически вставшей комнаты, а не загаданный.
	lines.append("Тип: " + _room_type_label(node_data.room_type))
	lines.append("Сцена: " + (node_data.room_scene_path if node_data.room_scene_path != "" else "—"))

	if not node_data.connections.is_empty():
		lines.append("")
		lines.append("[b]Связи[/b]")
		for conn: RS_LevelConnection in node_data.connections:
			var lock_note := " 🔒" if conn.is_locked() else ""
			lines.append(
				"  → %s (%s)%s"
				% [conn.target_node_id, RS_LevelConnection.Type.keys()[conn.type], lock_note]
			)

	return "\n".join(lines)


## Тот же поиск, что presets.gd делает при показе «что выпало»: пресет по
## совпадению пути сцены — обратной ссылки «узел → пресет» в данных нет.
## library.hub — тоже кандидат: хаб (домашний узел) теперь имеет свой
## RS_RoomPreset (hub.tres), просто вне пула автоподбора (см.
## RS_RoomPresetLibrary.hub) — секция инлайн-редактора должна узнавать его
## так же, как любой другой узел с пресетом, не только узлы из .presets.
func _room_type_label(id: StringName) -> String:
	var catalog := _library.type_catalog if _library else null
	if catalog:
		return catalog.label_of(id)
	return "—" if id == &"" else String(id)


func _preset_for(node_data: RS_LevelNode) -> RS_RoomPreset:
	if _library == null or node_data.room_scene_path == "":
		return null
	for preset: RS_RoomPreset in _library.presets:
		if preset and preset.scene and preset.scene.resource_path == node_data.room_scene_path:
			return preset
	if (
		_library.fallback
		and _library.fallback.scene
		and _library.fallback.scene.resource_path == node_data.room_scene_path
	):
		return _library.fallback
	if (
		_library.hub
		and _library.hub.scene
		and _library.hub.scene.resource_path == node_data.room_scene_path
	):
		return _library.hub
	return null


func _on_open_preset_pressed() -> void:
	var node_data := _selected_node_data()
	if node_data == null:
		return
	var preset := _preset_for(node_data)
	if preset:
		EditorInterface.edit_resource(preset)


func _on_open_scene_pressed() -> void:
	var node_data := _selected_node_data()
	if node_data == null or node_data.room_scene_path == "":
		return
	EditorInterface.open_scene_from_path(node_data.room_scene_path)


func _selected_node_data() -> RS_LevelNode:
	if _graph == null:
		return null
	return _graph.get_node_data(_host.selected_node_id())
#endregion


#region Инлайн-редактор пресета (v3-стретч)
## Пока идёт программное заполнение полей — value_changed на SpinBox иначе
## тут же перечитывал бы то же значение обратно и сохранял ресурс без
## реальной правки, на каждый клик по узлу.
var _filling_preset_section := false


func _fill_preset_section() -> void:
	_filling_preset_section = true
	_preset_label.text = _label_of(_editing_preset)
	_preset_label.tooltip_text = _editing_preset.resource_path
	_slot_spin.value = _editing_preset.slot_count
	_weight_spin.value = _editing_preset.weight
	_rebuild_tag_chips()
	_filling_preset_section = false


func _on_slot_changed(value: float) -> void:
	if _filling_preset_section or _editing_preset == null:
		return
	_editing_preset.slot_count = int(value)
	_save_editing_preset()


func _on_weight_changed(value: float) -> void:
	if _filling_preset_section or _editing_preset == null:
		return
	_editing_preset.weight = value
	_save_editing_preset()


## Тот же сбор, что у presets.gd._collect_known_tags и room_wizard.gd — своя
## копия, не общий код: инструменты этого редактора самодостаточны (см.
## [[Единый редактор геймдизайна]]).
func _collect_known_tags() -> void:
	_tag_catalog = _library.tag_catalog if _library else null
	var seen := {}
	if _library:
		for p: RS_RoomPreset in _library.presets:
			if p == null:
				continue
			for tag: StringName in p.tags:
				seen[tag] = true
		if _library.fallback:
			for tag: StringName in _library.fallback.tags:
				seen[tag] = true
	# Теги словаря — тоже: заведённый, но ещё никем не носимый тег иначе не
	# показался бы в облаке (см. presets.gd._collect_known_tags).
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
	if _editing_preset == null:
		return
	for tag: StringName in _known_tags:
		var chip := CheckBox.new()
		chip.text = String(tag)
		chip.button_pressed = _editing_preset.tags.has(tag)
		chip.tooltip_text = _tag_tooltip(tag)
		chip.toggled.connect(_on_tag_chip_toggled.bind(tag))
		_tag_flow.add_child(chip)


## Описание тега из словаря — или прямая просьба его завести: тег без описания
## неотличим от опечатки (см. presets.gd, там же он и заводится).
func _tag_tooltip(tag: StringName) -> String:
	if _tag_catalog == null:
		return ""
	var description := _tag_catalog.description_of(tag)
	if description != "":
		return description
	return "Нет описания. Заведи его во вкладке «Генератор» → словарь тегов."


func _on_tag_chip_toggled(pressed: bool, tag: StringName) -> void:
	if _editing_preset == null:
		return
	if pressed:
		if not _editing_preset.tags.has(tag):
			_editing_preset.tags.append(tag)
	elif _editing_preset.tags.has(tag):
		_editing_preset.tags.erase(tag)
	_save_editing_preset()


func _on_add_tag_pressed() -> void:
	var tag := _tagify(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag == &"" or _editing_preset == null:
		return
	if not _known_tags.has(tag):
		_known_tags.append(tag)
		_known_tags.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	_register_tag(tag)
	if not _editing_preset.tags.has(tag):
		_editing_preset.tags.append(tag)
	_rebuild_tag_chips()
	_save_editing_preset()


## Новый тег заводится в словаре СРАЗУ — инвариант «каждый тег пресетов есть в
## словаре» держит dev/room_tags_check, и только на нём работает отличие
## настоящего тега от опечатки. Описание пишется во вкладке «Генератор».
func _register_tag(tag: StringName) -> void:
	if _tag_catalog == null or _tag_catalog.has_id(tag):
		return
	_tag_catalog.add_id(tag)
	var path := _tag_catalog.resource_path
	if path != "":
		ResourceSaver.save(_tag_catalog, path)


## Тот же приём, что в presets.gd/room_wizard.gd — теги ASCII-идентификаторов,
## кириллица не нужна (не текст для игрока, ключ RS_RoomPreset.tags).
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


func _save_editing_preset() -> void:
	var err := ResourceSaver.save(_editing_preset, _editing_preset.resource_path)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	_set_status("Сохранено: " + _editing_preset.resource_path.get_file())


func _label_of(preset: RS_RoomPreset) -> String:
	if preset.display_name != "":
		return preset.display_name
	return preset.resource_path.get_file().get_basename()
#endregion
