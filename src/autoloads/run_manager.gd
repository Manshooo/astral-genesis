# res://src/autoloads/run_manager.gd
extends Node
## Управляет одним "забегом": граф уровня + загруженный СЛОЙ.
##
## Гранула стриминга — СЛОЙ (все узлы одной depth разом в дереве сцены), а не
## отдельная комната. Переход внутри слоя = телепорт игрока в уже стоящую
## комнату (ничего не грузится и не сносится); переход по вертикальному
## коннектору = деспавн всего слоя и спавн нового.
##
## Коридоров между комнатами нет: связь чисто логическая (двери ↔ рёбра графа),
## поэтому комнаты слоя просто расставляются по детерминированной сетке —
## см. _layer_layout.
##
## Двери и переходы: у дверей комнаты компонент C_DoorSlot, при спавне RunManager
## сопоставляет рёбра узла слотам и штампует на каждую дверь C_DoorPortal
## (target_node_id + locked_by) вместе с подсказкой. Лишние слоты запечатываются
## (_seal_door) — не выключаются, а объясняют игроку, что прохода нет.
##
## Прогресс забега: смена комнаты — контрольная точка (WorldSave.record_progress),
## вход в забег стартует с сохранённого узла, если забег не завершён.

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)
## Загружен новый слой (все его комнаты уже в дереве). depth == -1 — слой снят.
signal layer_changed(depth: int)
## Игрок сбежал на поверхность — забег (и пока вся игра) окончен победой.
signal run_finished
## БФЖ распался: запас жизни иссяк, пока душа была развоплощена (проигрыш).
signal died

## Заглушка «игра окончена»: экрана концовки пока нет — уходим в меню, как и
## «выход в меню» из паузы.
const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"
## Экран смерти: показывается после распада БФЖ (см. die).
const DEATH_SCENE := "res://src/ui/death_screen/death_screen.tscn"
## Сцена души-БФЖ. Спавним её скриптом при входе в забег, а не кладём в world.tscn:
## игрок должен появляться в уже сгенерированном мире, у входного узла графа.
const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"

## Шаг сетки между соседними комнатами одного этажа (по X). Комната ~22 м в
## поперечнике (полотна дверей торчат до ±11), берём с запасом — комнаты не
## должны соприкасаться даже коллайдерами, иначе луч взаимодействия или капсула
## игрока могут зацепить соседнюю.
const ROOM_SPACING := 60.0
## Разнос этажей ОДНОГО слоя по высоте. Комната ~6 м высотой — 20 м даёт
## гарантированный зазор и делает раскладку читаемой в отладке.
const FLOOR_SPACING := 20.0
## "Слой не загружен". Глубины графа — 0..4 (RS_LevelGraph.DEPTHS), так что -1
## никогда не совпадёт с реальной.
const NO_DEPTH := -1

## Подсказки на дверях. Состояние двери известно только при биндинге рёбер,
## поэтому prompt_text проставляем здесь, а не в пресете комнаты (в сценах он у
## дверей пустой). Игрок должен отличать рабочую дверь от запертой и от
## запечатанного проёма ДО нажатия — иначе непонятно, декор это или баг.
const DOOR_PROMPT_OPEN := "Пройти"
const DOOR_PROMPT_LOCKED := "Заперто"
const DOOR_PROMPT_SEALED := "Прохода нет"


## Одна заспавненная комната слоя. Вложенные сущности держим отдельно от самой
## комнаты, т.к. add_entity(room) регистрирует ТОЛЬКО саму комнату (обхода дерева
## в поисках вложенных Entity в GECS нет), а remove_entity(room) их не снимает.
class SpawnedRoom:
	extends RefCounted

	var node_id: StringName
	var entity: Entity
	## Вложенные сущности комнаты (Incubator, двери, тела) — регистрируются и
	## снимаются явно, см. _register_room_children / _despawn_layer.
	var children: Array[Entity] = []
	## Подмножество children — двери (с C_DoorSlot). Нужно для поиска двери,
	## ведущей обратно (_find_return_door).
	var doors: Array[Entity] = []


