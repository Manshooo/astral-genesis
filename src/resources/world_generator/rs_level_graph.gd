## res://src/resources/world_generator/rs_level_graph.gd
## Граф забега: комнаты и ветки коридора по слоям и этажам, связи между ними. Строится из сида и ручек (RS_WorldGenConfig) детерминированно —
## сейв хранит сид и снимок ручек. @tool: генератор гоняется из вкладки «Генератор мира», не-tool ресурс там плейсхолдер. Вики: [[Цикл забега]].
@tool
class_name RS_LevelGraph
extends Resource

@export var nodes: Dictionary[StringName, RS_LevelNode]
@export var entry_node_id: StringName
@export var exit_node_ids: Array[StringName]

## Версия генератора. Сейв помнит, на какой начат забег (RS_WorldSave.generator_version), и забег с другой сбрасывается на вход (RunManager._run_gen_config):
## тот же сид на другом генераторе — другой комплекс. Поднимать при любой правке, меняющей мир на том же сиде (вики: «Версии генератора»). Веса пресетов в снимок не входят.
const GENERATOR_VERSION := 12

## Глубина -> план раскладки слоя. Считается при генерации: рёбра «дверь → ветка» граф берёт из раскладки. Не сохраняется — граф выводится из сида.
var _plans: Dictionary[int, RS_LayerPlan] = {}
## Сид, из которого построен граф — для того, что выводится при спавне (погасшие лампы коридора): версию генератора ради него не поднимать.
var run_seed: int = 0

## Комната, когда библиотека не дала ничего: узел остаётся заглушкой.
const PLACEHOLDER_ROOM_SCENE := "res://src/levels/procedural/rooms/test_room.tscn"
## Сцена хаба: генератор её не ставит (хаб — уникальная комната конфига), константа нужна инструментам.
const HUB_ROOM_SCENE := "res://src/levels/hub/hub.tscn"
## Ручки по умолчанию, если зовущий не передал.
const DEFAULT_CONFIG_PATH := "res://data/world_gen_config.tres"

## От самого глубокого к поверхности (0 — поверхность, 5 — дно); порядок обязателен — по нему идут броски общего rng и пары слоёв.
const DEPTHS := [5, 4, 3, 2, 1, 0]
## Глубина хаба — для инструментов; генератор её не читает, расхождение ловит dev/corridor_graph_check.
const HOME_DEPTH := 3


## Строит граф забега. [param library] — пресеты (null — все комнаты заглушки), [param config] — ручки (null — data/world_gen_config.tres).
func generate_run(
	level_seed: int, library: RS_RoomPresetLibrary = null, config: RS_WorldGenConfig = null
) -> RS_LevelGraph:
	if config == null:
		config = load(DEFAULT_CONFIG_PATH) as RS_WorldGenConfig
	return RS_LevelGraph.new()._generate(level_seed, library, config)


## Все сцены, которые generate_run может поставить на узел — для прогрева кэшей в фоне (RS_RoomLayout.warm_scene_cache). Здесь, потому что источники сцен знает только генерация.
static func scene_paths(library: RS_RoomPresetLibrary, config: RS_WorldGenConfig) -> Array[String]:
	var presets: Array[RS_RoomPreset] = []
	if library:
		presets.append_array(library.presets)
		presets.append(library.fallback)
		presets.append(library.hub)
	if config:
		presets.append(config.floor_stairs)
		for unique in config.unique_rooms:
			if unique:
				presets.append(unique.preset)
	var paths: Array[String] = [PLACEHOLDER_ROOM_SCENE]
	for preset in presets:
		if preset and preset.scene and not paths.has(preset.scene.resource_path):
			paths.append(preset.scene.resource_path)
	return paths


func get_node_data(node_id: StringName) -> RS_LevelNode:
	return nodes.get(node_id)


## Все узлы слоя (всех его этажей) — гранула стриминга: слой грузится целиком (LayerStreamer.spawn).
func get_nodes_by_depth(depth: int) -> Array[RS_LevelNode]:
	var result: Array[RS_LevelNode] = []
	for node in nodes.values():
		if node.depth == depth:
			result.append(node)
	return result


