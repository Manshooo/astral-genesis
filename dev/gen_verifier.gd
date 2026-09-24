extends Node
## Дебаг-верификатор генератора уровня + библиотеки пресетов. Запусти сцену
## dev/gen_verifier.tscn (F6) — печатает по нескольким сидам:
##   - проблемы RS_RoomPresetLibrary.validate() (рассинхрон slot_count ↔ сцена);
##   - достижимость узлов от entry ДВУМЯ способами:
##       * по графу  — связен ли граф вообще (гарантия генератора);
##       * по дверям — что реально проходимо в мире: из комнаты в ветку коридора
##                     только через дверь на стороне, которую план отдал этой
##                     ветке (RS_LayerPlan.door_sides), на другой этаж или слой —
##                     только если в сцене есть портал;
##   - узлы с БОЛЬШЕ ЧЕМ ОДНИМ вертикальным ребром (смена глубины или этажа) —
##     портал в комнате один (LayerStreamer._bind_portals), лишнему ребру некуда деться;
##   - «заваренные двери»: дверей в сцене минус рёбер комнаты в коридоры. С
##     коридорами рёбер у комнаты ровно столько, сколько дверей, и метрика обязана
##     быть нулём — ненулевая значит, что подбор и раскладка разошлись со сценой;
##   - отказы трассы коридоров (RS_LayerPlan.routing_failures) и тайлы на этаж.
## Итоговую строку «Итог: …» разбирает dev/run_checks.ps1 — формат менять
## только вместе с ним.

const SEED_COUNT := 20

var _portal_cache: Dictionary[String, bool] = {}


func _ready() -> void:
	var library := GameConfig.config.room_preset_library as RS_RoomPresetLibrary
	var config := GameConfig.config.world_gen
	print("=== GEN VERIFIER (%d сидов) ===" % SEED_COUNT)
	_report_library(library)

	var worst_graph := 0
	var worst_doors := 0
	var worst_multi_vertical := 0
	var total_sealed_sum := 0
	var rooms_sum := 0
	var failures_sum := 0
	var tiles_sum := 0
	var floors_sum := 0
	var type_totals := {}
	for s in SEED_COUNT:
		var res := _verify_seed(s, library, config)
		for key: StringName in res["types"]:
			type_totals[key] = type_totals.get(key, 0) + res["types"][key]
		worst_graph = maxi(worst_graph, res["unreachable_graph"])
		worst_doors = maxi(worst_doors, res["unreachable_doors"])
		worst_multi_vertical = maxi(worst_multi_vertical, res["multi_vertical"])
		total_sealed_sum += res["sealed"]
		rooms_sum += res["rooms"]
		failures_sum += res["failures"]
		tiles_sum += res["tiles"]
		floors_sum += res["floors"]

	print(
		"--- Итог: макс. недостижимо по графу=%d, по дверям=%d, макс. узлов с 2+ вертикальными рёбрами=%d ---"
		% [worst_graph, worst_doors, worst_multi_vertical]
	)
	print("--- Заваренные двери: %d на %d комнат (обязано быть 0) ---" % [total_sealed_sum, rooms_sum])
	print(
		"--- Коридоры: %d тайлов на %d этажей (%.1f на этаж), отказов трассы %d ---"
		% [tiles_sum, floors_sum, float(tiles_sum) / maxi(floors_sum, 1), failures_sum]
	)
	_report_room_types(library, type_totals, rooms_sum)
	if library == null:
		print("ПОДСКАЗКА: room_preset_library не назначена в data/game_config.tres — всё на placeholder.")


## Распределение типов помещений по всем прогонам. Каталог задаёт, что МОЖЕТ
## выпасть, но встанет тип только там, где под него есть пресет: расхождение
## между «каталог знает 11 типов» и «в графе встречается один» — это не поломка,
## а мера того, сколько комнат ещё не нарисовано.
func _report_room_types(library: RS_RoomPresetLibrary, totals: Dictionary, total_rooms: int) -> void:
	if total_rooms <= 0:
		return
	var catalog := library.type_catalog if library else null

	var parts: Array[String] = []
	var keys := totals.keys()
	keys.sort_custom(func(a, b) -> bool: return totals[a] > totals[b])
	for key: StringName in keys:
		var label := catalog.label_of(key) if catalog else ("—" if key == &"" else String(key))
		parts.append("%s=%d" % [label, totals[key]])
	print(
		"--- Типы помещений (%s, %d встретилось): %s ---"
		% [
			("%d в каталоге" % catalog.types.size()) if catalog else "каталог не назначен",
			maxi(totals.size() - 1, 0),
			", ".join(parts),
		]
	)


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


