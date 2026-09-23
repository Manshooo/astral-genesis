extends Node
## Проверка графа забега (карточка «Процедурные коридоры между комнатами»):
## комнаты висят на ветках коридора, а рёбер у комнаты ровно столько, сколько
## дверей в её сцене.
##
## Всё здесь ломается тихо. Ребро без двери и дверь без ребра не бросают ошибок —
## первое делает соседа недостижимым, второе возвращает заваренные двери, от
## которых этот путь и уходит. Портал в комнате без вертикального ребра — мёртвый
## портал посреди пола, вертикальное ребро без портала — оборванный переход.
## Запертые наглухо переходы между слоями — непроходимый забег.
##
## Запускать: godot --headless dev/corridor_graph_check.tscn

const SEEDS := 30
const CONFIG_PATH := "res://data/world_gen_config.tres"
## Однодверная комната под «уникальную с шансом» — роль Архитектора, пока его
## комнаты нет. Сцена важна только числом дверей.
const STAND_IN_PRESET := "res://src/levels/procedural/rooms/lab/lab_room.tres"
## Сколько ассертов обязано отработать до сторожевого (см. _ready).
const EXPECTED_ASSERTS := 21

var _ok := 0
var _fail := 0
var _library: RS_RoomPresetLibrary
var _portal_by_scene: Dictionary[String, bool] = {}


func _ready() -> void:
	_library = GameConfig.config.room_preset_library
	var base := load(CONFIG_PATH) as RS_WorldGenConfig

	_check_config(base)
	var config := base.duplicate() as RS_WorldGenConfig
	_check_invariants(config)
	_check_determinism(config)
	_check_home_depth(config)
	_check_unique_chance(config)
	_check_snapshot()

	# SCRIPT ERROR внутри блока обрывает только этот блок, а не прогон: итог
	# печатается, провалов ноль, и сломанная генерация выглядит зелёной. Так и
	# случилось на первом прогоне — поэтому число ассертов сверяется с ожидаемым.
	var ran := _ok + _fail
	_check("все блоки дошли до конца", ran == EXPECTED_ASSERTS,
		"ассертов %d из %d — какой-то блок упал на ошибке скрипта" % [ran, EXPECTED_ASSERTS])

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------


func _check_config(base: RS_WorldGenConfig) -> void:
	_check("конфиг генерации загружается", base != null, CONFIG_PATH)
	_check("конфиг назначен в GameConfig", GameConfig.config.world_gen != null, "")
	var problems := base.validate() if base else ["нет конфига"]
	_check("конфиг валиден", problems.is_empty(), ", ".join(problems))


func _check_invariants(config: RS_WorldGenConfig) -> void:
	var entry_unique := _unique(config, true, false)
	var exit_unique := _unique(config, false, true)
	var problems := {
		"граф связен от входа": [],
		"вход — хаб": [],
		"выходы: число, глубина, сцена, тег": [],
		"у комнаты рёбер в коридоры ровно столько, сколько дверей в сцене": [],
		"двери комнаты ведут в ветки её этажа": [],
		"у каждой ветки есть хотя бы одна комната, и живёт она в своём этаже": [],
		"не больше одного вертикального ребра на узел": [],
		"портал в сцене ровно тогда, когда есть вертикальное ребро": [],
		"каждая пара соседних слоёв связана открытым переходом": [],
		"каждая пара этажей слоя связана переходом": [],
	}
	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, _library, config)
		_collect(graph, s, config, entry_unique, exit_unique, problems)
	for what: String in problems:
		var list: Array = problems[what]
		_check("%s (%d сидов)" % [what, SEEDS], list.is_empty(), ", ".join(list.slice(0, 4)))


