## res://src/resources/world_generator/rs_level_graph.gd
## Граф забега: комнаты и ветки коридора по слоям и этажам, связи между ними.
## Строится из сида и ручек генерации (RS_WorldGenConfig) детерминированно —
## сейв хранит сид и снимок ручек, а не комплекс.
##
## @tool — генератор гоняется из редакторской вкладки «Генератор мира» (превью слоя
## и прогон сидов), а не-tool ресурс там доступен только плейсхолдером.
@tool
class_name RS_LevelGraph
extends Resource

@export var nodes: Dictionary[StringName, RS_LevelNode]
@export var entry_node_id: StringName
@export var exit_node_ids: Array[StringName]

## Версия генератора. Сейв помнит, на какой начат забег (RS_WorldSave.
## generator_version), и забег с другой сбрасывается на вход
## (RunManager._run_gen_config): мир выводится из сида, и тот же сид на другом
## генераторе — другой комплекс, где сохранённый узел и посещённые комнаты
## легли бы на чужие места. Поднимать при любой правке, меняющей мир на том же
## сиде. 1 — клетка 8 м, повороты, раскладка сетью (карточка «Сетка уровня»);
## 2 — коридор отдельным узлом (карточка «Коридор — отдельный узел»); 3 — вес
## default_room сравнян с cross_a (карточка «Баг — default_room почти не
## выпадает в забеге»); 4 — комнаты этажа разбросаны, а не стоят решёткой, и
## этажи слоя связаны лестницей, а не порталами (карточка «Хаос раскладки
## этажа»). Все — v0.7.0. Веса пресетов в снимок ручек
## не входят, поэтому их правка меняет мир и начатого забега — отсюда и подъём
## версии.
const GENERATOR_VERSION := 4

## Глубина -> план раскладки слоя. Считается при генерации, а не по запросу:
## рёбра «дверь → ветка» граф берёт из раскладки, и план — её же результат, а не
## пересчёт (см. RS_LayerPlan). Не сохраняется: граф выводится из сида заново.
var _plans: Dictionary[int, RS_LayerPlan] = {}

## Комната на случай, когда библиотека не дала ничего (нет библиотеки, нет
## кандидата): генерация не падает, а узел честно остаётся заглушкой.
const PLACEHOLDER_ROOM_SCENE := "res://src/levels/procedural/rooms/test_room.tscn"
## Сцена хаба. Генератор её не ставит — хаб приходит уникальной комнатой из
## data/world_gen_config.tres; константа нужна инструментам (Room Wizard), чтобы
## узнать хаб по пути сцены.
const HUB_ROOM_SCENE := "res://src/levels/hub/hub.tscn"
## Ручки по умолчанию, если зовущий их не передал (инструменты, проверки).
const DEFAULT_CONFIG_PATH := "res://data/world_gen_config.tres"

## От самого глубокого к поверхности (поверхность — 0).
const DEPTHS := [4, 3, 2, 1, 0]
## Глубина хаба — для инструментов и отладки (слой по умолчанию во вкладке
## «Генератор мира»). Генератор её не читает: хаб ставит уникальная комната
## конфига, и расхождение с ней ловит dev/corridor_graph_check.
const HOME_DEPTH := 3


## Строит граф забега. [param library] — пресеты комнат (null — все комнаты
## заглушки), [param config] — ручки (null — data/world_gen_config.tres).
func generate_run(
	level_seed: int, library: RS_RoomPresetLibrary = null, config: RS_WorldGenConfig = null
) -> RS_LevelGraph:
	if config == null:
		config = load(DEFAULT_CONFIG_PATH) as RS_WorldGenConfig
	return RS_LevelGraph.new()._generate(level_seed, library, config)


func get_node_data(node_id: StringName) -> RS_LevelNode:
	return nodes.get(node_id)


