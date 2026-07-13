# res://src/autoloads/run_manager.gd
extends Node
## Управляет одним "забегом": граф уровня + какая комната сейчас активна.
## Пока БЕЗ стриминга соседей — только спавн/замена одной текущей комнаты.
##
## Двери и переходы — по ADR-0001: у дверей комнаты компонент C_DoorSlot, при
## спавне RunManager сопоставляет рёбра узла слотам и штампует на каждую дверь
## C_DoorPortal (target_node_id + locked_by). Лишние слоты запечатываются.

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)

var current_graph: RS_LevelGraph
var current_node_id: StringName = &""
var _current_room_entity: Entity
## Двери текущей комнаты — держим отдельно, т.к. add_entity(room) НЕ регистрирует
## вложенные сущности, и remove_entity(room) их не снимает (см. _despawn_current_room).
var _current_room_doors: Array[Entity] = []


## Вызывается дверью в хабе.
func enter_complex(run_seed: int = -1) -> void:
	if run_seed == -1:
		run_seed = randi()

	current_graph = RS_LevelGraph.new().generate_run(run_seed, GameConfig.config.room_preset_library)
	complex_entered.emit(current_graph)
	_spawn_room(current_graph.entry_node_id)


## Переход в другой узел графа (вызывается A_TravelThroughDoor).
func travel_to(node_id: StringName) -> void:
	if current_graph == null or current_graph.get_node_data(node_id) == null:
		push_warning("RunManager: некорректный переход в '%s'" % node_id)
		return
	_spawn_room(node_id, current_node_id)


## [param came_from] узел, из которого пришли — чтобы поставить игрока к двери,
## ведущей обратно, а не в общий SpawnPoint. Пусто = первый вход в забег.
func _spawn_room(node_id: StringName, came_from: StringName = &"") -> void:
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null:
		push_error("RunManager: нет данных узла '%s'" % node_id)
		return

	if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
		push_error("RunManager: невалидная room_scene_path у узла '%s'" % node_id)
		return

	_despawn_current_room()

	var room := (load(node_data.room_scene_path) as PackedScene).instantiate() as Entity
	ECS.world.add_entity(room)

	var ref := room.get_component(C_LevelNode) as C_LevelNode
	if ref:
		ref.node_id = node_id

	_current_room_entity = room
	_current_room_doors = _register_and_bind_doors(room, node_data)
	current_node_id = node_id
	room_changed.emit(node_id)
	_place_player_in_room(room, came_from)


## Снимает текущую комнату. Сначала двери (иначе после queue_free комнаты они
## остались бы битыми ссылками в реестре мира), затем саму комнату.
func _despawn_current_room() -> void:
	if not _current_room_doors.is_empty():
		ECS.world.remove_entities(_current_room_doors)
		_current_room_doors.clear()
	if _current_room_entity and is_instance_valid(_current_room_entity):
		ECS.world.remove_entity(_current_room_entity)
		_current_room_entity = null


## Находит двери комнаты (Entity с C_DoorSlot), регистрирует их в мире
## (add_entity(room) их не берёт) и штампует C_DoorPortal по рёбрам узла.
## Сопоставление сейчас по порядку slot_id ↔ порядку connections — это
## временный бутстрап Варианта A из ADR-0001. Умное сопоставление слот↔ребро
## приедет с RS_RoomPresetLibrary (Фаза 2), когда пресет начнёт объявлять слоты.
func _register_and_bind_doors(room: Entity, node_data: RS_LevelNode) -> Array[Entity]:
	var doors: Array[Entity] = []
	# owned=false — иначе двери, вставленные как инстансы под-сцены, не находятся.
	for node in room.find_children("*", "Entity", true, false):
		var e := node as Entity
		if e and e.has_component(C_DoorSlot):
			doors.append(e)
	if doors.is_empty():
		return doors

	# Детерминированный порядок независимо от раскладки нод в дереве.
	# Через String(): StringName сравнивается по внутреннему указателю, не лексикографически.
	doors.sort_custom(func(a, b): return String(_slot_id_of(a)) < String(_slot_id_of(b)))

	ECS.world.add_entities(doors)

	var connections := node_data.connections
	for i in doors.size():
		if i < connections.size():
			var conn := connections[i] as RS_LevelConnection
			var portal := C_DoorPortal.new()
			portal.target_node_id = conn.target_node_id
			portal.locked_by = conn.locked_by
			doors[i].add_component(portal)
		else:
			_seal_door(doors[i])  # рёбер меньше, чем проёмов — лишние запечатываем

	if connections.size() > doors.size():
		push_warning(
			"RunManager: у узла '%s' рёбер (%d) больше, чем дверей (%d) — часть недостижима"
			% [node_data.id, connections.size(), doors.size()]
		)
	return doors


## Запечатанная дверь: логически мертва (интеракция выключена). Визуальное
## «заваривание» — на совести арта/будущей системы.
func _seal_door(door: Entity) -> void:
	var inter := door.get_component(C_Interactable) as C_Interactable
	if inter:
		inter.enabled = false


func _slot_id_of(door: Entity) -> StringName:
	var slot := door.get_component(C_DoorSlot) as C_DoorSlot
	return slot.slot_id if slot else &""


func _place_player_in_room(room: Entity, came_from: StringName) -> void:
	var player := ECS.world.query.with_all([C_PlayerInput]).execute_one() as E_Player
	if player == null:
		return

	var target: Transform3D
	var return_door := _find_return_door(came_from)
	if return_door:
		target = (return_door as Node as Node3D).global_transform
	else:
		var spawn_point := room.get_node_or_null(^"SpawnPoint") as Node3D
		target = spawn_point.global_transform if spawn_point else room.global_transform
	(player as Node as Node3D).global_transform = target


## Дверь текущей комнаты, ведущая обратно в came_from — чтобы игрок появился у
## неё, а не в общем SpawnPoint. null, если пришли не через дверь (вход в забег).
func _find_return_door(came_from: StringName) -> Entity:
	if came_from == &"":
		return null
	for door in _current_room_doors:
		var portal := door.get_component(C_DoorPortal) as C_DoorPortal
		if portal and portal.target_node_id == came_from:
			return door
	return null
