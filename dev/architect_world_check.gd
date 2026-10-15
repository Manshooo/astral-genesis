extends "res://dev/check_harness.gd"
## Проверка шести слоёв и улучшений Архитектора, меняющих генерацию (карточка
## «Игровой цикл — от и до», §2 и §4.3): L5 в графе забега, «Меньше тупиков»,
## «Короткие пути», «Переходы ближе ко входу» и то, как они ложатся в снимок ручек.
##
## Всё здесь ломается тихо. Слой без перехода вниз не падает — он просто тупик
## для игрока. Улучшение, куплённое за тысячи эссенции и не доехавшее до снимка,
## выглядит как «неудачный сид». Улучшение, применённое к живой базе вместо
## копии, меняет уже начатый забег. Предпочтение переходов, потратившее лишний
## бросок, перекраивает весь комплекс, а не только переходы.
##
## Сейвы подменяются на время прогона и возвращаются: проверка вызывает
## RunManager._run_gen_config, а тот пишет в сейв забега.
##
## Запускать: godot --headless dev/architect_world_check.tscn

const SEEDS := 12
const CONFIG_PATH := "res://data/world_gen_config.tres"
## Доля, на которую «ближе ко входу» обязано сократить путь вниз по слою. Замер
## на 40 сидах — см. _check_transit; порог с запасом, чтобы проверка ловила
## пропавший эффект, а не колебание выборки.
const TRANSIT_GAIN := 0.9

var _library: RS_RoomPresetLibrary
var _world_save: RS_WorldSave
var _architect_save: PlayerSkillSave


func _ready() -> void:
	_print_passes = false
	_library = GameConfig.config.room_preset_library
	_world_save = WorldSave.save
	_architect_save = ArchitectManager.save
	var base := load(CONFIG_PATH) as RS_WorldGenConfig

	_check_six_layers(base)
	_check_layout_upgrades(base)
	_check_transit(base)
	_check_snapshot()

	_restore()
	_finish()


# --- 1. Шесть слоёв -----------------------------------------------------------


func _check_six_layers(base: RS_WorldGenConfig) -> void:
	_check("слои идут от дна к поверхности: 5..0",
		RS_LevelGraph.DEPTHS == [5, 4, 3, 2, 1, 0], str(RS_LevelGraph.DEPTHS))

	var diverged: Array[int] = []
	var missing: Array[String] = []
	var closed: Array[String] = []
	var below: Array[String] = []
	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, _library, base)
		if _signature(graph) != _signature(RS_LevelGraph.new().generate_run(s, _library, base)):
			diverged.append(s)
		for depth: int in RS_LevelGraph.DEPTHS:
			if graph.get_nodes_by_depth(depth).is_empty():
				missing.append("сид %d L%d" % [s, depth])
		# Открытый переход на каждую пару соседних слоёв: ключей нет, запертая
		# наглухо пара — непроходимый забег.
		var open_between := {}
		for node: RS_LevelNode in graph.nodes.values():
			for conn: RS_LevelConnection in node.connections:
				var target := graph.get_node_data(conn.target_node_id)
				if not conn.is_portal() or target == null or target.depth == node.depth:
					continue
				if absi(target.depth - node.depth) != 1:
					closed.append("сид %d: %s → %s прыгает через слой" % [s, node.id, target.id])
				if node.depth == 5 and target.depth > node.depth:
					below.append("сид %d: %s → %s" % [s, node.id, target.id])
				if not conn.is_locked():
					open_between[mini(node.depth, target.depth)] = true
		for depth in 5:
			if not open_between.has(depth):
				closed.append("сид %d: L%d–L%d" % [s, depth, depth + 1])
	_check("один сид — один комплекс на шести слоях (%d сидов)" % SEEDS, diverged.is_empty(), str(diverged))
	_check("на каждом из шести слоёв есть комнаты", missing.is_empty(), ", ".join(missing.slice(0, 4)))
	_check("каждая пара соседних слоёв связана открытым переходом, через слой не прыгает",
		closed.is_empty(), ", ".join(closed.slice(0, 4)))
	_check("с L5 вниз перехода нет", below.is_empty(), ", ".join(below.slice(0, 4)))

	# Тип помещения у узла разыгрывается в каталоге по глубине; если отрезок типа
	# обрывается на L4, дно остаётся без полигона, содержания существ и артефактов.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var at_bottom := {}
	for i in 400:
		at_bottom[_library.type_catalog.pick_for_depth(5, rng)] = true
	var absent: Array[String] = []
	for id in [&"proving_ground", &"creature_containment", &"artifact_containment", &"lab", &"storage"]:
		if not at_bottom.has(id):
			absent.append(String(id))
	_check("на дне разыгрываются полигон, существа, артефакты, лаборатории и склады",
		absent.is_empty(), "нет: %s" % ", ".join(absent))


