## Вкладка «Генератор мира» единого редактора геймдизайна: 3D-превью слоя тем же
## генератором и раскладкой, что в игре, плюс «Прогон сидов» — статистика подбора.
## Отрисовка и пикинг — GDT_ViewportHost. См. [[Редакторские инструменты]]
## («Коридоры и сетка во вьюпорте») и [[Цикл забега]].
@tool
extends VBoxContainer

const Ui := preload("res://addons/game_design_tool/shared/ui.gd")
const Library := preload("res://addons/game_design_tool/shared/library.gd")
const Undo := preload("res://addons/game_design_tool/shared/undo.gd")
const TagCloud := preload("res://addons/game_design_tool/shared/tag_cloud.gd")
const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")
const EditorState := preload("res://addons/game_design_tool/shared/editor_state.gd")

const TAB_TITLE := "Генератор мира"

## Раздел проектных метаданных вкладки (GDT_EditorState).
const SETTINGS_SECTION := "world_gen_tool"

## Куда идти писать описание тега (тултипы облака).
const TAG_HINT_WHERE := "вкладке «Редактор пресетов» → облако тегов"

## Наибольший сид забега: randi() и hash() отдают 32 бита без знака.
const SEED_MAX := 0xFFFFFFFF

# Автолоад в редакторе не работает, но его константа доступна через скрипт.
const SAVE_PATH := preload("res://src/autoloads/world_save.gd").SAVE_PATH

var _seed_spin: SpinBox
var _random_btn: Button
## Режим «Забег из сейва» намеренно не запоминается между запусками редактора.
var _save_run_toggle: Button
var _depth_option: OptionButton
var _visibility_menu: MenuButton
var _status: Label

## Прогон сидов: панель внизу, по умолчанию свёрнута.
var _seeds_panel: VBoxContainer
var _seeds_toggle: Button
var _seeds_spin: SpinBox
var _seeds_report: RichTextLabel
var _host: ViewportHost
var _info_label: RichTextLabel
var _open_preset_btn: Button
var _open_scene_btn: Button

## Инлайн-редактор пресета выделенного узла; виден, только если пресет найден.
var _preset_section: VBoxContainer
var _preset_label: Label
var _slot_spin: SpinBox
var _weight_spin: SpinBox
var _tag_cloud: TagCloud
var _new_tag_edit: LineEdit
var _editing_preset: RS_RoomPreset
## Поля пресета на момент последней записи — «было» для истории: облако тегов
## меняет массив на месте, и к сигналу в пресете уже «стало».
var _preset_snapshot := {}

var _graph: RS_LevelGraph
var _library: RS_RoomPresetLibrary
var _loaded := false

const WORLD_GEN_CONFIG_PATH := "res://data/world_gen_config.tres"
var _config: RS_WorldGenConfig
# GameConfig в редакторе не работает, поэтому кит берётся по пути.
const CORRIDOR_KIT_PATH := "res://data/corridor_kit.tres"


func _init() -> void:
	name = TAB_TITLE
	_build_ui()


## Первая генерация — при первом показе: она инстанцирует реальные сцены комнат.
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

	# SplitContainer со скрытым вторым ребёнком отдаёт всю высоту первому.
	var rows := VSplitContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorState.bind_split(rows, SETTINGS_SECTION, "seeds_panel_split", 0)
	add_child(rows)

	var split := HSplitContainer.new()
	split.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	EditorState.bind_split(split, SETTINGS_SECTION, "viewport_side_split", -320)
	rows.add_child(split)
	rows.add_child(_build_seeds_panel())

	_host = ViewportHost.new()
	_host.node_picked.connect(_on_node_picked)
	split.add_child(_host)
	split.add_child(_build_side_panel())

	_status = Ui.status_label()
	add_child(_status)


