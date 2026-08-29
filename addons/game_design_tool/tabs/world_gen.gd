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
##
## Здесь же живёт «Прогон сидов» — статистика подбора по N сидам, приехавшая из
## вкладки пресетов. Оба инструмента отвечают на один вопрос «что генератор
## выдаёт», только с разного расстояния: превью — про ОДИН слой одного сида,
## прогон — про выборку из многих; разводить их по вкладкам значило заставлять
## переключаться между вопросом и его же ответом в цифрах.
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const TagCloud := preload("res://addons/game_design_tool/shared/tag_cloud.gd")
const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")

const TAB_TITLE := "Генератор мира"

## EditorSettings.set_project_metadata — тот самый пробел из [[Единый редактор
## геймдизайна]] («Решено, но не реализовано» в MVP): сид/глубина/оверлеи/
## камера переживают перезапуск редактора. Метаданные ПРОЕКТА, не установки
## Godot — у другого проекта своя генерация, чужой сид тут бессмысленен.
const SETTINGS_SECTION := "world_gen_tool"

## Куда идти писать описание тега — текст для тултипов облака.
const TAG_HINT_WHERE := "вкладке «Редактор пресетов» → словарь тегов"

var _seed_spin: SpinBox
var _depth_option: OptionButton
var _visibility_menu: MenuButton
var _status: Label

## Прогон сидов: панель внизу, по умолчанию свёрнута. Живёт здесь, а не во
## вкладке пресетов, где была раньше: «что реально выпадает в забеге» — вопрос
## про мир, а не про отдельный пресет, и смотреть ответ правильно там, где этот
## мир видно. Свёрнута по умолчанию, потому что 3D-превью — главное содержимое
## вкладки, а отчёт нужен раз в несколько правок.
var _seeds_panel: VBoxContainer
var _seeds_toggle: Button
var _seeds_spin: SpinBox
var _seeds_report: RichTextLabel
var _host: ViewportHost
var _info_label: RichTextLabel
var _open_preset_btn: Button
var _open_scene_btn: Button

## Инлайн-редактор пресета выделенного узла (v3-стретч) — прямо здесь, без
## похода на вкладку «Редактор пресетов» или в инспектор. Виден, только когда
## у узла есть сцена, для которой в библиотеке нашёлся пресет.
var _preset_section: VBoxContainer
var _preset_label: Label
var _slot_spin: SpinBox
var _weight_spin: SpinBox
## Облако тегов — общий GDT_TagCloud, тот же, что в доке Room Wizard: описание
## живёт тултипом, потому что секция узла — приложение к 3D-превью, и отдавать
## её половину под текст описаний неправильно. Читать их глазами — во вкладке
## «Редактор пресетов».
var _tag_cloud: TagCloud
var _new_tag_edit: LineEdit
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


## Первую генерацию откладываем до первого показа вкладки — как и «Редактор
## пресетов»: строить слой (реальные сцены комнат) ради вкладки, которую могут
## не открыть за сессию, незачем.
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

	# Вертикальный сплит: превью сверху, отчёт прогона снизу. Панель отчёта
	# скрыта — SplitContainer со скрытым вторым ребёнком отдаёт всю высоту
	# первому, поэтому свёрнутый прогон не отъедает у вьюпорта ничего.
	var rows := VSplitContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(rows)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(split)
	rows.add_child(_build_seeds_panel())

	_host = ViewportHost.new()
	_host.node_picked.connect(_on_node_picked)
	split.add_child(_host)
	split.add_child(_build_side_panel())
	split.split_offset = -320  # боковая панель у правого края, вьюпорту — остальное

	_status = Ui.status_label()
	add_child(_status)


func _build_toolbar() -> Control:
	var row := HBoxContainer.new()

	row.add_child(Ui.label("Сид:"))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = 999999
	_seed_spin.step = 1
	_seed_spin.value = 0
	row.add_child(_seed_spin)
	row.add_child(Ui.button("Случайный", _on_random_seed_pressed))
	row.add_child(Ui.button("Пересобрать", _on_rebuild_pressed))

	row.add_child(VSeparator.new())

	row.add_child(Ui.label("Глубина:"))
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
	row.add_child(Ui.button("Сбросить вид", _on_reset_view_pressed))

	row.add_child(VSeparator.new())
	_seeds_toggle = Button.new()
	_seeds_toggle.text = "Прогон сидов"
	_seeds_toggle.toggle_mode = true
	_seeds_toggle.tooltip_text = (
		"Статистика подбора по N сидам: что выпало и почему остальные пресеты отсеялись"
	)
	_seeds_toggle.toggled.connect(_on_seeds_toggled)
	row.add_child(_seeds_toggle)

	return row


