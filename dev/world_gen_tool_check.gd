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
##
## Состояние между сессиями (EditorSettings.set_project_metadata — сид/глубина/
## оверлеи/камера) тоже НЕ проверяется по чтению/записи в EditorSettings как
## таковой: headless-прогон сцены — это не работающий редактор
## (Engine.is_editor_hint() ложно), сам singleton не инициализирован, и звать
## его было бы ложным тестом чужого пути. Проверяется тот путь, который здесь
## реально исполняется — что _restore_state() безопасно откатывается на
## дефолты и всё равно строит граф, см. _check_restore_state.

var _ok := 0
var _fail := 0

const ViewportHost := preload("res://addons/game_design_tool/world/viewport_host.gd")
const Picker := preload("res://addons/game_design_tool/world/picker.gd")
const WorldGen := preload("res://addons/game_design_tool/tabs/world_gen.gd")
const LabelsOverlay := preload("res://addons/game_design_tool/world/overlays/labels_overlay.gd")
const OverlayRegistry := preload("res://addons/game_design_tool/world/overlay_registry.gd")
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
	_check_room_outline(library, host)
	_check_restore_state()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## RoomsOverlay.set_selected: material_overlay ставится РОВНО на геометрию
## выбранной комнаты и снимается с прежней при переключении/сбросе. Молчаливая
## поломка (например, если Entity-каст на комнату вдруг перестанет
## срабатывать) не бросила бы ошибку — обводка просто не появилась бы, и
## заметно это было бы только глазами в редакторе.
func _check_room_outline(library: RS_RoomPresetLibrary, host: ViewportHost) -> void:
	var graph := RS_LevelGraph.new().generate_run(0, library)
	var layer_nodes := graph.get_nodes_by_depth(RS_LevelGraph.HOME_DEPTH)
	if layer_nodes.size() < 2:
		_check("обводка: слой L%d содержит хотя бы 2 узла для теста" % RS_LevelGraph.HOME_DEPTH, false, "%d" % layer_nodes.size())
		return
	var plan := RS_LayerPlan.build(layer_nodes)
	host.show_layer(graph, layer_nodes, plan)

	var first_id := layer_nodes[0].id
	var second_id := layer_nodes[1].id
	var overlay := host._rooms_overlay
	var outline: Material = overlay.OUTLINE_MATERIAL

	overlay.set_selected(first_id)
	_check(
		"обводка: у выбранной комнаты material_overlay = обводка",
		_all_geometries_have_material(overlay, first_id, outline),
		""
	)

	overlay.set_selected(second_id)
	_check(
		"обводка: со старой комнаты снимается при смене выделения",
		_all_geometries_have_material(overlay, first_id, null),
		""
	)
	_check(
		"обводка: у новой выбранной комнаты material_overlay = обводка",
		_all_geometries_have_material(overlay, second_id, outline),
		""
	)

	overlay.set_selected(&"")
	_check(
		"обводка: снимается при сбросе выделения",
		_all_geometries_have_material(overlay, second_id, null),
		""
	)