func _build_toolbar() -> Control:
	var row := HBoxContainer.new()

	row.add_child(Ui.label("Сид:"))
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = SEED_MAX
	_seed_spin.step = 1
	_seed_spin.value = 0
	_seed_spin.select_all_on_focus = true
	_seed_spin.custom_minimum_size = Vector2(130, 0)  # десять знаков сида
	_seed_spin.tooltip_text = (
		"Сид забега — тот, что в отладочном оверлее игры («сид забега», копируется из меню отладки).\n"
		+ "Забег строится из сида, СЛЕПКА ручек генерации и версии генератора, сохранённых\n"
		+ "в сейве при его начале, а здесь берётся текущий data/world_gen_config.tres.\n"
		+ "Если ручки правили после начала забега, тот же сид даст здесь другой мир —\n"
		+ "забег, как он есть в сейве, показывает кнопка «Забег из сейва»."
	)
	row.add_child(_seed_spin)
	_random_btn = Ui.button("Случайный", _on_random_seed_pressed)
	row.add_child(_random_btn)
	row.add_child(Ui.button("Пересобрать", _on_rebuild_pressed))

	_save_run_toggle = Button.new()
	_save_run_toggle.text = "Забег из сейва"
	_save_run_toggle.toggle_mode = true
	_save_run_toggle.tooltip_text = (
		"Комплекс забега из сейва игры (%s): сид забега и слепок ручек,\n" % SAVE_PATH
		+ "с которыми он начат, — тот же мир, что строит игра при загрузке.\n"
		+ "Открывается слой игрока с выделенной комнатой, где он остановился.\n"
		+ "«Пересобрать» перечитывает сейв — после новой контрольной точки."
	)
	_save_run_toggle.toggled.connect(_on_save_run_toggled)
	row.add_child(_save_run_toggle)

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


## Панель прогона; сид тулбара ей не нужен — прогон гоняет сиды 0..N-1 (см. вики).
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
	EditorState.write(SETTINGS_SECTION, "seeds_panel", pressed)


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


## Слоты/вес/теги ПРЕСЕТА выделенного узла. Не то же, что «Теги» узла в
## _info_label: node.tags — требования узла графа, preset.tags — способности комнаты.
func _build_preset_section() -> Control:
	_preset_section = VBoxContainer.new()

	_preset_label = Ui.ellipsis_label()
	_preset_section.add_child(_preset_label)

	var slot_row := HBoxContainer.new()
	slot_row.add_child(Ui.label("Слоты:"))
	_slot_spin = SpinBox.new()
	Library.configure_spin(_slot_spin, Library.SLOT_RANGE)
	_slot_spin.value_changed.connect(_on_slot_changed)
	slot_row.add_child(_slot_spin)
	_preset_section.add_child(slot_row)

	var weight_row := HBoxContainer.new()
	weight_row.add_child(Ui.label("Вес:"))
	_weight_spin = SpinBox.new()
	Library.configure_spin(_weight_spin, Library.WEIGHT_RANGE)
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


## Пункты — циклом по реестру: новый оверлей — строка в OverlayRegistry.OVERLAYS.
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


## PopupMenu не переключает check-пункт сам; id пункта — индекс в OverlayRegistry.OVERLAYS.
func _on_visibility_item_pressed(id: int) -> void:
	var popup := _visibility_menu.get_popup()
	var idx := popup.get_item_index(id)
	var new_state := not popup.is_item_checked(idx)
	popup.set_item_checked(idx, new_state)
	var overlay: Dictionary = OverlayRegistry.OVERLAYS[id]
	_host.set_overlay_visible(overlay["id"], new_state)
	EditorState.write(SETTINGS_SECTION, "overlay_" + String(overlay["id"]), new_state)
#endregion


#region Генерация
func _on_random_seed_pressed() -> void:
	_seed_spin.value = randi()


func _on_rebuild_pressed() -> void:
	# Без сброса кэша сцен раскладка осталась бы по правке двери до пересборки.
	RS_RoomLayout.clear_scene_cache()
	_rebuild_graph()