## Панель прогона. Отдельный сид у неё не спрашивается намеренно: прогон гоняет
## сиды 0..N-1 и отвечает на статистический вопрос «что вообще выпадает», а сид
## в тулбаре — про КОНКРЕТНЫЙ слой во вьюпорте. Связать их одним полем значило
## бы смешать разбор одного забега с выборкой по многим.
func _build_seeds_panel() -> Control:
	_seeds_panel = VBoxContainer.new()
	_seeds_panel.visible = false
	_seeds_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_child(Ui.label("Сидов:"))
	_seeds_spin = SpinBox.new()
	_seeds_spin.min_value = 1
	_seeds_spin.max_value = 200
	_seeds_spin.value = 30
	row.add_child(_seeds_spin)
	var run := Ui.button("Прогнать", _on_preview_pressed)
	run.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(run)
	_seeds_panel.add_child(row)

	_seeds_report = Ui.report_label(140)
	_seeds_panel.add_child(_seeds_report)
	return _seeds_panel


func _on_seeds_toggled(pressed: bool) -> void:
	_seeds_panel.visible = pressed
	_set_meta("seeds_panel", pressed)


func _build_side_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)

	panel.add_child(Ui.label("Узел"))

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.selection_enabled = true
	_info_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_info_label)

	panel.add_child(HSeparator.new())
	panel.add_child(_build_preset_section())
	panel.add_child(HSeparator.new())

	_open_preset_btn = Ui.button("Открыть пресет", _on_open_preset_pressed)
	panel.add_child(_open_preset_btn)
	_open_scene_btn = Ui.button("Открыть сцену", _on_open_scene_pressed)
	panel.add_child(_open_scene_btn)

	_clear_selection()
	return panel


## Слоты/вес/теги ПРЕСЕТА выделенного узла — редактируются прямо здесь, тем же
## приёмом, что и вкладка «Редактор пресетов» (presets.gd) и Room Wizard
## (room_wizard.gd). Не то же самое, что «Теги узла» в _info_label выше:
## node_data.tags — структурные требования УЗЛА графа (их проставляет
## генератор), preset.tags — способности РЕСУРСА комнаты; путать их нельзя,
## поэтому секции визуально разделены.
func _build_preset_section() -> Control:
	_preset_section = VBoxContainer.new()

	_preset_label = Ui.ellipsis_label()
	_preset_section.add_child(_preset_label)

	var slot_row := HBoxContainer.new()
	slot_row.add_child(Ui.label("Слоты:"))
	_slot_spin = SpinBox.new()
	_slot_spin.min_value = 0
	_slot_spin.max_value = 12
	_slot_spin.step = 1
	_slot_spin.value_changed.connect(_on_slot_changed)
	slot_row.add_child(_slot_spin)
	_preset_section.add_child(slot_row)

	var weight_row := HBoxContainer.new()
	weight_row.add_child(Ui.label("Вес:"))
	_weight_spin = SpinBox.new()
	_weight_spin.min_value = 0.0
	_weight_spin.max_value = 10.0
	_weight_spin.step = 0.1
	_weight_spin.value_changed.connect(_on_weight_changed)
	weight_row.add_child(_weight_spin)
	_preset_section.add_child(weight_row)

	_preset_section.add_child(Ui.label("Теги пресета:"))
	_tag_cloud = TagCloud.new(TAG_HINT_WHERE)
	_tag_cloud.preset_changed.connect(_save_editing_preset)
	_preset_section.add_child(_tag_cloud)

	var new_tag_row := HBoxContainer.new()
	_new_tag_edit = LineEdit.new()
	_new_tag_edit.placeholder_text = "новый тег"
	_new_tag_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_tag_edit.text_submitted.connect(func(_t: String) -> void: _on_add_tag_pressed())
	new_tag_row.add_child(_new_tag_edit)
	new_tag_row.add_child(Ui.button("+", _on_add_tag_pressed))
	_preset_section.add_child(new_tag_row)

	return _preset_section


func _set_status(text: String) -> void:
	Ui.set_status(_status, text)


func _on_reset_view_pressed() -> void:
	_host.frame_layer()


## Выпадающее меню, а не чекбоксы в ряд: чекбоксов уже три и будет больше
## («Двери» — заявленный, но пока не построенный четвёртый оверлей, см.
## overlay_registry.gd), а в панели инструментов место не резиновое. Пункты —
## циклом по реестру: новый оверлей — строка в OverlayRegistry.OVERLAYS, а не
## правка этого кода.
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
	# button_pressed сам зовёт _on_seeds_toggled, панель встаёт вместе с кнопкой.
	_seeds_toggle.button_pressed = _get_meta("seeds_panel", false)

	var depth: int = _get_meta("depth", RS_LevelGraph.HOME_DEPTH)
	var depth_idx := _depth_option.get_item_index(depth)
	if depth_idx >= 0:
		_depth_option.select(depth_idx)

	var popup := _visibility_menu.get_popup()
	for i in OverlayRegistry.OVERLAYS.size():
		var overlay: Dictionary = OverlayRegistry.OVERLAYS[i]
		var visible_state: bool = _get_meta(
			"overlay_" + String(overlay["id"]), overlay["default_visible"]
		)
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
	_library = Library.load_library()
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + Library.LIBRARY_PATH)
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
	_host.show_layer(_layer_view(_current_depth()))
	_clear_selection()