## План раскладки слоя depth — тот, по которому граф поставил рёбра. null — слоя нет.
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


# Генерация
# Порядок проходов: сначала решается, КАКАЯ комната в узле, потом ей раздаются рёбра — столько, сколько в её сцене дверей (заваренных дверей нет по построению).
#   1. комнаты по слоям и этажам; 2. уникальные комнаты (резерв узлов); 3. вертикаль (лестницы между этажами, порталы между слоями); 4. типы помещений;
#   5. подбор сцен, поворот и число дверей; 6. раскладка этажа (RS_CorridorPlanner) — из неё коридоры и рёбра. Шестой проход совместный: в какую ветку ведёт дверь, решает раскладка.


## Тег нужды в портале (см. RS_RoomPresetLibrary.PORTAL_TAG).
const PORTAL_TAG := &"vertical_hub"
const EXIT_TAG := &"level_exit"


func _generate(
	level_seed: int, library: RS_RoomPresetLibrary, config: RS_WorldGenConfig
) -> RS_LevelGraph:
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed
	run_seed = level_seed

	# depth -> Array этажей, этаж — Array[RS_LevelNode] комнат.
	var floors_by_depth: Dictionary = {}
	# depth -> следующий index_in_layer: коридоры встают в конец слоя.
	var next_index: Dictionary = {}
	for depth: int in DEPTHS:
		var floors: Array = []
		var index := 0
		var floor_count := rng.randi_range(config.floor_count_min, config.floor_count_max)
		# Поправка после броска, а не диапазоном: rng тратится одинаково, нетронутые слои остаются прежними.
		if _needs_second_floor(config, depth):
			floor_count = maxi(floor_count, 2)
		for f in floor_count:
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
		# Рёбра дверей — когда разложены все этажи: верхняя дверь лестницы ведёт в коридор этажа выше.
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


## Сколько сокетов сборной комнаты станут дверями — бросок в диапазоне пресета; 0 — двери в сцене. Из СВОЕГО потока на узел (сид + id), не общего rng:
## общий сдвинулся бы от первой же сборной комнаты, и правка пресета меняла бы чужие комнаты.
static func _roll_socket_doors(level_seed: int, node: RS_LevelNode, preset: RS_RoomPreset) -> int:
	if preset == null or preset.scene == null:
		return 0
	var sockets := RS_RoomLayout.socket_count_of_scene(preset.scene.resource_path)
	if sockets == 0:
		return 0
	var roll := RandomNumberGenerator.new()
	roll.seed = hash("%d/%s" % [level_seed, node.id])
	return clampi(roll.randi_range(preset.doors_min, preset.doors_max), 1, sockets)


## Поворот комнаты — четверть оборота из своего потока на узел, отдельного от дверей. Для всех комнат, включая уникальные: «передней» стены нет.
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


## Резервирует узлы под уникальные комнаты; возвращает их пресеты (подбор обычных их не предлагает). Каждый экземпляр тратит ТРИ броска rng при любом исходе:
## пропущенный сдвинул бы всё, что разыгрывается после.
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
			# Индекс, а не глубина из отрезка: вычеркнутая глубина не перекашивает шансы соседних; при одной допустимой (хаб, выход) бросок прежний.
			var depths := unique.allowed_depths()
			var depth_index := rng.randi_range(0, maxi(depths.size() - 1, 0))
			var entry_node: RS_LevelNode = null
			if unique.apart_from_entry and entry_node_id != &"":
				entry_node = get_node_data(entry_node_id)
			var pool: Array[RS_LevelNode] = []
			if not depths.is_empty():
				for floor_rooms: Array in floors_by_depth.get(depths[depth_index], []):
					for node: RS_LevelNode in floor_rooms:
						if reserved.has(node.id):
							continue
						if entry_node and node.depth == entry_node.depth and node.floor_index == entry_node.floor_index:
							continue
						pool.append(node)
			var pick := rng.randi_range(0, maxi(pool.size() - 1, 0))
			# Все глубины вычеркнуты — конфиг невалиден (RS_WorldGenConfig.validate()): лучше не поставить и сказать громко. Броски сделаны всё равно — поток rng остальных не должен зависеть.
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


