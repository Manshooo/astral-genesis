class_name RS_LevelGraph
extends Resource

@export var nodes: Dictionary[StringName, RS_LevelNode]
@export var entry_node_id: StringName
@export var exit_node_ids: Array[StringName]

const EXTRA_EDGE_RATIO := 0.25
## ВРЕМЕННО: пока нет RS_RoomPresetLibrary с реальными пресетами комнат,
## все узлы получают одну и ту же тестовую сцену — чтобы проверить пайплайн
## enter_complex() -> generate_run() -> _spawn_room() целиком, не блокируясь
## на контенте. Замени на реальный путь к тестовой комнате с Entity-рутом,
## C_LevelNodeRef в component_resources и дочерним Node3D "SpawnPoint".
const PLACEHOLDER_ROOM_SCENE := "res://src/levels/procedural/rooms/test_room.tscn"


func generate_run(level_seed: int) -> RS_LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	var graph := RS_LevelGraph.new()

	var l3 := graph._generate_layer(rng, 3, 14)
	var l2 := graph._generate_layer(rng, 2, 18)
	var l1 := graph._generate_layer(rng, 1, 22)
	var l0 := graph._generate_layer(rng, 0, 6)

	graph._connect_layers(rng, l3, l2, 3)
	graph._connect_layers(rng, l2, l1, 4)
	graph._connect_layers(rng, l1, l0, 2, true)
	graph._place_exits(rng, l0, 2)

	graph.merge([l3, l2, l1, l0])
	graph.entry_node_id = l3.nodes[rng.randi_range(0, l3.nodes.size() - 1)].id

	return graph


func _generate_layer(rng: RandomNumberGenerator, depth: int, room_count: int) -> RS_LevelLayer:
	var layer := RS_LevelLayer.new()
	for i in room_count:
		var node := RS_LevelNode.new()
		node.id = StringName("L%d_room_%d" % [depth, i])
		node.depth = depth
		node.room_scene_path = PLACEHOLDER_ROOM_SCENE
		layer.nodes.append(node)

	# Случайное спэннинг-дерево: каждый следующий узел подключается к случайному
	# уже подключённому — гарантирует связность внутри слоя без циклов.
	var order := _shuffled_range(rng, 1, room_count)
	var connected_indices: Array[int] = [0]
	for idx in order:
		var other_idx: int = connected_indices[rng.randi_range(0, connected_indices.size() - 1)]
		_link_nodes(layer.nodes[idx], layer.nodes[other_idx], RS_LevelConnection.Type.CORRIDOR)
		connected_indices.append(idx)

	# Дополнительные рёбра для циклов — альтернативные маршруты внутри слоя.
	var extra_edges := int(room_count * EXTRA_EDGE_RATIO)
	for i in extra_edges:
		var a := rng.randi_range(0, room_count - 1)
		var b := rng.randi_range(0, room_count - 1)
		if a == b:
			continue
		if layer.nodes[a].get_connection_to(layer.nodes[b].id) != null:
			continue
		_link_nodes(layer.nodes[a], layer.nodes[b], RS_LevelConnection.Type.DOOR)

	return layer


## Соединяет два соседних слоя через connector_count вертикальных хабов.
## guarantee_one_open гарантирует, что хотя бы один коннектор не заперт —
## критично для перехода L1->L0, чтобы забег был всегда завершим.
func _connect_layers(
	rng: RandomNumberGenerator,
	layer_from: RS_LevelLayer,
	layer_to: RS_LevelLayer,
	connector_count: int,
	guarantee_one_open: bool = false,
) -> void:
	var upper_pool := _shuffled_array(rng, layer_from.nodes)
	var lower_pool := _shuffled_array(rng, layer_to.nodes)
	connector_count = min(connector_count, upper_pool.size(), lower_pool.size())

	for i in connector_count:
		var upper_node: RS_LevelNode = upper_pool[i]
		var lower_node: RS_LevelNode = lower_pool[i]
		upper_node.add_tag_unique(&"vertical_hub")
		lower_node.add_tag_unique(&"vertical_hub")

		var conn_type := (
			RS_LevelConnection.Type.ELEVATOR
			if rng.randf() > 0.5
			else RS_LevelConnection.Type.STAIRWELL
		)
		var locked := false
		if not (guarantee_one_open and i == 0):
			locked = rng.randf() < 0.35  # ~35% коннекторов заперты — плейсхолдер под ключ/навык

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


## Для слияния слоёв в один граф
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


func _shuffled_range(rng: RandomNumberGenerator, from: int, to_exclusive: int) -> Array[int]:
	var arr: Array[int] = []
	for i in range(from, to_exclusive):
		arr.append(i)
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr


func _shuffled_array(rng: RandomNumberGenerator, source: Array) -> Array:
	var arr := source.duplicate()
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
	return arr
