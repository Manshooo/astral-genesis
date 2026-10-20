# res://src/world/layer_streamer.gd
# Стриминг слоя забега: спавн и снос ВСЕХ узлов одной глубины (комнаты и тайлы веток), планы слоёв, раздача рёбер графа дверям и порталам. Отдельно от RunManager: у стриминга своё состояние и инварианты
# (позиция до add_entity, free() старых тайлов, отсев съеденных тел). RefCounted: в дереве живут его комнаты и тайлы, уходят со сценой; владелец (автолоад) переживает смену сцены, поэтому ссылки бывают битыми — проверять is_instance_valid. Вики: [[Цикл забега]].
class_name LayerStreamer
extends RefCounted

## «Слой не загружен»: глубины графа 0..5 (RS_LevelGraph.DEPTHS).
const NO_DEPTH := -1

## Заспавненная комната слоя. Вложенные сущности держим отдельно: add_entity(room) регистрирует ТОЛЬКО саму комнату, remove_entity(room) их не снимает.
class SpawnedRoom:
	extends RefCounted

	var node_id: StringName
	var entity: Entity
	## Вложенные сущности комнаты (двери, тела) — регистрируются и снимаются явно (_register_room_children / despawn).
	var children: Array[Entity] = []
	## Подмножество children — двери (C_DoorSlot); для поиска выхода обратно (PlayerPlacement.return_exit).
	var doors: Array[Entity] = []
	## Подмножество children — вертикальные порталы; им достаются рёбра со сменой глубины (_bind_portals).
	var portals: Array[Entity] = []
	## Дверь -> грань плана (GridTopology.face): сборной её поставил спавн, запечённая получает по стене (_bind_doors).
	var door_faces: Dictionary[Entity, Vector4i] = {}

	## Всё, что может нести C_DoorPortal, то есть вести в соседний узел.
	func exits() -> Array[Entity]:
		var all: Array[Entity] = doors.duplicate()
		all.append_array(portals)
		return all

	## Грань двери; NO_SIDE — не дверь или стена не определилась.
	func face_of(door: Entity) -> Vector4i:
		return door_faces.get(door, Vector4i(0, 0, 0, GridTopology.NO_SIDE))


## Граф забега; планы слоёв — его же (RS_LevelGraph.layer_plan).
var graph: RS_LevelGraph
## Глубина загруженного слоя (NO_DEPTH — ничего не загружено).
var depth: int = NO_DEPTH
## node_id -> SpawnedRoom для ВСЕХ комнат загруженного слоя.
var rooms: Dictionary[StringName, SpawnedRoom] = {}
## Ветка коридора -> тайлы слоя: голая геометрия со светом, не сущности ECS. Держим ради сноса слоя и «заспавнен ли узел» (присутствие в коридоре меняет текущий узел).
var corridor_tiles: Dictionary[StringName, Array] = {}
## Тайники эссенции в тупиках слоя (LayerFinds): находка — сущность, снимать из мира явно; комнатные уходят с комнатой.
var cache_finds: Array[Entity] = []
## Навмеш слоя: запекается по готовности, снимается вместе с ним.
var navigation := LayerNavigation.new()

## Общий родитель тайлов под ECS.world (_corridor_parent).
var _corridor_root: Node3D

## Показанные узлы слоя (reveal_around); пусто — показано всё (пока текущий узел не назначен).
var _shown: Dictionary[StringName, bool] = {}

## На сколько рёбер графа от текущего узла слой виден: весь слой в дереве (~170 ламп), окклюзия отсекает геометрию, но не свет. Два шага — из комнаты виден коридор, с его развилки поперечный;
## прямую линию взгляда рёбра не покрывают (на кресте узел меняется, третий за двумя рёбрами оставлял пустоту, 15 % узлов), поэтому прямые добавляются по плану (visible_from).
const VISIBLE_HOPS := 2

