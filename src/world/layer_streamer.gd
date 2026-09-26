# res://src/world/layer_streamer.gd
# Стриминг слоя забега: спавн и снос ВСЕХ узлов одной глубины разом (комнаты и
# тайлы веток коридора), планы слоёв и раздача рёбер графа по дверям и порталам.
#
# Жил внутри RunManager вместе с автоматом забега, контрольными точками и
# постановкой игрока — пять обязанностей в тысяче строк, где спавн комнаты и
# запись сейва ходили в одни и те же поля. Отдельно он потому, что у стриминга
# своё состояние (что сейчас в дереве, какие планы посчитаны) и свои инварианты
# (позиция до add_entity, free() старых тайлов, отсев съеденных тел), и ни одно
# из них автомату забега знать не нужно: тот говорит «загрузи слой N», «сними
# слой», «какая комната у этой двери» — и больше ничего.
#
# RefCounted, а не узел: сам он в дереве не живёт, живут его комнаты и тайлы —
# под миром ECS, и уходят вместе со сценой мира. Отсюда главная ловушка: владелец
# (RunManager) — автолоад и переживает смену сцены, поэтому ссылки здесь бывают
# битыми, и всё, что их трогает, проверяет is_instance_valid.
class_name LayerStreamer
extends RefCounted

## «Слой не загружен». Глубины графа — 0..4 (RS_LevelGraph.DEPTHS), так что -1
## никогда не совпадёт с реальной.
const NO_DEPTH := -1

## Подсказки на дверях. Состояние двери известно только при раздаче рёбер,
## поэтому prompt_text проставляем здесь, а не в пресете комнаты (в сценах он у
## дверей пустой). Игрок должен отличать рабочую дверь от запертой и от
## запечатанного проёма ДО нажатия — иначе непонятно, декор это или баг.
const DOOR_PROMPT_OPEN := "Пройти"
const DOOR_PROMPT_LOCKED := "Заперто"
const DOOR_PROMPT_SEALED := "Прохода нет"
## Дверь в коридор: она не переносит, а открывается (коридорная раскладка).
const DOOR_PROMPT_UNSEAL := "Открыть"

## Подсказки на вертикальных порталах. Вверх/вниз считаем по глубине цели, а не
## по знаку depth_delta: у слоёв номер РАСТЁТ вглубь, и знак читается наоборот.
const PORTAL_PROMPT_UP := "Подняться"
const PORTAL_PROMPT_DOWN := "Спуститься"
const PORTAL_PROMPT_LOCKED := "Портал заблокирован"
const PORTAL_PROMPT_DEAD := "Портал мёртв"


## Одна заспавненная комната слоя. Вложенные сущности держим отдельно от самой
## комнаты, т.к. add_entity(room) регистрирует ТОЛЬКО саму комнату (обхода дерева
## в поисках вложенных Entity в GECS нет), а remove_entity(room) их не снимает.
class SpawnedRoom:
	extends RefCounted

	var node_id: StringName
	var entity: Entity
	## Вложенные сущности комнаты (Incubator, двери, тела) — регистрируются и
	## снимаются явно, см. _register_room_children / despawn.
	var children: Array[Entity] = []
	## Подмножество children — двери (с C_DoorSlot). Нужно для поиска выхода,
	## ведущего обратно (PlayerPlacement.return_exit).
	var doors: Array[Entity] = []
	## Подмножество children — вертикальные порталы. Им достаются рёбра со сменой
	## глубины (см. _bind_portals); в остальном они такой же «выход», как дверь.
	var portals: Array[Entity] = []

	## Всё, что может нести C_DoorPortal, то есть вести в соседний узел графа.
	func exits() -> Array[Entity]:
		var all: Array[Entity] = doors.duplicate()
		all.append_array(portals)
		return all


