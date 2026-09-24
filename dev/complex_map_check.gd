extends "res://dev/check_harness.gd"
## Проверка экрана карты комплекса (карточка «Экран карты комплекса»): правило
## видимости по уровням улучшения, сам экран на сгенерированном графе, путь
## открытия через UIManager и терминал в хабе на настоящем забеге.
##
## Ломается здесь всё тихо. Уровень, открывший чужой слой раньше времени, просто
## показывает лишнее — и улучшение Архитектора обесценено; уровень 1, видящий
## меньше мини-карты, выглядит как пустой экран. Обратная проекция курсора,
## съехавшая на полклетки, подписывает соседнюю комнату. Терминал, чей
## C_VisualRoot указывает мимо меша, работает, но не подсвечивается — а
## ключ перевода с опечаткой показывает игроку «MAP_NO_LINK».
##
## Сейв забега и сейв Архитектора подменяются на время прогона и возвращаются.
##
## Запускать: godot --headless dev/complex_map_check.tscn

const RUN_SEED := 515151
const HUB_DEPTH := 3
## Все ключи, которые экран и терминал показывают игроку.
const KEYS: Array[String] = [
	"MAP_TITLE", "MAP_TERMINAL_PROMPT", "MAP_NO_LINK", "MAP_LEVEL", "MAP_CLOSE", "MAP_LAYER",
	"MAP_LAYER_CLOSED", "MAP_HERE", "MAP_FLOOR", "MAP_ROOM", "MAP_CORRIDOR", "MAP_VISITED",
	"MAP_UNEXPLORED", "MAP_PORTAL_UP", "MAP_PORTAL_DOWN", "MAP_PORTAL_TARGET", "MAP_LOCKED",
	"MAP_HINT", "MAP_UNIQUE_HUB", "MAP_UNIQUE_EXIT", "MAP_UNIQUE_ARCHITECT",
]

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _architect_save: PlayerSkillSave
var _base_config: RS_WorldGenConfig
var _locale: String

var _graph: RS_LevelGraph
var _plans: Dictionary[int, RS_LayerPlan] = {}


func _ready() -> void:
	# Пауза экрана карты не должна останавливать саму проверку.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save
	_architect_save = ArchitectManager.save
	_base_config = GameConfig.config.world_gen
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")

	_graph = RS_LevelGraph.new().generate_run(RUN_SEED, GameConfig.config.room_preset_library, _base_config)

	_check_input_and_texts()
	_check_knowledge()
	await _check_screen()
	await _check_run()

	_restore()

	_finish()


# ---------------------------------------------------------------------------


func _check_input_and_texts() -> void:
	_check("действие map есть в InputMap и переназначается",
		InputMap.has_action(&"map") and SettingsManager.REBINDABLE_ACTIONS.has(&"map"), "")
	var map_code := SettingsManager._first_code_of(&"map")
	var clashes: Array[String] = []
	for action: StringName in InputMap.get_actions():
		if action != &"map" and not String(action).begins_with("ui_") and SettingsManager._first_code_of(action) == map_code:
			clashes.append(String(action))
	_check("клавиша карты не занята другим действием", map_code != "" and clashes.is_empty(),
		"код %s, занят: %s" % [map_code, clashes])
	var missing: Array[String] = []
	for key in KEYS:
		if tr(key) == key:
			missing.append(key)
	_check("все ключи карты переведены", missing.is_empty(), str(missing))