## Метаданные врага ростера: id маркера (_spawn_roster_enemies); сущность получает C_BodyOrigin.
const ROSTER_ID_META := &"roster_marker_id"

## Сколько spawn_async тратит на спавн за кадр, мкс: под шторкой кадр должен ещё и нарисоваться.
const SPAWN_FRAME_BUDGET_USEC := 8000


## Новый граф забега; планы слоёв приходят с ним.
func set_graph(new_graph: RS_LevelGraph) -> void:
	graph = new_graph


## План слоя layer_depth: посчитан при генерации без спавна, доступен для незагруженных слоёв (карта комплекса).
func plan_for_depth(layer_depth: int) -> RS_LayerPlan:
	return graph.layer_plan(layer_depth)


func is_spawned(node_id: StringName) -> bool:
	return rooms.has(node_id) or corridor_tiles.has(node_id)


func room(node_id: StringName) -> SpawnedRoom:
	return rooms.get(node_id)


func room_of_door(door: Entity) -> SpawnedRoom:
	for spawned: SpawnedRoom in rooms.values():
		if spawned.doors.has(door):
			return spawned
	return null


## Спавнит ВСЕ узлы слоя разом; предыдущий слой уже снят (иначе комнаты наложатся). false — глубины нет в графе.
func spawn(layer_depth: int) -> bool:
	var layer_nodes := graph.get_nodes_by_depth(layer_depth)
	if layer_nodes.is_empty():
		push_error("LayerStreamer: в графе нет узлов глубины %d" % layer_depth)
		return false

	var plan := plan_for_depth(layer_depth)
	for node_data in layer_nodes:
		_spawn_node(node_data, plan)
	depth = layer_depth
	navigation.bake(ECS.world)
	return true


## Как spawn, но порциями: узел за узлом, при исчерпании SPAWN_FRAME_BUDGET_USEC ждёт кадр tree (весь слой за кадр ~240 мс, профайлер 13.10). После каждого ожидания спрашивает [param keep_going]:
## вход могли перебить или сцену сменить — тогда слой чужой. false — нет глубины или спавн оборван (зовущий знает, что из двух). Глубина ставится по завершении. Порядок и содержимое как у spawn.
func spawn_async(layer_depth: int, tree: SceneTree, keep_going: Callable) -> bool:
	var layer_nodes := graph.get_nodes_by_depth(layer_depth)
	if layer_nodes.is_empty():
		push_error("LayerStreamer: в графе нет узлов глубины %d" % layer_depth)
		return false

	var plan := plan_for_depth(layer_depth)
	var started := Time.get_ticks_usec()
	for node_data in layer_nodes:
		if Time.get_ticks_usec() - started > SPAWN_FRAME_BUDGET_USEC:
			await tree.process_frame
			if not keep_going.call():
				return false
			started = Time.get_ticks_usec()
		_spawn_node(node_data, plan)
	depth = layer_depth
	navigation.bake(ECS.world)
	return true


## Один узел слоя: комната — сценой, коридор — тайлами кита.
func _spawn_node(node_data: RS_LevelNode, plan: RS_LayerPlan) -> void:
	# У коридора нет сцены: собирается из тайлов кита по трассе плана.
	if node_data.role == RS_LevelNode.Role.CORRIDOR:
		_spawn_corridor(node_data, plan)
		return
	var entity := _instantiate_room(node_data)
	if entity == null:
		return
	rooms[node_data.id] = _spawn_room(node_data, entity, plan)