## Подпись графа: узлы, сцены и рёбра в стабильном порядке.
func _signature(graph: RS_LevelGraph) -> String:
	var ids: Array = graph.nodes.keys()
	ids.sort()
	var parts: PackedStringArray = []
	for id: StringName in ids:
		var node := graph.get_node_data(id)
		var targets: PackedStringArray = []
		for conn: RS_LevelConnection in node.connections:
			targets.append("%s:%d:%s" % [conn.target_node_id, conn.type, conn.locked_by])
		parts.append("%s|%s|%d|%s" % [id, node.room_scene_path, node.turns, ",".join(targets)])
	return "\n".join(parts)


# --- 2. Тупики и петли ----------------------------------------------------------


func _check_layout_upgrades(base: RS_WorldGenConfig) -> void:
	var plain := base.duplicate() as RS_WorldGenConfig
	var upgraded := base.duplicate() as RS_WorldGenConfig
	_buy_all()
	ArchitectManager.apply_to_gen_config(upgraded)

	_check("«Меньше тупиков» снимает ручку, но не до нуля",
		upgraded.dead_ends < plain.dead_ends and upgraded.dead_ends >= 1,
		"было %d, стало %d" % [plain.dead_ends, upgraded.dead_ends])
	_check("«Короткие пути» добавляют петли в пределах ручки",
		upgraded.corridor_loops > plain.corridor_loops and upgraded.corridor_loops <= 4,
		"было %d, стало %d" % [plain.corridor_loops, upgraded.corridor_loops])

	var before := RS_LayoutMetrics.new()
	var after := RS_LayoutMetrics.new()
	for s in SEEDS:
		before.add(_metrics(s, plain))
		after.add(_metrics(s, upgraded))
	print("  тупиков на этаж %.2f → %.2f, петель по коридору %.2f → %.2f" % [
		before.dead_ends_per_floor(), after.dead_ends_per_floor(),
		before.corridor_loops_per_floor(), after.corridor_loops_per_floor()])
	_check("на тех же сидах в плане тупиков меньше, но они остались",
		after.dead_ends < before.dead_ends and after.dead_ends > 0,
		"%d → %d" % [before.dead_ends, after.dead_ends])
	_check("на тех же сидах в плане петель по коридору больше",
		after.corridor_loops > before.corridor_loops,
		"%d → %d" % [before.corridor_loops, after.corridor_loops])


func _metrics(s: int, config: RS_WorldGenConfig) -> RS_LayoutMetrics:
	var graph := RS_LevelGraph.new().generate_run(s, _library, config)
	var metrics := RS_LayoutMetrics.new()
	for depth: int in RS_LevelGraph.DEPTHS:
		metrics.add(RS_LayoutMetrics.of_plan(graph.layer_plan(depth)))
	return metrics


# --- 3. Переходы ближе ко входу ---------------------------------------------------