## Все узлы конкретного слоя (across всех его этажей). Это гранула стриминга:
## RunManager грузит слой ЦЕЛИКОМ (все комнаты одновременно в дереве сцены) и
## сносит его только при смене глубины — см. LayerStreamer.spawn.
func get_nodes_by_depth(depth: int) -> Array[RS_LevelNode]:
	var result: Array[RS_LevelNode] = []
	for node in nodes.values():
		if node.depth == depth:
			result.append(node)
	return result


## План раскладки слоя [param depth] — тот, по которому граф поставил рёбра в
## коридоры. Один на игру, карту и инструменты. null — такого слоя нет.
func layer_plan(depth: int) -> RS_LayerPlan:
	return _plans.get(depth)


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


# ---------------------------------------------------------------------------
# Генерация
#
# Порядок проходов — из карточки «Рефакторинг генератора мира», и он обратный
# тому, что был до коридоров (степень узла → комната под неё): сначала
# решается, КАКАЯ комната стоит в узле, и только потом ей раздаются рёбра —
# ровно столько, сколько в её сцене дверей. Отсюда заваренных
# дверей нет по построению, а «гарантированный тупик» хаба перестаёт быть
# особым случаем: у его сцены одна дверь.
#
#   1. комнаты по слоям и этажам (узлы без рёбер);
#   2. уникальные комнаты — резерв узлов под заранее известные сцены;
#   3. вертикаль — лестницы между этажами слоя (или порталы, если лестницы в
#      ручках нет) и порталы между слоями;
#   4. типы помещений;
#   5. подбор сцен остальным комнатам, их поворот и число дверей;
#   6. раскладка этажа (RS_CorridorPlanner) — и из неё коридоры и рёбра
#      «дверь → коридор», «коридор → коридор».
#
# Шестой проход — совместный: в какую ветку ведёт дверь, решает раскладка, а граф
# записывает то, что она построила. Наоборот, как было до п. 7 карточки «Сетка
# уровня», укладки могло не быть вовсе, и её выкупали правилом «все двери комнаты
# в одну ветку» — ценой коридора вокруг комнаты.
# ---------------------------------------------------------------------------


## Тег, которым узел объявляет нужду в портале (см. RS_RoomPresetLibrary.PORTAL_TAG).
const PORTAL_TAG := &"vertical_hub"
const EXIT_TAG := &"level_exit"