## Граф забега. Смена графа сбрасывает планы (см. set_graph).
var graph: RS_LevelGraph
## Глубина загруженного слоя (NO_DEPTH — ничего не загружено).
var depth: int = NO_DEPTH
## node_id -> SpawnedRoom для ВСЕХ комнат загруженного слоя.
var rooms: Dictionary[StringName, SpawnedRoom] = {}
## Ветка коридора -> собранные тайлы загруженного слоя. Не сущности ECS, а голая
## геометрия со светом: у тайла нет ни компонентов, ни поведения, и мир ради него
## регистрировать незачем. Держим ради сноса слоя и ради «заспавнен ли узел» —
## присутствие игрока в коридоре меняет текущий узел так же, как в комнате.
var corridor_tiles: Dictionary[StringName, Array] = {}

## Снимок ручек, по которым построен граф: шаг решётки комнат — тоже ручка, и план
## обязан строиться по тем же числам, что и граф.
var _gen_config: RS_WorldGenConfig
## depth -> RS_LayerPlan. План детерминирован от графа и не зависит от того,
## загружен слой или нет, — считается один раз за забег. Карта комплекса
## спрашивает планы слоёв, в которых игрок ещё не был.
var _plans: Dictionary[int, RS_LayerPlan] = {}
## Общий родитель тайлов под ECS.world — см. _corridor_parent.
var _corridor_root: Node3D


## Новый граф забега и ручки, по которым он построен. Планы прошлого графа к
## новому не относятся — сбрасываем.
func set_graph(new_graph: RS_LevelGraph, gen_config: RS_WorldGenConfig) -> void:
	graph = new_graph
	_gen_config = gen_config
	_plans.clear()


## План слоя [param layer_depth] — где стоит каждая комната и какое ребро уходит
## в какую дверь. Считается БЕЗ спавна (стороны дверей берутся из кэша по пути
## сцены), поэтому доступен и для незагруженных слоёв.
func plan_for_depth(layer_depth: int) -> RS_LayerPlan:
	if _plans.has(layer_depth):
		return _plans[layer_depth]
	var plan := RS_LayerPlan.build(graph.get_nodes_by_depth(layer_depth), _gen_config)
	_plans[layer_depth] = plan
	return plan


func is_spawned(node_id: StringName) -> bool:
	return rooms.has(node_id) or corridor_tiles.has(node_id)


func room(node_id: StringName) -> SpawnedRoom:
	return rooms.get(node_id)


func room_of_door(door: Entity) -> SpawnedRoom:
	for spawned: SpawnedRoom in rooms.values():
		if spawned.doors.has(door):
			return spawned
	return null


## Спавнит ВСЕ узлы слоя [param layer_depth] разом. Предполагает, что
## предыдущий слой уже снят (despawn) — иначе комнаты наложатся по сетке.
## false — в графе нет такой глубины.
func spawn(layer_depth: int) -> bool:
	var layer_nodes := graph.get_nodes_by_depth(layer_depth)
	if layer_nodes.is_empty():
		push_error("LayerStreamer: в графе нет узлов глубины %d" % layer_depth)
		return false

	var plan := plan_for_depth(layer_depth)
	for node_data in layer_nodes:
		# У коридора нет сцены: он собирается из тайлов кита по трассе плана.
		if node_data.role == RS_LevelNode.Role.CORRIDOR:
			_spawn_corridor(node_data, plan)
			continue
		var entity := _instantiate_room(node_data)
		if entity == null:
			continue
		rooms[node_data.id] = _spawn_room(node_data, entity, plan)
	depth = layer_depth
	return true