var current_graph: RS_LevelGraph
var current_node_id: StringName = &""
## Глубина загруженного слоя (NO_DEPTH — ничего не загружено).
var current_depth: int = NO_DEPTH
## node_id -> SpawnedRoom для ВСЕХ комнат текущего слоя, а не только той, где
## стоит игрок.
var _rooms: Dictionary[StringName, SpawnedRoom] = {}


## Точка входа в забег: генерирует комплекс и ставит игрока в стартовый узел.
## Комплекс НЕ читается из сейва покомнатно — он выводится из сида, а сейв даёт
## только точку, где игрок остановился (см. _start_node_id).
func enter_complex(run_seed: int = -1) -> void:
	if run_seed == -1:
		run_seed = WorldSave.save.run_seed()  # детерминированно из (world_seed, death_count)

	# Игрок появляется в уже сгенерированном мире: сперва спавним душу, затем граф,
	# затем входной слой — _enter_node → _place_player_in_room поставит её на место.
	_spawn_player()
	current_graph = RS_LevelGraph.new().generate_run(run_seed, GameConfig.config.room_preset_library)
	complex_entered.emit(current_graph)
	_restore_player_progress()
	_enter_node(_start_node_id())


## Узел, с которого начинается сессия: сохранённый (продолжение забега) или
## входной. Сейв мог быть сделан на другом сиде/версии графа — если узла в графе
## нет, молча откатываемся на вход, а не роняем забег.
func _start_node_id() -> StringName:
	var saved := WorldSave.save
	if saved.run_in_progress and current_graph.get_node_data(saved.current_node_id) != null:
		return saved.current_node_id
	if saved.run_in_progress:
		push_warning(
			"RunManager: сохранённый узел '%s' отсутствует в графе — старт с входного"
			% saved.current_node_id
		)
	return current_graph.entry_node_id


## Возвращает БФЖ сохранённый остаток распада. Иначе загрузка работала бы как
## бесплатное восстановление: свежая E_Player всегда несёт полный C_Lifespan.
func _restore_player_progress() -> void:
	if not WorldSave.save.run_in_progress or WorldSave.save.lifespan_remaining < 0.0:
		return
	var player := _get_player()
	if player == null:
		return
	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life:
		life.current = minf(WorldSave.save.lifespan_remaining, life.max_duration)


## Инстанцирует душу-БФЖ и регистрирует её в мире, если её там ещё нет.
## Позиционирование — на совести _place_player_in_room (при входе в первый узел).
##
## Учёт WorldSave/новой игры: сид забега уже выведен в enter_complex из
## (world_seed, death_count); свежая E_Player несёт полный запас жизни — её
## идентичность (C_BodySnatch, C_Lifespan) навешивает define_components(), а не
## сцена, так что каждый новый забег стартует с непочатым C_Lifespan.
func _spawn_player() -> void:
	if _get_player() != null:
		return  # уже в мире (напр. повторный enter_complex в той же сцене)
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	ECS.world.add_entity(player)


## Побег на поверхность = ОКОНЧАНИЕ ИГРЫ (победа). Это НЕ возврат в хаб — тот
## происходит только при смерти (пока не реализовано, нужен death_count/состояния).
## Зовётся A_FinishRun из комнаты-выхода (тег level_exit).
func finish_run() -> void:
	if current_graph == null:
		return  # не в забеге — выходить неоткуда

	WorldSave.clear_run()  # забег завершён: «Загрузить» начнёт этот мир заново
	_end_run()
	run_finished.emit()

	# TODO: экран концовки/победы. Пока — в меню, как «выход в меню» из паузы.
	get_tree().change_scene_to_file(MENU_SCENE)