func _generate(
	level_seed: int, library: RS_RoomPresetLibrary, config: RS_WorldGenConfig
) -> RS_LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed

	# depth -> Array этажей, этаж — Array[RS_LevelNode] комнат.
	var floors_by_depth: Dictionary = {}
	# depth -> следующий index_in_layer: коридоры встают в конец слоя после комнат.
	var next_index: Dictionary = {}
	for depth: int in DEPTHS:
		var floors: Array = []
		var index := 0
		for f in rng.randi_range(config.floor_count_min, config.floor_count_max):
			var floor_rooms: Array[RS_LevelNode] = []
			for i in config.rooms_per_floor:
				var id := StringName("L%d_F%d_room_%d" % [depth, f, i])
				floor_rooms.append(_add_node(id, depth, f, index, RS_LevelNode.Role.ROOM))
				index += 1
			floors.append(floor_rooms)
		floors_by_depth[depth] = floors
		next_index[depth] = index

	var reserved: Dictionary[StringName, RS_UniqueRoom] = {}
	var unique_presets := _place_unique_rooms(rng, config, floors_by_depth, reserved)
	if entry_node_id == &"":
		push_error("RS_LevelGraph: вход не размещён — проверьте уникальные комнаты в конфиге")

	if config.floor_stairs and config.floor_stairs.scene:
		_place_floor_stairs(rng, config, floors_by_depth, reserved)
	else:
		_connect_floors_vertically(rng, floors_by_depth, reserved)
	_connect_layers_vertically(rng, config, floors_by_depth, reserved)

	var catalog := library.type_catalog if library else null
	if catalog:
		for node: RS_LevelNode in nodes.values():
			if not reserved.has(node.id):
				node.room_type = catalog.pick_for_depth(node.depth, rng)

	for node: RS_LevelNode in nodes.values():
		node.turns = _roll_turns(level_seed, node)
		if reserved.has(node.id):
			node.socket_doors = _roll_socket_doors(level_seed, node, reserved[node.id].preset)
			continue
		var preset := library.select_preset(node, rng, unique_presets) if library else null
		node.room_scene_path = preset.scene.resource_path if preset and preset.scene else PLACEHOLDER_ROOM_SCENE
		node.room_type = preset.room_type if preset else &""
		node.socket_doors = _roll_socket_doors(level_seed, node, preset)

	for depth: int in DEPTHS:
		var plan := RS_LayerPlan.new()
		var floors: Array = floors_by_depth[depth]
		for f in floors.size():
			next_index[depth] = _lay_out_floor(level_seed, config, plan, floors[f], depth, f, next_index[depth])
		# Рёбра дверей — когда разложены все этажи: верхняя дверь лестницы ведёт в
		# коридор этажа выше, и он появляется, только когда очередь доходит до того
		# этажа. Порядок прежний: этажи по очереди, у комнаты — двери по граням.
		for floor_rooms: Array in floors:
			for room: RS_LevelNode in floor_rooms:
				var faces: Dictionary = plan.door_faces.get(room.id, {})
				for face: Vector4i in faces:
					_link_nodes(room, nodes[faces[face]], RS_LevelConnection.Type.CORRIDOR)
		for face: Vector4i in plan.pending_doors:
			plan.routing_failures.append(
				"%s: дверь на уровне %d, а этажа там нет" % [plan.pending_doors[face], face.y]
			)
		for joint: Array in plan.branch_joints():
			_link_nodes(nodes[joint[0]], nodes[joint[1]], RS_LevelConnection.Type.CORRIDOR)
		_plans[depth] = plan

	return self


## Сколько сокетов комнаты, собранной по маске (C_RoomShell), станут дверями —
## бросок в диапазоне пресета; 0 — у комнаты двери в сцене.
##
## Бросок из СВОЕГО потока на узел (сид + id), а не из общего rng. Общий поток
## сдвинулся бы от первой же сборной комнаты, и всё, что разыгрывается после неё,
## стало бы другим: правка одного пресета меняла бы чужие комнаты, а миры, где
## сборных комнат нет, — вообще все. Свой поток даёт то же, ради чего общий
## тратится одинаково при любом исходе: остальной граф от этого броска не зависит.
static func _roll_socket_doors(level_seed: int, node: RS_LevelNode, preset: RS_RoomPreset) -> int:
	if preset == null or preset.scene == null:
		return 0
	var sockets := RS_RoomLayout.socket_count_of_scene(preset.scene.resource_path)
	if sockets == 0:
		return 0
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%d/%s" % [level_seed, node.id])
	return clampi(roll.randi_range(preset.doors_min, preset.doors_max), 1, sockets)


## Поворот комнаты — четверть оборота, бросок из своего потока на узел, по той же
## причине, что и число дверей (_roll_socket_doors): остальной граф от него не
## зависит. Поток отдельный и от дверей — иначе поворот зависел бы от того,
## бросались ли двери. Все комнаты, включая уникальные: «передней» стены у
## комнат нет (решение 24.09 карточки «Сетка уровня»).
static func _roll_turns(level_seed: int, node: RS_LevelNode) -> int:
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%d/%s/turns" % [level_seed, node.id])
	return roll.randi_range(0, SquareGridTopology.SIDE_COUNT - 1)


func _add_node(
	id: StringName, depth: int, floor_index: int, index_in_layer: int, role: RS_LevelNode.Role
) -> RS_LevelNode:
	var node := RS_LevelNode.new()
	node.id = id
	node.depth = depth
	node.floor_index = floor_index
	node.index_in_layer = index_in_layer
	node.role = role
	node.room_scene_path = PLACEHOLDER_ROOM_SCENE if role == RS_LevelNode.Role.ROOM else ""
	nodes[id] = node
	return node


