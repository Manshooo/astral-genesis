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
## не входят. Инлайн-редактор пресета в боковой панели (world_gen.gd, v3-
## стретч) проверяется только на ЧТЕНИЕ — какой пресет резолвится и что форма
## им заполняется; сами обработчики правки (_on_slot_changed и т.д.) пишут в
## реальные файлы проекта и здесь не зовутся — та же дисциплина, что у кнопок
## Room Wizard (см. dev/room_wizard_check.gd).

var _ok := 0
var _fail := 0

const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const WorldGen := preload("res://addons/game_design_tool/tabs/world_gen.gd")
const LIBRARY_PATH := "res://data/room_preset_library.tres"
const SEED_COUNT := 30
## Сид с известным составом узлов — для проверки инлайн-редактора пресета
## достаточно одного прогона, не всех тридцати.
const INLINE_EDITOR_SEED := 0


func _ready() -> void:
	var library := ResourceLoader.load(LIBRARY_PATH) as RS_RoomPresetLibrary
	_check("библиотека пресетов загружается", library != null, LIBRARY_PATH)

	var host := ViewportHost.new()
	add_child(host)

	for seed_value in range(SEED_COUNT):
		_check_seed(seed_value, library, host)

	_check_inline_preset_editor()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## Читает форму инлайн-редактора после клика по узлу — не пишет ничего.
func _check_inline_preset_editor() -> void:
	var tab := WorldGen.new()
	add_child(tab)
	tab._seed_spin.value = INLINE_EDITOR_SEED
	tab._rebuild_graph()

	# Узел с пресетом: любой, для чьей сцены RS_RoomPresetLibrary реально
	# подобрала пресет из библиотеки (не хаб — тот отдельная авторская сцена,
	# не пресет, и не placeholder — генерация с реальной библиотекой их не
	# оставляет).
	var with_preset: RS_LevelNode
	for node_data: RS_LevelNode in tab._graph.nodes.values():
		if tab._preset_for(node_data) != null:
			with_preset = node_data
			break
	_check("seed %d: нашёлся узел с пресетом для проверки редактора" % INLINE_EDITOR_SEED, with_preset != null, "")
	if with_preset:
		tab._on_node_picked(with_preset.id)
		var preset := tab._preset_for(with_preset)
		_check("узел с пресетом: секция редактора видима", tab._preset_section.visible, "")
		_check("узел с пресетом: _editing_preset — тот же ресурс", tab._editing_preset == preset, "")
		_check(
			"узел с пресетом: слоты в форме совпадают с ресурсом",
			int(tab._slot_spin.value) == preset.slot_count,
			"форма=%d, ресурс=%d" % [int(tab._slot_spin.value), preset.slot_count]
		)
		_check(
			"узел с пресетом: вес в форме совпадает с ресурсом",
			is_equal_approx(tab._weight_spin.value, preset.weight),
			"форма=%s, ресурс=%s" % [tab._weight_spin.value, preset.weight]
		)
		var chip_count: int = tab._tag_flow.get_child_count()
		_check(
			"узел с пресетом: чекбоксов тегов по числу известных тегов",
			chip_count == tab._known_tags.size(),
			"чипов=%d, известных тегов=%d" % [chip_count, tab._known_tags.size()]
		)

	# Хаб — авторская сцена дома, не пресет из библиотеки: секция обязана
	# спрятаться, а не показать пустую/чужую форму.
	var hub_data := tab._graph.get_node_data(tab._graph.entry_node_id)
	tab._on_node_picked(hub_data.id)
	_check("узел хаба: пресет не найден", tab._editing_preset == null, "")
	_check("узел хаба: секция редактора скрыта", not tab._preset_section.visible, "")

	tab._clear_selection()
	_check("после сброса выделения: секция редактора скрыта", not tab._preset_section.visible, "")

	tab.free()


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