## Снимает ВЕСЬ загруженный слой: по комнате сначала вложенные сущности, затем комнату. Ссылки могут указывать на УЖЕ ОСВОБОЖДЁННЫЕ (владелец переживает смену сцены), а remove_entity типизирован — freed-объект
## роняет проверку типа до тела функции, поэтому невалидные отсеиваем заранее. true — слой был загружен.
func despawn() -> bool:
	navigation.clear()
	for spawned: SpawnedRoom in rooms.values():
		_remove_valid_entities(spawned.children)
		if is_instance_valid(spawned.entity):
			ECS.world.remove_entity(spawned.entity)
	rooms.clear()
	# free(), не queue_free(): все слои раскладываются от одной клетки (0, 0), дожившие тайлы стояли бы коллизией внутри нового слоя.
	for tiles: Array in corridor_tiles.values():
		for tile in tiles:
			if is_instance_valid(tile):
				(tile as Node).free()
	corridor_tiles.clear()
	LayerFinds.remove_all(cache_finds)
	_shown.clear()
	var was_loaded := depth != NO_DEPTH
	depth = NO_DEPTH
	return was_loaded


## Показывает узлы, видимые из node_id (visible_from), и прячет остальные.
func reveal_around(node_id: StringName) -> void:
	var near := visible_from(graph, node_id)
	for id: StringName in rooms:
		var on := near.has(id)
		if _shown.get(id, true) != on and is_instance_valid(rooms[id].entity):
			_set_room_visible(rooms[id].entity as Node as Node3D, on)
		_shown[id] = on
	for id: StringName in corridor_tiles:
		var on := near.has(id)
		if _shown.get(id, true) != on:
			for tile in corridor_tiles[id]:
				if is_instance_valid(tile):
					(tile as Node3D).visible = on
		_shown[id] = on


## Что видно из узла: не дальше VISIBLE_HOPS рёбер и всё на прямой линии взгляда по плану (RS_LayerPlan.in_sight_of). Портальные рёбра не в счёт (другой слой не в дереве). Статическая — проверки зовут её без спавна.
static func visible_from(level_graph: RS_LevelGraph, node_id: StringName) -> Dictionary[StringName, bool]:
	var near: Dictionary[StringName, bool] = {node_id: true}
	var hops: Dictionary[StringName, int] = {node_id: 0}
	var queue: Array[StringName] = [node_id]
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		if hops[current] >= VISIBLE_HOPS:
			continue
		var node_data := level_graph.get_node_data(current)
		if node_data == null:
			continue
		for conn: RS_LevelConnection in node_data.connections:
			if conn.is_portal() or hops.has(conn.target_node_id):
				continue
			hops[conn.target_node_id] = hops[current] + 1
			near[conn.target_node_id] = true
			queue.append(conn.target_node_id)
	var here := level_graph.get_node_data(node_id)
	var plan := level_graph.layer_plan(here.depth) if here else null
	if plan:
		near.merge(plan.in_sight_of(node_id))
	return near


## Показан ли узел (для проверок и ShadowBudget-подобных потребителей).
func is_shown(node_id: StringName) -> bool:
	return _shown.get(node_id, true)


## Прячет содержимое комнаты, кроме ходящего: враг в погоне живёт под её корнем и стал бы невидимкой рядом с игроком.
func _set_room_visible(room_root: Node3D, on: bool) -> void:
	for child in room_root.get_children():
		if child is Node3D and not child is CharacterBody3D:
			(child as Node3D).visible = on


func _remove_valid_entities(list: Array[Entity]) -> void:
	var valid: Array[Entity] = []
	for e in list:
		if is_instance_valid(e):
			valid.append(e)
	if not valid.is_empty():
		ECS.world.remove_entities(valid)


