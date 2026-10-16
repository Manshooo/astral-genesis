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

## «Слой не загружен». Глубины графа — 0..5 (RS_LevelGraph.DEPTHS), так что -1
## никогда не совпадёт с реальной.
const NO_DEPTH := -1

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
	## Дверь -> грань плана, в которой она стоит (GridTopology.face). Дверь
	## сборной комнаты знает грань с рождения — её туда поставил спавн; дверь,
	## запечённая в сцену, получает грань по своей стене (см. _bind_doors).
	var door_faces: Dictionary[Entity, Vector4i] = {}

	## Всё, что может нести C_DoorPortal, то есть вести в соседний узел графа.
	func exits() -> Array[Entity]:
		var all: Array[Entity] = doors.duplicate()
		all.append_array(portals)
		return all

	## Грань двери; сторона GridTopology.NO_SIDE — не дверь или стена не определилась.
	func face_of(door: Entity) -> Vector4i:
		return door_faces.get(door, Vector4i(0, 0, 0, GridTopology.NO_SIDE))


## Граф забега; планы слоёв — его же (RS_LevelGraph.layer_plan).
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
## Тайники эссенции в тупиках загруженного слоя (LayerFinds). Отдельно от тайлов:
## у тайла нет сущности, а находка — сущность, и снимать её надо из мира явно.
## Находки в комнатах здесь не числятся — они дети комнаты и уходят с ней.
var cache_finds: Array[Entity] = []
## Навмеш загруженного слоя: запекается по готовности слоя, снимается вместе с ним.
var navigation := LayerNavigation.new()

## Общий родитель тайлов под ECS.world — см. _corridor_parent.
var _corridor_root: Node3D

## Узлы слоя, которые сейчас показаны (reveal_around). Пусто — показано всё:
## так слой выходит из spawn, пока текущий узел ещё не назначен.
var _shown: Dictionary[StringName, bool] = {}

## На сколько рёбер графа от текущего узла слой виден. Весь слой стоит в дереве
## разом (~170 ламп), а окклюзия Godot отсекает геометрию, но не свет: лампа
## комнаты за стеной светила бы сквозь неё и тратила кадр. Граф — честный
## посредник «что видно»: глазу открыто только то, что соединено проёмами.
## Два шага, а не один: из комнаты через дверь виден коридор, а с его развилки —
## поперечный коридор и двери его комнат; прямая же линия взгляда остаётся в
## одном коридоре, раскладка отдаёт развилку прямому (RS_CorridorPlanner).
const VISIBLE_HOPS := 2

## Метаданные врага ростера: id маркера, с которого он встал (см.
## _spawn_roster_enemies). Сущность с этим id получает C_BodyOrigin.
const ROSTER_ID_META := &"roster_marker_id"

## Сколько spawn_async тратит на спавн за кадр, микросекунды. Меньше кадра в
## 60 FPS с запасом: под шторкой загрузки кадр должен успеть ещё и нарисоваться.
const SPAWN_FRAME_BUDGET_USEC := 8000


## Новый граф забега; планы слоёв приходят вместе с ним.
func set_graph(new_graph: RS_LevelGraph) -> void:
	graph = new_graph


## План слоя [param layer_depth] — где стоит каждая комната и какое ребро уходит
## в какую дверь. Посчитан при генерации графа, без спавна, поэтому доступен и для
## незагруженных слоёв: карта комплекса спрашивает слои, где игрок ещё не был.
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
		_spawn_node(node_data, plan)
	depth = layer_depth
	navigation.bake(ECS.world)
	return true


## Как spawn, но порциями: узел за узлом, и как только кадр выбрал
## SPAWN_FRAME_BUDGET_USEC, ждёт следующий кадр [param tree]. Нужен входу в
## забег под шторкой (RunManager.enter_complex_async): весь слой за один кадр —
## ~240 мс (профайлер 13.10), и строка загрузки на это время замирала.
##
## После каждого ожидания спрашивает [param keep_going]: вход могли перебить или
## сцену мира сменить, и тогда слой уже чужой — новый вход его снёс, а
## дописывать в него нельзя. false — слоя нет в графе или спавн оборван; что из
## двух, зовущий знает сам (он и решает, жив ли вход). Глубина слоя ставится
## только по завершении — до этого слой не считается загруженным.
##
## Порядок и содержимое те же, что у spawn: порция — только когда отдать кадр,
## а погасшие лампы и места комнат от кадров не зависят.
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
	# У коридора нет сцены: он собирается из тайлов кита по трассе плана.
	if node_data.role == RS_LevelNode.Role.CORRIDOR:
		_spawn_corridor(node_data, plan)
		return
	var entity := _instantiate_room(node_data)
	if entity == null:
		return
	rooms[node_data.id] = _spawn_room(node_data, entity, plan)


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
	navigation.clear()
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
	LayerFinds.remove_all(cache_finds)
	_shown.clear()
	var was_loaded := depth != NO_DEPTH
	depth = NO_DEPTH
	return was_loaded