## Настоящая смерть БФЖ: запас распада иссяк, пока душа была РАЗВОПЛОЩЕНА
## (событие "run_ended" от S_Lifespan). В отличие от finish_run (побег = победа),
## смерть фиксируется в сейве — death_count++ меняет будущую генерацию — и уводит
## на экран смерти. Зовётся отложенно из O_RunEnded (нельзя сносить забег в
## середине прохода ECS по сущностям).
func die() -> void:
	if current_graph == null:
		return  # не в забеге — умирать некому

	WorldSave.record_death()  # death_count++ → следующий run_seed() иной
	_end_run()
	died.emit()

	# TODO: анимация распада/затемнение перед экраном. Пока — сразу экран смерти.
	get_tree().change_scene_to_file(DEATH_SCENE)


## Общий снос забега для finish_run/die: убрать загруженный слой и обнулить граф.
## Игрока и системы не трогаем — они уходят вместе со сценой мира при смене сцены.
func _end_run() -> void:
	_despawn_layer()
	current_graph = null
	current_node_id = &""


## Переход в другой узел графа (вызывается A_TravelThroughDoor).
func travel_to(node_id: StringName) -> void:
	if current_graph == null or current_graph.get_node_data(node_id) == null:
		push_warning("RunManager: некорректный переход в '%s'" % node_id)
		return
	_enter_node(node_id, current_node_id)


## Делает [param node_id] текущим узлом: догружает его слой, если игрок сменил
## глубину, и переставляет игрока в нужную комнату.
## [param came_from] узел, из которого пришли — чтобы поставить игрока к двери,
## ведущей обратно, а не в общий SpawnPoint. Пусто = первый вход в забег.
func _enter_node(node_id: StringName, came_from: StringName = &"") -> void:
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null:
		push_error("RunManager: нет данных узла '%s'" % node_id)
		return

	# Слой уже в дереве — комната-цель стоит на месте, грузить нечего.
	if node_data.depth != current_depth:
		_despawn_layer()
		_spawn_layer(node_data.depth)

	var room: SpawnedRoom = _rooms.get(node_id)
	if room == null:
		push_error("RunManager: комната узла '%s' не заспавнилась" % node_id)
		return

	current_node_id = node_id
	# Смена комнаты — гранула сохранения забега: дальше игрок продолжит отсюда.
	WorldSave.record_progress(node_id, _player_lifespan())
	room_changed.emit(node_id)
	_place_player_in_room(room, came_from)


## Спавнит ВСЕ комнаты слоя [param depth] разом. Предполагает, что предыдущий
## слой уже снят (_despawn_layer) — иначе комнаты наложатся по сетке.
func _spawn_layer(depth: int) -> void:
	var layer_nodes := current_graph.get_nodes_by_depth(depth)
	if layer_nodes.is_empty():
		push_error("RunManager: в графе нет узлов глубины %d" % depth)
		return

	var layout := _layer_layout(layer_nodes)
	for node_data in layer_nodes:
		var room := _spawn_room(node_data, layout[node_data.id])
		if room:
			_rooms[node_data.id] = room

	current_depth = depth
	layer_changed.emit(depth)


## Детерминированная раскладка комнат слоя: этажи разносим по высоте, комнаты
## одного этажа — в ряд по X. Порядок внутри этажа задаётся index_in_layer, а не
## порядком обхода графа: раскладка обязана совпадать от запуска к запуску при
## одном сиде (иначе сейв «текущей комнаты» приводит игрока не туда).
func _layer_layout(layer_nodes: Array[RS_LevelNode]) -> Dictionary[StringName, Vector3]:
	var by_floor: Dictionary[int, Array] = {}
	for node_data in layer_nodes:
		if not by_floor.has(node_data.floor_index):
			by_floor[node_data.floor_index] = []
		by_floor[node_data.floor_index].append(node_data)

	var layout: Dictionary[StringName, Vector3] = {}
	for floor_index: int in by_floor:
		var row: Array = by_floor[floor_index]
		row.sort_custom(func(a, b): return a.index_in_layer < b.index_in_layer)
		for column in row.size():
			var node_data: RS_LevelNode = row[column]
			layout[node_data.id] = Vector3(column * ROOM_SPACING, floor_index * FLOOR_SPACING, 0.0)
	return layout