## Застраивает ветку коридора кусками кита: на тайл плана — кусок под маску, с торцами у дверей комнат (RS_LayerPlan.door_mask). Нет куска под маску — тайл пропускается с ошибкой (раскладка таких не выдаёт, это надо видеть).
func _spawn_corridor(node_data: RS_LevelNode, plan: RS_LayerPlan) -> void:
	var kit := GameConfig.config.corridor_kit
	if kit == null:
		push_error("LayerStreamer: нет набора кусков коридора (GameConfig.corridor_kit)")
		return
	var parent := _corridor_parent()
	var light := RS_DepthLighting.layer(node_data.depth)
	var dead_chance := light.dead_lamp_chance if light else 0.0
	var tiles: Array[Node3D] = []
	for cell: Vector3i in plan.corridor_tiles:
		if plan.node_by_cell.get(cell, &"") != node_data.id:
			continue
		var tile := kit.instantiate(plan.corridor_tiles[cell], plan.door_mask(cell))
		if tile == null:
			push_error("LayerStreamer: нет куска кита под маску %d (тайл %s)" % [plan.corridor_tiles[cell], cell])
			continue
		if _is_lamp_dead(node_data.depth, cell, dead_chance):
			_remove_lamps(tile)
		# Позиция ДО входа в дерево, как у комнат: иначе коллизия зарегистрируется в начале координат.
		tile.position = plan.embedding.cell_origin(cell)
		parent.add_child(tile)
		tiles.append(tile)
	corridor_tiles[node_data.id] = tiles
	cache_finds.append_array(LayerFinds.place_caches(node_data, plan, graph.run_seed))


## Погасла ли лампа тайла — своим ГСЧ от (сид, слой, клетка), не общим: тот же мир гасит те же лампы, граф не зависит. Слой в ключе — все слои раскладываются от (0, 0).
func _is_lamp_dead(layer_depth: int, cell: Vector3i, chance: float) -> bool:
	if chance <= 0.0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([graph.run_seed, layer_depth, cell])
	return rng.randf() < chance


## Снимает лампы тайла до входа в дерево: погасшая не светит и не занимает ячейку атласа (ShadowBudget). Плафон остаётся тёмным — мёртвый светильник, не дыра.
func _remove_lamps(tile: Node3D) -> void:
	for node in tile.find_children("*", "Light3D", true, false):
		if not node is LevelLight:
			continue
		var light := node as Node3D
		for child in light.get_children():
			if child is LampFixture:
				var fixture := child as LampFixture
				var placed := light.transform * fixture.transform
				# Владелец плафона — корень сцены лампы, которая уйдёт: без сброса Godot ругается на чужого владельца.
				for owned: Node in [fixture as Node] + fixture.find_children("*", "", true, false):
					owned.owner = null
				light.remove_child(fixture)
				light.get_parent().add_child(fixture)
				fixture.transform = placed
				fixture.go_dark()
		light.free()


## Родитель тайлов — под миром ECS, чтобы уходить со сценой; ссылка бывает битой — заводим заново.
func _corridor_parent() -> Node3D:
	if not is_instance_valid(_corridor_root) or not _corridor_root.is_inside_tree():
		_corridor_root = Node3D.new()
		_corridor_root.name = "Corridors"
		ECS.world.add_child(_corridor_root)
	return _corridor_root


## Инстанцирует сцену комнаты, НЕ добавляя в мир; null — путь невалиден.
func _instantiate_room(node_data: RS_LevelNode) -> Entity:
	if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
		push_error("LayerStreamer: невалидная room_scene_path у узла '%s'" % node_data.id)
		return null
	return (load(node_data.room_scene_path) as PackedScene).instantiate() as Entity