## Показывает узлы слоя не дальше VISIBLE_HOPS рёбер от [param node_id] и
## прячет остальные. Портальные рёбра не в счёт: за ними другой слой, его в
## дереве нет, а соседний этаж за порталом виден только после перехода.
func reveal_around(node_id: StringName) -> void:
	var near := {node_id: 0}
	var queue: Array[StringName] = [node_id]
	while not queue.is_empty():
		var current: StringName = queue.pop_front()
		var hops: int = near[current]
		if hops >= VISIBLE_HOPS:
			continue
		var node_data := graph.get_node_data(current)
		if node_data == null:
			continue
		for conn: RS_LevelConnection in node_data.connections:
			if conn.is_portal() or near.has(conn.target_node_id):
				continue
			near[conn.target_node_id] = hops + 1
			queue.append(conn.target_node_id)

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


## Показан ли узел (для проверок и ShadowBudget-подобных потребителей).
func is_shown(node_id: StringName) -> bool:
	return _shown.get(node_id, true)


## Прячет содержимое комнаты, кроме того, что ходит: враг, вышедший из своей
## комнаты в погоню, живёт под её корнем, и спрятанный вместе с ней он стал бы
## невидимкой рядом с игроком. Прятать корень целиком поэтому нельзя.
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


## Застраивает ветку коридора кусками кита: на каждый её тайл плана — кусок под
## маску проёмов, повёрнутый на нужную четверть оборота, с торцами на сторонах,
## упёршихся в двери комнат (RS_LayerPlan.door_mask). Нет куска под маску (тупик)
## — тайл пропускается с ошибкой: раскладка таких не выдаёт, и если выдала, это
## надо видеть, а не залатывать молча.
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
		# Позиция ДО входа в дерево — как и у комнат (_spawn_room): иначе
		# коллизия тайла успеет зарегистрироваться в начале координат.
		tile.position = plan.embedding.cell_origin(cell)
		parent.add_child(tile)
		tiles.append(tile)
	corridor_tiles[node_data.id] = tiles
	cache_finds.append_array(LayerFinds.place_caches(node_data, plan, graph.run_seed))


## Погасла ли лампа тайла — от сида мира, слоя и клетки, своим ГСЧ, а не общим:
## тот же мир после загрузки гасит те же лампы, и ни порядок спавна, ни сама
## генерация от этого броска не зависят. Слой в ключе — потому что все слои
## раскладываются от одной клетки (0, 0), и без него погасшие лампы совпадали бы
## клетками на всех слоях.
func _is_lamp_dead(layer_depth: int, cell: Vector3i, chance: float) -> bool:
	if chance <= 0.0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([graph.run_seed, layer_depth, cell])
	return rng.randf() < chance