func _all_geometries_have_material(overlay, node_id: StringName, material: Material) -> bool:
	var entity := overlay._rooms[node_id] as Entity
	var geometries := RS_EntityVisuals.geometries(entity)
	if geometries.is_empty():
		return false
	for geometry: GeometryInstance3D in geometries:
		if geometry.material_overlay != material:
			return false
	return true


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

		# Оверлей «Подписи»: одна подпись на слой, показывается только по
		# set_selected — строится независимо от текущей глубины вкладки
		# (with_preset может быть на любой), поэтому проверяется отдельным
		# оверлеем на СВОЁМ слое, а не через tab._host (тот показывает только
		# _current_depth()).
		var own_layer := tab._graph.get_nodes_by_depth(with_preset.depth)
		var own_plan := RS_LayerPlan.build(own_layer)
		var labels_overlay := LabelsOverlay.new()
		labels_overlay.rebuild(own_layer, own_plan, tab._preset_labels_for(own_layer))
		_check("после rebuild без выделения: подпись скрыта", not labels_overlay._label.visible, "")

		labels_overlay.set_selected(with_preset.id)
		_check("после set_selected: подпись видима", labels_overlay._label.visible, "")
		var label_text: String = labels_overlay._label.text
		_check(
			"узел с пресетом: подпись содержит id и имя пресета",
			label_text.contains(String(with_preset.id)) and label_text.contains(tab._label_of(preset)),
			label_text
		)

		# +5 м от ВЕРХА AABB комнаты, не просто «над узлом»: у комнат с разным
		# габаритом фиксированная высота либо утыкалась бы в потолок, либо
		# неоправданно далеко висела над низкой.
		var expected_aabb := Picker.room_aabb(with_preset.id, own_layer, own_plan)
		var expected_y: float = expected_aabb.position.y + expected_aabb.size.y + labels_overlay.ABOVE_AABB
		_check(
			"узел с пресетом: подпись стоит на +5 м от верха AABB комнаты",
			is_equal_approx(labels_overlay._label.position.y, expected_y),
			"подпись.y=%s, ожидалось=%s" % [labels_overlay._label.position.y, expected_y]
		)

		labels_overlay.set_selected(&"")
		_check("после сброса выделения: подпись скрыта", not labels_overlay._label.visible, "")

		labels_overlay.free()

	# Хаб — авторская сцена дома, не пресет из библиотеки: секция обязана
	# спрятаться, а не показать пустую/чужую форму.
	var hub_data := tab._graph.get_node_data(tab._graph.entry_node_id)
	tab._on_node_picked(hub_data.id)
	_check("узел хаба: пресет не найден", tab._editing_preset == null, "")
	_check("узел хаба: секция редактора скрыта", not tab._preset_section.visible, "")

	tab._clear_selection()
	_check("после сброса выделения: секция редактора скрыта", not tab._preset_section.visible, "")

	tab.free()


## _restore_state() — реальный путь, которым вкладка стартует при первом
## показе (_on_visibility_changed), а не только _rebuild_graph() напрямую, как
## в проверке выше. Headless-прогон — это игровой прогон сцены, не редактор
## (Engine.is_editor_hint() ложно, см. world_gen.gd._get_meta), поэтому
## EditorSettings здесь не читается и не пишется: проверяем, что при этом
## _restore_state() всё равно достраивает граф на дефолтах и не падает — то
## есть что путь безопасен ДО того, как в нём вообще появится реальный
## EditorSettings в живом редакторе.
##
## _restore_state() вызывается САМ, через _ready() → _on_visibility_changed()
## (тот же путь, что и в редакторе) — не вызывать его ещё раз вручную:
## _on_visibility_changed()'ный _loaded защищает только от повторного
## АВТОМАТИЧЕСКОГО вызова, повторный ручной так же честно поймает camera_changed
## на "already connected", как поймал бы баг в реальном дублирующем вызове.
func _check_restore_state() -> void:
	var tab := WorldGen.new()
	add_child(tab)

	_check("_restore_state вне редактора: сид упал на дефолт 0", int(tab._seed_spin.value) == 0, "%s" % tab._seed_spin.value)
	_check(
		"_restore_state вне редактора: глубина упала на дефолт HOME_DEPTH",
		tab._current_depth() == RS_LevelGraph.HOME_DEPTH,
		"%d" % tab._current_depth()
	)
	_check("_restore_state: граф построен", tab._graph != null and not tab._graph.nodes.is_empty(), "")

	var popup := tab._visibility_menu.get_popup()
	for i in OverlayRegistry.OVERLAYS.size():
		var overlay: Dictionary = OverlayRegistry.OVERLAYS[i]
		_check(
			"_restore_state вне редактора: чекбокс «%s» упал на дефолт" % overlay["title"],
			popup.is_item_checked(popup.get_item_index(i)) == overlay["default_visible"],
			""
		)

	_check(
		"_restore_state: подписался на camera_changed ровно один раз",
		tab._host.camera_changed.get_connections().size() == 1,
		"%d" % tab._host.camera_changed.get_connections().size()
	)

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
		# «Подписи» — одна на весь оверлей, показывается только по set_selected
		# (see_layer завершается _select(&"") — см. viewport_host.gd), поэтому
		# после rebuild её не должно быть видно вовсе, независимо от того,
		# сколько в слое узлов. Содержимое/позиция подписи проверяются отдельно
		# и подробно в _check_inline_preset_editor — здесь только «не утекла
		# видимой с прошлого слоя».
		_check(
			"%s: подпись скрыта сразу после пересборки слоя" % label,
			not host._labels_overlay._label.visible,
			""
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