## Инстанцирует комнату узла в точке [param origin] и регистрирует всё её
## содержимое в мире. null, если у узла невалидная сцена.
func _spawn_room(node_data: RS_LevelNode, origin: Vector3) -> SpawnedRoom:
	if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
		push_error("RunManager: невалидная room_scene_path у узла '%s'" % node_data.id)
		return null

	var entity := (load(node_data.room_scene_path) as PackedScene).instantiate() as Entity
	# Позицию ставим ДО add_entity: тот сам вносит узел в дерево, и комната должна
	# попасть туда сразу на своё место — иначе коллайдеры успевают
	# зарегистрироваться в начале координат и телепортируются следом.
	# Через Node: Entity наследует Node, и прямой каст Entity→Node3D анализатор
	# GDScript не пропускает (тот же приём, что в _arrival_transform_for_door).
	var spatial := entity as Node as Node3D
	if spatial:
		spatial.position = origin

	ECS.world.add_entity(entity)

	var ref := entity.get_component(C_LevelNode) as C_LevelNode
	if ref:
		ref.node_id = node_data.id

	var room := SpawnedRoom.new()
	room.node_id = node_data.id
	room.entity = entity
	room.children = _register_room_children(entity)
	room.doors = _bind_doors(room, node_data)
	return room


## Снимает ВЕСЬ загруженный слой. По каждой комнате сначала вложенные сущности
## (иначе после queue_free комнаты они остались бы битыми ссылками в реестре
## мира), затем саму комнату.
##
## Ссылки могут указывать на УЖЕ ОСВОБОЖДЁННЫЕ сущности: RunManager — autoload и
## переживает смену сцены, так что после «Выхода в меню» прошлый забег улетает
## вместе со сценой мира, а ссылки остаются битыми. remove_entity(entity: Entity)
## типизирован — freed-объект роняет проверку типа ещё ДО тела функции (там, где
## стоит is_instance_valid), поэтому отсеиваем невалидные заранее.
func _despawn_layer() -> void:
	for room: SpawnedRoom in _rooms.values():
		_remove_valid_entities(room.children)
		if is_instance_valid(room.entity):
			ECS.world.remove_entity(room.entity)
	_rooms.clear()
	if current_depth != NO_DEPTH:
		current_depth = NO_DEPTH
		layer_changed.emit(NO_DEPTH)


## remove_entities только для живых сущностей — см. про freed-ссылки в
## _despawn_layer.
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


## Штампует C_DoorPortal на двери комнаты (подмножество room.children с
## C_DoorSlot) по рёбрам узла. Сами двери уже зарегистрированы в мире
## _register_room_children — здесь только биндинг рёбер к слотам.
## Сопоставление сейчас по порядку slot_id ↔ порядку connections — это
## временный бутстрап «Варианта A». Умное сопоставление слот↔ребро
## приедет с RS_RoomPresetLibrary (Фаза 2), когда пресет начнёт объявлять слоты.
func _bind_doors(room: SpawnedRoom, node_data: RS_LevelNode) -> Array[Entity]:
	var doors: Array[Entity] = []
	for e in room.children:
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
			_set_door_prompt(
				doors[i], DOOR_PROMPT_LOCKED if portal.is_locked() else DOOR_PROMPT_OPEN
			)
		else:
			_seal_door(doors[i])  # рёбер меньше, чем проёмов — лишние запечатываем

	if connections.size() > doors.size():
		push_warning(
			"RunManager: у узла '%s' рёбер (%d) больше, чем дверей (%d) — часть недостижима"
			% [node_data.id, connections.size(), doors.size()]
		)
	return doors