## Резервирует узлы под уникальные комнаты. Возвращает их пресеты — подбор
## обычных комнат их не предлагает, иначе выход выпадал бы вторым финишем.
##
## Каждый экземпляр тратит ТРИ броска rng при любом исходе — шанс, глубина,
## узел: пропущенный бросок сдвинул бы всё, что разыгрывается после, и то, что
## комната Архитектора в этот раз не выпала, перетасовало бы весь комплекс.
func _place_unique_rooms(
	rng: RandomNumberGenerator,
	config: RS_WorldGenConfig,
	floors_by_depth: Dictionary,
	reserved: Dictionary[StringName, RS_UniqueRoom],
) -> Array[RS_RoomPreset]:
	var presets: Array[RS_RoomPreset] = []
	for unique: RS_UniqueRoom in config.unique_rooms:
		if unique == null or unique.preset == null or unique.preset.scene == null:
			continue
		presets.append(unique.preset)
		for c in unique.count:
			var roll := rng.randf()
			# Индекс, а не глубина из отрезка: так вычеркнутая глубина не
			# перекашивает шансы соседних. При одной допустимой глубине (хаб,
			# выход) бросок тот же randi_range(a, a), что и до списка вычеркнутых,
			# — прежние сиды дают прежний комплекс.
			var depths := unique.allowed_depths()
			var depth_index := rng.randi_range(0, maxi(depths.size() - 1, 0))
			var pool: Array[RS_LevelNode] = []
			if not depths.is_empty():
				for floor_rooms: Array in floors_by_depth.get(depths[depth_index], []):
					for node: RS_LevelNode in floor_rooms:
						if not reserved.has(node.id):
							pool.append(node)
			var pick := rng.randi_range(0, maxi(pool.size() - 1, 0))
			# Все глубины вычеркнуты — конфиг невалиден (RS_WorldGenConfig.validate()).
			# Раньше комната молча вставала на depth_min — то есть ровно туда, куда
			# дизайнер её не пускал. Лучше не поставить и сказать громко. Броски выше
			# сделаны всё равно: поток rng у остальных записей не должен зависеть от
			# того, сломана эта или нет.
			if depths.is_empty():
				push_error(
					"RS_LevelGraph: у уникальной комнаты «%s» вычеркнуты все глубины %d..%d — не ставлю"
					% [unique.preset.resource_path.get_file(), unique.depth_min, unique.depth_max]
				)
				continue
			# randf() включает единицу: «шанс 1.0» обязан размещать всегда.
			var placed := unique.chance >= 1.0 or roll < unique.chance
			if not placed or pool.is_empty():
				continue
			var node: RS_LevelNode = pool[pick]
			reserved[node.id] = unique
			node.room_scene_path = unique.preset.scene.resource_path
			node.room_type = unique.preset.room_type
			node.door_teleports = unique.door_teleports
			if unique.entry:
				entry_node_id = node.id
			if unique.exit:
				node.add_tag_unique(EXIT_TAG)
				exit_node_ids.append(node.id)
	return presets


## Этажи одного слоя связывает портал, если лестницы в ручках нет (иначе —
## _place_floor_stairs): ходить по коридорам можно только в
## плоскости этажа. Этажи идут по порядку, на каждую пару по одному переходу.
## Проходится ДО межслойных: без него этаж отрезан от слоя, а межслойных
## переходов хватит и на остатке (их бывает меньше заявленного, но не ноль).
func _connect_floors_vertically(
	rng: RandomNumberGenerator,
	floors_by_depth: Dictionary,
	reserved: Dictionary[StringName, RS_UniqueRoom],
) -> void:
	for depth: int in DEPTHS:
		var floors: Array = floors_by_depth[depth]
		for f in range(floors.size() - 1):
			var lower := _free_for_portal(floors[f], reserved)
			var upper := _free_for_portal(floors[f + 1], reserved)
			if lower.is_empty() or upper.is_empty():
				push_error("RS_LevelGraph: этаж %d слоя %d не с чем связать порталом" % [f + 1, depth])
				continue
			var a: RS_LevelNode = lower[rng.randi_range(0, lower.size() - 1)]
			var b: RS_LevelNode = upper[rng.randi_range(0, upper.size() - 1)]
			_link_vertical(a, b, RS_LevelConnection.Type.STAIRWELL, &"", 0)