## Снимает лампы тайла, пока он не вошёл в дерево: погасшая лампа не должна ни
## светить, ни занимать ячейку теневого атласа (ShadowBudget считает лампы группы).
## Плафон остаётся на месте лампы тёмным — мёртвый светильник, а не дыра в потолке.
func _remove_lamps(tile: Node3D) -> void:
	for node in tile.find_children("*", "Light3D", true, false):
		if not node is LevelLight:
			continue
		var light := node as Node3D
		for child in light.get_children():
			if child is LampFixture:
				var fixture := child as LampFixture
				var placed := light.transform * fixture.transform
				# Владелец плафона и его деталей — корень сцены лампы, которая
				# сейчас уйдёт: без сброса Godot ругается на чужого владельца.
				for owned: Node in [fixture as Node] + fixture.find_children("*", "", true, false):
					owned.owner = null
				light.remove_child(fixture)
				light.get_parent().add_child(fixture)
				fixture.transform = placed
				fixture.go_dark()
		light.free()


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
	# Место и поворот ставим ДО add_entity: тот сам вносит узел в дерево, и комната должна
	# попасть туда сразу на своё место — иначе коллайдеры успевают
	# зарегистрироваться в начале координат и телепортируются следом.
	# Через Node: Entity наследует Node, и прямой каст Entity→Node3D анализатор
	# GDScript не пропускает.
	var spatial := entity as Node as Node3D
	if spatial:
		spatial.transform = plan.room_transform(node_data.id)

	# Стены и двери сборной комнаты — тоже до add_entity: двери должны попасть в
	# обход вложенных сущностей (_register_room_children) вместе с остальными.
	var shell := RS_RoomLayout.shell_of(entity)
	var assembled: Dictionary[Node3D, Vector4i] = {}
	if shell and spatial:
		if shell.walls:
			assembled = shell.walls.assemble(spatial, node_data.id, plan)
		else:
			push_error("LayerStreamer: у коробки '%s' нет кита стен" % node_data.room_scene_path)

	# Враги ростера — детьми комнаты до add_entity: тогда обход вложенных сущностей
	# (_register_room_children) подхватит их вместе с остальными, и снесёт их тот же
	# despawn, без отдельного учёта.
	_spawn_roster_enemies(entity, node_data)
	# Находки эссенции на маркерах комнаты — до add_entity, дочерними сущностями
	# (см. LayerFinds.place_in_room).
	LayerFinds.place_in_room(entity, node_data, graph.run_seed)

	ECS.world.add_entity(entity)

	var spawned := SpawnedRoom.new()
	spawned.node_id = node_data.id
	spawned.entity = entity
	spawned.children = _register_room_children(entity, node_data.id)
	# Слот — после регистрации, как и всё, что меняет состав компонентов живой
	# сущности. Нужен той же выборке дверей, что и у запечённых (_bind_doors).
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
		elif e.has_meta(ROSTER_ID_META):
			# Враг ростера несёт id своего маркера, и O_EnemyDeath передаст его
			# трупу: съеденный труп помечает id в сейве, и маркер больше не
			# разыгрывается (_spawn_roster_enemies).
			var origin := C_BodyOrigin.new()
			origin.body_id = e.get_meta(ROSTER_ID_META)
			e.add_component(origin)
	return children


## Ставит врагов ростера на маркеры [code]EnemySpawn*[/code] сцены комнаты. Кто
## встанет, решает RS_EnemyRoster.roll — функция сида, слоя, узла и маркера, —
## поэтому слой, собранный заново, возвращает тех же врагов на те же места.
## Маркер, чей враг уже съеден (труп поглощён, см. O_EnemyDeath), не разыгрывается.
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
		# Позиция — от комнаты, а не глобальная: комната ещё не в дереве.
		(enemy as Node as Node3D).transform = RS_EntityVisuals.transform_relative_to(node, room_entity)


## Стабильный id авторского тела: узел графа плюс путь узла внутри комнаты.
## Сцена тела своего id не знает и знать не может — один и тот же e_body.tscn
## стоит в разных комнатах, а сид одинаково восстанавливает их все.
func _body_id(node_id: StringName, room_entity: Entity, body: Node) -> StringName:
	return StringName("%s/%s" % [node_id, room_entity.get_path_to(body)])


## Штампует C_DoorPortal на двери комнаты (подмножество children с C_DoorSlot): за
## каждой дверью — ветка, которую план поставил на её грань
## (RS_LayerPlan.door_faces). По граням, а не по рёбрам: две двери комнаты
## законно ведут в одну ветку, и по id соседа их не различить. Порядок дверей
## поэтому ничего не решает — каждая привязывается сама, по своей грани. Дверь
## сборной комнаты грань уже знает; запечённая в сцену получает её по своей стене
## — сцена такой комнаты в одну клетку, и грань — это клетка комнаты и сторона.
## Остаточного принципа нет — рёбер в коридоры у комнаты ровно столько, сколько
## дверей; дверь без ветки значит, что план и сцена разошлись, и её честнее
## заварить с предупреждением, чем увести не туда.
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


## Раздаёт рёбра ПОРТАЛОВ порталам комнаты — между слоями и, если лестницы в
## ручках нет, между этажами слоя. Портальное ребро узнаётся по типу
## (RS_LevelConnection.is_portal): верхняя дверь лестницы тоже ведёт на другой
## этаж, но это дверь, и её ребро раздаёт _bind_doors. Портал без ребра
## «глушится» так же, как лишняя дверь: остаётся интерактивным, а на нажатие
## отвечает сообщением, что прохода нет.
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


## Запечатанная дверь: ребра под этот слот нет, идти некуда. Интеракцию НЕ
## выключаем: выключенную дверь S_InteractionDetector игнорирует — она не
## подсвечивается и молчит, и игрок не отличает «прохода нет» от бага. Вместо
## этого штампуем ПУСТОЙ C_DoorPortal (пустой target_node_id = «запечатан», см.
## C_DoorPortal): A_TravelThroughDoor по тому же признаку никуда не ведёт и
## отвечает на нажатие экранным сообщением.
func _seal_door(door: Entity) -> void:
	door.add_component(C_DoorPortal.new())  # target_node_id == &"" — прохода нет
