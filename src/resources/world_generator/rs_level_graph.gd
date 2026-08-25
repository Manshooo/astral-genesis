## res://src/resources/world_generator/rs_level_graph.gd
## @tool — генератор гоняется из редакторского дока «Генератор» (предпросмотр
## выборки по сидам), а не-tool ресурс там доступен только плейсхолдером.
@tool
class_name RS_LevelGraph
extends Resource

@export var nodes: Dictionary[StringName, RS_LevelNode]
@export var entry_node_id: StringName
@export var exit_node_ids: Array[StringName]

const EXTRA_EDGE_RATIO := 0.25
## ВРЕМЕННО: пока нет RS_RoomPresetLibrary с реальными пресетами комнат.
const PLACEHOLDER_ROOM_SCENE := "res://src/levels/procedural/rooms/test_room.tscn"
## Домашний узел (entry) — это хаб: уникальная авторская сцена, а не пресет из
## библиотеки. Игрок стартует здесь и уходит в комплекс через её дверь.
const HUB_ROOM_SCENE := "res://src/levels/hub/hub.tscn"

## От самого глубокого к поверхности. Домашний слой игрока — L3, он НЕ центр
## и не концентратор — это гарантируется отдельно ниже (_generate_floor).
const DEPTHS := [4, 3, 2, 1, 0]
## Глубина домашнего слоя игрока. ВАЖНО: это НЕ игровой тюнинг-параметр — ни одна
## рантайм-система не читает depth, на геймплей само число не влияет. Это якорь
## ГЕНЕРАТОРНОГО ИНВАРИАНТА: три места обязаны ссылаться на один и тот же слой —
##   1) выбор домашнего узла: layers_by_depth[HOME_DEPTH] (см. generate_run);
##   2) размещение гарантированного тупика в комнате 0/этаж 0 ЭТОГО слоя
##      (_generate_layer_with_floors: dead_end_index);
##   3) исключение домашнего узла из кандидатов в vertical_hub (generate_run),
##      иначе у тупика появится второе ребро и degree=1 сломается.
## Инлайнить как литерал `3` в трёх местах опасно: рассинхрон тихо ломает тупик.
## Должно быть значением из DEPTHS. Структурно: дом в СЕРЕДИНЕ комплекса — под ним
## есть слой (4), над ним три к выходу (2,1,0). Число = L3 по лору (История.md).
const HOME_DEPTH := 3
## Поверхность — слой, откуда игрок убегает. Как и HOME_DEPTH, это якорь
## инварианта, а не тюнинг: на этом слое гарантируется тупик под комнату-выход
## (см. _generate_layer_with_floors и _place_exits). Комната-выход обслуживает
## мало рёбер, а на узле с четырьмя дверями она отсеивается по вместимости — без
## гарантированного тупика забег порой физически нельзя выиграть.
const SURFACE_DEPTH := 0
const ROOMS_PER_FLOOR := 4
const FLOOR_COUNT_MIN := 1
const FLOOR_COUNT_MAX := 3
const INTER_LAYER_CONNECTOR_COUNT := 3
## Потолок степени узла: не больше стольких рёбер (= дверей) на комнату. Гварды
## ниже держат его на всех необязательных рёбрах и коннекторах; остовное дерево
## имеет приоритет над лимитом (связность важнее).
const MAX_ROOM_DEGREE := 4