## Снимает ВЕСЬ загруженный слой. По каждой комнате сначала вложенные сущности
## (иначе после queue_free комнаты они остались бы битыми ссылками в реестре
## мира), затем саму комнату. true — слой был загружен и снят.
##
## Ссылки могут указывать на УЖЕ ОСВОБОЖДЁННЫЕ сущности: владелец — автолоад и
## переживает смену сцены, так что после «Выхода в меню» прошлый забег улетает
## вместе со сценой мира, а ссылки остаются битыми. remove_entity(entity: Entity)
## типизирован — freed-объект роняет проверку типа ещё ДО тела функции, поэтому
## отсеиваем невалидные заранее.
func despawn() -> bool:
	for spawned: SpawnedRoom in rooms.values():
		_remove_valid_entities(spawned.children)
		if is_instance_valid(spawned.entity):
			ECS.world.remove_entity(spawned.entity)
	rooms.clear()
	# free(), не queue_free(): все слои раскладываются от одной клетки (0, 0), и
	# тайлы старого слоя, дожившие до конца кадра, стояли бы коллизией внутри
	# только что заспавненного нового.
	for tiles: Array in corridor_tiles.values():
		for tile in tiles:
			if is_instance_valid(tile):
				(tile as Node).free()
	corridor_tiles.clear()
	var was_loaded := depth != NO_DEPTH
	depth = NO_DEPTH
	return was_loaded


func _remove_valid_entities(list: Array[Entity]) -> void:
	var valid: Array[Entity] = []
	for e in list:
		if is_instance_valid(e):
			valid.append(e)
	if not valid.is_empty():
		ECS.world.remove_entities(valid)


## Застраивает ветку коридора кусками кита: на каждый её тайл плана — кусок под
## маску проёмов, повёрнутый на нужную четверть оборота. Нет куска под маску
## (торец) — тайл пропускается с ошибкой: раскладка таких не выдаёт, и если
## выдала, это надо видеть, а не залатывать молча.
func _spawn_corridor(node_data: RS_LevelNode, plan: RS_LayerPlan) -> void:
	var kit := GameConfig.config.corridor_kit
	if kit == null:
		push_error("LayerStreamer: нет набора кусков коридора (GameConfig.corridor_kit)")
		return
	var parent := _corridor_parent()
	var tiles: Array[Node3D] = []
	for cell: Vector3i in plan.corridor_tiles:
		if plan.node_by_cell.get(cell, &"") != node_data.id:
			continue
		var tile := kit.instantiate(plan.corridor_tiles[cell])
		if tile == null:
			push_error("LayerStreamer: нет куска кита под маску %d (тайл %s)" % [plan.corridor_tiles[cell], cell])
			continue
		# Позиция ДО входа в дерево — как и у комнат (_spawn_room): иначе
		# коллизия тайла успеет зарегистрироваться в начале координат.
		tile.position = plan.embedding.cell_origin(cell)
		parent.add_child(tile)
		tiles.append(tile)
	corridor_tiles[node_data.id] = tiles


## Родитель тайлов — под миром ECS, чтобы уходить вместе со сценой мира. Ссылка
## переживает смену сцены и бывает битой: тогда заводим заново.
func _corridor_parent() -> Node3D:
	if not is_instance_valid(_corridor_root) or not _corridor_root.is_inside_tree():
		_corridor_root = Node3D.new()
		_corridor_root.name = "Corridors"
		ECS.world.add_child(_corridor_root)
	return _corridor_root


## Инстанцирует сцену комнаты, НЕ добавляя её в мир. null — путь сцены невалиден.
func _instantiate_room(node_data: RS_LevelNode) -> Entity:
	if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
		push_error("LayerStreamer: невалидная room_scene_path у узла '%s'" % node_data.id)
		return null
	return (load(node_data.room_scene_path) as PackedScene).instantiate() as Entity


