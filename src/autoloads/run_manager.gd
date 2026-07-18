# res://src/autoloads/run_manager.gd
extends Node
## Управляет одним "забегом": граф уровня + какая комната сейчас активна.
## Пока БЕЗ стриминга соседей — только спавн/замена одной текущей комнаты.
##
## Двери и переходы: у дверей комнаты компонент C_DoorSlot, при
## спавне RunManager сопоставляет рёбра узла слотам и штампует на каждую дверь
## C_DoorPortal (target_node_id + locked_by). Лишние слоты запечатываются.

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)
## Игрок сбежал на поверхность — забег (и пока вся игра) окончен победой.
signal run_finished

## Заглушка «игра окончена»: экрана концовки пока нет — уходим в меню, как и
## «выход в меню» из паузы.
const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"

var current_graph: RS_LevelGraph
var current_node_id: StringName = &""
var _current_room_entity: Entity
## Вложенные сущности комнаты — держим отдельно, т.к. add_entity(room) регистрирует
## ТОЛЬКО саму комнату (обхода дерева в поисках вложенных Entity в GECS нет), а
## remove_entity(room) их не снимает. Регистрируем/снимаем их явно (см.
## _register_room_children и _despawn_current_room).
var _current_room_children: Array[Entity] = []
## Подмножество _current_room_children — двери (с C_DoorSlot). Нужно для поиска
## двери, ведущей обратно (_find_return_door).
var _current_room_doors: Array[Entity] = []


## Вызывается дверью в хабе.
func enter_complex(run_seed: int = -1) -> void:
	if run_seed == -1:
		run_seed = WorldSave.save.run_seed()  # детерминированно из (world_seed, death_count)

	current_graph = RS_LevelGraph.new().generate_run(run_seed, GameConfig.config.room_preset_library)
	complex_entered.emit(current_graph)
	_spawn_room(current_graph.entry_node_id)


## Побег на поверхность = ОКОНЧАНИЕ ИГРЫ (победа). Это НЕ возврат в хаб — тот
## происходит только при смерти (пока не реализовано, нужен death_count/состояния).
## Зовётся A_FinishRun из комнаты-выхода (тег level_exit).
func finish_run() -> void:
	if current_graph == null:
		return  # не в забеге — выходить неоткуда

	_despawn_current_room()
	current_graph = null
	current_node_id = &""
	run_finished.emit()

	# TODO: экран концовки/победы. Пока — в меню, как «выход в меню» из паузы.
	get_tree().change_scene_to_file(MENU_SCENE)


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
	_current_room_children = _register_room_children(room)
	_current_room_doors = _bind_doors(node_data)
	current_node_id = node_id
	room_changed.emit(node_id)
	_place_player_in_room(room, came_from)


## Снимает текущую комнату. Сначала вложенные сущности (иначе после queue_free
## комнаты они остались бы битыми ссылками в реестре мира), затем саму комнату.
##
## Ссылки могут указывать на УЖЕ ОСВОБОЖДЁННЫЕ сущности: RunManager — autoload и
## переживает смену сцены, так что после «Выхода в меню» прошлый забег улетает
## вместе со сценой мира, а ссылки остаются битыми. remove_entity(entity: Entity)
## типизирован — freed-объект роняет проверку типа ещё ДО тела функции (там, где
## стоит is_instance_valid), поэтому отсеиваем невалидные заранее.
func _despawn_current_room() -> void:
	_remove_valid_entities(_current_room_children)
	_current_room_children.clear()
	_current_room_doors.clear()  # подмножество children — уже сняты выше
	if is_instance_valid(_current_room_entity):
		ECS.world.remove_entity(_current_room_entity)
	_current_room_entity = null


## remove_entities только для живых сущностей — см. про freed-ссылки в
## _despawn_current_room.
func _remove_valid_entities(list: Array[Entity]) -> void:
	var valid: Array[Entity] = []
	for e in list:
		if is_instance_valid(e):
			valid.append(e)
	if not valid.is_empty():
		ECS.world.remove_entities(valid)