func _check_transit(base: RS_WorldGenConfig) -> void:
	var far := base.duplicate() as RS_WorldGenConfig
	var near := base.duplicate() as RS_WorldGenConfig
	var half := base.duplicate() as RS_WorldGenConfig
	far.transit_near_entry = 0.0
	half.transit_near_entry = 0.5
	near.transit_near_entry = 1.0

	var sums := [0.0, 0.0, 0.0]
	var counts := [0, 0, 0]
	var unreachable := 0
	var spent: Array[String] = []
	for s in 40:
		var graphs := [
			RS_LevelGraph.new().generate_run(s, _library, far),
			RS_LevelGraph.new().generate_run(s, _library, half),
			RS_LevelGraph.new().generate_run(s, _library, near),
		]
		for i in graphs.size():
			for depth in [4, 3, 2, 1]:
				var way := _way_down(graphs[i], depth)
				if way < 0:
					unreachable += 1
					continue
				sums[i] += way
				counts[i] += 1
		# Предпочтение — порядок кандидатов после броска: rng тратится одинаково,
		# поэтому комнаты, которых предпочтение не касается, остаются прежними.
		if not _unrelated_rooms_equal(graphs[0], graphs[2]):
			spent.append("сид %d" % s)
	var means: Array[float] = []
	for i in 3:
		means.append(sums[i] / maxi(counts[i], 1))
	print("  путь вниз по слою, рёбер: 0.0 → %.2f, 0.5 → %.2f, 1.0 → %.2f (слоёв %d, недостижимых %d)"
		% [means[0], means[1], means[2], counts[0], unreachable])
	_check("от входа слоя до перехода вниз всегда есть путь по рёбрам", unreachable == 0, "слоёв без пути: %d" % unreachable)
	_check("«ближе ко входу» сокращает путь вниз по графу",
		means[2] < means[0] * TRANSIT_GAIN, "%.2f против %.2f" % [means[2], means[0]])
	_check("полсилы — между нулём и полной силой",
		means[1] <= means[0] and means[1] >= means[2] - 0.001, "%.2f / %.2f / %.2f" % [means[0], means[1], means[2]])
	_check("предпочтение не тратит броски: остальные комнаты те же", spent.is_empty(), ", ".join(spent.slice(0, 4)))


## Комнаты, которых предпочтение не касается, в двух графах одинаковы. Касается
## оно только того, на какие узлы лёг тег портала; у узла с тем же набором тегов
## подбор сцены берёт тот же бросок из того же места общего потока — если поток
## сдвинулся (лишний или пропущенный бросок), разойдутся почти все.
func _unrelated_rooms_equal(a: RS_LevelGraph, b: RS_LevelGraph) -> bool:
	var compared := 0
	for id: StringName in a.nodes:
		var x := a.get_node_data(id)
		var y := b.get_node_data(id)
		if y == null or x.role != RS_LevelNode.Role.ROOM or x.tags != y.tags:
			continue
		compared += 1
		if x.room_scene_path != y.room_scene_path or x.turns != y.turns:
			return false
	return compared > 0


## Длина кратчайшего пути по рёбрам графа внутри слоя [param depth] от места
## прихода до комнаты с переходом вниз; −1 — пути нет. Приход — вход (на слое хаба
## игрок начинает с него) или комнаты с переходом наверх. Рёбра-порталы не идут:
## путь считается внутри слоя.
func _way_down(graph: RS_LevelGraph, depth: int) -> int:
	var arrivals: Array[StringName] = []
	var exits := {}
	for node in graph.get_nodes_by_depth(depth):
		for conn: RS_LevelConnection in node.connections:
			var target := graph.get_node_data(conn.target_node_id)
			if not conn.is_portal() or target == null or target.depth == depth:
				continue
			if target.depth < depth:
				arrivals.append(node.id)
			else:
				exits[node.id] = true
	var entry := graph.get_node_data(graph.entry_node_id)
	if entry != null and entry.depth == depth:
		arrivals = [entry.id]
	if arrivals.is_empty() or exits.is_empty():
		return -1
	var dist := {}
	var queue: Array[StringName] = []
	for id in arrivals:
		dist[id] = 0
		queue.append(id)
	var head := 0
	while head < queue.size():
		var id := queue[head]
		head += 1
		if exits.has(id):
			return dist[id]
		for conn: RS_LevelConnection in graph.get_node_data(id).connections:
			if conn.is_portal() or dist.has(conn.target_node_id):
				continue
			dist[conn.target_node_id] = dist[id] + 1
			queue.append(conn.target_node_id)
	return -1