## Ставит уже инстанцированную комнату на её место по плану и регистрирует всё
## её содержимое в мире.
func _spawn_room(node_data: RS_LevelNode, entity: Entity, plan: RS_LayerPlan) -> SpawnedRoom:
	# Позицию ставим ДО add_entity: тот сам вносит узел в дерево, и комната должна
	# попасть туда сразу на своё место — иначе коллайдеры успевают
	# зарегистрироваться в начале координат и телепортируются следом.
	# Через Node: Entity наследует Node, и прямой каст Entity→Node3D анализатор
	# GDScript не пропускает.
	var spatial := entity as Node as Node3D
	if spatial:
		spatial.position = plan.position_of(node_data.id)

	ECS.world.add_entity(entity)

	var spawned := SpawnedRoom.new()
	spawned.node_id = node_data.id
	spawned.entity = entity
	spawned.children = _register_room_children(entity, node_data.id)
	spawned.doors = _bind_doors(spawned, node_data, plan)
	return spawned


## Регистрирует в мире все вложенные сущности комнаты (Incubator, двери и т.п.).
## Нужно, т.к. add_entity(room) кладёт в мир ТОЛЬКО саму комнату — обхода дерева
## в поисках вложенных Entity в GECS нет.
##
## Здесь же отсеиваются УЖЕ ПОГЛОЩЁННЫЕ тела: комната приходит из сцены целой,
## сколько бы раз игрок в ней ни вселялся, потому что комплекс восстанавливается
## из сида, а не из сейва.
func _register_room_children(room_entity: Entity, node_id: StringName) -> Array[Entity]:
	var children: Array[Entity] = []
	# owned=false — иначе сущности, вставленные как инстансы под-сцены, не находятся.
	for node in room_entity.find_children("*", "Entity", true, false):
		var e := node as Entity
		if e == null:
			continue
		var body := e as E_Body
		if body and WorldSave.save.consumed_body_ids.has(_body_id(node_id, room_entity, body)):
			# Тело съедено захватом — иначе рядом с игроком встанет копия того,
			# в ком он сидит. В мир его не регистрируем, поэтому одного кадра до
			# освобождения узла ни одна система не увидит.
			body.queue_free()
			continue
		children.append(e)
	if not children.is_empty():
		ECS.world.add_entities(children)

	# Происхождение штампуем ПОСЛЕ регистрации — как и рёбра дверям (_bind_doors):
	# правка состава компонентов должна дойти до архетипов уже живой сущности.
	for e in children:
		var body := e as E_Body
		if body:
			var origin := C_BodyOrigin.new()
			origin.body_id = _body_id(node_id, room_entity, body)
			body.add_component(origin)
	return children


## Стабильный id авторского тела: узел графа плюс путь узла внутри комнаты.
## Сцена тела своего id не знает и знать не может — один и тот же e_body.tscn
## стоит в разных комнатах, а сид одинаково восстанавливает их все.
func _body_id(node_id: StringName, room_entity: Entity, body: Node) -> StringName:
	return StringName("%s/%s" % [node_id, room_entity.get_path_to(body)])


## Штампует C_DoorPortal на двери комнаты (подмножество children с C_DoorSlot): за
## каждой дверью — ветка, которую план поставил на её сторону
## (RS_LayerPlan.door_sides). По сторонам, а не по рёбрам: две двери комнаты
## законно ведут в одну ветку, и по id соседа их не различить. Порядок дверей
## поэтому ничего не решает — каждая привязывается сама, по своей стене.
## Остаточного принципа нет — рёбер в коридоры у комнаты ровно столько, сколько
## дверей; дверь без ветки значит, что план и сцена разошлись, и её честнее
## заварить с предупреждением, чем увести не туда.
func _bind_doors(spawned: SpawnedRoom, node_data: RS_LevelNode, plan: RS_LayerPlan) -> Array[Entity]:
	var doors: Array[Entity] = []
	for e in spawned.children:
		if e.has_component(C_DoorSlot):
			doors.append(e)
	_bind_portals(spawned, node_data)

	var sides: Dictionary = plan.door_sides.get(node_data.id, {})
	for door in doors:
		var side := RS_RoomLayout.door_side(door as Node as Node3D, spawned.entity)
		var target: StringName = sides.get(side, &"")
		if target == &"":
			push_warning("LayerStreamer: у двери '%s' узла '%s' нет ветки за стороной %s" % [door.name, node_data.id, RS_RoomLayout.side_name(side)])
			_seal_door(door)
			continue
		var portal := C_DoorPortal.new()
		portal.target_node_id = target
		door.add_component(portal)
		_set_door_prompt(door, DOOR_PROMPT_OPEN if node_data.door_teleports else DOOR_PROMPT_UNSEAL)
	return doors