## [param library] если задана — на финальном проходе подбирает каждому узлу
## реальную сцену комнаты по его тегам и числу рёбер. null =
## оставить placeholder у всех узлов (поведение до появления библиотеки).
func generate_run(level_seed: int, library: RS_RoomPresetLibrary = null) -> RS_LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	var graph := RS_LevelGraph.new()

	var layers_by_depth: Dictionary = {}  # int(depth) -> RS_LevelLayer
	for depth in DEPTHS:
		layers_by_depth[depth] = graph._generate_layer_with_floors(rng, depth)

	# Тупики (этаж 0, комната 0 своего слоя) сгенерированы как degree=1 —
	# см. _generate_floor. Они НИКОГДА не должны попасть в пул хабов ниже, иначе
	# вертикальный коннектор добавит им второе ребро и тупик сломается.
	var home_entry: RS_LevelNode = (layers_by_depth[HOME_DEPTH] as RS_LevelLayer).nodes[0]
	var surface_exit: RS_LevelNode = (layers_by_depth[SURFACE_DEPTH] as RS_LevelLayer).nodes[0]

	# Каждый средний слой участвует в ДВУХ соединениях — со слоем глубже и со
	# слоем ближе к поверхности, — а портал в комнате ровно один (_bind_portals).
	# Раньше кандидаты на хаба выбирались отдельно для каждой пары слоёв, и один
	# и тот же узел мог достаться хабом дважды: лишнее вертикальное ребро
	# утекало обычной двери, а на карте такая дверь выглядела соседней комнатой
	# этажа, хотя вела совсем на другой слой. Поэтому пул кандидатов каждого
	# слоя делится ЗАРАНЕЕ на две непересекающиеся половины — под связь вниз и
	# под связь вверх, — см. _split_vertical_hub_pool.
	var hub_pools: Dictionary = {}  # depth -> {"as_upper": [...], "as_lower": [...]}
	for depth in DEPTHS:
		var excluded: Array[StringName] = []
		if depth == HOME_DEPTH:
			excluded.append(home_entry.id)
		if depth == SURFACE_DEPTH:
			excluded.append(surface_exit.id)
		hub_pools[depth] = graph._split_vertical_hub_pool(
			rng,
			layers_by_depth[depth],
			excluded,
			depth != SURFACE_DEPTH,  # нужен пул «вниз», кроме самой поверхности
			depth != DEPTHS[0],  # нужен пул «вверх», кроме самого глубокого слоя
			INTER_LAYER_CONNECTOR_COUNT,
		)

	for i in range(DEPTHS.size() - 1):
		var upper_depth: int = DEPTHS[i]  # глубже
		var lower_depth: int = DEPTHS[i + 1]  # ближе к поверхности
		var guarantee_open := lower_depth == 0  # последний рывок к поверхности всегда проходим
		graph._connect_vertical_layers(
			rng,
			hub_pools[upper_depth]["as_upper"],
			hub_pools[lower_depth]["as_lower"],
			guarantee_open,
			0.35,
		)

	graph._place_exits(rng, layers_by_depth[0], 2)

	var all_layers: Array[RS_LevelLayer] = []
	for depth in DEPTHS:
		all_layers.append(layers_by_depth[depth])
	graph.merge(all_layers)

	# Подстановка реальных сцен комнат — ТОЛЬКО здесь, когда все connections уже
	# проставлены (иначе select_preset не знает нужного числа слотов).
	graph._assign_room_scenes(rng, library)

	graph.entry_node_id = home_entry.id
	# Хаб перекрывает подбор из библиотеки: домашний узел всегда — сцена хаба.
	graph.nodes[home_entry.id].room_scene_path = HUB_ROOM_SCENE

	return graph


## Генерирует один СЛОЙ (depth), состоящий из 1-3 этажей. Каждый этаж —
## отдельный кластер комнат, этажи внутри слоя соединяются floor_hub'ами.
## Для HOME_DEPTH и SURFACE_DEPTH комната 0 этажа 0 всегда генерируется как
## гарантированный тупик (см. _generate_floor(dead_end_index)): дом — чтобы у
## входного узла было ровно одно ребро, поверхность — чтобы комнате-выходу
## досталось место, которое она по вместимости обслужит.
func _generate_layer_with_floors(rng: RandomNumberGenerator, depth: int) -> RS_LevelLayer:
	var floor_count := rng.randi_range(FLOOR_COUNT_MIN, FLOOR_COUNT_MAX)
	var floor_layers: Array[RS_LevelLayer] = []
	var dead_end_id: StringName = &""

	var running_index := 0
	for f in floor_count:
		var needs_dead_end := f == 0 and (depth == HOME_DEPTH or depth == SURFACE_DEPTH)
		var dead_end_index := 0 if needs_dead_end else -1
		var floor_layer := _generate_floor(rng, depth, f, ROOMS_PER_FLOOR, running_index, dead_end_index)
		if dead_end_index != -1:
			dead_end_id = floor_layer.nodes[dead_end_index].id
		running_index += floor_layer.nodes.size()
		floor_layers.append(floor_layer)

	# floor_hub-коннекторы между этажами ОДНОГО слоя — без замков (уже загружены
	# все этажи разом, гейтить прогресс тут незачем), тупик слоя исключён.
	var excluded: Array[StringName] = []
	if dead_end_id != &"":
		excluded.append(dead_end_id)
	for i in range(floor_layers.size() - 1):
		_connect_layers(rng, floor_layers[i], floor_layers[i + 1], 1, true, 0.0, &"floor_hub", excluded)

	var merged := RS_LevelLayer.new()
	for floor_layer in floor_layers:
		merged.nodes.append_array(floor_layer.nodes)
	return merged


