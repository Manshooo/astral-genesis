## res://src/resources/world_generator/rs_level_graph.gd
class_name RS_LevelGraph
extends Resource

@export var nodes: Dictionary[StringName, RS_LevelNode]
@export var entry_node_id: StringName
@export var exit_node_ids: Array[StringName]

const EXTRA_EDGE_RATIO := 0.25
## ВРЕМЕННО: пока нет RS_RoomPresetLibrary с реальными пресетами комнат.
const PLACEHOLDER_ROOM_SCENE := "res://src/levels/procedural/rooms/test_room.tscn"

## От самого глубокого к поверхности. Домашний слой игрока — L3, он НЕ центр
## и не концентратор — это гарантируется отдельно ниже (_generate_floor).
const DEPTHS := [4, 3, 2, 1, 0]
const HOME_DEPTH := 3
const ROOMS_PER_FLOOR := 4
const FLOOR_COUNT_MIN := 1
const FLOOR_COUNT_MAX := 3
const INTER_LAYER_CONNECTOR_COUNT := 3


func generate_run(level_seed: int) -> RS_LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	var graph := RS_LevelGraph.new()

	var layers_by_depth: Dictionary = {}  # int(depth) -> RS_LevelLayer
	for depth in DEPTHS:
		layers_by_depth[depth] = graph._generate_layer_with_floors(rng, depth)

	# Домашняя лаборатория (L3, этаж 0, комната 0) сгенерирована как тупик —
	# см. _generate_floor. Она НИКОГДА не должна попасть в пул хабов ниже.
	var home_entry: RS_LevelNode = (layers_by_depth[HOME_DEPTH] as RS_LevelLayer).nodes[0]

	for i in range(DEPTHS.size() - 1):
		var upper_depth: int = DEPTHS[i]  # глубже
		var lower_depth: int = DEPTHS[i + 1]  # ближе к поверхности
		var excluded: Array[StringName] = []
		if upper_depth == HOME_DEPTH or lower_depth == HOME_DEPTH:
			excluded.append(home_entry.id)
		var guarantee_open := lower_depth == 0  # последний рывок к поверхности всегда проходим
		graph._connect_layers(
			rng,
			layers_by_depth[upper_depth],
			layers_by_depth[lower_depth],
			INTER_LAYER_CONNECTOR_COUNT,
			guarantee_open,
			0.35,
			&"vertical_hub",
			excluded,
		)

	graph._place_exits(rng, layers_by_depth[0], 2)

	var all_layers: Array[RS_LevelLayer] = []
	for depth in DEPTHS:
		all_layers.append(layers_by_depth[depth])
	graph.merge(all_layers)

	graph.entry_node_id = home_entry.id

	return graph


## Генерирует один СЛОЙ (depth), состоящий из 1-3 этажей. Каждый этаж —
## отдельный кластер комнат, этажи внутри слоя соединяются floor_hub'ами.
## Для HOME_DEPTH комната 0 этажа 0 всегда генерируется как гарантированный
## тупик (см. _generate_floor(dead_end_index)).
func _generate_layer_with_floors(rng: RandomNumberGenerator, depth: int) -> RS_LevelLayer:
	var floor_count := rng.randi_range(FLOOR_COUNT_MIN, FLOOR_COUNT_MAX)
	var floor_layers: Array[RS_LevelLayer] = []
	var home_entry_id: StringName = &""

	var running_index := 0
	for f in floor_count:
		var dead_end_index := 0 if (depth == HOME_DEPTH and f == 0) else -1
		var floor_layer := _generate_floor(rng, depth, f, ROOMS_PER_FLOOR, running_index, dead_end_index)
		if dead_end_index != -1:
			home_entry_id = floor_layer.nodes[dead_end_index].id
		running_index += floor_layer.nodes.size()
		floor_layers.append(floor_layer)

	# floor_hub-коннекторы между этажами ОДНОГО слоя — без замков (уже загружены
	# все этажи разом, гейтить прогресс тут незачем), домашний тупик исключён.
	var excluded: Array[StringName] = []
	if home_entry_id != &"":
		excluded.append(home_entry_id)
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
		var other_idx: int = connected_indices[rng.randi_range(0, connected_indices.size() - 1)]
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
		_link_nodes(layer.nodes[a], layer.nodes[b], RS_LevelConnection.Type.DOOR)

	if dead_end_index != -1:
		var attach_to: int = connected_indices[rng.randi_range(0, connected_indices.size() - 1)]
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
	var from_candidates := layer_from.nodes.filter(func(n): return not excluded_ids.has(n.id))
	var to_candidates := layer_to.nodes.filter(func(n): return not excluded_ids.has(n.id))
	var upper_pool := _shuffled_array(rng, from_candidates)
	var lower_pool := _shuffled_array(rng, to_candidates)
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


func _place_exits(rng: RandomNumberGenerator, layer: RS_LevelLayer, exit_count: int = 2) -> void:
	var pool := _shuffled_array(rng, layer.nodes)
	exit_count = min(exit_count, pool.size())
	for i in exit_count:
		pool[i].add_tag_unique(&"level_exit")
		exit_node_ids.append(pool[i].id)


func get_node_data(node_id: StringName) -> RS_LevelNode:
	return nodes.get(node_id)


## Все узлы конкретного слоя (across всех его этажей) — используется
## RunManager при загрузке слоя целиком.
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


func _link_nodes(a: RS_LevelNode, b: RS_LevelNode, type: RS_LevelConnection.Type) -> void:
	var forward := RS_LevelConnection.new()
	forward.target_node_id = b.id
	forward.type = type
	a.connections.append(forward)

	var backward := RS_LevelConnection.new()
	backward.target_node_id = a.id
	backward.type = type
	b.connections.append(backward)


func _shuffled_array(rng: RandomNumberGenerator, source: Array) -> Array:
	var arr := source.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