## Этажи слоя связывает лестница (RS_WorldGenConfig.floor_stairs): по одной на
## пару соседних этажей, комнатой нижнего из них. Её коробка в два уровня, и
## верхняя дверь ведёт в коридор этажа выше — это обычное коридорное ребро,
## которое раскладка ставит, дойдя до того этажа (RS_LayerPlan.pending_doors).
## Порталы между этажами ею заменены: слой стоит в дереве целиком, этажи — друг
## над другом, и подняться можно ногами, а не переносом.
##
## Лестница резервируется как уникальная комната — сцена задана заранее, подбор
## и порталы слоёв её не трогают.
func _place_floor_stairs(
	rng: RandomNumberGenerator,
	config: RS_WorldGenConfig,
	floors_by_depth: Dictionary,
	reserved: Dictionary[StringName, RS_UniqueRoom],
) -> void:
	var stairs := RS_UniqueRoom.new()
	stairs.preset = config.floor_stairs
	for depth: int in DEPTHS:
		var floors: Array = floors_by_depth[depth]
		for f in range(floors.size() - 1):
			var free := _free_for_portal(floors[f], reserved)
			if free.is_empty():
				push_error("RS_LevelGraph: этаж %d слоя %d некуда поставить лестницу" % [f, depth])
				continue
			var node: RS_LevelNode = free[rng.randi_range(0, free.size() - 1)]
			reserved[node.id] = stairs
			node.room_scene_path = stairs.preset.scene.resource_path
			node.room_type = stairs.preset.room_type


## Соседние слои — через layer_connectors порталов. Пулы каждого слоя делятся
## заранее на «вниз» и «вверх»: средний слой участвует в двух соединениях, и без
## раздела первое съело бы кандидатов второго. Первый переход каждой пары открыт
## всегда — ключей в игре нет, и запертые наглухо пары делали бы забег
## непроходимым.
func _connect_layers_vertically(
	rng: RandomNumberGenerator,
	config: RS_WorldGenConfig,
	floors_by_depth: Dictionary,
	reserved: Dictionary[StringName, RS_UniqueRoom],
) -> void:
	# depth -> {"down": связь со слоем глубже, "up": связь со слоем ближе к поверхности}
	var pools: Dictionary = {}
	for depth: int in DEPTHS:
		var free: Array[RS_LevelNode] = []
		for floor_rooms: Array in floors_by_depth[depth]:
			free.append_array(_free_for_portal(floor_rooms, reserved))
		var down: Array = []
		var up: Array = []
		var needs_down: bool = depth != DEPTHS[0]  # глубже самого глубокого некуда
		var needs_up: bool = depth != DEPTHS[DEPTHS.size() - 1]  # выше поверхности некуда
		var prefer_down := true
		for node in _shuffled_array(rng, free):
			var take_down: bool = needs_down and down.size() < config.layer_connectors
			var take_up: bool = needs_up and up.size() < config.layer_connectors
			if take_down and (prefer_down or not take_up):
				down.append(node)
			elif take_up:
				up.append(node)
			prefer_down = not prefer_down
		pools[depth] = {"down": down, "up": up}

	for i in range(DEPTHS.size() - 1):
		var deeper: int = DEPTHS[i]
		var shallower: int = DEPTHS[i + 1]
		var from: Array = pools[deeper]["up"]
		var to: Array = pools[shallower]["down"]
		var count := mini(config.layer_connectors, mini(from.size(), to.size()))
		if count == 0:
			push_error("RS_LevelGraph: слои %d и %d нечем связать" % [deeper, shallower])
		for c in count:
			var type := (
				RS_LevelConnection.Type.ELEVATOR if rng.randf() > 0.5 else RS_LevelConnection.Type.STAIRWELL
			)
			var lock_roll := rng.randf()
			var locked := c > 0 and lock_roll < config.layer_lock_chance
			_link_vertical(from[c], to[c], type, &"level_access_key" if locked else &"", -1)