## dead_end_index >= 0: эта комната генерируется В ОБХОД обычного спэннинг-
## дерева — сначала строим дерево по всем ОСТАЛЬНЫМ комнатам, а тупиковую
## комнату прикрепляем РОВНО ОДНИМ ребром в конце. Так гарантируется degree=1
## без риска, что рандом спэннинг-дерева или доп.рёбра случайно дадут ей
## больше связей (что и произошло бы при обычной пост-обрезке).
func _generate_floor(
	rng: RandomNumberGenerator,
	depth: int,
	floor_index: int,
	room_count: int,
	index_offset: int,
	dead_end_index: int = -1,
) -> RS_LevelLayer:
	var layer := RS_LevelLayer.new()
	for i in room_count:
		var node := RS_LevelNode.new()
		node.id = StringName("L%d_F%d_room_%d" % [depth, floor_index, i])
		node.depth = depth
		node.floor_index = floor_index
		node.index_in_layer = index_offset + i
		node.room_scene_path = PLACEHOLDER_ROOM_SCENE
		layer.nodes.append(node)

	var tree_indices: Array[int] = []
	for i in room_count:
		if i != dead_end_index:
			tree_indices.append(i)

	var root: int = tree_indices[0]
	var connected_indices: Array[int] = [root]
	for idx in _shuffled_array(rng, tree_indices.slice(1)):
		var other_idx: int = _pick_open_index(rng, layer, connected_indices)
		_link_nodes(layer.nodes[idx], layer.nodes[other_idx], RS_LevelConnection.Type.CORRIDOR)
		connected_indices.append(idx)

	var extra_edges := int(tree_indices.size() * EXTRA_EDGE_RATIO)
	for i in extra_edges:
		var a: int = tree_indices[rng.randi_range(0, tree_indices.size() - 1)]
		var b: int = tree_indices[rng.randi_range(0, tree_indices.size() - 1)]
		if a == b:
			continue
		if layer.nodes[a].get_connection_to(layer.nodes[b].id) != null:
			continue
		if _degree(layer.nodes[a]) >= MAX_ROOM_DEGREE or _degree(layer.nodes[b]) >= MAX_ROOM_DEGREE:
			continue  # доп.ребро необязательно — не превышаем лимит степени
		_link_nodes(layer.nodes[a], layer.nodes[b], RS_LevelConnection.Type.DOOR)

	if dead_end_index != -1:
		var attach_to: int = _pick_open_index(rng, layer, connected_indices)
		_link_nodes(layer.nodes[dead_end_index], layer.nodes[attach_to], RS_LevelConnection.Type.CORRIDOR)

	return layer


## Соединяет два соседних слоя/этажа через connector_count хабов.
## guarantee_one_open гарантирует, что хотя бы один коннектор не заперт.
## excluded_ids — узлы, которые никогда не должны стать хабом (домашний тупик).
func _connect_layers(
	rng: RandomNumberGenerator,
	layer_from: RS_LevelLayer,
	layer_to: RS_LevelLayer,
	connector_count: int,
	guarantee_one_open: bool = false,
	lock_chance: float = 0.35,
	hub_tag: StringName = &"vertical_hub",
	excluded_ids: Array[StringName] = [],
) -> void:
	var from_candidates := layer_from.nodes.filter(
		func(n): return not excluded_ids.has(n.id) and _degree(n) < MAX_ROOM_DEGREE
	)
	var to_candidates := layer_to.nodes.filter(
		func(n): return not excluded_ids.has(n.id) and _degree(n) < MAX_ROOM_DEGREE
	)
	var upper_pool := _shuffled_array(rng, from_candidates)
	var lower_pool := _shuffled_array(rng, to_candidates)
	_stamp_connectors(rng, upper_pool, lower_pool, connector_count, guarantee_one_open, lock_chance, hub_tag)