func _collect(
	graph: RS_LevelGraph,
	s: int,
	config: RS_WorldGenConfig,
	entry_unique: RS_UniqueRoom,
	exit_unique: RS_UniqueRoom,
	problems: Dictionary,
) -> void:
	var unreachable := graph.nodes.size() - _reachable(graph).size()
	if unreachable > 0:
		problems["граф связен от входа"].append("сид %d: %d недостижимо" % [s, unreachable])

	var entry := graph.get_node_data(graph.entry_node_id)
	if entry == null or entry.room_scene_path != entry_unique.preset.scene.resource_path:
		problems["вход — хаб"].append("сид %d" % s)

	var exits_ok := graph.exit_node_ids.size() == exit_unique.count
	for id in graph.exit_node_ids:
		var node := graph.get_node_data(id)
		exits_ok = exits_ok and node != null and exit_unique.covers_depth(node.depth)
		exits_ok = exits_ok and node.room_scene_path == exit_unique.preset.scene.resource_path
		exits_ok = exits_ok and node.has_tag(&"level_exit")
	if not exits_ok:
		problems["выходы: число, глубина, сцена, тег"].append("сид %d: %s" % [s, graph.exit_node_ids])

	var open_between: Dictionary = {}  # "глубже-мельче" -> открытых переходов
	var floor_links: Dictionary = {}  # "слой/этаж-этаж" -> переходов
	for node: RS_LevelNode in graph.nodes.values():
		var verticals := 0
		var horizontals := 0
		for conn: RS_LevelConnection in node.connections:
			var target := graph.get_node_data(conn.target_node_id)
			var vertical := target.depth != node.depth or target.floor_index != node.floor_index
			if vertical:
				verticals += 1
				if target.depth < node.depth and not conn.is_locked():
					var key := "%d-%d" % [node.depth, target.depth]
					open_between[key] = open_between.get(key, 0) + 1
				elif target.depth == node.depth and target.floor_index == node.floor_index + 1:
					var key := "%d/%d-%d" % [node.depth, node.floor_index, target.floor_index]
					floor_links[key] = floor_links.get(key, 0) + 1
				continue
			horizontals += 1
			if node.role == RS_LevelNode.Role.ROOM and target.role != RS_LevelNode.Role.CORRIDOR:
				problems["двери комнаты ведут в ветки её этажа"].append("сид %d %s→%s" % [s, node.id, target.id])

		if verticals > 1:
			problems["не больше одного вертикального ребра на узел"].append("сид %d %s" % [s, node.id])

		if node.role == RS_LevelNode.Role.ROOM:
			var doors := RS_RoomLayout.door_count_of_scene(node.room_scene_path)
			if horizontals != doors:
				problems["у комнаты рёбер в коридоры ровно столько, сколько дверей в сцене"].append(
					"сид %d %s: рёбер %d, дверей %d" % [s, node.id, horizontals, doors]
				)
			if _has_portal(node.room_scene_path) != (verticals > 0):
				problems["портал в сцене ровно тогда, когда есть вертикальное ребро"].append(
					"сид %d %s" % [s, node.id]
				)
		else:
			var rooms := 0
			for conn: RS_LevelConnection in node.connections:
				var target := graph.get_node_data(conn.target_node_id)
				if target.role == RS_LevelNode.Role.ROOM:
					rooms += 1
			if rooms == 0 or verticals > 0 or node.room_scene_path != "":
				problems["у каждой ветки есть хотя бы одна комната, и живёт она в своём этаже"].append(
					"сид %d %s" % [s, node.id]
				)

	for i in range(RS_LevelGraph.DEPTHS.size() - 1):
		var key := "%d-%d" % [RS_LevelGraph.DEPTHS[i], RS_LevelGraph.DEPTHS[i + 1]]
		if open_between.get(key, 0) == 0:
			problems["каждая пара соседних слоёв связана открытым переходом"].append("сид %d %s" % [s, key])

	for depth: int in RS_LevelGraph.DEPTHS:
		var floors := 0
		for node in graph.get_nodes_by_depth(depth):
			floors = maxi(floors, node.floor_index + 1)
		for f in range(floors - 1):
			if floor_links.get("%d/%d-%d" % [depth, f, f + 1], 0) == 0:
				problems["каждая пара этажей слоя связана переходом"].append("сид %d слой %d этаж %d" % [s, depth, f])


func _check_determinism(config: RS_WorldGenConfig) -> void:
	var diverged: Array[int] = []
	for s in 5:
		var a := RS_LevelGraph.new().generate_run(s, _library, config)
		var b := RS_LevelGraph.new().generate_run(s, _library, config)
		if _signature(a) != _signature(b):
			diverged.append(s)
	_check("один сид — один комплекс", diverged.is_empty(), str(diverged))



## HOME_DEPTH — глубина хаба для инструментов и отладки, а хаб ставит конфиг.
## Разойдутся — вкладка «Генератор мира» по умолчанию откроет не тот слой, и
## заметит это только глаз.
func _check_home_depth(config: RS_WorldGenConfig) -> void:
	var graph := RS_LevelGraph.new().generate_run(0, _library, config)
	var entry := graph.get_node_data(graph.entry_node_id)
	_check("HOME_DEPTH совпадает с глубиной хаба из конфига",
		entry != null and entry.depth == RS_LevelGraph.HOME_DEPTH,
		"хаб на L%d, HOME_DEPTH=%d" % [entry.depth if entry else -1, RS_LevelGraph.HOME_DEPTH])


