# res://src/autoloads/run_manager.gd
extends Node
## Управляет одним "забегом": граф уровня + какая комната сейчас активна.
## Пока БЕЗ стриминга соседей — только спавн/замена одной текущей комнаты.

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)

var current_graph: RS_LevelGraph
var current_node_id: StringName = &""
var _current_room_entity: Entity


## Вызывается дверью в хабе.
func enter_complex(run_seed: int = -1) -> void:
	if run_seed == -1:
		run_seed = randi()

	current_graph = RS_LevelGraph.new().generate_run(run_seed)
	complex_entered.emit(current_graph)
	_spawn_room(current_graph.entry_node_id)


## Переход в другой узел графа (для дверей внутри комнат — следующий шаг).
func travel_to(node_id: StringName) -> void:
	if current_graph == null or current_graph.get_node_data(node_id) == null:
		push_warning("RunManager: некорректный переход в '%s'" % node_id)
		return
	_spawn_room(node_id)


func _spawn_room(node_id: StringName) -> void:
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null:
		push_error("RunManager: нет данных узла '%s'" % node_id)
		return

	if _current_room_entity and is_instance_valid(_current_room_entity):
		ECS.world.remove_entity(_current_room_entity)
		_current_room_entity = null

	if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
		push_error("RunManager: невалидная room_scene_path у узла '%s'" % node_id)
		return

	var room := (load(node_data.room_scene_path) as PackedScene).instantiate() as Entity
	ECS.world.add_entity(room)

	var ref := room.get_component(C_LevelNode) as C_LevelNode
	if ref:
		ref.node_id = node_id

	_current_room_entity = room
	current_node_id = node_id
	room_changed.emit(node_id)
	_place_player_in_room(room)


func _place_player_in_room(room: Entity) -> void:
	var player := ECS.world.query.with_all([C_PlayerInput]).execute_one() as E_Player
	if player == null:
		return
	var spawn_point := room.get_node_or_null(^"SpawnPoint") as Node3D
	var target: Transform3D = spawn_point.global_transform if spawn_point else room.global_transform
	(player as Node as Node3D).global_transform = target