## Правило видимости (MapKnowledge) по уровням — на графе без забега.
func _check_knowledge() -> void:
	var hub := _graph.entry_node_id
	var visited: Array[StringName] = [hub]

	var any_at_zero := false
	for depth: int in RS_LevelGraph.DEPTHS:
		any_at_zero = any_at_zero or not MapKnowledge.visible_nodes(_graph, depth, 0, HUB_DEPTH, visited).is_empty()
	_check("уровень 0: не видно ничего", not any_at_zero, "")

	var level1 := MapKnowledge.visible_nodes(_graph, HUB_DEPTH, 1, HUB_DEPTH, visited)
	var minimap := MapKnowledge.known_nodes(_graph.get_nodes_by_depth(HUB_DEPTH), visited)
	var covers := true
	for node_data in minimap:
		covers = covers and level1.has(node_data)
	_check("уровень 1 видит не меньше мини-карты", covers and level1.has(_graph.get_node_data(hub)),
		"уровень 1: %d, мини-карта: %d" % [level1.size(), minimap.size()])
	var only_known := true
	for node_data in level1:
		only_known = only_known and minimap.has(node_data)
	_check("уровень 1 не показывает непосещённое без двери туда",
		only_known and level1.size() < _graph.get_nodes_by_depth(HUB_DEPTH).size(), "")

	# Посещённая комната другого этажа — первый уровень охватывает все этажи слоя.
	var other_floor := _node_on_other_floor(HUB_DEPTH, _graph.get_node_data(hub).floor_index)
	if other_floor:
		var wider: Array[StringName] = [hub, other_floor.id]
		_check("уровень 1: посещённое на других этажах слоя видно",
			MapKnowledge.visible_nodes(_graph, HUB_DEPTH, 1, HUB_DEPTH, wider).has(other_floor), "")
	else:
		_check("уровень 1: у слоя хаба есть второй этаж (сид)", false, "сменить RUN_SEED")

	_check("уровни 1–2: чужие слои закрыты",
		MapKnowledge.visible_nodes(_graph, 2, 2, HUB_DEPTH, visited).is_empty()
			and not MapKnowledge.is_layer_open(1, 4, HUB_DEPTH), "")
	_check("уровень 2: свой слой целиком",
		MapKnowledge.visible_nodes(_graph, HUB_DEPTH, 2, HUB_DEPTH, visited).size()
			== _graph.get_nodes_by_depth(HUB_DEPTH).size(), "")
	var all_open := true
	for depth: int in RS_LevelGraph.DEPTHS:
		all_open = all_open and MapKnowledge.visible_nodes(_graph, depth, 3, HUB_DEPTH, visited).size() \
			== _graph.get_nodes_by_depth(depth).size()
	_check("уровень 3: все слои целиком", all_open, "")

	# Портал: ровно у комнат с вертикальным ребром, и ведёт на другой этаж/слой.
	var wrong: Array[String] = []
	for node_data: RS_LevelNode in _graph.nodes.values():
		var conn := MapKnowledge.portal_of(_graph, node_data)
		if (conn != null) != node_data.has_tag(RS_LevelGraph.PORTAL_TAG):
			wrong.append(String(node_data.id))
	_check("портал узнаётся ровно у комнат с порталом", wrong.is_empty(), ", ".join(wrong.slice(0, 4)))


