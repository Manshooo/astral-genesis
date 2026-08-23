extends Node
## Дебаг-верификатор генератора уровня + библиотеки пресетов (ADR-0001/0003).
## Запусти сцену dev/gen_verifier.tscn (F6) — печатает по нескольким сидам:
##   - проблемы RS_RoomPresetLibrary.validate() (рассинхрон slot_count ↔ сцена);
##   - «недобор дверей»: узлы, где дверей меньше, чем рёбер (RunManager обрубит лишние);
##   - достижимость узлов от entry ДВУМЯ способами:
##       * по графу  — связен ли граф вообще (гарантия генератора);
##       * по дверям  — сколько реально проходимо, если из узла ведут только
##                      первые slot_count рёбер (так RunManager раздаёт C_DoorPortal).
##   - узлы с БОЛЬШЕ ЧЕМ ОДНИМ вертикальным (меняющим глубину) ребром — портал в
##     комнате один (RunManager._bind_portals), второе такое ребро утекало бы
##     обычной двери и на карте выглядело соседней комнатой этажа, хотя вело на
##     другой слой (v0.5.0 «Вертикальные переходы — только порталом»).
##   - «заваренные двери»: сумма (дверей в сцене - рёбер узла) по всему графу —
##     сколько дверей физически есть, но не ведут никуда (RunManager._seal_door).
##     Это НЕ провал сам по себе (часть неизбежна — тупики, нехватка пресетов
##     нужного размера), а метрика для настройки RS_RoomPresetLibrary
##     (EXCESS_SLOT_DECAY): смотреть на среднее по прогону при добавлении новых
##     пресетов/правке весов, а не на абсолютный ноль.
## Большая разница «граф vs двери» = комнат не хватает дверей (нужны пресеты).

const SEED_COUNT := 20

var _door_count_cache: Dictionary = {}  # scene_path -> int (C_DoorSlot; -1 если сцены нет)


func _ready() -> void:
	var library := GameConfig.config.room_preset_library as RS_RoomPresetLibrary
	print("=== GEN VERIFIER (%d сидов) ===" % SEED_COUNT)
	_report_library(library)

	var worst_graph := 0
	var worst_doors := 0
	var worst_multi_vertical := 0
	var total_sealed_sum := 0
	var nodes_with_sealed_sum := 0
	var total_nodes_sum := 0
	for s in SEED_COUNT:
		var res := _verify_seed(s, library)
		worst_graph = max(worst_graph, res["unreachable_graph"])
		worst_doors = max(worst_doors, res["unreachable_doors"])
		worst_multi_vertical = max(worst_multi_vertical, res["multi_vertical"])
		total_sealed_sum += res["total_sealed"]
		nodes_with_sealed_sum += res["nodes_with_sealed"]
		total_nodes_sum += res["total_nodes"]

	print(
		"--- Итог: макс. недостижимо по графу=%d, по дверям=%d, макс. узлов с 2+ вертикальными рёбрами=%d ---"
		% [worst_graph, worst_doors, worst_multi_vertical]
	)
	print(
		(
			"--- Заваренные двери: %d всего на %d узлов (%.2f на узел), узлов хоть с одной заваренной=%d (%.0f%%) ---"
			% [
				total_sealed_sum,
				total_nodes_sum,
				float(total_sealed_sum) / total_nodes_sum,
				nodes_with_sealed_sum,
				100.0 * nodes_with_sealed_sum / total_nodes_sum,
			]
		)
	)
	if library == null:
		print("ПОДСКАЗКА: room_preset_library не назначена в data/game_config.tres — всё на placeholder.")


func _report_library(library: RS_RoomPresetLibrary) -> void:
	if library == null:
		print("library == null")
		return
	var problems := library.validate()
	if problems.is_empty():
		print("validate(): OK (%d пресетов)" % library.presets.size())
	else:
		push_warning("validate(): %d проблем:" % problems.size())
		for p in problems:
			push_warning("  " + p)


func _verify_seed(seed_value: int, library: RS_RoomPresetLibrary) -> Dictionary:
	var graph := RS_LevelGraph.new().generate_run(seed_value, library)
	var total := graph.nodes.size()

	var undercap := _undercapacity_nodes(graph)
	var unreachable_graph := _bfs_unreachable(graph, false).size()
	var unreachable_doors := _bfs_unreachable(graph, true).size()
	var multi_vertical := _multi_vertical_edge_nodes(graph)
	var sealed := _sealed_door_stats(graph)

	print(
		(
			(
				"seed %2d: узлов=%d, недобор дверей=%d, недостижимо граф=%d / двери=%d, "
				+ "узлов с 2+ вертикальными рёбрами=%d, заварено дверей=%d (узлов=%d)"
			)
			% [
				seed_value,
				total,
				undercap.size(),
				unreachable_graph,
				unreachable_doors,
				multi_vertical.size(),
				sealed["total_sealed"],
				sealed["nodes_with_sealed"],
			]
		)
	)
	return {
		"unreachable_graph": unreachable_graph,
		"unreachable_doors": unreachable_doors,
		"multi_vertical": multi_vertical.size(),
		"total_sealed": sealed["total_sealed"],
		"nodes_with_sealed": sealed["nodes_with_sealed"],
		"total_nodes": total,
	}