# --- 4. Снимок ручек -----------------------------------------------------------------


func _check_snapshot() -> void:
	var base := GameConfig.config.world_gen
	var base_dead_ends := base.dead_ends
	var base_loops := base.corridor_loops

	ArchitectManager.save = ArchitectManager._fresh_save()
	var fresh := RS_WorldSave.new()
	WorldSave.save = fresh
	var untouched: RS_WorldGenConfig = RunManager._run_gen_config()
	_check("без улучшений снимок равен базе",
		untouched.dead_ends == base_dead_ends and untouched.corridor_loops == base_loops
			and is_zero_approx(untouched.transit_near_entry),
		"тупиков %d, петель %d" % [untouched.dead_ends, untouched.corridor_loops])

	_buy_all()
	fresh = RS_WorldSave.new()
	WorldSave.save = fresh
	var upgraded: RS_WorldGenConfig = RunManager._run_gen_config()
	_check("улучшения ложатся в снимок нового забега",
		upgraded.dead_ends < base_dead_ends and upgraded.corridor_loops > base_loops
			and is_equal_approx(upgraded.transit_near_entry, 1.0) and fresh.gen_config == upgraded,
		"тупиков %d, петель %d, переходы %.2f" % [upgraded.dead_ends, upgraded.corridor_loops, upgraded.transit_near_entry])
	_check("живая база от улучшений не меняется",
		base.dead_ends == base_dead_ends and base.corridor_loops == base_loops
			and is_zero_approx(base.transit_near_entry),
		"тупиков %d, петель %d" % [base.dead_ends, base.corridor_loops])

	# Купленное посреди забега действует со следующего: начатый комплекс строился
	# по другим ручкам, и сохранённый узел лёг бы в чужую комнату.
	var in_progress := RS_WorldSave.new()
	in_progress.run_in_progress = true
	in_progress.gen_config = base.duplicate() as RS_WorldGenConfig
	in_progress.generator_version = RS_LevelGraph.GENERATOR_VERSION
	WorldSave.save = in_progress
	var continued: RS_WorldGenConfig = RunManager._run_gen_config()
	_check("начатый забег улучшений не получает",
		continued == in_progress.gen_config and continued.dead_ends == base_dead_ends
			and continued.corridor_loops == base_loops and is_zero_approx(continued.transit_near_entry),
		"тупиков %d, петель %d" % [continued.dead_ends, continued.corridor_loops])

	# Предел, который не открывают данные: лишний ранг не выводит ручки из диапазона.
	for id in ArchitectManager.save.ranks:
		ArchitectManager.save.ranks[id] = 9
	var over := base.duplicate() as RS_WorldGenConfig
	ArchitectManager.apply_to_gen_config(over)
	_check("лишние ранги в данных не выводят ручки из диапазона",
		over.dead_ends >= 1 and over.corridor_loops <= 4 and over.transit_near_entry <= 1.0,
		"тупиков %d, петель %d, переходы %.2f" % [over.dead_ends, over.corridor_loops, over.transit_near_entry])

	WorldSave.save = _world_save


# ---------------------------------------------------------------------------


## Все ранги всех улучшений раскладки — без покупки: проверке нужно состояние
## дерева, а не путь к нему (цены сверяет architect_check).
func _buy_all() -> void:
	ArchitectManager.save = ArchitectManager._fresh_save()
	for def in ArchitectManager.SKILL_TREE.skills:
		ArchitectManager.save.ranks[def.id] = def.max_rank


func _restore() -> void:
	ArchitectManager.save = _architect_save
	WorldSave.save = _world_save