## Слой глубины [param depth] в том виде, в каком его рисуют оверлеи: узлы,
## раскладка (та же RS_LayerPlan, что у игры) и подписи пресетов.
func _layer_view(depth: int) -> LayerView:
	var layer_nodes := _graph.get_nodes_by_depth(depth)
	return LayerView.new(
		_graph, layer_nodes, RS_LayerPlan.build(layer_nodes), _preset_labels_for(layer_nodes)
	)


## node_id -> имя пресета, для оверлея «Подписи». Тот же поиск, что
## _preset_for делает для одного узла (инлайн-редактор) — здесь просто
## для всех узлов слоя разом, до того как их отрисует ViewportHost.
func _preset_labels_for(layer_nodes: Array[RS_LevelNode]) -> Dictionary:
	var labels := {}
	for node_data: RS_LevelNode in layer_nodes:
		labels[node_data.id] = Library.label_of(_preset_for(node_data))
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


func _room_type_label(id: StringName) -> String:
	var catalog := _library.type_catalog if _library else null
	if catalog:
		return catalog.label_of(id)
	return "—" if id == &"" else String(id)


## Пресет узла — обратной ссылки «узел → пресет» в данных нет, ищем по
## совпадению пути сцены. Хаб узнаётся наравне с остальными (см.
## GDT_Library.preset_for_scene): у него тоже есть RS_RoomPreset, просто вне
## пула автоподбора.
func _preset_for(node_data: RS_LevelNode) -> RS_RoomPreset:
	return Library.preset_for_scene(_library, node_data.room_scene_path)


func _on_open_preset_pressed() -> void:
	if _editing_preset:
		EditorInterface.edit_resource(_editing_preset)


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
	_preset_label.text = Library.label_of(_editing_preset)
	_preset_label.tooltip_text = _editing_preset.resource_path
	_slot_spin.value = _editing_preset.slot_count
	_weight_spin.value = _editing_preset.weight
	# Словарный запас перечитываем на каждое выделение: библиотеку мог поправить
	# соседний инструмент или инспектор, пока вкладка была открыта.
	_tag_cloud.set_vocabulary(_library)
	_tag_cloud.show_for(_editing_preset)
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


func _on_add_tag_pressed() -> void:
	var tag := _tag_cloud.add_new(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag != &"":
		_set_status("Тег «%s» заведён и повешен." % tag)


## Зовётся и облаком тегов через preset_changed — заполнение секции его тоже
## трогает (show_for), поэтому флаг проверяем здесь, а не только в спинбоксах.
func _save_editing_preset() -> void:
	if _filling_preset_section or _editing_preset == null:
		return
	var err := Library.save_preset(_editing_preset)
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	_set_status("Сохранено: " + _editing_preset.resource_path.get_file())
#endregion


#region Прогон сидов
## Гоняет генератор по N сидам и показывает, что реально выпало и почему остальные
## пресеты отсеялись. Выбор берём из настоящего прогона (room_scene_path), причины
## отсева — из RS_RoomPresetLibrary.explain_selection: жёсткие фильтры
## (вместимость/теги/специфичность) от rng не зависят, поэтому цифры честные.
##
## Прогон НЕ трогает ни _graph, ни вьюпорт: он строит свои графы и выбрасывает
## их. Иначе кнопка «Прогнать» незаметно подменяла бы слой под камерой на
## последний из просчитанных сидов.
func _on_preview_pressed() -> void:
	if _library == null:
		_rebuild_graph()
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

	_seeds_report.text = _preview_report(seeds, nodes_total, picks, reasons, degrees)
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
		+ "его выиграл, смотри в «Что выпало». Слоты, вес и теги правятся во вкладке "
		+ "«Редактор пресетов» или в панели узла справа.[/i]"
	)
	return out


## Подпись пресета по пути сцены — для колонки «что выпало». Ищем ТЕМ ЖЕ
## поиском, что и боковая панель: пока у прогона был свой обход, он не знал про
## library.hub, и хаб отчитывался как «вне библиотеки» в каждом прогоне.
## Сцены действительно вне библиотеки (placeholder) показываем по имени файла.
func _label_for_scene(scene_path: String) -> String:
	var preset := Library.preset_for_scene(_library, scene_path)
	if preset == null:
		return scene_path.get_file().get_basename() + " (вне библиотеки)"
	var suffix := " (fallback)" if preset == _library.fallback else ""
	return Library.label_of(preset) + suffix
#endregion