## Экран на сгенерированном графе, без забега.
func _check_screen() -> void:
	var hub := _graph.entry_node_id
	var visited: Array[StringName] = [hub]

	# --- уровень 1 -----------------------------------------------------------
	var screen := await _open_screen(1, hub, visited)
	var enabled: Array[int] = []
	for depth: int in screen._layer_buttons:
		if not screen._layer_buttons[depth].disabled:
			enabled.append(depth)
	_check("уровень 1: активна только кнопка своего слоя", enabled == [HUB_DEPTH] and screen.selected_layer() == HUB_DEPTH,
		"активны %s" % [enabled])
	var hub_shown := false
	for view in screen.floor_views():
		hub_shown = hub_shown or view.shows(hub)
	_check("уровень 1: хаб на карте, пустых этажей нет",
		hub_shown and screen.floor_views().size() == 1, "панелей %d" % screen.floor_views().size())
	screen.free()

	# --- уровень 2 -----------------------------------------------------------
	screen = await _open_screen(2, hub, visited)
	var floors := {}
	for node_data in _graph.get_nodes_by_depth(HUB_DEPTH):
		floors[node_data.floor_index] = true
	var shown_once := true
	for node_data in _graph.get_nodes_by_depth(HUB_DEPTH):
		var times := 0
		for view in screen.floor_views():
			times += 1 if view.shows(node_data.id) else 0
		shown_once = shown_once and times == 1
	_check("уровень 2: панель на каждый этаж, каждый узел ровно в одной",
		screen.floor_views().size() == floors.size() and shown_once,
		"панелей %d, этажей %d" % [screen.floor_views().size(), floors.size()])

	var projected := true
	var portals_marked := true
	var misses: Array[String] = []
	for view in screen.floor_views():
		for node_data in view.rooms:
			var point := view.to_screen(Vector2(view.plan.cells[node_data.id]))
			if view.node_at_point(point) != node_data.id:
				projected = false
				misses.append("%s→%s" % [node_data.id, view.node_at_point(point)])
			if (MapKnowledge.portal_of(_graph, node_data) != null) != view.portals.has(node_data.id):
				portals_marked = false
	_check("под центром комнаты курсор находит её саму", projected, ", ".join(misses.slice(0, 4)))
	_check("портал помечен у каждой показанной комнаты с порталом", portals_marked, "")
	var markers_empty := true
	for view in screen.floor_views():
		markers_empty = markers_empty and view.markers.is_empty()
	_check("до уровня 4 пометок содержимого нет", markers_empty, "")

	# Межслойный портал на втором уровне ведёт в закрытый слой — второго конца нет.
	var interlayer := _interlayer_portal_room(HUB_DEPTH)
	_check("уровень 2: второй конец межслойного портала не показан",
		interlayer != null and screen.portal_pair(interlayer.id) == &"", "")
	screen.free()

	# --- уровень 3 -----------------------------------------------------------
	screen = await _open_screen(3, hub, visited)
	var all_enabled := true
	for depth: int in screen._layer_buttons:
		all_enabled = all_enabled and not screen._layer_buttons[depth].disabled
	_check("уровень 3: все слои доступны", all_enabled and screen._layer_buttons.size() == RS_LevelGraph.DEPTHS.size(), "")
	var target := _graph.get_node_data(screen.portal_pair(interlayer.id))
	_check("уровень 3: второй конец межслойного портала найден",
		target != null and target.depth != HUB_DEPTH, "")
	screen._on_node_pressed(interlayer.id)
	await get_tree().process_frame
	var highlighted := false
	for view in screen.floor_views():
		highlighted = highlighted or (view.highlighted == target.id and view.shows(target.id))
	_check("клик по порталу открывает слой второго конца и подсвечивает его",
		screen.selected_layer() == target.depth and highlighted,
		"слой %d, ждали %d" % [screen.selected_layer(), target.depth])

	var exit_id: StringName = _graph.exit_node_ids[0]
	_check("уровень 3: содержимое комнат ещё скрыто",
		screen.describe(exit_id).begins_with(tr("MAP_ROOM")) and screen.marker_of(_graph.get_node_data(exit_id)).is_empty(),
		screen.describe(exit_id))
	var portal_conn := MapKnowledge.portal_of(_graph, interlayer)
	portal_conn.locked_by = &"level_access_key"
	_check("уровень 3: замок портала не выдаётся", not screen.describe(interlayer.id).contains(tr("MAP_LOCKED").split(":")[0]),
		screen.describe(interlayer.id))
	screen.free()

	# --- уровень 4 -----------------------------------------------------------
	screen = await _open_screen(4, hub, visited)
	_check("уровень 4: выход назван выходом", screen.describe(exit_id).begins_with(tr("MAP_UNIQUE_EXIT")),
		screen.describe(exit_id))
	_check("уровень 4: запертый портал называет ключ",
		screen.describe(interlayer.id).contains(A_TravelThroughDoor.KEY_NAMES[&"level_access_key"]),
		screen.describe(interlayer.id))
	var letters := {}
	for id: StringName in [hub, exit_id, _architect_id()]:
		var marker := screen.marker_of(_graph.get_node_data(id))
		if marker.get("unique", false):
			letters[marker["letter"]] = true
	_check("у уникальных комнат разные значки-заглушки", letters.size() == 3, str(letters.keys()))
	var typed := _typed_room()
	var type_marker := screen.marker_of(typed) if typed else {}
	var type := GameConfig.config.room_preset_library.type_catalog.by_id(typed.room_type) if typed else null
	_check("уровень 4: у комнаты с типом значок типа",
		type != null and not type_marker.get("unique", true) and type_marker["letter"] == tr(type.label()).substr(0, 1).to_upper(),
		str(type_marker))
	portal_conn.locked_by = &""
	screen.free()