## Делит узлы ОДНОГО слоя на два непересекающихся пула под будущих вертикальных
## хабов — «вниз» (as_upper: слой играет роль upper_depth, связь со слоем
## глубже) и «вверх» (as_lower: слой играет роль lower_depth, связь со слоем
## ближе к поверхности). Тот же узел не должен попасть в оба пула — иначе ему
## достанутся два вертикальных ребра при одном портале в комнате (см.
## _connect_vertical_layers). Если кандидатов не хватает на оба пула по
## connector_count — делим ЧЕРЕДОВАНИЕМ после тасовки, а не отдаём всё одной
## стороне: иначе соседний слой с другой стороны рискует остаться вовсе без
## связи.
func _split_vertical_hub_pool(
	rng: RandomNumberGenerator,
	layer: RS_LevelLayer,
	excluded_ids: Array[StringName],
	needs_as_upper: bool,
	needs_as_lower: bool,
	connector_count: int,
) -> Dictionary:
	var eligible := layer.nodes.filter(
		func(n): return not excluded_ids.has(n.id) and _degree(n) < MAX_ROOM_DEGREE
	)
	var shuffled := _shuffled_array(rng, eligible)

	var as_upper: Array[RS_LevelNode] = []
	var as_lower: Array[RS_LevelNode] = []
	var prefer_upper := true
	for node: RS_LevelNode in shuffled:
		if as_upper.size() >= connector_count and as_lower.size() >= connector_count:
			break
		var take_upper := needs_as_upper and as_upper.size() < connector_count
		var take_lower := needs_as_lower and as_lower.size() < connector_count
		if take_upper and (prefer_upper or not take_lower):
			as_upper.append(node)
		elif take_lower:
			as_lower.append(node)
		elif take_upper:
			as_upper.append(node)
		prefer_upper = not prefer_upper

	return {"as_upper": as_upper, "as_lower": as_lower}


## Соединяет два соседних СЛОЯ вертикальными коннекторами по уже готовым
## непересекающимся пулам (см. _split_vertical_hub_pool) — сам не выбирает
## кандидатов, чтобы один узел не мог получить хаб-роль дважды.
func _connect_vertical_layers(
	rng: RandomNumberGenerator,
	upper_pool: Array,
	lower_pool: Array,
	guarantee_one_open: bool,
	lock_chance: float,
) -> void:
	_stamp_connectors(
		rng, upper_pool, lower_pool, INTER_LAYER_CONNECTOR_COUNT, guarantee_one_open, lock_chance, &"vertical_hub"
	)


## Общий код раздачи коннекторов для _connect_layers (сам подбирает кандидатов
## из слоя) и _connect_vertical_layers (получает уже готовые непересекающиеся
## пулы) — тип связи, замки и сами RS_LevelConnection одинаковы в обоих
## случаях, разница только в источнике пулов.
func _stamp_connectors(
	rng: RandomNumberGenerator,
	upper_pool: Array,
	lower_pool: Array,
	connector_count: int,
	guarantee_one_open: bool,
	lock_chance: float,
	hub_tag: StringName,
) -> void:
	connector_count = min(connector_count, upper_pool.size(), lower_pool.size())
	for i in connector_count:
		var upper_node: RS_LevelNode = upper_pool[i]
		var lower_node: RS_LevelNode = lower_pool[i]
		upper_node.add_tag_unique(hub_tag)
		lower_node.add_tag_unique(hub_tag)

		var conn_type := (
			RS_LevelConnection.Type.ELEVATOR
			if rng.randf() > 0.5
			else RS_LevelConnection.Type.STAIRWELL
		)
		var locked := false
		if not (guarantee_one_open and i == 0):
			locked = rng.randf() < lock_chance

		var down := RS_LevelConnection.new()
		down.target_node_id = lower_node.id
		down.type = conn_type
		down.depth_delta = -1
		if locked:
			down.locked_by = &"level_access_key"
		upper_node.connections.append(down)

		var up := RS_LevelConnection.new()
		up.target_node_id = upper_node.id
		up.type = conn_type
		up.depth_delta = 1
		if locked:
			up.locked_by = &"level_access_key"
		lower_node.connections.append(up)


