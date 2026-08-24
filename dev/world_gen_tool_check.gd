extends Node
## Проверяет тот слой редакторского тула «Генератор мира»
## (addons/game_design_tool/world/), который молча ломается: неверный пикинг
## или утёкшая геометрия не падают с ошибкой, они просто показывают не то,
## что нарисовано, — узнаётся только руками в редакторе, если вообще
## замечается. Headless-прогон: godot --headless dev/world_gen_tool_check.tscn
##
## Гоняет RS_LevelGraph.generate_run по 30 сидам, для каждой глубины строит
## RS_LayerPlan (тот же класс, которым RunManager раскладывает слой в игре —
## см. [[Цикл забега]]) и зовёт ViewportHost.show_layer(), как это делает
## сама вкладка при пересборке.
##
## EditorInterface-кнопки («Открыть пресет»/«Открыть сцену») не проверяются —
## их некуда звать headless, и в путь данных generate_run → plan → пикинг они
## не входят.

var _ok := 0
var _fail := 0

const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const LIBRARY_PATH := "res://data/room_preset_library.tres"
const SEED_COUNT := 30


func _ready() -> void:
	var library := ResourceLoader.load(LIBRARY_PATH) as RS_RoomPresetLibrary
	_check("библиотека пресетов загружается", library != null, LIBRARY_PATH)

	var host := ViewportHost.new()
	add_child(host)

	for seed_value in range(SEED_COUNT):
		_check_seed(seed_value, library, host)

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _check_seed(seed_value: int, library: RS_RoomPresetLibrary, host: ViewportHost) -> void:
	var graph := RS_LevelGraph.new().generate_run(seed_value, library)

	for depth: int in RS_LevelGraph.DEPTHS:
		var layer_nodes := graph.get_nodes_by_depth(depth)
		if layer_nodes.is_empty():
			continue
		var plan := RS_LayerPlan.build(layer_nodes)
		var label := "seed %d L%d" % [seed_value, depth]

		# --- 1. Оверлеи строят ровно по узлу на комнату/сферу, без утечек
		# предыдущей раскладки. Регресс на баг живого прогона: RoomsOverlay и
		# GraphOverlay чистили детей queue_free()'ом, а пересборка идёт
		# синхронно (сид/глубина меняются в один тик) — отложенное удаление не
		# успевало сработать между вызовами show_layer, и счётчик комнат рос от
		# слоя к слою. Чинит free() вместо queue_free() в обоих оверлеях.
		host.show_layer(graph, layer_nodes, plan)
		_check(
			"%s: комнат построено по числу узлов" % label,
			host._rooms_overlay.get_child_count() == layer_nodes.size(),
			"%d комнат, %d узлов" % [host._rooms_overlay.get_child_count(), layer_nodes.size()]
		)
		_check(
			"%s: сфер графа построено по числу узлов" % label,
			host._graph_overlay._spheres.size() == layer_nodes.size(),
			"%d сфер, %d узлов" % [host._graph_overlay._spheres.size(), layer_nodes.size()]
		)

		# --- 2. Пикинг: ray-vs-AABB находит узел, а не соседа снизу/сверху.
		# Луч пускается из точки ВНУТРИ коробки конкретной комнаты, а не
		# откуда-то сверху всего слоя: этажи одного depth штатно стоят друг
		# над другом по одной сетке X/Z (связаны floor_hub — то же самое,
		# что видит игрок), и луч издалека сверху честно нашёл бы ближайший
		# по лучу этаж, а не тот, что проверяется. Коробки высотой 7 м при
		# разносе FLOOR_SPACING=20 м не пересекаются, так что точка чуть выше
		# пола комнаты гарантированно принадлежит только её собственной коробке.
		for node_data: RS_LevelNode in layer_nodes:
			var pos: Vector3 = plan.positions[node_data.id]
			var picked := Picker.pick(pos + Vector3(0, 3.0, 0), Vector3.DOWN, layer_nodes, plan)
			_check(
				"%s: пикинг узла %s находит его самого" % [label, node_data.id],
				picked == node_data.id,
				"нашёл %s" % (picked if picked != &"" else "ничего")
			)

		# Луч мимо всех комнат слоя не должен ничего находить.
		var far_pick := Picker.pick(Vector3(100000, 50, 100000), Vector3.DOWN, layer_nodes, plan)
		_check("%s: луч мимо слоя не пикает ничего" % label, far_pick == &"", "нашёл %s" % far_pick)

	# --- 3. Сброс статического кэша RS_RoomLayout (зовётся вкладкой на
	# «Пересобрать») не должен падать и не должен ломать последующие запросы.
	RS_RoomLayout.clear_scene_cache()
	_check("seed %d: clear_scene_cache отрабатывает" % seed_value, true, "")


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