## Ставит инстанцированную комнату на место по плану и регистрирует содержимое.
func _spawn_room(node_data: RS_LevelNode, entity: Entity, plan: RS_LayerPlan) -> SpawnedRoom:
	# Место и поворот ДО add_entity: иначе коллайдеры регистрируются в начале координат. Через Node: прямой каст Entity→Node3D анализатор не пропускает.
	var spatial := entity as Node as Node3D
	if spatial:
		spatial.transform = plan.room_transform(node_data.id)

	# Стены и двери сборной комнаты — до add_entity: двери попадут в обход вложенных сущностей.
	var shell := RS_RoomLayout.shell_of(entity)
	var assembled: Dictionary[Node3D, Vector4i] = {}
	if shell and spatial:
		if shell.walls:
			assembled = shell.walls.assemble(spatial, node_data.id, plan)
		else:
			push_error("LayerStreamer: у коробки '%s' нет кита стен" % node_data.room_scene_path)

	# Враги ростера — детьми комнаты до add_entity: подхватит _register_room_children, снесёт despawn.
	_spawn_roster_enemies(entity, node_data)
	# Находки эссенции на маркерах — до add_entity (LayerFinds.place_in_room).
	LayerFinds.place_in_room(entity, node_data, graph.run_seed)

	ECS.world.add_entity(entity)

	var spawned := SpawnedRoom.new()
	spawned.node_id = node_data.id
	spawned.entity = entity
	spawned.children = _register_room_children(entity, node_data.id)
	# Слот — после регистрации, как всё, меняющее состав компонентов живой сущности (_bind_doors).
	for node: Node3D in assembled:
		var door := node as Node as Entity
		if door == null:
			continue
		var slot := C_DoorSlot.new()
		slot.slot_id = StringName("%s_%d" % [RS_RoomLayout.side_name(assembled[node].w), spawned.door_faces.size()])
		door.add_component(slot)
		spawned.door_faces[door] = assembled[node]
	spawned.doors = _bind_doors(spawned, node_data, plan)
	return spawned


## Регистрирует вложенные сущности комнаты (add_entity(room) кладёт только её). Отсеивает УЖЕ ПОГЛОЩЁННЫЕ тела: комната приходит из сцены целой, комплекс — из сида.
func _register_room_children(room_entity: Entity, node_id: StringName) -> Array[Entity]:
	var children: Array[Entity] = []
	# owned=false — иначе сущности из инстансов под-сцен не находятся.
	for node in room_entity.find_children("*", "Entity", true, false):
		var e := node as Entity
		if e == null:
			continue
		var body := e as E_Body
		if body and WorldSave.save.consumed_body_ids.has(_body_id(node_id, room_entity, body)):
			# Тело съедено — иначе рядом встала бы копия того, в ком игрок сидит; в мир не регистрируем.
			body.queue_free()
			continue
		children.append(e)
	if not children.is_empty():
		ECS.world.add_entities(children)

	# Происхождение штампуем ПОСЛЕ регистрации, как рёбра дверям: правка состава должна дойти до архетипов.
	for e in children:
		var body := e as E_Body
		if body:
			var origin := C_BodyOrigin.new()
			origin.body_id = _body_id(node_id, room_entity, body)
			body.add_component(origin)
		elif e.has_meta(ROSTER_ID_META):
			# Враг ростера несёт id маркера, O_EnemyDeath передаст его трупу: съеденный труп помечает id в сейве, маркер больше не разыгрывается.
			var origin := C_BodyOrigin.new()
			origin.body_id = e.get_meta(ROSTER_ID_META)
			e.add_component(origin)
	return children


## Ставит врагов ростера на маркеры EnemySpawn*: кто встанет, решает RS_EnemyRoster.roll (слой, собранный заново, вернёт тех же). Маркер с съеденным трупом не разыгрывается.
func _spawn_roster_enemies(room_entity: Entity, node_data: RS_LevelNode) -> void:
	var room_node := room_entity as Node as Node3D
	if room_node == null:
		return
	var roster := RS_EnemyRoster.current()
	for node in room_entity.find_children("EnemySpawn*", "Marker3D", true, false):
		var marker_id := StringName("%s/%s" % [node_data.id, room_entity.get_path_to(node)])
		if WorldSave.save.consumed_body_ids.has(marker_id):
			continue
		var scene := roster.roll(graph.run_seed, node_data.depth, node_data.id, node.name)
		if scene == null:
			continue
		var enemy := scene.instantiate() as Entity
		if enemy == null:
			continue
		enemy.set_meta(ROSTER_ID_META, marker_id)
		room_entity.add_child(enemy)
		# Позиция — от комнаты: она ещё не в дереве.
		(enemy as Node as Node3D).transform = RS_EntityVisuals.transform_relative_to(node, room_entity)