## Запечатанная дверь: ребра под этот слот нет, идти некуда. Интеракцию НЕ
## выключаем (раньше выключали): выключенную дверь S_InteractionDetector
## игнорирует — она не подсвечивается и молчит, и игрок не отличает «прохода
## нет» от бага. Вместо этого штампуем ПУСТОЙ C_DoorPortal (пустой
## target_node_id = «запечатан», см. C_DoorPortal) и объясняем подсказкой;
## A_TravelThroughDoor по тому же признаку никуда не ведёт.
## Визуальное «заваривание» — на совести арта/будущей системы.
func _seal_door(door: Entity) -> void:
	door.add_component(C_DoorPortal.new())  # target_node_id == &"" — прохода нет
	# Нажимать бессмысленно, поэтому и клавишу в подсказке не предлагаем.
	_set_door_prompt(door, DOOR_PROMPT_SEALED, false)


func _set_door_prompt(door: Entity, prompt: String, show_key_hint: bool = true) -> void:
	var inter := door.get_component(C_Interactable) as C_Interactable
	if inter == null:
		return
	inter.prompt_text = prompt
	inter.show_key_hint = show_key_hint


func _slot_id_of(door: Entity) -> StringName:
	var slot := door.get_component(C_DoorSlot) as C_DoorSlot
	return slot.slot_id if slot else &""


func _get_player() -> E_Player:
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as E_Player


## Остаток распада БФЖ для сейва. -1 = писать нечего (нет игрока/компонента).
func _player_lifespan() -> float:
	var player := _get_player()
	if player == null:
		return -1.0
	var life := player.get_component(C_Lifespan) as C_Lifespan
	return life.current if life else -1.0


## На сколько метров вглубь комнаты отступать от двери, чтобы капсула игрока не
## оказалась в стене/проёме (радиус капсулы ~0.63, проём ~2.8 в ширину).
const ARRIVAL_OFFSET := 1.5


func _place_player_in_room(room: SpawnedRoom, came_from: StringName) -> void:
	var player := _get_player()
	if player == null:
		return

	var room_node := room.entity as Node as Node3D
	var spawn_point := room.entity.get_node_or_null(^"SpawnPoint") as Node3D
	var target: Transform3D
	var return_door := _find_return_door(room, came_from)
	if return_door:
		# НЕ трансформ самой двери: её origin — в плоскости стены и на высоте
		# центра полотна (~2.3 м). Ставим игрока ПЕРЕД дверью, вглубь комнаты, на
		# высоте пола, лицом внутрь — иначе капсулу спавнит в геометрии и роняет.
		target = _arrival_transform_for_door(return_door, room_node, spawn_point)
	elif spawn_point:
		target = spawn_point.global_transform
	else:
		target = room_node.global_transform
	(player as Node as Node3D).global_transform = target


## Безопасная точка прибытия у двери [param door]: горизонтально отступаем от
## двери к центру комнаты (направление надёжно независимо от ориентации двери —
## в пресете двери не сориентированы внутрь единообразно), высоту берём от
## SpawnPoint (пол), разворачиваем игрока лицом вглубь комнаты.
func _arrival_transform_for_door(door: Entity, room_node: Node3D, spawn_point: Node3D) -> Transform3D:
	var door_origin := (door as Node as Node3D).global_transform.origin
	var room_origin := room_node.global_transform.origin

	var into_room := room_origin - door_origin
	into_room.y = 0.0
	if into_room.length() < 0.001:
		into_room = -(door as Node as Node3D).global_transform.basis.z  # запасной вариант
	into_room = into_room.normalized()

	var pos := door_origin + into_room * ARRIVAL_OFFSET
	pos.y = spawn_point.global_transform.origin.y if spawn_point else room_origin.y

	return Transform3D.IDENTITY.translated(pos).looking_at(pos + into_room, Vector3.UP)


## Дверь комнаты [param room], ведущая обратно в came_from — чтобы игрок появился
## у неё, а не в общем SpawnPoint. null, если пришли не через дверь (вход в забег).
func _find_return_door(room: SpawnedRoom, came_from: StringName) -> Entity:
	if came_from == &"":
		return null
	for door in room.doors:
		var portal := door.get_component(C_DoorPortal) as C_DoorPortal
		if portal and portal.target_node_id == came_from:
			return door
	return null