## Порядок важен: show_layer сама кадрирует камеру и эмитит camera_changed —
## подписка раньше перезаписала бы сохранённую позицию до restore_camera.
func _restore_state() -> void:
	_seed_spin.value = EditorState.read(SETTINGS_SECTION, "seed", 0)
	# button_pressed сам зовёт _on_seeds_toggled, панель встаёт вместе с кнопкой.
	_seeds_toggle.button_pressed = EditorState.read(SETTINGS_SECTION, "seeds_panel", false)

	var depth: int = EditorState.read(SETTINGS_SECTION, "depth", RS_LevelGraph.HOME_DEPTH)
	var depth_idx := _depth_option.get_item_index(depth)
	if depth_idx >= 0:
		_depth_option.select(depth_idx)

	var popup := _visibility_menu.get_popup()
	for i in OverlayRegistry.OVERLAYS.size():
		var overlay: Dictionary = OverlayRegistry.OVERLAYS[i]
		var visible_state: bool = EditorState.read(
			SETTINGS_SECTION, "overlay_" + String(overlay["id"]), overlay["default_visible"]
		)
		popup.set_item_checked(popup.get_item_index(i), visible_state)
		_host.set_overlay_visible(overlay["id"], visible_state)

	_rebuild_graph()

	if EditorState.read(SETTINGS_SECTION, "camera_saved", false):
		var pos: Vector3 = EditorState.read(SETTINGS_SECTION, "camera_position", Vector3.ZERO)
		var rot: Vector3 = EditorState.read(SETTINGS_SECTION, "camera_rotation", Vector3.ZERO)
		_host.restore_camera(pos, rot)

	_host.camera_changed.connect(_on_camera_changed)


func _on_camera_changed() -> void:
	EditorState.write(SETTINGS_SECTION, "camera_position", _host.camera_position())
	EditorState.write(SETTINGS_SECTION, "camera_rotation", _host.camera_rotation_degrees())
	EditorState.write(SETTINGS_SECTION, "camera_saved", true)


func _rebuild_graph() -> void:
	_library = Library.load_library()
	if _library == null:
		_set_status("⚠ Не удалось загрузить " + Library.LIBRARY_PATH)
		return
	if _save_run_toggle.button_pressed:
		var saved := UserResourceFile.read(SAVE_PATH, RS_WorldSave, TAB_TITLE) as RS_WorldSave
		if saved != null:
			show_save_run(saved)
			return
		_save_run_toggle.set_pressed_no_signal(false)
		_set_seed_editable(true)
		_build_from_seed()
		_set_status("⚠ Сейва игры нет (%s) — показан сид из поля" % SAVE_PATH)
		return
	_build_from_seed()


func _build_from_seed() -> void:
	var run_seed := int(_seed_spin.value)
	_config = _world_gen_config()
	_graph = RS_LevelGraph.new().generate_run(run_seed, _library, _config)
	_rebuild_layer()
	_set_status("Сид %d, узлов в графе: %d" % [run_seed, _graph.nodes.size()])
	EditorState.write(SETTINGS_SECTION, "seed", run_seed)


## Комплекс забега из сейва [param saved] — по правилу входа в игре (см. вики).
## Сид из сейва в EditorState не пишется: выключив режим, возвращаешься к своему.
func show_save_run(saved: RS_WorldSave) -> void:
	var run_seed := saved.run_seed()
	var snapshot := saved.resumable_gen_config()
	_config = snapshot if snapshot != null else _world_gen_config()
	_seed_spin.value = run_seed
	_graph = RS_LevelGraph.new().generate_run(run_seed, _library, _config)

	var player_node: RS_LevelNode = null
	if snapshot != null:
		player_node = _graph.get_node_data(saved.current_node_id)
	if player_node != null:
		_depth_option.select(_depth_option.get_item_index(player_node.depth))
	_rebuild_layer()
	if player_node != null:
		_host.select(player_node.id)
		_host.focus_selected()

	var where := "забег не начат — показан следующий, по текущим ручкам"
	if saved.run_in_progress and snapshot == null:
		where = "забег начат на другом генераторе — игра сбросит его на вход, ручки текущие"
	elif snapshot != null:
		where = "ручки — слепок начала забега, игрок в %s" % (
			player_node.id if player_node != null else "узле входа"
		)
	_set_status("Забег из сейва: сид %d, смертей %d; %s" % [run_seed, saved.death_count, where])


func _on_save_run_toggled(pressed: bool) -> void:
	_set_seed_editable(not pressed)
	if not pressed:
		_seed_spin.value = EditorState.read(SETTINGS_SECTION, "seed", 0)
	_rebuild_graph()