## Уникальная комната «как Архитектор»: шанс 0 — её нет нигде, в том числе
## обычным подбором (пресет уникальной из пула исключён); шанс 1 — ровно одна, в
## своём диапазоне глубин, и рёбер у неё столько, сколько дверей в сцене.
func _check_unique_chance(config: RS_WorldGenConfig) -> void:
	var stand_in := load(STAND_IN_PRESET) as RS_RoomPreset
	var scene_path := stand_in.scene.resource_path
	for chance: float in [0.0, 1.0]:
		var with_unique := config.duplicate() as RS_WorldGenConfig
		var unique := RS_UniqueRoom.new()
		unique.preset = stand_in
		unique.depth_min = 1
		unique.depth_max = 4
		unique.chance = chance
		with_unique.unique_rooms = config.unique_rooms.duplicate()
		with_unique.unique_rooms.append(unique)

		var counts: Array[int] = []
		var out_of_range := 0
		for s in 10:
			var graph := RS_LevelGraph.new().generate_run(s, _library, with_unique)
			var found := 0
			for node: RS_LevelNode in graph.nodes.values():
				if node.room_scene_path == scene_path:
					found += 1
					if not unique.covers_depth(node.depth):
						out_of_range += 1
			counts.append(found)
		var expected := 0 if chance == 0.0 else 1
		_check("уникальная с шансом %.0f встречается %d раз на забег" % [chance, expected],
			counts.all(func(c): return c == expected), str(counts))
		if chance > 0.0:
			_check("и стоит в своём диапазоне глубин", out_of_range == 0, "вне диапазона %d" % out_of_range)


## Снимок ручек: новый забег снимает конфиг в сейв, начатый — продолжает по
## снимку, даже если базовый конфиг с тех пор поменялся. Сейв подменяется в
## памяти и возвращается; на диск прогон не пишет.
func _check_snapshot() -> void:
	var original := WorldSave.save
	var fresh := RS_WorldSave.new()
	WorldSave.save = fresh

	var taken: RS_WorldGenConfig = RunManager._run_gen_config()
	_check("новый забег снимает ручки в сейв",
		taken != null and fresh.gen_config == taken and taken != GameConfig.config.world_gen, "")

	var in_progress := RS_WorldSave.new()
	in_progress.run_in_progress = true
	in_progress.gen_config = GameConfig.config.world_gen.duplicate() as RS_WorldGenConfig
	in_progress.gen_config.rooms_per_floor = 7
	WorldSave.save = in_progress
	var continued: RS_WorldGenConfig = RunManager._run_gen_config()
	_check("начатый забег идёт по своему снимку, а не по базе",
		continued == in_progress.gen_config and continued.rooms_per_floor == 7, "")

	in_progress.clear_run()
	_check("конец забега отпускает снимок", in_progress.gen_config == null, "")

	WorldSave.save = original


# ---------------------------------------------------------------------------


func _unique(config: RS_WorldGenConfig, entry: bool, exit: bool) -> RS_UniqueRoom:
	for unique: RS_UniqueRoom in config.unique_rooms:
		if unique and unique.entry == entry and unique.exit == exit:
			return unique
	return null


func _reachable(graph: RS_LevelGraph) -> Dictionary:
	var seen := {graph.entry_node_id: true}
	var queue: Array[StringName] = [graph.entry_node_id]
	while not queue.is_empty():
		var node := graph.get_node_data(queue.pop_front())
		if node == null:
			continue
		for conn: RS_LevelConnection in node.connections:
			if not seen.has(conn.target_node_id):
				seen[conn.target_node_id] = true
				queue.append(conn.target_node_id)
	return seen


## Есть ли в сцене вертикальный портал — по самой сцене, а не по тегу пресета:
## тег мог разойтись со сценой, а сверять надо с тем, что встанет в мире.
func _has_portal(scene_path: String) -> bool:
	if _portal_by_scene.has(scene_path):
		return _portal_by_scene[scene_path]
	var found := false
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		found = not room.find_children("*", "E_VerticalPortal", true, false).is_empty()
		room.free()
	_portal_by_scene[scene_path] = found
	return found


func _signature(graph: RS_LevelGraph) -> String:
	var lines: Array[String] = []
	for node: RS_LevelNode in graph.nodes.values():
		var conns: Array[String] = []
		for conn: RS_LevelConnection in node.connections:
			conns.append("%s:%d:%s:%d" % [conn.target_node_id, conn.type, conn.locked_by, conn.depth_delta])
		lines.append("%s|%d|%s|%s|%s|%d|%d|%s" % [
			node.id, node.role, node.room_scene_path, node.room_type, node.tags,
			node.floor_index, node.index_in_layer, ",".join(conns),
		])
	lines.append("entry=%s exits=%s" % [graph.entry_node_id, graph.exit_node_ids])
	return "\n".join(lines)


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