## Регистрирует в мире все вложенные сущности комнаты (Incubator, двери и т.п.).
## Нужно, т.к. add_entity(room) кладёт в мир ТОЛЬКО саму комнату — обхода дерева
## в поисках вложенных Entity в GECS нет.
func _register_room_children(room: Entity) -> Array[Entity]:
	var children: Array[Entity] = []
	# owned=false — иначе сущности, вставленные как инстансы под-сцены, не находятся.
	for node in room.find_children("*", "Entity", true, false):
		var e := node as Entity
		if e:
			children.append(e)
	if not children.is_empty():
		ECS.world.add_entities(children)
	return children


## Штампует C_DoorPortal на двери комнаты (подмножество _current_room_children с
## C_DoorSlot) по рёбрам узла. Сами двери уже зарегистрированы в мире
## _register_room_children — здесь только биндинг рёбер к слотам.
## Сопоставление сейчас по порядку slot_id ↔ порядку connections — это
## временный бутстрап «Варианта A». Умное сопоставление слот↔ребро
## приедет с RS_RoomPresetLibrary (Фаза 2), когда пресет начнёт объявлять слоты.
func _bind_doors(node_data: RS_LevelNode) -> Array[Entity]:
	var doors: Array[Entity] = []
	for e in _current_room_children:
		if e.has_component(C_DoorSlot):
			doors.append(e)
	if doors.is_empty():
		return doors

	# Детерминированный порядок независимо от раскладки нод в дереве.
	# Через String(): StringName сравнивается по внутреннему указателю, не лексикографически.
	doors.sort_custom(func(a, b): return String(_slot_id_of(a)) < String(_slot_id_of(b)))

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


func _get_player() -> E_Player:
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as E_Player


## На сколько метров вглубь комнаты отступать от двери, чтобы капсула игрока не
## оказалась в стене/проёме (радиус капсулы ~0.63, проём ~2.8 в ширину).
const ARRIVAL_OFFSET := 1.5


func _place_player_in_room(room: Entity, came_from: StringName) -> void:
	var player := _get_player()
	if player == null:
		return

	var spawn_point := room.get_node_or_null(^"SpawnPoint") as Node3D
	var target: Transform3D
	var return_door := _find_return_door(came_from)
	if return_door:
		# НЕ трансформ самой двери: её origin — в плоскости стены и на высоте
		# центра полотна (~2.3 м). Ставим игрока ПЕРЕД дверью, вглубь комнаты, на
		# высоте пола, лицом внутрь — иначе капсулу спавнит в геометрии и роняет.
		target = _arrival_transform_for_door(return_door, room, spawn_point)
	elif spawn_point:
		target = spawn_point.global_transform
	else:
		target = room.global_transform
	(player as Node as Node3D).global_transform = target


## Безопасная точка прибытия у двери [param door]: горизонтально отступаем от
## двери к центру комнаты (направление надёжно независимо от ориентации двери —
## в пресете двери не сориентированы внутрь единообразно), высоту берём от
## SpawnPoint (пол), разворачиваем игрока лицом вглубь комнаты.
func _arrival_transform_for_door(door: Entity, room: Entity, spawn_point: Node3D) -> Transform3D:
	var door_origin := (door as Node as Node3D).global_transform.origin
	var room_origin := (room as Node as Node3D).global_transform.origin

	var into_room := room_origin - door_origin
	into_room.y = 0.0
	if into_room.length() < 0.001:
		into_room = -(door as Node as Node3D).global_transform.basis.z  # запасной вариант
	into_room = into_room.normalized()

	var pos := door_origin + into_room * ARRIVAL_OFFSET
	pos.y = spawn_point.global_transform.origin.y if spawn_point else room_origin.y

	return Transform3D.IDENTITY.translated(pos).looking_at(pos + into_room, Vector3.UP)


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