## Комнаты этажа, которым ещё можно дать портал: не уникальные (их сцена задана
## и портала в ней может не быть) и без вертикального ребра — портал в комнате
## ровно один (LayerStreamer._bind_portals).
func _free_for_portal(
	floor_rooms: Array, reserved: Dictionary[StringName, RS_UniqueRoom]
) -> Array[RS_LevelNode]:
	var free: Array[RS_LevelNode] = []
	for node: RS_LevelNode in floor_rooms:
		if not reserved.has(node.id) and not node.has_tag(PORTAL_TAG):
			free.append(node)
	return free


## Вертикальное ребро в обе стороны. [param depth_delta] — со стороны [param a]:
## −1 = a глубже b; 0 = переход между этажами одного слоя. Оба конца получают
## тег портала — по нему подбор даст им комнату с порталом.
func _link_vertical(
	a: RS_LevelNode, b: RS_LevelNode, type: RS_LevelConnection.Type, locked_by: StringName, depth_delta: int
) -> void:
	a.add_tag_unique(PORTAL_TAG)
	b.add_tag_unique(PORTAL_TAG)
	var down := RS_LevelConnection.new()
	down.target_node_id = b.id
	down.type = type
	down.locked_by = locked_by
	down.depth_delta = depth_delta
	a.connections.append(down)
	var up := RS_LevelConnection.new()
	up.target_node_id = a.id
	up.type = type
	up.locked_by = locked_by
	up.depth_delta = -depth_delta
	b.connections.append(up)


## Раскладывает этаж в [param plan] и записывает в граф то, что раскладка
## построила: коридоры — по узлу на отрезок сети между развилками (карточка
## «Коридор — отдельный узел»). Рёбра дверей и стыков коридоров ставит
## _generate, когда разложены все этажи слоя: верхняя дверь лестницы смотрит в
## коридор этажа выше, которого ещё нет.
## Возвращает следующий свободный index_in_layer.
##
## Сколько на этаже коридоров, решает сеть, а не бросок: раньше граф бросал число
## веток и раскладка резала сеть на столько кусков, и в одну ветку попадали
## коридоры с развилками — узлом был не коридор, а их связка. Раскладка — из
## своего потока этажа (сид + слой + этаж): иначе её правка сдвигала бы всё, что
## разыгрывается после.
func _lay_out_floor(
	level_seed: int,
	config: RS_WorldGenConfig,
	plan: RS_LayerPlan,
	floor_rooms: Array,
	depth: int,
	floor_index: int,
	index: int,
) -> int:
	var rooms: Array[RS_LevelNode] = []
	for node: RS_LevelNode in floor_rooms:
		rooms.append(node)
		if node.door_count() == 0:
			push_warning("RS_LevelGraph: у комнаты '%s' нет дверей — она недостижима" % node.id)

	var layout := RandomNumberGenerator.new()
	layout.seed = hash("%d/L%d_F%d/layout" % [level_seed, depth, floor_index])
	var prefix := "L%d_F%d_corridor_" % [depth, floor_index]
	for id in RS_CorridorPlanner.plan_floor(plan, rooms, prefix, floor_index, config, layout):
		_add_node(id, depth, floor_index, index, RS_LevelNode.Role.CORRIDOR)
		index += 1
	return index
