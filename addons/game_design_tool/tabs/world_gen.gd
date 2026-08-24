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

const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")

var _seed_spin: SpinBox
var _depth_option: OptionButton
var _status: Label
var _host: ViewportHost
var _info_label: RichTextLabel
var _open_preset_btn: Button
var _open_scene_btn: Button

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
		_rebuild_graph()


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

	# Чекбоксы — циклом по реестру, не захардкожены: новый оверлей добавляется
	# строкой в OverlayRegistry.OVERLAYS, а не правкой этого цикла.
	for overlay: Dictionary in OverlayRegistry.OVERLAYS:
		var check := CheckBox.new()
		check.text = overlay["title"]
		check.button_pressed = overlay["default_visible"]
		var overlay_id: StringName = overlay["id"]
		check.toggled.connect(func(pressed: bool) -> void: _host.set_overlay_visible(overlay_id, pressed))
		row.add_child(check)

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

	_open_preset_btn = _button("Открыть пресет", _on_open_preset_pressed)
	panel.add_child(_open_preset_btn)
	_open_scene_btn = _button("Открыть сцену", _on_open_scene_pressed)
	panel.add_child(_open_scene_btn)

	_clear_selection()
	return panel


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


#region Генерация
func _on_random_seed_pressed() -> void:
	_seed_spin.value = randi() % 1000000


func _on_rebuild_pressed() -> void:
	# Дизайнер мог поправить сцену комнаты (дверь, положение) с прошлой
	# пересборки — без сброса тул продолжит показывать старую раскладку
	# (см. RS_RoomLayout.clear_scene_cache).
	RS_RoomLayout.clear_scene_cache()
	_rebuild_graph()


func _rebuild_graph() -> void:
	_library = ResourceLoader.load(LIBRARY_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_RoomPresetLibrary
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + LIBRARY_PATH)
		return
	var run_seed := int(_seed_spin.value)
	_graph = RS_LevelGraph.new().generate_run(run_seed, _library)
	_rebuild_layer()
	_set_status("Сид %d, узлов в графе: %d" % [run_seed, _graph.nodes.size()])


func _current_depth() -> int:
	var idx := _depth_option.selected
	if idx < 0:
		return RS_LevelGraph.HOME_DEPTH
	return _depth_option.get_item_id(idx)


func _on_depth_selected(_index: int) -> void:
	_rebuild_layer()


func _rebuild_layer() -> void:
	if _graph == null:
		return
	var depth := _current_depth()
	var layer_nodes := _graph.get_nodes_by_depth(depth)
	var plan := RS_LayerPlan.build(layer_nodes)
	_host.show_layer(_graph, layer_nodes, plan)
	_clear_selection()
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
	_open_preset_btn.disabled = _preset_for(node_data) == null
	_open_scene_btn.disabled = (
		node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path)
	)


func _clear_selection() -> void:
	_info_label.text = "[i]Кликни по комнате во вьюпорте.[/i]"
	_open_preset_btn.disabled = true
	_open_scene_btn.disabled = true


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