func _set_seed_editable(editable: bool) -> void:
	_seed_spin.editable = editable
	_random_btn.disabled = not editable


func _current_depth() -> int:
	var idx := _depth_option.selected
	if idx < 0:
		return RS_LevelGraph.HOME_DEPTH
	return _depth_option.get_item_id(idx)


func _on_depth_selected(_index: int) -> void:
	_rebuild_layer()
	EditorState.write(SETTINGS_SECTION, "depth", _current_depth())


func _rebuild_layer() -> void:
	if _graph == null:
		return
	_host.show_layer(_layer_view(_current_depth()))
	_clear_selection()


func _layer_view(depth: int) -> LayerView:
	var layer_nodes := _graph.get_nodes_by_depth(depth)
	var view := LayerView.new(
		_graph, layer_nodes, _graph.layer_plan(depth), _preset_labels_for(layer_nodes)
	)
	if ResourceLoader.exists(CORRIDOR_KIT_PATH):
		view.kit = load(CORRIDOR_KIT_PATH) as RS_CorridorKit
	return view


## null — ресурса нет, генератор возьмёт ручки по умолчанию. CACHE_MODE_REPLACE —
## правка в инспекторе видна по «Пересобрать».
func _world_gen_config() -> RS_WorldGenConfig:
	if not ResourceLoader.exists(WORLD_GEN_CONFIG_PATH):
		return null
	return ResourceLoader.load(WORLD_GEN_CONFIG_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as RS_WorldGenConfig


## node_id -> имя пресета, для оверлея «Подписи».
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
	# Тип — другая ось подбора, чем теги; не сливать (см. «Цикл забега»).
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


## Обратной ссылки «узел → пресет» нет — ищем по пути сцены (хаб тоже находится).
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


#region Инлайн-редактор пресета
## Гасит эхо value_changed при программном заполнении: иначе каждый клик по узлу
## «сохранял» бы пресет без правки.
var _filling_preset_section := false


func _fill_preset_section() -> void:
	_filling_preset_section = true
	_preset_label.text = Library.label_of(_editing_preset)
	_preset_label.tooltip_text = _editing_preset.resource_path
	_slot_spin.value = _editing_preset.slot_count
	_weight_spin.value = _editing_preset.weight
	_tag_cloud.set_vocabulary(_library)
	_tag_cloud.show_for(_editing_preset)
	_filling_preset_section = false
	_preset_snapshot = _snapshot_of(_editing_preset)


static func _snapshot_of(preset: RS_RoomPreset) -> Dictionary:
	return {
		"slot_count": preset.slot_count,
		"weight": preset.weight,
		"tags": preset.tags.duplicate(),
	}


func _on_slot_changed(value: float) -> void:
	if _filling_preset_section or _editing_preset == null:
		return
	_editing_preset.slot_count = int(value)
	_save_editing_preset(true)


func _on_weight_changed(value: float) -> void:
	if _filling_preset_section or _editing_preset == null:
		return
	_editing_preset.weight = value
	_save_editing_preset(true)


func _on_add_tag_pressed() -> void:
	var tag := _tag_cloud.add_new(_new_tag_edit.text)
	_new_tag_edit.text = ""
	if tag != &"":
		_set_status("Тег «%s» заведён и повешен." % tag)


## Зовётся и облаком тегов (preset_changed), которое show_for тоже трогает —
## поэтому флаг проверяется здесь. Правка идёт в историю как «снимок → текущее»;
## [param merge] склеивает тики спинбокса в один шаг.
func _save_editing_preset(merge := false) -> void:
	if _filling_preset_section or _editing_preset == null:
		return
	var now := _snapshot_of(_editing_preset)
	var changes := {}
	for property: String in now:
		if now[property] != _preset_snapshot.get(property):
			changes[property] = [_preset_snapshot.get(property), now[property]]
	if changes.is_empty():
		return
	var err := Undo.commit(
		"Пресет в «Генераторе мира»", _editing_preset, changes,
		_after_preset_edit.bind(_editing_preset), merge
	)
	_preset_snapshot = now
	if err != OK:
		_set_status("⚠ Не удалось сохранить (код %d)" % err)
		return
	_set_status("Сохранено: " + _editing_preset.resource_path.get_file())


## Отложенно: правка приходит из сигнала чекбокса облака, а перерисовка пересобирает
## облако и освободила бы чекбокс посреди его же сигнала.
func _after_preset_edit(preset: RS_RoomPreset) -> void:
	if preset == _editing_preset:
		_refill_preset_section.call_deferred(preset)


func _refill_preset_section(preset: RS_RoomPreset) -> void:
	if preset == _editing_preset and not _filling_preset_section:
		_fill_preset_section()
#endregion


#region Прогон сидов
## Не трогает ни _graph, ни вьюпорт: свои графы строит и выбрасывает. Что считается
## и откуда берутся причины отсева — в вики.
func _on_preview_pressed() -> void:
	# Двери считаются через кэш сцен — без сброса цифры пойдут по старой геометрии.
	RS_RoomLayout.clear_scene_cache()
	if _library == null:
		_rebuild_graph()
	if _library == null:
		return
	var seeds := int(_seeds_spin.value)
	var config := _world_gen_config()
	var excluded: Array[RS_RoomPreset] = []
	if config:
		for unique: RS_UniqueRoom in config.unique_rooms:
			if unique and unique.preset:
				excluded.append(unique.preset)
	var picks := {}  # label -> сколько раз реально выбран
	var presence := {}  # label -> { глубина или ANYWHERE: в скольких сидах выпал }
	var reasons := {}  # label -> { причина: сколько раз }
	var degrees := {}  # дверей у комнаты -> сколько комнат
	var layout := RS_LayoutMetrics.new()
	var nodes_total := 0
	var failures := 0

	for s in seeds:
		var graph := RS_LevelGraph.new().generate_run(s, _library, config)
		for depth: int in RS_LevelGraph.DEPTHS:
			var plan := graph.layer_plan(depth)
			failures += plan.routing_failures.size()
			layout.add(RS_LayoutMetrics.of_plan(plan))
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		var seen := {}  # label -> { глубина: true } — где пресет стоит в этом сиде
		for node: RS_LevelNode in graph.nodes.values():
			if node.role == RS_LevelNode.Role.CORRIDOR:
				continue
			nodes_total += 1
			var degree := node.door_count()
			degrees[degree] = degrees.get(degree, 0) + 1
			var picked := _label_for_scene(node.room_scene_path)
			picks[picked] = picks.get(picked, 0) + 1
			if not seen.has(picked):
				seen[picked] = {}
			seen[picked][node.depth] = true
			if excluded.any(func(p: RS_RoomPreset) -> bool: return p.scene and p.scene.resource_path == node.room_scene_path):
				continue

			var explained: Dictionary = _library.explain_selection(node, rng, excluded)["reasons"]
			for label: String in explained:
				# У explain свой rng и свой победитель: «выбран» сливаем с «дошёл до
				# весов» — таблица отсева только о жёстких фильтрах.
				var reason: String = explained[label]
				if reason == RS_RoomPresetLibrary.REASON_SELECTED:
					reason = RS_RoomPresetLibrary.REASON_CANDIDATE
				if not reasons.has(label):
					reasons[label] = {}
				reasons[label][reason] = reasons[label].get(reason, 0) + 1
		_count_presence(presence, seen)

	_seeds_report.text = _preview_report(seeds, nodes_total, picks, presence, reasons, degrees)
	_seeds_report.text += _corridor_report(layout, failures)
	_set_status("Прогнано сидов: %d, комнат: %d" % [seeds, nodes_total])


## Метрики RS_LayoutMetrics — те же, что печатает dev/corridor_layout_check.
func _corridor_report(layout: RS_LayoutMetrics, failures: int) -> String:
	var out := "\n[b]Коридоры[/b]: %d тайлов на %d этажей" % [layout.tiles, layout.floors]
	if failures > 0:
		out += " — [color=#e0624b]отказов трассы: %d[/color]" % failures
	out += "\n[code]%s[/code]" % "\n".join(layout.report_lines())
	return out


## Ключ «на весь комплекс» в таблице «Где встретить».
const ANYWHERE := -1


## Сид засчитывается пресету раз на слой и раз на комплекс: «встретит ли», не «сколько».
static func _count_presence(presence: Dictionary, seen: Dictionary) -> void:
	for label: String in seen:
		if not presence.has(label):
			presence[label] = {}
		var counts: Dictionary = presence[label]
		counts[ANYWHERE] = counts.get(ANYWHERE, 0) + 1
		for depth: int in seen[label]:
			counts[depth] = counts.get(depth, 0) + 1


## Одна на отчёт и на проверку — формат у них не разъедется.
static func _presence_line(label: String, counts: Dictionary, seeds: int) -> String:
	var line := "%-24s %4d%%" % [label, _percent(counts.get(ANYWHERE, 0), seeds)]
	for depth: int in RS_LevelGraph.DEPTHS:
		line += " %4d%%" % _percent(counts.get(depth, 0), seeds)
	return line


static func _percent(part: int, whole: int) -> int:
	return roundi(100.0 * part / maxi(whole, 1))


func _preview_report(
	seeds: int,
	nodes_total: int,
	picks: Dictionary,
	presence: Dictionary,
	reasons: Dictionary,
	degrees: Dictionary,
) -> String:
	var out := "[b]Прогон %d сидов, %d комнат[/b]\n" % [seeds, nodes_total]

	out += "\n[b]Что выпало[/b] (доля среди всех комнат всех сидов)\n[code]"
	var picked_labels := picks.keys()
	picked_labels.sort_custom(func(a, b): return picks[a] > picks[b])
	for label: String in picked_labels:
		out += "%-24s %5d  %4.1f%%\n" % [label, picks[label], 100.0 * picks[label] / maxi(nodes_total, 1)]
	out += "[/code]"

	out += "\n[b]Где встретить[/b] (в скольких сидах выпал хотя бы раз; * — слой хаба, с него начинается забег)\n[code]"
	var header := "%-24s %5s" % ["", "весь"]
	for depth: int in RS_LevelGraph.DEPTHS:
		header += " %5s" % ("L%d%s" % [depth, "*" if depth == RS_LevelGraph.HOME_DEPTH else ""])
	out += header + "\n"
	var present_labels := presence.keys()
	present_labels.sort_custom(func(a, b): return presence[a][ANYWHERE] > presence[b][ANYWHERE])
	for label: String in present_labels:
		out += _presence_line(label, presence[label], seeds) + "\n"
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

	out += "\n[b]Двери комнат (сколько дверей = сколько рёбер в коридоры)[/b]\n[code]"
	var degree_keys := degrees.keys()
	degree_keys.sort()
	for degree: int in degree_keys:
		out += "дверей %d: %5d комнат\n" % [degree, degrees[degree]]
	out += "[/code]"

	out += (
		"\n[i]Порядок отбора: портал (есть ровно тогда, когда узлу нужен переход) → "
		+ "теги (node.tags ⊆ preset.tags) → тип помещения → вес. "
		+ "Тип — ПРЕДПОЧТЕНИЕ, а не фильтр: если в группе нет ни одного пресета "
		+ "загаданного узлу типа, группа идёт дальше целиком. "
		+ "Вес применяется ПОСЛЕДНИМ: если конкуренты отсеялись раньше, правка веса "
		+ "не изменит ничего — сначала смотри на «портал» и «теги». "
		+ "Дверей у комнаты ровно столько, сколько рёбер в коридоры: смесь комнат "
		+ "по числу дверей задают веса пресетов. "
		+ "«Дошёл до весов» — сколько раз пресет участвовал в броске; сколько раз он "
		+ "его выиграл, смотри в «Что выпало». Вес и теги правятся во вкладке "
		+ "«Редактор пресетов» или в панели узла справа.[/i]"
	)
	return out


## Поиск тот же, что у боковой панели (иначе хаб отчитывался бы «вне библиотеки»).
func _label_for_scene(scene_path: String) -> String:
	var preset := Library.preset_for_scene(_library, scene_path)
	if preset == null:
		return scene_path.get_file().get_basename() + " (вне библиотеки)"
	var suffix := " (fallback)" if preset == _library.fallback else ""
	return Library.label_of(preset) + suffix
#endregion