## Раздаёт ВЕРТИКАЛЬНЫЕ рёбра порталам комнаты — и между слоями, и между этажами
## слоя: ходить по коридорам можно только в плоскости этажа. Портал без ребра
## «глушится» так же, как лишняя дверь: остаётся интерактивным, но объясняет, что
## никуда не ведёт.
##
## Портал в комнате ровно один, и генератор гарантирует не больше одного
## вертикального ребра на узел (RS_LevelGraph._free_for_portal): лишнему ребру
## здесь некуда деться, и оно было бы молча потеряно — поэтому предупреждение.
func _bind_portals(spawned: SpawnedRoom, node_data: RS_LevelNode) -> void:
	var portals: Array[Entity] = []
	for e in spawned.children:
		if e is E_VerticalPortal:
			portals.append(e)
	spawned.portals = portals

	# Порядок фиксируем по имени узла: раздача рёбер обязана быть детерминированной.
	portals.sort_custom(func(a, b): return String(a.name) < String(b.name))

	var free_portals := portals.duplicate()
	for conn: RS_LevelConnection in node_data.connections:
		var target := graph.get_node_data(conn.target_node_id)
		var is_vertical := target != null and (
			target.depth != node_data.depth or target.floor_index != node_data.floor_index
		)
		if not is_vertical:
			continue
		if free_portals.is_empty():
			push_warning("LayerStreamer: у узла '%s' нет портала под ребро в '%s'" % [node_data.id, conn.target_node_id])
			continue
		var portal: Entity = free_portals.pop_front()
		_stamp_portal(portal, conn)
		_set_door_prompt(portal, _portal_prompt(node_data, target, conn))

	for portal in free_portals:
		_seal_door(portal)
		_set_door_prompt(portal, PORTAL_PROMPT_DEAD, false)


## Куда ведёт портал — вверх (к поверхности, depth меньше; выше по этажу) или вниз.
func _portal_prompt(
	node_data: RS_LevelNode, target: RS_LevelNode, conn: RS_LevelConnection
) -> String:
	if conn.locked_by != &"":
		return PORTAL_PROMPT_LOCKED
	if target.depth == node_data.depth:
		# Между этажами слоя: этажи разнесены вверх по номеру (RS_LayerPlan).
		return PORTAL_PROMPT_UP if target.floor_index > node_data.floor_index else PORTAL_PROMPT_DOWN
	return PORTAL_PROMPT_UP if target.depth < node_data.depth else PORTAL_PROMPT_DOWN


func _stamp_portal(door: Entity, conn: RS_LevelConnection) -> void:
	var portal := C_DoorPortal.new()
	portal.target_node_id = conn.target_node_id
	portal.locked_by = conn.locked_by
	door.add_component(portal)
	_set_door_prompt(door, DOOR_PROMPT_LOCKED if portal.is_locked() else DOOR_PROMPT_OPEN)


## Запечатанная дверь: ребра под этот слот нет, идти некуда. Интеракцию НЕ
## выключаем: выключенную дверь S_InteractionDetector игнорирует — она не
## подсвечивается и молчит, и игрок не отличает «прохода нет» от бага. Вместо
## этого штампуем ПУСТОЙ C_DoorPortal (пустой target_node_id = «запечатан», см.
## C_DoorPortal) и объясняем подсказкой; A_TravelThroughDoor по тому же признаку
## никуда не ведёт.
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