## Узлы с БОЛЬШЕ ЧЕМ ОДНИМ вертикальным (меняющим depth) ребром. В комнате
## ровно один портал, поэтому второе такое ребро раньше утекало обычной двери
## (RunManager._bind_portals → rest → _bind_doors) и на карте выглядело
## соседней комнатой этажа, хотя вело на другой слой. RS_LevelGraph держит
## этот список пустым через _split_vertical_hub_pool — узел получает хаб-роль
## не больше одного раза за весь граф.
func _multi_vertical_edge_nodes(graph: RS_LevelGraph) -> Array:
	var result: Array = []
	for node in graph.nodes.values():
		var vertical_edges := 0
		for conn in node.connections:
			var target := graph.get_node_data(conn.target_node_id)
			if target != null and target.depth != node.depth:
				vertical_edges += 1
		if vertical_edges > 1:
			result.append(node.id)
	return result


## Сколько дверей в графе физически есть, но не ведут никуда (RunManager
## запечатает их _seal_door'ом), и на скольких узлах есть хотя бы одна такая.
## Не «баг» — часть неизбежна (тупики), но метрика для настройки весов
## RS_RoomPresetLibrary (EXCESS_SLOT_DECAY): комната с большим запасом дверей,
## из которых открыты одна-две, — ровно то, на что жаловались в задаче.
func _sealed_door_stats(graph: RS_LevelGraph) -> Dictionary:
	var total_sealed := 0
	var nodes_with_sealed := 0
	for node: RS_LevelNode in graph.nodes.values():
		var doors := _doors_in_scene(node.room_scene_path)
		if doors < 0:
			continue
		var sealed := doors - node.connections.size()
		if sealed > 0:
			total_sealed += sealed
			nodes_with_sealed += 1
	return {"total_sealed": total_sealed, "nodes_with_sealed": nodes_with_sealed}


## Узлы, где дверей в сцене меньше, чем рёбер (RunManager обрубит лишние рёбра).
func _undercapacity_nodes(graph: RS_LevelGraph) -> Array:
	var result: Array = []
	for node in graph.nodes.values():
		var doors := _doors_in_scene(node.room_scene_path)
		if doors >= 0 and doors < node.connections.size():
			result.append(node.id)
	return result


## BFS от entry. door_limited=true → из узла проходимы только первые
## slot_count рёбер (так RunManager раздаёт C_DoorPortal по порядку connections).
func _bfs_unreachable(graph: RS_LevelGraph, door_limited: bool) -> Array:
	var seen: Dictionary = {}
	var queue: Array = [graph.entry_node_id]
	seen[graph.entry_node_id] = true
	while not queue.is_empty():
		var current = queue.pop_front()
		var node := graph.get_node_data(current)
		if node == null:
			continue
		var conns := node.connections
		var reach := conns.size()
		if door_limited:
			var doors := _doors_in_scene(node.room_scene_path)
			if doors >= 0:
				reach = min(reach, doors)
		for i in reach:
			var target: StringName = conns[i].target_node_id
			if not seen.has(target):
				seen[target] = true
				queue.append(target)

	var unreachable: Array = []
	for nid in graph.nodes.keys():
		if not seen.has(nid):
			unreachable.append(nid)
	return unreachable


func _doors_in_scene(scene_path: String) -> int:
	if _door_count_cache.has(scene_path):
		return _door_count_cache[scene_path]
	var count := -1
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var inst := (load(scene_path) as PackedScene).instantiate()
		var slots := inst.find_children("*", "Entity", true, false).filter(
			func(n): return _has_door_slot(n)
		)
		count = slots.size()
		inst.free()
	_door_count_cache[scene_path] = count
	return count


## Есть ли на сущности слот двери. См. пояснение в rs_room_preset_library.gd:
## detached-инстанс не проходит _ready, поэтому has_component пуст — тогда
## смотрим component_resources (@export, доступен сразу после instantiate).
func _has_door_slot(n: Node) -> bool:
	if not (n is Entity):
		return false
	var e := n as Entity
	if e.has_component(C_DoorSlot):
		return true
	for c in e.component_resources:
		if c is C_DoorSlot:
			return true
	return false