## Стабильный id авторского тела: узел графа плюс путь внутри комнаты (один e_body.tscn стоит в разных комнатах).
func _body_id(node_id: StringName, room_entity: Entity, body: Node) -> StringName:
	return StringName("%s/%s" % [node_id, room_entity.get_path_to(body)])


## Штампует C_DoorPortal на двери комнаты: за каждой — ветка, которую план поставил на её грань (RS_LayerPlan.door_faces). По граням, не по рёбрам: две двери законно ведут в одну ветку. Дверь сборной комнаты
## грань знает, запечённая получает по стене (клетка комнаты и сторона). Дверь без ветки — план и сцена разошлись: заваривается с предупреждением, а не уводит не туда.
func _bind_doors(spawned: SpawnedRoom, node_data: RS_LevelNode, plan: RS_LayerPlan) -> Array[Entity]:
	var doors: Array[Entity] = []
	for e in spawned.children:
		if e.has_component(C_DoorSlot):
			doors.append(e)
	_bind_portals(spawned, node_data)

	var faces: Dictionary = plan.door_faces.get(node_data.id, {})
	var anchor: Vector3i = plan.cells.get(node_data.id, Vector3i.ZERO)
	for door in doors:
		if not spawned.door_faces.has(door):
			# Сторона стены — в осях сцены; в мир её переводит поворот комнаты.
			var wall := RS_RoomLayout.door_side(door as Node as Node3D, spawned.entity)
			wall = plan.topology.rotate_side(anchor, wall, -plan.turns.get(node_data.id, 0))
			spawned.door_faces[door] = GridTopology.face(anchor, wall)
		var face := spawned.face_of(door)
		var target: StringName = faces.get(face, &"")
		if target == &"":
			push_warning("LayerStreamer: у двери '%s' узла '%s' нет ветки за стороной %s" % [door.name, node_data.id, RS_RoomLayout.side_name(face.w)])
			_seal_door(door)
			continue
		var portal := C_DoorPortal.new()
		portal.target_node_id = target
		door.add_component(portal)
	return doors


## Раздаёт рёбра ПОРТАЛОВ порталам комнаты (между слоями и, без лестницы, между этажами); узнаётся по типу (RS_LevelConnection.is_portal) — верхняя дверь лестницы это дверь (_bind_doors).
## Портал без ребра глушится: остаётся интерактивным, отвечает «прохода нет». Портал в комнате один, лишнему ребру некуда деться — предупреждение.
func _bind_portals(spawned: SpawnedRoom, node_data: RS_LevelNode) -> void:
	var portals: Array[Entity] = []
	for e in spawned.children:
		if e is E_VerticalPortal:
			portals.append(e)
	spawned.portals = portals

	# Порядок по имени узла: раздача рёбер детерминирована.
	portals.sort_custom(func(a, b): return String(a.name) < String(b.name))

	var free_portals := portals.duplicate()
	for conn: RS_LevelConnection in node_data.connections:
		var target := graph.get_node_data(conn.target_node_id)
		if target == null or not conn.is_portal():
			continue
		if free_portals.is_empty():
			push_warning("LayerStreamer: у узла '%s' нет портала под ребро в '%s'" % [node_data.id, conn.target_node_id])
			continue
		var portal: Entity = free_portals.pop_front()
		_stamp_portal(portal, conn)

	for portal in free_portals:
		_seal_door(portal)


func _stamp_portal(door: Entity, conn: RS_LevelConnection) -> void:
	var portal := C_DoorPortal.new()
	portal.target_node_id = conn.target_node_id
	portal.locked_by = conn.locked_by
	door.add_component(portal)


## Запечатанная дверь: ребра под слот нет. Интеракцию НЕ выключаем (выключенную S_InteractionDetector игнорирует, и «прохода нет» не отличить от бага): пустой C_DoorPortal, A_TravelThroughDoor отвечает сообщением.
func _seal_door(door: Entity) -> void:
	door.add_component(C_DoorPortal.new())  # target_node_id == &"" — прохода нет