## Помечает узлы поверхностного слоя тегом level_exit. Кандидатов не берём подряд
## из перемешанного пула, а упорядочиваем — иначе выход почти всегда достаётся
## узлу-коннектору, и забег становится непроходимым:
##   1. Узлы БЕЗ тега vertical_hub идут первыми. У коннектора теги
##      [vertical_hub, floor_hub, level_exit] — по специфичности подбор отдаёт ему
##      vertical_hub-пресет, а в той сцене нет двери с A_FinishRun. Победить в
##      такой «комнате выхода» физически нечем.
##   2. Внутри группы — по возрастанию степени: комната-выход обслуживает мало
##      рёбер (slot_count в exit_room.tres, рядом со сценой), на узле с четырьмя дверями
##      она отсеется по вместимости.
## Детерминированность сохраняется: пул сперва перемешивается тем же rng.
func _place_exits(rng: RandomNumberGenerator, layer: RS_LevelLayer, exit_count: int = 2) -> void:
	var shuffled := _shuffled_array(rng, layer.nodes)
	var by_degree := func(a: RS_LevelNode, b: RS_LevelNode) -> bool: return _degree(a) < _degree(b)

	var plain := shuffled.filter(func(n: RS_LevelNode) -> bool: return not n.has_tag(&"vertical_hub"))
	var hubs := shuffled.filter(func(n: RS_LevelNode) -> bool: return n.has_tag(&"vertical_hub"))
	plain.sort_custom(by_degree)
	hubs.sort_custom(by_degree)

	var pool: Array = plain + hubs  # коннекторы — только если обычных узлов не хватило
	exit_count = min(exit_count, pool.size())
	for i in exit_count:
		pool[i].add_tag_unique(&"level_exit")
		exit_node_ids.append(pool[i].id)


func get_node_data(node_id: StringName) -> RS_LevelNode:
	return nodes.get(node_id)


## Все узлы конкретного слоя (across всех его этажей). Это гранула стриминга:
## RunManager грузит слой ЦЕЛИКОМ (все комнаты одновременно в дереве сцены) и
## сносит его только при смене глубины — см. RunManager._spawn_layer.
func get_nodes_by_depth(depth: int) -> Array[RS_LevelNode]:
	var result: Array[RS_LevelNode] = []
	for node in nodes.values():
		if node.depth == depth:
			result.append(node)
	return result


func merge(layers: Array[RS_LevelLayer]) -> void:
	for layer in layers:
		for node in layer.nodes:
			nodes[node.id] = node


## Финальный проход: подбирает каждому узлу сцену комнаты через библиотеку
## пресетов. Узлам, которым пресет не нашёлся (или library == null), остаётся
## заранее проставленный PLACEHOLDER_ROOM_SCENE — генерация не падает.
func _assign_room_scenes(rng: RandomNumberGenerator, library: RS_RoomPresetLibrary) -> void:
	if library == null:
		return
	for node in nodes.values():
		var preset := library.select_preset(node, rng)
		if preset and preset.scene:
			node.room_scene_path = preset.scene.resource_path


func _link_nodes(a: RS_LevelNode, b: RS_LevelNode, type: RS_LevelConnection.Type) -> void:
	var forward := RS_LevelConnection.new()
	forward.target_node_id = b.id
	forward.type = type
	a.connections.append(forward)

	var backward := RS_LevelConnection.new()
	backward.target_node_id = a.id
	backward.type = type
	b.connections.append(backward)


func _degree(node: RS_LevelNode) -> int:
	return node.connections.size()


## Индекс из pool (индексы в layer.nodes) с приоритетом узлов, у которых ещё есть
## место (degree < MAX_ROOM_DEGREE). Свободных нет — берём любой: рвать остовное
## дерево ради лимита степени нельзя, связность важнее.
func _pick_open_index(rng: RandomNumberGenerator, layer: RS_LevelLayer, pool: Array[int]) -> int:
	var open := pool.filter(func(ci): return _degree(layer.nodes[ci]) < MAX_ROOM_DEGREE)
	var chosen: Array = open if not open.is_empty() else pool
	return chosen[rng.randi_range(0, chosen.size() - 1)]


func _shuffled_array(rng: RandomNumberGenerator, source: Array) -> Array:
	var arr := source.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
