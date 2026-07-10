class_name RS_LevelGraph
extends Resource

@export var nodes: Dictionary[StringName, RS_LevelNode]
@export var entry_node_id: StringName
@export var exit_node_ids: Array[StringName]

func generate_run(level_seed: int) -> RS_LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	var graph := RS_LevelGraph.new()
	var l3 := _generate_layer(rng, 3, 14)
	var l2 := _generate_layer(rng, 2, 18)
	var l1 := _generate_layer(rng, 1, 22)
	var l0 := _generate_layer(rng, 0, 6)
	
	_connect_layers(rng, l3, l2, 3)
	_connect_layers(rng, l2, l1, 4)
	_connect_layers(rng, l1, l0, 2, true)
	_place_exits(rng, l0, 2)
	graph.merge([l3, l2, l1, l0])
	return graph

func _generate_layer(rng: RandomNumberGenerator, depth: int, room_count: int) -> RS_LevelGraph:
	return RS_LevelGraph.new()

func _connect_layers(
	rng: RandomNumberGenerator,
	layer_from: RS_LevelGraph,
	layer_to: RS_LevelGraph,
	connector_count: int,
	guarantee_one_open: bool = false # Значение по умолчанию через '='
	) -> void:
	pass

func _place_exits(rng: RandomNumberGenerator, layer: RS_LevelGraph, exit_count: int = 2) -> void:
	pass

## Для слияния слоёв в один граф
func merge(layers: Array[RS_LevelGraph]) -> void:
	pass