## Нужен ли слою второй этаж: на нём может встать вход, а с ним комната, которой на этаж входа нельзя (RS_UniqueRoom.apart_from_entry). Решается до розыгрыша, по глубинам, где обе МОГУТ встать.
static func _needs_second_floor(config: RS_WorldGenConfig, depth: int) -> bool:
	var entry_here := false
	var apart_here := false
	for unique: RS_UniqueRoom in config.unique_rooms:
		if unique == null or not unique.covers_depth(depth):
			continue
		entry_here = entry_here or unique.entry
		apart_here = apart_here or unique.apart_from_entry
	return entry_here and apart_here


## Этажи слоя связывает портал, если лестницы в ручках нет (иначе — _place_floor_stairs); по одному на пару. ДО межслойных: иначе этаж отрезан от слоя.
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


## Этажи слоя связывает лестница (RS_WorldGenConfig.floor_stairs): по одной на пару соседних, комнатой нижнего. Верхняя дверь ведёт в коридор этажа выше — обычное ребро,
## которое раскладка ставит, дойдя до того этажа (RS_LayerPlan.pending_doors). Резервируется как уникальная комната.
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


## Соседние слои — через layer_connectors порталов. Пулы слоя делятся заранее на «вниз» и «вверх» (средний слой участвует в двух соединениях). Первый переход пары открыт всегда: ключей нет.
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
		var anchor := _arrival_floor(depth)
		for node in _prefer_floor(_shuffled_array(rng, free), anchor, config.transit_near_entry):
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


## Этаж, к которому жмутся переходы слоя (transit_near_entry): на слое хаба — этаж входа, на остальных — нижний (0): куда придёт переход сверху, до раскладки неизвестно.
func _arrival_floor(depth: int) -> int:
	var entry := get_node_data(entry_node_id)
	return entry.floor_index if entry != null and entry.depth == depth else 0


## Переставляет кандидатов ближе к этажу floor_index: ключ — смесь места в тасовке и расстояния по этажам, [param strength] 0 — как есть, 1 — по этажам. Броска нет, rng тратится одинаково.
static func _prefer_floor(candidates: Array, floor_index: int, strength: float) -> Array:
	if strength <= 0.0 or candidates.size() < 2:
		return candidates
	var span := 1.0
	for node: RS_LevelNode in candidates:
		span = maxf(span, absf(node.floor_index - floor_index))
	var keyed: Array = []
	for i in candidates.size():
		var node: RS_LevelNode = candidates[i]
		var key := lerpf(float(i) / candidates.size(), absf(node.floor_index - floor_index) / span, strength)
		keyed.append([key, i, node])
	# Номер в тасовке — второй ключ: sort_custom нестабилен.
	keyed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	var result: Array = []
	for entry: Array in keyed:
		result.append(entry[2])
	return result


## Комнаты этажа, которым ещё можно дать портал: не уникальные и без вертикального ребра (портал в комнате один, LayerStreamer._bind_portals).
func _free_for_portal(
	floor_rooms: Array, reserved: Dictionary[StringName, RS_UniqueRoom]
) -> Array[RS_LevelNode]:
	var free: Array[RS_LevelNode] = []
	for node: RS_LevelNode in floor_rooms:
		if not reserved.has(node.id) and not node.has_tag(PORTAL_TAG):
			free.append(node)
	return free


## Вертикальное ребро в обе стороны; depth_delta со стороны a (−1 = a глубже b; 0 — между этажами слоя). Оба конца получают тег портала.
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


## Раскладывает этаж в plan и записывает в граф коридоры (по узлу на отрезок сети между развилками); их число решает сеть, не бросок. Рёбра дверей и стыков ставит _generate,
## когда разложены все этажи. Раскладка — из своего потока этажа (сид + слой + этаж). Возвращает следующий свободный index_in_layer.
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