## Настоящий забег: открытие через UIManager, клавиша, терминал в хабе.
func _check_run() -> void:
	var world := _new_world()
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh
	GameConfig.config.world_gen = _base_config.duplicate() as RS_WorldGenConfig
	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	await get_tree().physics_frame
	UIManager.enabled = true

	ArchitectManager.save = ArchitectManager._fresh_save()
	UIManager.open_complex_map()
	await get_tree().process_frame
	var player := RunManager._get_player()
	var message := player.get_component(C_ScreenMessage) as C_ScreenMessage if player else null
	_check("уровень 0: экрана нет, игрок получает строку «нет связи»",
		UIManager._stack.is_empty() and message != null and message.text == tr("MAP_NO_LINK"),
		"стек %d, сообщение %s" % [UIManager._stack.size(), message.text if message else "нет"])

	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = 2
	_press_map()
	await get_tree().process_frame
	var screen := _top_map()
	_check("клавиша карты открывает экран на паузе", screen != null and get_tree().paused, "")
	var marker_on := false
	if screen:
		for view in screen.floor_views():
			marker_on = marker_on or (view.show_player and view.shows(RunManager.current_node_id))
	_check("маркер игрока на панели его этажа", marker_on, "")
	UIManager.open_complex_map()
	_check("второй раз экран не открывается", UIManager._stack.size() == 1, "стек %d" % UIManager._stack.size())
	_press_map()
	await get_tree().process_frame
	_check("та же клавиша закрывает и снимает паузу", UIManager._stack.is_empty() and not get_tree().paused, "")

	UIManager.push_screen(Control.new(), true)
	_press_map()
	_check("поверх другого экрана карта не открывается", UIManager._stack.size() == 1 and _top_map() == null, "")
	UIManager.close_all()

	# Терминал в хабе.
	var terminal: E_InteractableObject = null
	var hub_room = RunManager._rooms.get(RunManager.current_graph.entry_node_id)
	if hub_room:
		for e: Entity in hub_room.children:
			var obj := e as E_InteractableObject
			if obj and obj.actions.any(func(a): return a is A_OpenComplexMap):
				terminal = obj
	var interactable := terminal.get_component(C_Interactable) as C_Interactable if terminal else null
	_check("в хабе есть терминал карты с подсказкой",
		interactable != null and interactable.prompt_text == "MAP_TERMINAL_PROMPT" and not interactable.requires_body, "")
	var body := terminal.get_node_or_null(^"InteractBody") as StaticBody3D if terminal else null
	_check("объём терминала на слое interactives", body != null and body.collision_layer == 8,
		"слой %s" % (body.collision_layer if body else "нет"))
	var geometries := RS_EntityVisuals.geometries(terminal) if terminal else []
	_check("подсветка терминала находит меш screen2",
		not geometries.is_empty() and String(geometries[0].name).begins_with("screen2"),
		str(geometries.map(func(g): return g.name)))
	if terminal:
		terminal.interact()
	await get_tree().process_frame
	_check("касание терминала открывает экран карты", _top_map() != null, "")
	UIManager.close_all()
	UIManager.enabled = false
	RunManager._end_run()


# ---------------------------------------------------------------------------


func _open_screen(level: int, here: StringName, visited: Array[StringName]) -> UI_ComplexMap:
	var screen: UI_ComplexMap = UIManager.COMPLEX_MAP_SCENE.instantiate()
	add_child(screen)
	screen.setup(_graph, level, here, visited, _plan_of)
	await get_tree().process_frame
	await get_tree().process_frame
	for view in screen.floor_views():
		view.fit()
	return screen


func _plan_of(depth: int) -> RS_LayerPlan:
	if not _plans.has(depth):
		_plans[depth] = RS_LayerPlan.build(_graph.get_nodes_by_depth(depth), _base_config)
	return _plans[depth]


func _node_on_other_floor(depth: int, floor_index: int) -> RS_LevelNode:
	for node_data in _graph.get_nodes_by_depth(depth):
		if node_data.floor_index != floor_index and node_data.role == RS_LevelNode.Role.ROOM:
			return node_data
	return null


func _interlayer_portal_room(depth: int) -> RS_LevelNode:
	for node_data in _graph.get_nodes_by_depth(depth):
		var conn := MapKnowledge.portal_of(_graph, node_data)
		if conn and _graph.get_node_data(conn.target_node_id).depth != depth:
			return node_data
	return null


func _architect_id() -> StringName:
	for node_data: RS_LevelNode in _graph.nodes.values():
		if node_data.room_scene_path.ends_with("architect_room.tscn"):
			return node_data.id
	return &""


func _typed_room() -> RS_LevelNode:
	for node_data: RS_LevelNode in _graph.nodes.values():
		if node_data.role == RS_LevelNode.Role.ROOM and node_data.room_type != &"" \
				and not node_data.room_scene_path.ends_with("hub.tscn"):
			return node_data
	return null


func _top_map() -> UI_ComplexMap:
	if UIManager._stack.is_empty():
		return null
	return UIManager._stack.back().screen as UI_ComplexMap


## Нажатие клавиши карты тем же путём, что живое: событие в _unhandled_input.
func _press_map() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_M
	key.pressed = true
	UIManager._unhandled_input(key)


func _restore() -> void:
	GameConfig.config.world_gen = _base_config
	WorldSave.save = _save_object
	ArchitectManager.save = _architect_save
	TranslationServer.set_locale(_locale)
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")