func _verify_seed(seed_value: int, library: RS_RoomPresetLibrary, config: RS_WorldGenConfig) -> Dictionary:
	var graph := RS_LevelGraph.new().generate_run(seed_value, library, config)
	var plans: Dictionary = {}  # depth -> RS_LayerPlan
	var failures := 0
	var tiles := 0
	var floors := 0
	for depth: int in RS_LevelGraph.DEPTHS:
		var plan := RS_LayerPlan.build(graph.get_nodes_by_depth(depth), config)
		plans[depth] = plan
		failures += plan.routing_failures.size()
		tiles += plan.corridor_tiles.size()
		var seen_floors := {}
		for node in graph.get_nodes_by_depth(depth):
			seen_floors[node.floor_index] = true
		floors += seen_floors.size()

	var rooms := 0
	var sealed := 0
	for node: RS_LevelNode in graph.nodes.values():
		if node.role != RS_LevelNode.Role.ROOM:
			continue
		rooms += 1
		sealed += maxi(RS_RoomLayout.door_count_of_scene(node.room_scene_path) - _horizontal_edges(graph, node), 0)

	var unreachable_graph := _bfs_unreachable(graph, plans, false).size()
	var unreachable_doors := _bfs_unreachable(graph, plans, true).size()
	var multi_vertical := _multi_vertical_edge_nodes(graph).size()

	print(
		"seed %2d: узлов=%d (комнат %d), недостижимо граф=%d / двери=%d, узлов с 2+ вертикальными рёбрами=%d, заварено=%d, тайлов=%d, отказов трассы=%d"
		% [seed_value, graph.nodes.size(), rooms, unreachable_graph, unreachable_doors, multi_vertical, sealed, tiles, failures]
	)
	return {
		"unreachable_graph": unreachable_graph,
		"unreachable_doors": unreachable_doors,
		"multi_vertical": multi_vertical,
		"sealed": sealed,
		"rooms": rooms,
		"failures": failures,
		"tiles": tiles,
		"floors": floors,
		"types": _room_type_counts(graph),
	}


## Сколько комнат каждого типа реально встало в графе — метрика, не проверка.
## Считается по ФАКТИЧЕСКОМУ room_type узла (после подбора он равен типу
## вставшего пресета), а не по загаданному: интересно, чем комплекс населён на
## самом деле, а не что генератор хотел.
func _room_type_counts(graph: RS_LevelGraph) -> Dictionary:
	var counts := {}
	for node: RS_LevelNode in graph.nodes.values():
		if node.role != RS_LevelNode.Role.ROOM:
			continue
		var key: StringName = node.room_type
		counts[key] = counts.get(key, 0) + 1
	return counts


func _is_vertical(node: RS_LevelNode, target: RS_LevelNode) -> bool:
	return target.depth != node.depth or target.floor_index != node.floor_index


func _horizontal_edges(graph: RS_LevelGraph, node: RS_LevelNode) -> int:
	var count := 0
	for conn: RS_LevelConnection in node.connections:
		var target := graph.get_node_data(conn.target_node_id)
		if target != null and not _is_vertical(node, target):
			count += 1
	return count


## Узлы с БОЛЬШЕ ЧЕМ ОДНИМ вертикальным ребром (смена глубины или этажа). В
## комнате ровно один портал, и второму такому ребру некуда деться.
func _multi_vertical_edge_nodes(graph: RS_LevelGraph) -> Array:
	var result: Array = []
	for node: RS_LevelNode in graph.nodes.values():
		var vertical_edges := 0
		for conn: RS_LevelConnection in node.connections:
			var target := graph.get_node_data(conn.target_node_id)
			if target != null and _is_vertical(node, target):
				vertical_edges += 1
		if vertical_edges > 1:
			result.append(node.id)
	return result


## BFS от entry. [param physical] — ходить только так, как пустит мир: из
## комнаты в ветку — через дверь, которую план поставил на эту ветку (а пар
## «сторона → ветка» столько, сколько дверей), вертикальным ребром — только если
## в сцене комнаты есть портал. Ветка коридора пропускает по всем своим рёбрам:
## стыки веток открыты.
func _bfs_unreachable(graph: RS_LevelGraph, plans: Dictionary, physical: bool) -> Array:
	var seen: Dictionary = {graph.entry_node_id: true}
	var queue: Array = [graph.entry_node_id]
	while not queue.is_empty():
		var node := graph.get_node_data(queue.pop_front())
		if node == null:
			continue
		var reachable: Array[StringName] = []
		if not physical or node.role == RS_LevelNode.Role.CORRIDOR:
			for conn: RS_LevelConnection in node.connections:
				reachable.append(conn.target_node_id)
		else:
			var plan: RS_LayerPlan = plans[node.depth]
			reachable.append_array(plan.door_sides.get(node.id, {}).values())
			if _has_portal(node.room_scene_path):
				for conn: RS_LevelConnection in node.connections:
					var target := graph.get_node_data(conn.target_node_id)
					if target != null and _is_vertical(node, target):
						reachable.append(conn.target_node_id)
		for target_id in reachable:
			if not seen.has(target_id):
				seen[target_id] = true
				queue.append(target_id)

	var unreachable: Array = []
	for nid in graph.nodes.keys():
		if not seen.has(nid):
			unreachable.append(nid)
	return unreachable


func _has_portal(scene_path: String) -> bool:
	if _portal_cache.has(scene_path):
		return _portal_cache[scene_path]
	var found := false
	if scene_path != "" and ResourceLoader.exists(scene_path):
		var room := (load(scene_path) as PackedScene).instantiate()
		found = not room.find_children("*", "E_VerticalPortal", true, false).is_empty()
		room.free()
	_portal_cache[scene_path] = found
	return found
