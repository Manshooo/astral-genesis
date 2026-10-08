extends "res://dev/check_harness.gd"
## Проверка экрана карты комплекса (карточка «Экран карты комплекса»): правило
## видимости по уровням улучшения, сам экран на сгенерированном графе, путь
## открытия через UIManager, мини-карта по Tab и терминал в хабе на настоящем
## забеге.
##
## Ломается здесь всё тихо. Уровень, открывший чужой слой раньше времени, просто
## показывает лишнее — и улучшение Архитектора обесценено; уровень 1, видящий
## меньше мини-карты, выглядит как пустой экран. Обратная проекция курсора,
## съехавшая на полклетки, подписывает соседнюю комнату. Терминал без меша в
## своём Visual работает, но не подсвечивается — а ключ перевода с опечаткой
## показывает игроку «MAP_NO_LINK».
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
	"HUD_MAP_HIDE", "HUD_MAP_FULL", "ACTION_MAP_MINI", "MAP_TERMINAL_ONLY",
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
	for map_action: StringName in [&"map", &"map_mini"]:
		_check("действие %s есть в InputMap и переназначается" % map_action,
			InputMap.has_action(map_action) and SettingsManager.REBINDABLE_ACTIONS.has(map_action), "")
		var map_code := SettingsManager._first_code_of(map_action)
		var clashes: Array[String] = []
		for action: StringName in InputMap.get_actions():
			if action != map_action and not String(action).begins_with("ui_") \
					and SettingsManager._first_code_of(action) == map_code:
				clashes.append(String(action))
		_check("клавиша %s не занята другим действием" % map_action, map_code != "" and clashes.is_empty(),
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
	# Узел — на стольких панелях, сколько этажей занимает: лестница стоит на своём
	# этаже и на этаже выше, и коридор там упирается в её верхнюю дверь. Считаются
	# только этажи, которые у слоя есть: высокий зал на верхнем этаже (Архитектор
	# 1×1×2) уходит верхом туда, где этажа нет, и панели под этот верх нет.
	var shown_once := true
	var wrong: Array[String] = []
	var hub_plan := _graph.layer_plan(HUB_DEPTH)
	for node_data in _graph.get_nodes_by_depth(HUB_DEPTH):
		var times := 0
		for view in screen.floor_views():
			times += 1 if view.shows(node_data.id) else 0
		var floors_taken: int = 1
		if node_data.role == RS_LevelNode.Role.ROOM:
			var bottom: int = hub_plan.cells[node_data.id].y
			var height: int = hub_plan.footprints.get(node_data.id, Vector3i.ONE).y
			floors_taken = 0
			for level in range(bottom, bottom + height):
				floors_taken += 1 if floors.has(level) else 0
		if times != floors_taken:
			shown_once = false
			wrong.append("%s: %d из %d" % [node_data.id, times, floors_taken])
	_check("уровень 2: панель на каждый этаж, каждый узел — на каждом своём этаже",
		screen.floor_views().size() == floors.size() and shown_once,
		"панелей %d, этажей %d; %s" % [screen.floor_views().size(), floors.size(), ", ".join(wrong.slice(0, 4))])

	var projected := true
	var portals_marked := true
	var misses: Array[String] = []
	for view in screen.floor_views():
		for node_data in view.rooms:
			var cell: Vector3i = view.plan.cells[node_data.id]
			var point := view.to_screen(Vector2(cell.x, cell.z))
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
		screen.describe(interlayer.id).contains(tr(A_TravelThroughDoor.KEY_NAMES[&"level_access_key"])),
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

	var hud: CanvasLayer = (load("res://src/ui/hud/hud.tscn") as PackedScene).instantiate()
	add_child(hud)
	var mini := hud.get_node(^"Hud/MiniMap") as UI_MiniMap
	if message:
		message.text = ""
	_press(KEY_TAB)
	await get_tree().process_frame
	# show_on ставит новый компонент, а не пишет в старый.
	message = player.get_component(C_ScreenMessage) as C_ScreenMessage if player else null
	_check("уровень 0: мини-карта не открывается, игрок получает строку «нет связи»",
		mini != null and not mini.is_open and not mini.visible and message != null and message.text == tr("MAP_NO_LINK"),
		"сообщение %s" % (message.text if message else "нет"))

	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = 2
	await _check_mini_map(mini)
	_press(KEY_TAB)
	await get_tree().process_frame
	_check("ниже последнего ранга подсказки «[M] Вся карта» нет", mini._hint_hide.visible and not mini._hint_full.visible, "")
	if player:
		player.remove_component(C_ScreenMessage)
	_press_map()
	await get_tree().process_frame
	message = player.get_component(C_ScreenMessage) as C_ScreenMessage if player else null
	_check("ниже последнего ранга M карту не открывает, а отсылает к терминалу",
		UIManager._stack.is_empty() and not get_tree().paused and mini.is_open
		and message != null and message.text == tr("MAP_TERMINAL_ONLY"),
		"стек %d, сообщение %s" % [UIManager._stack.size(), message.text if message else "нет"])

	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = ArchitectStats.MAP_LEVEL_MAX
	await get_tree().process_frame
	_check("на последнем ранге подсказка зовёт и к полной карте",
		mini._hint_full.visible and mini._hint_full.plain_text() == "[M] %s" % tr("HUD_MAP_FULL"), mini._hint_full.plain_text())
	_press_map()
	await get_tree().process_frame
	_check("полная карта сворачивает мини-карту", _top_map() != null and not mini.is_open, "")
	_press_map()
	await get_tree().process_frame
	_press(KEY_TAB)
	UIManager.push_screen(Control.new(), true)
	_press(KEY_TAB)
	_check("поверх экрана Tab мини-карту не трогает", mini.is_open, "")
	UIManager.close_all()
	_press(KEY_TAB)
	hud.queue_free()

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
	var hub_room = RunManager.layer.rooms.get(RunManager.current_graph.entry_node_id)
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
	# Сверка по поддереву Visual, а не по имени меша: имя внутри .glb — дело арта,
	# и проверка на «Screen» упала в первый же раз, как пришёл настоящий проп.
	var geometries := RS_EntityVisuals.geometries(terminal) if terminal else []
	var visual := terminal.get_node_or_null(^"Visual") if terminal else null
	_check("подсветка терминала находит меш его пропа",
		visual != null and not geometries.is_empty()
			and geometries.all(func(g: Node) -> bool: return g == visual or visual.is_ancestor_of(g)),
		str(geometries.map(func(g): return terminal.get_path_to(g))))
	# С первого ранга: терминал — то место, где карту целиком смотрят до
	# последнего ранга, клавиша M в забеге ему не замена.
	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = MapKnowledge.LEVEL_VISITED
	if terminal:
		terminal.interact()
	await get_tree().process_frame
	_check("касание терминала открывает экран карты уже на первом ранге", _top_map() != null, "")
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
		_plans[depth] = _graph.layer_plan(depth)
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


## Мини-карта по Tab в забеге: не экран и не пауза, видит текущий этаж, волна
## прорисовки идёт от текущего узла, та же клавиша растворяет её.
func _check_mini_map(mini: UI_MiniMap) -> void:
	_press(KEY_TAB)
	await get_tree().process_frame
	_check("Tab открывает мини-карту без паузы и мимо стека экранов",
		mini.is_open and mini.visible and not get_tree().paused and UIManager._stack.is_empty(), "")
	var view := mini.build_view()
	var here := RunManager.current_node_id
	_check("мини-карта показывает текущий узел", mini.shows(here), str(view.keys()))
	var later := &""
	for node_id: StringName in mini._start_at:
		if mini._start_at[node_id] > 0.0:
			later = node_id
	var at := mini._opened_at + UI_MiniMap.CONTOUR_SECONDS
	_check("контур текущего узла прорисован раньше соседей",
		later != &"" and mini.progress_of(here, at) == 1.0 and mini.progress_of(later, at) < 1.0,
		"соседний %s" % later)

	# Коридор — квадратами по клеткам, проступающими от входа волны по одному.
	var chain := {}
	for branch in mini.branches:
		var ranks: Array[int] = []
		for cell in mini.tiles_of(branch.id):
			ranks.append(mini._tile_rank.get(cell, -1))
		if ranks.max() > 0:
			chain = {"branch": branch.id, "tiles": mini.tiles_of(branch.id), "ranks": ranks}
			break
	var in_order := false
	if not chain.is_empty():
		var first: Vector2i = chain.tiles[chain.ranks.find(0)]
		var last: Vector2i = chain.tiles[chain.ranks.find(chain.ranks.max())]
		var moment: float = mini._opened_at + mini._starts_at(chain.branch) + UI_MiniMap.TILE_FADE
		in_order = mini.tile_progress(chain.branch, first, moment) == 1.0 \
			and mini.tile_progress(chain.branch, last, moment) < 1.0
	_check("квадраты коридора проступают по очереди, у каждой клетки свой номер",
		in_order and not chain.ranks.has(-1), str(chain.get("ranks", [])))
	var reached_through := true
	for branch in mini.branches:
		for conn: RS_LevelConnection in RunManager.current_graph.get_node_data(branch.id).connections:
			var target := conn.target_node_id
			if mini.shows(target) and mini._starts_at(target) > mini._starts_at(branch.id):
				var length := 0
				for cell in mini.tiles_of(branch.id):
					length = maxi(length, mini._tile_rank.get(cell, 0) + 1)
				reached_through = reached_through and mini._starts_at(target) + 0.0001 >= \
					mini._starts_at(branch.id) + length * UI_MiniMap.TILE_DELAY
	_check("узел за коридором начинается, когда до него дошла цепочка", reached_through, "")

	var step_before := mini._target_step
	mini._target_step = step_before * 0.5
	mini._ease_scale(0.016)
	_check("новый размер этажа перетекает, а не прыгает",
		mini._step < step_before and mini._step > step_before * 0.5, "%.2f → %.2f" % [step_before, mini._step])
	mini._dirty = true
	await get_tree().process_frame

	# Узнали новый узел при открытой карте: он прорисовывается с этого момента,
	# а показанное не начинает рисоваться заново.
	var starts_before := mini._start_at.duplicate()
	for node_data in mini.rooms + mini.branches:
		if not WorldSave.save.visited_node_ids.has(node_data.id):
			WorldSave.save.visited_node_ids.append(node_data.id)
			break
	var marked := UI_HudMood.now() - mini._opened_at
	mini._dirty = true
	await get_tree().process_frame
	var newcomer := &""
	var kept := true
	for node_data in mini.rooms + mini.branches:
		if not starts_before.has(node_data.id):
			newcomer = node_data.id
		else:
			kept = kept and is_equal_approx(mini._starts_at(node_data.id), starts_before[node_data.id])
	_check("узнанный при открытой карте узел прорисовывается с этого момента, а не возникает",
		newcomer != &"" and mini._starts_at(newcomer) >= marked and kept,
		"новый %s, старт %.2f при %.2f, прежние на месте: %s" % [newcomer, mini._starts_at(newcomer), marked, kept])

	var floor_text: String = tr("MAP_FLOOR") % (mini.floor_index + 1)
	_check("ранг 2: заголовок называет слой и этаж, стрелок ещё нет",
		mini._title.text.contains(floor_text) and mini._title.text.contains(tr("MAP_LAYER") % view.depth)
		and not mini.shows_arrows(), mini._title.text)
	_check("подсказка: «[Tab] Свернуть»", mini._hint_hide.plain_text() == "[Tab] %s" % tr("HUD_MAP_HIDE"),
		mini._hint_hide.plain_text())
	var frame := mini.frame_rect()
	var outline := mini._frame_outline(UI_HudMood.now())
	var ragged_inside := frame.grow(3.0).has_point(outline[outline.size() / 3]) \
		and not frame.grow(-3.0).has_point(outline[outline.size() / 3])
	_check("рамка обводит и заголовок, и план, и подсказку, а рвётся у самого края",
		frame.has_point(mini._title.position) and frame.encloses(Rect2(Vector2.ZERO, mini.size))
		and frame.has_point(mini._hint_hide.position + Vector2(0.0, UI_MiniMap.HINT_HEIGHT - 1.0))
		and outline[0].is_equal_approx(outline[outline.size() - 1]) and ragged_inside,
		"%s" % frame)
	_check("мини-карта мышь не ловит", mini.mouse_filter == Control.MOUSE_FILTER_IGNORE, "")
	_press(KEY_TAB)
	await get_tree().process_frame
	_check("та же клавиша закрывает: растворяется, а не пропадает", not mini.is_open and mini.visible, "")
	await get_tree().create_timer(UI_MiniMap.CLOSE_SECONDS + 0.1).timeout
	_check("и через %.2f с её нет" % UI_MiniMap.CLOSE_SECONDS, not mini.visible, "")

	# Что ранги добавляют мини-карте: глубину — второй, стрелки связей — третий.
	var rank_before: int = ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL]
	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = MapKnowledge.LEVEL_VISITED
	_press(KEY_TAB)
	await get_tree().process_frame
	# process_frame приходит до _process узлов — пересборка мини-карты кадром позже.
	await get_tree().process_frame
	_check("ранг 1: заголовок — только этаж, без глубины, стрелок нет",
		mini.is_open and mini.title_text() == tr("MAP_FLOOR") % (mini.floor_index + 1) and not mini.shows_arrows(),
		mini.title_text())
	_press(KEY_TAB)
	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = MapKnowledge.LEVEL_COMPLEX
	_press(KEY_TAB)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("ранг 3: стрелки лестниц и порталов есть", mini.is_open and mini.shows_arrows(), "")
	_press(KEY_TAB)
	ArchitectManager.save.ranks[ArchitectStats.MAP_LEVEL] = rank_before


## Нажатие клавиши карты тем же путём, что живое: событие в _unhandled_input.
func _press_map() -> void:
	_press(KEY_M)


func _press(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = keycode
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
