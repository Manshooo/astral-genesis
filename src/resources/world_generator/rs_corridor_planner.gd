## res://src/resources/world_generator/rs_corridor_planner.gd
## Коридорная раскладка этажа: комнаты вразброс, сеть коридоров — дерево по клеткам, связывающее все двери этажа, и петли с тупиками
## поверх. Здесь решается, какие в сети коридоры и куда ведёт каждая дверь: граф берёт эти узлы и рёбра у раскладки
## (RS_LevelGraph._lay_out_floor), а не диктует ей. Работает только в клетках и сторонах топологии; квадратна лишь расстановка
## комнат (прямоугольные footprint'ы). Случайность — только из переданного rng, своего потока этажа (общий поток сдвигался бы).
## Вики: [[Цикл забега]] (раскладка этажа); замеры решений — карточки «Сетка уровня» и «Хаос раскладки этажа».
@tool
class_name RS_CorridorPlanner
extends RefCounted

## Запас клеток вокруг комнат этажа, по которому может пройти сеть.
const ROUTE_MARGIN := 1
## Предел расширения запаса, если трасса не нашлась: дальше её уже заперли.
const MAX_ROUTE_MARGIN := 7
## Цена поворота сверх шага (без неё первый же прогон дал 43 % поворотов).
const TURN_COST := 3
## Цена прохода сквозь комнату от двери к двери в _distances: иначе сеть, разорванная комнатами, считалась бы несвязной.
const ROOM_HOP := 2
## Случайных точек на комнату при разбросе: из годных выбор взвешен шумом, при одной шум ничего не решал бы.
const SCATTER_TRIES := 24
## Частота шума плотности в клетках: пятно ~12 клеток — одно-два сгущения на этаж.
const NOISE_FREQUENCY := 0.08
## Насколько шум тянет комнаты в сгущения: вес точки — шум в этой степени.
const NOISE_SHARPNESS := 3.0
## Предел вытянутости области этажа.
const MAX_ASPECT := 2.0
## Сколько раз ствол сети ищет обход обволакиваемой комнаты (_route_around).
const ENVELOP_RETRIES := 3
## Петля, срезающая по сети меньше этого, — обход пары клеток, а не другой путь.
const MIN_LOOP_GAIN := 6
## Тупик — отросток не длиннее этого.
const DEAD_END_LENGTH := 2

var _plan: RS_LayerPlan
var _topology: GridTopology
var _level := 0
## Клетка комнаты -> комната.
var _room_at: Dictionary[Vector3i, StringName] = {}
## Комната -> грани её дверей.
var _doors: Dictionary[StringName, Array] = {}
## Клетка перед дверью -> чья дверь.
var _front_room: Dictionary[Vector3i, StringName] = {}
## Комнаты этого этажа: раскладка вправе убрать им запасную дверь; верх лестницы ниже не входит — его дверь единственная.
var _rooms: Dictionary[StringName, RS_LevelNode] = {}
## Тайл сети -> соседние тайлы, связанные проёмом.
var _links: Dictionary[Vector3i, Array] = {}
## Тайл -> номер коридора; до разреза (_segment) вся сеть — нулевой.
var _owner: Dictionary[Vector3i, int] = {}
## Клетки перед дверями — концы, которые сеть обязана связать.
var _terminals: Array[Vector3i] = []
var _dead_ends: Array[Vector3i] = []
## Где ищутся петли и тупики: комнаты этажа с сетью и запасом.
var _area := Rect2i()
## Центр комнат этажа в клетках — к нему смотрят двери.
var _center := Vector2.ZERO


func _init(plan: RS_LayerPlan, level: int) -> void:
	_plan = plan
	_topology = plan.topology
	_level = level


## Раскладывает этаж floor_index в plan: комнаты, сеть, двери, петли, тупики, коридоры. Возвращает имена коридоров ([param id_prefix] + номер).
static func plan_floor(
	plan: RS_LayerPlan,
	rooms: Array[RS_LevelNode],
	id_prefix: String,
	floor_index: int,
	config: RS_WorldGenConfig,
	rng: RandomNumberGenerator,
) -> Array[StringName]:
	var planner := RS_CorridorPlanner.new(plan, floor_index)
	planner._place_rooms(rooms, config.room_gap, config.room_density, rng)
	for room in rooms:
		planner._rooms[room.id] = room
	for room in rooms:
		planner._choose_doors(room)
	planner._adopt_pending()
	planner._grow_network()
	planner._join_spare_doors()
	planner._add_loops(config.corridor_loops)
	planner._add_dead_ends(config.dead_ends, rng)
	var ids: Array[StringName] = []
	for k in planner._segment():
		ids.append(StringName("%s%d" % [id_prefix, k]))
	planner._write(ids)
	return ids


# Комнаты и двери


## Комнаты разбросаны по области: каждая в случайную точку с улицей в gap клеток, из годных чаще выигрывают места с шумом плотности — так
## комнаты сбиваются в кучки с пустырями (решётка до 29.09 давала однотипные этажи). Цена — длина коридоров (6.3 тайла на комнату против 4.4 при
## density 0.65). Порядок перетасован: хаб и выход решает сид этажа. Клетка комнаты — угловая клетка footprint в осях мира. Площадь области —
## сумма footprint'ов с улицами / density; упёрлись в край — область растёт на клетку.
func _place_rooms(rooms: Array[RS_LevelNode], gap: int, density: float, rng: RandomNumberGenerator) -> void:
	var sizes: Dictionary[StringName, Vector3i] = {}
	var budget := 0
	for room in rooms:
		var size := RS_RoomLayout.footprint_of_scene(room.room_scene_path)
		sizes[room.id] = Vector3i(size.z, size.y, size.x) if room.turns % 2 else size
		budget += (sizes[room.id].x + gap) * (sizes[room.id].z + gap)
	var order := rooms.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: RS_LevelNode = order[i]
		order[i] = order[j]
		order[j] = swap

	# Вытянутость области — тоже бросок, иначе все этажи одной формы.
	var aspect := rng.randf_range(1.0 / MAX_ASPECT, MAX_ASPECT)
	var side := sqrt(budget / clampf(density, 0.05, 1.0))
	var area := Rect2i(0, 0, maxi(ceili(side * sqrt(aspect)), 1), maxi(ceili(side / sqrt(aspect)), 1))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = NOISE_FREQUENCY

	var sum := Vector2.ZERO
	for room: RS_LevelNode in order:
		var size: Vector3i = sizes[room.id]
		var anchor := _scatter_anchor(size, gap, area, noise, rng)
		while anchor == Vector3i.MAX:
			area = area.grow_individual(0, 0, 1, 1)
			anchor = _scatter_anchor(size, gap, area, noise, rng)
		_put(room, anchor, size)
		sum += Vector2(anchor.x + (size.x - 1) * 0.5, anchor.z + (size.z - 1) * 0.5)
	_center = sum / maxi(order.size(), 1)


## Угловая клетка под footprint size: SCATTER_TRIES случайных точек, из годных — взвешенно по шуму. Vector3i.MAX — годных нет.
func _scatter_anchor(
	size: Vector3i, gap: int, area: Rect2i, noise: FastNoiseLite, rng: RandomNumberGenerator
) -> Vector3i:
	var fits: Array[Vector3i] = []
	var weights: Array[float] = []
	for t in SCATTER_TRIES:
		# Бросок тратится при любом исходе: иначе число бросков зависело бы от занятости точек.
		var anchor := Vector3i(
			rng.randi_range(area.position.x, maxi(area.end.x - size.x, area.position.x)),
			_level,
			rng.randi_range(area.position.y, maxi(area.end.y - size.z, area.position.y)),
		)
		if not _fits(anchor, size, gap, area):
			continue
		var centre := Vector2(anchor.x + size.x * 0.5, anchor.z + size.z * 0.5)
		fits.append(anchor)
		weights.append(pow((noise.get_noise_2dv(centre) + 1.0) * 0.5, NOISE_SHARPNESS))
	if fits.is_empty():
		return Vector3i.MAX
	if WeightedPick.total(weights) <= 0.0:
		return fits[0]
	return fits[WeightedPick.index(weights, rng.randf())]


## Встаёт ли footprint так, чтобы до любой занятой клетки плана на его уровнях оставалось не меньше gap (в том числе верх высокой комнаты этажа ниже).
func _fits(anchor: Vector3i, size: Vector3i, gap: int, area: Rect2i) -> bool:
	if anchor.x + size.x > area.end.x or anchor.z + size.z > area.end.y:
		return false
	var around := anchor - Vector3i(gap, 0, gap)
	for cell in SquareGridTopology.box(around, size + Vector3i(gap * 2, 0, gap * 2)):
		if _plan.node_by_cell.has(cell):
			return false
	return true


## Ставит комнату в план: угловая клетка, footprint, поворот и клетки на всех уровнях (иначе node_at не узнал бы комнату под потолком зала).
func _put(room: RS_LevelNode, anchor: Vector3i, size: Vector3i) -> void:
	_plan.cells[room.id] = anchor
	_plan.footprints[room.id] = size
	_plan.turns[room.id] = room.turns
	# Комната без дверей тоже ключ: по ключам door_faces метрики считают комнаты.
	_plan.door_faces[room.id] = {}
	for cell in SquareGridTopology.box(anchor, size):
		if _plan.node_by_cell.has(cell):
			_plan.routing_failures.append("%s: клетка %s уже занята %s" % [room.id, cell, _plan.node_by_cell[cell]])
		_plan.node_by_cell[cell] = room.id
		_room_at[cell] = room.id


## Грани под двери комнаты: у комнаты с дверями в сцене — их стороны, повёрнутые вместе с комнатой; у собранной по сокетам —
## RS_LevelNode.socket_doors сокетов (_pick_sockets) из объявленных коробкой, иначе из граней нижнего уровня.
## Дверь выше этажа комнаты (верх лестницы) ждёт в плане раскладку своего этажа (_adopt_pending).
func _choose_doors(room: RS_LevelNode) -> void:
	var anchor: Vector3i = _plan.cells[room.id]
	var faces: Array[Vector4i] = []
	if room.socket_doors == 0:
		for side: int in RS_RoomLayout.door_sides_of_scene(room.room_scene_path):
			faces.append(GridTopology.face(anchor, _topology.rotate_side(anchor, side, -room.turns)))
	else:
		var shell := RS_RoomLayout.shell_of_scene(room.room_scene_path)
		var sockets := _topology.perimeter(_plan.room_cells(room.id))
		if shell and not shell.door_sockets.is_empty():
			sockets = RS_RoomLayout.sockets_in_plan(room.room_scene_path, room.turns, anchor)
		faces = _pick_sockets(room.id, sockets, room.socket_doors)
	_doors[room.id] = []
	for face in faces:
		if face.y != _level:
			_plan.pending_doors[face] = room.id
			continue
		_add_door(room.id, face)


func _add_door(room: StringName, face: Vector4i) -> void:
	_doors[room].append(face)
	_terminals.append(_front(face))
	_front_room[_front(face)] = room


## Забирает из плана двери комнат этажа ниже, чей уровень — этот (верх лестницы): они становятся концами сети. Клетки такой комнаты считаются комнатой, иначе петля обволокла бы верх.
func _adopt_pending() -> void:
	for face: Vector4i in _plan.pending_doors.keys():
		if face.y != _level:
			continue
		var room: StringName = _plan.pending_doors[face]
		_plan.pending_doors.erase(face)
		if not _doors.has(room):
			_doors[room] = []
			for cell in _plan.room_cells(room):
				if cell.y == _level:
					_room_at[cell] = room
		_add_door(room, face)


## count сокетов комнаты под двери: не больше одной на сторону (на каждом уровне), стороны — туда, где соседи; с двумя дверями комната сквозная
## (противоположные стороны, если там есть соседи). Сторону тянут комнаты этажа в её сторону — вес обратно расстоянию и тем сильнее, чем прямее
## напротив (не центр этажа). До 08.10 двери шли к центру и давали коридор вокруг угла комнаты (61 % комнат, сквозных 0 %; карточка «Сетка уровня»).
## Сторон меньше, чем дверей, — остаток добирается лучшими сокетами; пресету столько дверей не дают (RS_RoomPresetLibrary.validate).
func _pick_sockets(room: StringName, sockets: Array[Vector4i], count: int) -> Array[Vector4i]:
	var center := _room_center(room)
	var pull: Dictionary[Vector2i, float] = {}  # (уровень, сторона) -> тяга
	var aim: Dictionary[Vector2i, Vector2] = {}  # куда тянут — взвешенная точка соседей
	var best: Dictionary[Vector2i, Vector4i] = {}
	for face in sockets:
		var key := Vector2i(face.y, face.w)
		if pull.has(key):
			continue
		var cell := GridTopology.face_cell(face)
		var step := _topology.neighbour(cell, face.w) - cell
		var normal := Vector2(step.x, step.z).normalized()
		var weight := 0.0
		var point := Vector2.ZERO
		for other: StringName in _rooms:
			if other == room:
				continue
			var to := _room_center(other) - center
			var facing := normal.dot(to.normalized()) if to.length() > 0.0 else 0.0
			if facing <= 0.0:
				continue
			var w := facing / to.length()
			weight += w
			point += _room_center(other) * w
		pull[key] = weight
		aim[key] = point / weight if weight > 0.0 else _center
	for face in sockets:
		var key := Vector2i(face.y, face.w)
		var front := _front(face)
		if not best.has(key) or _closer(front, _front(best[key]), aim[key]):
			best[key] = face

	var sides := best.keys()
	sides.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return pull[a] > pull[b] if pull[a] != pull[b] else _face_before(best[a], best[b]))
	var picked: Array[Vector2i] = []
	if count >= 1 and not sides.is_empty():
		picked.append(sides[0])
	if count >= 2 and not sides.is_empty():
		var first: Vector2i = sides[0]
		var across := Vector2i(first.x, _topology.opposite(GridTopology.face_cell(best[first]), first.y))
		if pull.get(across, 0.0) > 0.0:
			picked.append(across)
	for key: Vector2i in sides:
		if picked.size() >= count:
			break
		if not picked.has(key):
			picked.append(key)
	var faces: Array[Vector4i] = []
	for key in picked:
		faces.append(best[key])
	if faces.size() < count:
		var rest := sockets.filter(func(face: Vector4i) -> bool: return not faces.has(face))
		rest.sort_custom(func(a: Vector4i, b: Vector4i) -> bool: return _closer(_front(a), _front(b), _center))
		for face: Vector4i in rest.slice(0, count - faces.size()):
			faces.append(face)
	return faces


## Центр footprint комнаты в клетках, плоскость (X, Z).
func _room_center(room: StringName) -> Vector2:
	var anchor: Vector3i = _plan.cells[room]
	var size: Vector3i = _plan.footprints.get(room, Vector3i.ONE)
	return Vector2(anchor.x + (size.x - 1) * 0.5, anchor.z + (size.z - 1) * 0.5)


## Ближе ли клетка a к точке to, чем b; при равенстве — порядок клеток (раскладка совпадает от запуска к запуску).
func _closer(a: Vector3i, b: Vector3i, to: Vector2) -> bool:
	var da := Vector2(a.x, a.z).distance_squared_to(to)
	var db := Vector2(b.x, b.z).distance_squared_to(to)
	return da < db if da != db else _before(a, b)


# Сеть и коридоры


## Сеть — дерево по клеткам, связывающее все клетки перед дверями: от двери, ближайшей к центру, дальше каждый раз ближайшая к проложенному (Прим для
## дерева Штейнера; в заданном порядке дальняя дверь тянула бы «лесенку» параллельных коридоров). Комната в сети — звено: стоит одной двери связаться,
## остальные тоже в сети через саму комнату (_enter_room) — комнаты встают сквозными, а не связываются кратчайшим путём вокруг угла.
func _grow_network() -> void:
	_terminals.sort_custom(_nearer_center)
	if _terminals.is_empty():
		_area = _bounds().grow(ROUTE_MARGIN)
		return
	var search := _bounds().grow(ROUTE_MARGIN)
	var to_network := func(cell: Vector3i) -> bool: return _links.has(cell)
	_enter_room(_front_room[_terminals[0]])
	while true:
		# Свободны — двери комнат, ещё не вошедших в сеть.
		var pending: Array[Vector3i] = []
		for terminal in _terminals:
			if not _links.has(terminal):
				pending.append(terminal)
		if pending.is_empty():
			break
		# Нижняя оценка — путь по сетке до ближайшего тайла: тем, кому не обогнать найденную, поиск не нужен.
		var bound: Dictionary[Vector3i, int] = {}
		for terminal in pending:
			var nearest := 1 << 30
			for cell: Vector3i in _links:
				nearest = mini(nearest, absi(cell.x - terminal.x) + absi(cell.z - terminal.z))
			bound[terminal] = nearest
		pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return bound[a] < bound[b] if bound[a] != bound[b] else _nearer_center(a, b))
		var best: Array[Vector3i] = []
		for terminal in pending:
			if not best.is_empty() and bound[terminal] >= best.size() - 1:
				break
			var path := _route_around(terminal, to_network, search)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if best.is_empty():
			for terminal in pending:
				_plan.routing_failures.append("этаж %d: дверь перед %s не связана с сетью" % [_level, terminal])
			break
		_claim(best)
		# Трасса могла пройти мимо двери другой комнаты — та тоже в сети.
		for cell in best:
			if _front_room.has(cell):
				_enter_room(_front_room[cell])
	_area = _bounds().grow(ROUTE_MARGIN)


## Комната вошла в сеть: клетки перед её дверями — узлы сети, пусть пока без проёмов.
func _enter_room(room: StringName) -> void:
	for front in _fronts(room):
		if not _links.has(front):
			_links[front] = []


## Клетки перед дверями комнаты на этом этаже.
func _fronts(room: StringName) -> Array[Vector3i]:
	var fronts: Array[Vector3i] = []
	for face: Vector4i in _doors.get(room, []):
		fronts.append(_front(face))
	return fronts


## Двери вошедших комнат, к которым коридор не подошёл: каждая тянется к сети отдельно, как петля (_add_loops) — к далёкому по сети месту, не по своему
## поясу (_ring) и не вплотную к ближней сети. Нет трассы — двери нет (сокет остаётся стеной): пресет задаёт «сколько можно». Последнюю дверь не трогаем.
## Выигрыш — тот же MIN_LOOP_GAIN; выигрыш 2 (замер 08.10) давал сквозных 39 % против 29 %, но запасная дверь замыкалась на соседний коридор той же комнаты.
func _join_spare_doors() -> void:
	for front: Vector3i in _terminals.duplicate():
		if not _links.has(front) or not (_links[front] as Array).is_empty():
			continue
		var room: StringName = _front_room[front]
		# Последняя дверь остаётся, даже если вести некуда: без неё комнату не достать.
		if _fronts(room).size() <= 1:
			continue
		var dist := _distances(front)
		var ring := _ring(room)
		var goal := func(cell: Vector3i) -> bool: return dist.get(cell, 0) >= MIN_LOOP_GAIN
		var passable := func(cell: Vector3i) -> bool:
			return _free(cell, _area) and not ring.has(cell) and not _near_except(cell, dist, front)
		var path := GridRouter.find_path(_topology, front, goal, passable, TURN_COST)
		if not path.is_empty() and dist[path[-1]] - (path.size() - 1) >= MIN_LOOP_GAIN and not _envelops(path):
			_claim(path)
		elif _rooms.has(room):
			_drop_door(room, front)
		else:
			# Верх лестницы этажа ниже — дверь между этажами, её не убрать.
			var fallback := _route_around(front, func(cell: Vector3i) -> bool:
				return _links.has(cell) and cell != front, _area)
			if fallback.is_empty():
				_plan.routing_failures.append("этаж %d: дверь перед %s не связана с сетью" % [_level, front])
			else:
				_claim(fallback)


func _drop_door(room: StringName, front: Vector3i) -> void:
	_links.erase(front)
	_terminals.erase(front)
	_front_room.erase(front)
	for face: Vector4i in (_doors[room] as Array).duplicate():
		if _front(face) == front:
			_doors[room].erase(face)
	_rooms[room].socket_doors -= 1
	_plan.dropped_doors += 1


## Режет сеть на коридоры — отрезки между развилками (карточка «Коридор — отдельный узел»): поворот и дверь не режут, развилка режет (иначе
## узел и карта менялись бы каждые 8 м). Клетка развилки достаётся коридору, идущему через неё прямо, боковой примыкает; разрез — только граница
## владения, проём открыт. Возвращает число коридоров; номера — по порядку дверей (нулевой — у ближайшей к центру), затем перемычки и тупики.
##
## Собираются объединением, не вырезанием боковых проёмов: петля может вернуть коридор к его развилке сбоку («Р»), и разрез ничего не отделил бы.
## Такая развилка отпускает сперва одного прямого соседа, потом другого, иначе остаётся коридором в одну клетку.
func _segment() -> int:
	var keep: Dictionary[Vector3i, Array] = {}  # развилка -> прямые соседи, с кем она в одном коридоре
	for tile: Vector3i in _links:
		if (_links[tile] as Array).size() >= 3:
			keep[tile] = _through_pair(tile)
	var root := _join(keep)
	var looped := _self_joined(keep, root)
	while looped != Vector3i.MAX:
		var pair := _through_pair(looped)
		var kept: Array = keep[looped]
		if kept.size() == 2:
			keep[looped] = [pair[0]]
		elif kept.size() == 1 and kept[0] == pair[0]:
			keep[looped] = [pair[1]]
		else:
			keep[looped] = []
		root = _join(keep)
		looped = _self_joined(keep, root)
	_owner.clear()
	var number: Dictionary[Vector3i, int] = {}  # корень коридора -> номер
	var starts: Array[Vector3i] = []
	starts.append_array(_terminals)
	starts.append_array(_links.keys())
	for start in starts:
		if _links.has(start) and not number.has(root[start]):
			number[root[start]] = number.size()
	for tile: Vector3i in _links:
		_owner[tile] = number[root[tile]]
	return number.size()


## Коридоры как множества тайлов (тайл -> корень). Проём объединяет двоих, если оба его принимают: обычный тайл — любой, развилка — только прямых соседей (keep).
func _join(keep: Dictionary[Vector3i, Array]) -> Dictionary[Vector3i, Vector3i]:
	var parent: Dictionary[Vector3i, Vector3i] = {}
	for tile: Vector3i in _links:
		parent[tile] = tile
	for tile: Vector3i in _links:
		for next: Vector3i in _links[tile]:
			if not _before(tile, next) or not _accepts(keep, tile, next) or not _accepts(keep, next, tile):
				continue
			var a := _find(parent, tile)
			var b := _find(parent, next)
			if a != b:
				parent[b] = a
	var root: Dictionary[Vector3i, Vector3i] = {}
	for tile: Vector3i in _links:
		root[tile] = _find(parent, tile)
	return root


## Развилка в одном коридоре с соседом, которого не принимала (коридор вернулся сбоку); Vector3i.MAX — таких нет.
func _self_joined(keep: Dictionary[Vector3i, Array], root: Dictionary[Vector3i, Vector3i]) -> Vector3i:
	for tile: Vector3i in keep:
		for next: Vector3i in _links[tile]:
			if not _accepts(keep, tile, next) and root[next] == root[tile]:
				return tile
	return Vector3i.MAX


func _accepts(keep: Dictionary[Vector3i, Array], tile: Vector3i, next: Vector3i) -> bool:
	return not keep.has(tile) or (keep[tile] as Array).has(next)


static func _find(parent: Dictionary[Vector3i, Vector3i], tile: Vector3i) -> Vector3i:
	while parent[tile] != tile:
		tile = parent[tile]
	return tile


## Два соседа развилки, через которых коридор идёт прямо (GridTopology.opposite). У креста — тот, что длиннее прямо в обе стороны, при равенстве — с меньшей стороной.
## Прямого нет — пусто: клетка остаётся отдельным коридором.
func _through_pair(tile: Vector3i) -> Array[Vector3i]:
	var linked: Array = _links[tile]
	var best: Array[Vector3i] = []
	var best_run := -1
	for side in _topology.side_count(tile):
		var back := _topology.opposite(tile, side)
		if back <= side:
			continue
		var ahead := _topology.neighbour(tile, side)
		var behind := _topology.neighbour(tile, back)
		if not linked.has(ahead) or not linked.has(behind):
			continue
		var run := _straight_run(tile, side) + _straight_run(tile, back)
		if run > best_run:
			best_run = run
			best = [ahead, behind]
	return best


## Сколько тайлов подряд сеть идёт прямо от from через сторону side.
func _straight_run(from: Vector3i, side: int) -> int:
	var run := 0
	var cell := from
	var out := side
	while run < _links.size():
		var next := _topology.neighbour(cell, out)
		if not (_links[cell] as Array).has(next):
			break
		run += 1
		out = _topology.opposite(next, _topology.back_side(cell, out))
		cell = next
	return run


# Петли и тупики


## Петли: короткая трасса по свободным клеткам между двумя далёкими по сети тайлами, берётся самая выгодная (сколько шагов срезает). Не ставится петля,
## обволакивающая комнату (_envelops) или впритык к ближней сети (второй ряд вдоль коридора). Перебор был горячей точкой (755 мс из 1124, профайлер
## 13.10): трасса, заведомо не обгоняющая лучшую, не ищется (_loop_cost_cap, _may_beat) — раскладка на тех же сидах не меняется, версия генератора не растёт.
func _add_loops(count: int) -> void:
	for k in count:
		var best: Array[Vector3i] = []
		var best_gain := 0
		for a: Vector3i in _links.keys():
			var dist := _distances(a)
			var cap := _loop_cost_cap(dist, best_gain)
			if cap < 0:
				continue
			var far := _far_tiles(dist)
			var blocked := _near_cells(dist)
			var goal := func(cell: Vector3i) -> bool: return dist.get(cell, 0) >= MIN_LOOP_GAIN
			var passable := func(cell: Vector3i) -> bool: return _free(cell, _area) and not blocked.has(cell)
			for side in _topology.side_count(a):
				var start := _topology.neighbour(a, side)
				if not _free(start, _area) or not _may_beat(start, far, dist, best_gain):
					continue
				var path := GridRouter.find_path(_topology, start, goal, passable, TURN_COST, cap)
				if path.is_empty():
					continue
				var gain: int = dist[path[-1]] - path.size()
				if gain <= best_gain:
					continue
				var loop: Array[Vector3i] = [a]
				loop.append_array(path)
				if _envelops(loop):
					continue
				best = loop
				best_gain = gain
		if best.is_empty():
			return
		_claim(best)


## Потолок цены трассы петли, при которой она ещё может обогнать лучшую (best_gain); −1 — никакая. Выгода = расстояние до конца по сети − (шагов + 1), поэтому
## шагов не больше max_steps = дальше всего − 2 − best_gain; цена = шаги + TURN_COST за поворот, поворотов не больше шагов без первого.
func _loop_cost_cap(dist: Dictionary[Vector3i, int], best_gain: int) -> int:
	var reach := 0
	for cell: Vector3i in dist:
		reach = maxi(reach, dist[cell])
	var max_steps := reach - 2 - best_gain
	if max_steps < 1:
		return -1
	return (1 + TURN_COST) * max_steps - TURN_COST


## Тайлы, где может кончиться петля (не ближе MIN_LOOP_GAIN), от дальних к ближним — для _may_beat.
func _far_tiles(dist: Dictionary[Vector3i, int]) -> Array[Vector3i]:
	var far: Array[Vector3i] = []
	for cell: Vector3i in dist:
		if dist[cell] >= MIN_LOOP_GAIN:
			far.append(cell)
	far.sort_custom(func(x: Vector3i, y: Vector3i) -> bool: return dist[x] > dist[y])
	return far


## Может ли трасса от start дать выгоду больше best_gain: шагов не меньше GridTopology.min_steps, клеток — на одну больше шагов.
func _may_beat(start: Vector3i, far: Array[Vector3i], dist: Dictionary[Vector3i, int], best_gain: int) -> bool:
	for cell in far:
		if dist[cell] - 1 <= best_gain:
			return false  # дальше по списку только ближние: им не хватит и без шагов
		if dist[cell] - _topology.min_steps(start, cell) - 1 > best_gain:
			return true
	return false


## Клетки, через которые петле идти нельзя, — вплотную к тайлу ближней сети (ближе MIN_LOOP_GAIN): второй ряд вдоль коридора. Считаются раз на тайл, не на шаг поиска.
func _near_cells(dist: Dictionary[Vector3i, int]) -> Dictionary[Vector3i, bool]:
	var cells: Dictionary[Vector3i, bool] = {}
	for tile: Vector3i in _links:
		if dist.get(tile, 0) >= MIN_LOOP_GAIN:
			continue
		for side in _topology.side_count(tile):
			cells[_topology.neighbour(tile, side)] = true
	return cells


## Тупики: отросток в одну-две клетки в свободное место, лучше не вдоль стены комнаты. Не касается других тайлов (иначе щель между коридорами)
## и не обволакивает комнату. Конец отмечается в плане (RS_LayerPlan.dead_ends); что в нём лежит, решает не генератор.
func _add_dead_ends(count: int, rng: RandomNumberGenerator) -> void:
	for k in count:
		var candidates: Array[Array] = []
		var best_score := 1 << 30
		for a: Vector3i in _links.keys():
			# С развилки отросток сделал бы крест, с конца тупика — удлинил бы его.
			if (_links[a] as Array).size() >= 3 or _dead_ends.has(a):
				continue
			for side in _topology.side_count(a):
				var spur: Array[Vector3i] = [a]
				var cell := _topology.neighbour(a, side)
				while spur.size() <= DEAD_END_LENGTH and _free(cell, _area) and not _touches_tiles(cell, spur[-1]):
					spur.append(cell)
					cell = _topology.neighbour(cell, side)
				if spur.size() < 2 or _envelops(spur):
					continue
				var score := 0
				for i in range(1, spur.size()):
					if _touches_room(spur[i]):
						score += 1
				if score < best_score:
					best_score = score
					candidates.clear()
				if score == best_score:
					candidates.append(spur)
		if candidates.is_empty():
			return
		var stub: Array[Vector3i] = []
		stub.assign(candidates[rng.randi_range(0, candidates.size() - 1)])
		_claim(stub)
		_dead_ends.append(stub[-1])


## Обволокла бы комнату трасса path: сеть в поясе вокруг комнаты связала бы две её двери или подошла с трёх сторон (RS_LayoutMetrics.wraps — одно правило на
## раскладку и метрику). Ставятся до разреза на коридоры — игрок видит коридор вокруг комнаты, как его ни режь. Комната без дверей не в счёт.
## По поясу, а не по сторонам: коридоры с трёх-четырёх сторон — перекрёсток; обволакивание — один кусок, огибающий комнату вплотную.
func _envelops(path: Array[Vector3i]) -> bool:
	return not _enveloped(path).is_empty()


## Комнаты, которые обволокла бы трасса path (см. _envelops).
func _enveloped(path: Array[Vector3i]) -> Array[StringName]:
	var added: Dictionary[Vector3i, Array] = {}
	for i in path.size():
		var cell := path[i]
		if not added.has(cell):
			added[cell] = []
		if i > 0:
			added[cell].append(path[i - 1])
			added[path[i - 1]].append(cell)
	var is_tile := func(cell: Vector3i) -> bool: return _links.has(cell) or added.has(cell)
	var linked := func(a: Vector3i, b: Vector3i) -> bool:
		return (_links.has(a) and (_links[a] as Array).has(b)) or (added.has(a) and (added[a] as Array).has(b))
	# Пояс комнаты — клетки в шаге от неё и углы, поэтому смотрим на два шага.
	var rooms: Dictionary[StringName, bool] = {}
	for cell in path:
		for side in _topology.side_count(cell):
			var next := _topology.neighbour(cell, side)
			for near in [next] + _side_neighbours(next):
				if _room_at.has(near):
					rooms[_room_at[near]] = true
	var enveloped: Array[StringName] = []
	for room: StringName in rooms:
		var fronts := _fronts(room)
		if fronts.is_empty():
			continue
		if RS_LayoutMetrics.wraps(_ring(room), fronts, is_tile, linked):
			enveloped.append(room)
	return enveloped


func _side_neighbours(cell: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for side in _topology.side_count(cell):
		cells.append(_topology.neighbour(cell, side))
	return cells


## Пояс комнаты на уровне этого этажа (RS_LayoutMetrics.ring_of); у лестницы этажа ниже здесь её верх.
func _ring(room: StringName) -> Dictionary[Vector3i, int]:
	return RS_LayoutMetrics.ring_of(_topology, _plan.room_cells(room), _level)


# В план


## Переносит сеть в план: маски проёмов, чей коридор, грани дверей с коридорами, тупики. Клетка коридора — его первый тайл. Грани дверей дописываются к записанным (лестница этажа ниже).
func _write(corridor_ids: Array[StringName]) -> void:
	for tile: Vector3i in _links:
		var mask := 0
		for next: Vector3i in _links[tile]:
			mask |= 1 << _topology.side_toward(tile, next)
		var corridor := corridor_ids[_owner[tile]]
		_plan.corridor_tiles[tile] = mask
		_plan.node_by_cell[tile] = corridor
		if not _plan.cells.has(corridor):
			_plan.cells[corridor] = tile
	for room: StringName in _doors:
		var faces: Dictionary = _plan.door_faces.get(room, {})
		for face: Vector4i in _doors[room]:
			var front := _front(face)
			if not _owner.has(front):
				continue  # сеть до двери не дотянулась — это уже в routing_failures
			faces[face] = corridor_ids[_owner[front]]
			_plan.corridor_tiles[front] |= 1 << _topology.back_side(GridTopology.face_cell(face), face.w)
		_plan.door_faces[room] = faces
	for cell in _dead_ends:
		_plan.dead_ends[cell] = true


# Мелочь


## Трасса от start до первой клетки goal (GridRouter.find_path): сперва в area, затем запас растёт — обход лучше отказа.
func _route(
	start: Vector3i, goal: Callable, area: Rect2i, avoid: Dictionary[Vector3i, bool] = {}
) -> Array[Vector3i]:
	var margin := 0
	while margin <= MAX_ROUTE_MARGIN - ROUTE_MARGIN:
		var grown := area.grow(margin)
		var passable := func(cell: Vector3i) -> bool: return _free(cell, grown) and not avoid.has(cell)
		var path := GridRouter.find_path(_topology, start, goal, passable, TURN_COST)
		if not path.is_empty():
			return path
		margin += 2
	return []


## Трасса от двери к сети, не обволакивающая комнат (_envelops): обволокла — пояс запрещается и трасса ищется заново, не больше ENVELOP_RETRIES раз.
## Петлям и тупикам такая трасса просто не ставится, а ствол обязан дойти — ему обход (без него обволакивалось 0.6–1.2 % комнат, замер 29.09; с ним 0).
## Обхода нет — первая трасса: дверь без сети хуже коридора вокруг комнаты. Свой пояс закрыт сразу, кроме клетки перед дверью.
func _route_around(start: Vector3i, goal: Callable, area: Rect2i) -> Array[Vector3i]:
	var avoid: Dictionary[Vector3i, bool] = {}
	if _front_room.has(start):
		for cell in _ring(_front_room[start]):
			if cell != start and not _links.has(cell):
				avoid[cell] = true
	var path := _route(start, goal, area, avoid)
	if path.is_empty():
		avoid.clear()
		path = _route(start, goal, area)
	for attempt in ENVELOP_RETRIES:
		var rooms := _enveloped(path)
		if rooms.is_empty():
			break
		for room in rooms:
			for cell in _ring(room):
				if cell != start and not _links.has(cell):
					avoid[cell] = true
		var detour := _route(start, goal, area, avoid)
		if detour.is_empty():
			break
		path = detour
	return path


## Занимает клетки пути под сеть и открывает проёмы между соседними; чей коридор — решит _segment.
func _claim(path: Array[Vector3i]) -> void:
	for cell in path:
		if not _links.has(cell):
			_links[cell] = []
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		if not (_links[a] as Array).has(b):
			_links[a].append(b)
			_links[b].append(a)


## Свободна ли клетка под трассу: на своём уровне, в области, не комната (в том числе верх зала этажа ниже) и не тайл.
func _free(cell: Vector3i, area: Rect2i) -> bool:
	return (
		cell.y == _level
		and area.has_point(Vector2i(cell.x, cell.z))
		and not _plan.node_by_cell.has(cell)
		and not _links.has(cell)
	)


## Касается ли клетка тайла ближней сети (ближе MIN_LOOP_GAIN от начала петли), кроме except.
func _near_except(cell: Vector3i, dist: Dictionary, except: Vector3i) -> bool:
	for side in _topology.side_count(cell):
		var next := _topology.neighbour(cell, side)
		if next != except and _links.has(next) and dist.get(next, 0) < MIN_LOOP_GAIN:
			return true
	return false


func _touches_tiles(cell: Vector3i, except: Vector3i) -> bool:
	for side in _topology.side_count(cell):
		var next := _topology.neighbour(cell, side)
		if next != except and _links.has(next):
			return true
	return false


func _touches_room(cell: Vector3i) -> bool:
	for side in _topology.side_count(cell):
		if _room_at.has(_topology.neighbour(cell, side)):
			return true
	return false


## Расстояния по сети от start: шаг по проёму — 1, проход сквозь комнату — ROOM_HOP (сеть разорвана комнатами и связна только через них).
func _distances(start: Vector3i) -> Dictionary[Vector3i, int]:
	var dist: Dictionary[Vector3i, int] = {start: 0}
	var buckets: Array[Array] = [[start]]
	var cost := 0
	while cost < buckets.size():
		for cell: Vector3i in buckets[cost]:
			if dist[cell] != cost:
				continue
			var steps: Array[Vector3i] = []
			var costs: Array[int] = []
			for next: Vector3i in _links[cell]:
				steps.append(next)
				costs.append(1)
			if _front_room.has(cell):
				for other in _fronts(_front_room[cell]):
					if other != cell and _links.has(other):
						steps.append(other)
						costs.append(ROOM_HOP)
			for i in steps.size():
				var total := cost + costs[i]
				if dist.has(steps[i]) and dist[steps[i]] <= total:
					continue
				dist[steps[i]] = total
				while buckets.size() <= total:
					buckets.append([])
				buckets[total].append(steps[i])
		cost += 1
	return dist


## Прямоугольник комнат и тайлов этажа в плоскости (X, Z).
func _bounds() -> Rect2i:
	var rect := Rect2i()
	var first := true
	for cell: Vector3i in _room_at:
		if first:
			rect = Rect2i(Vector2i(cell.x, cell.z), Vector2i.ZERO)
			first = false
		else:
			rect = rect.expand(Vector2i(cell.x, cell.z))
	for cell: Vector3i in _links:
		rect = rect.expand(Vector2i(cell.x, cell.z))
	return rect


func _front(face: Vector4i) -> Vector3i:
	return _topology.neighbour(GridTopology.face_cell(face), face.w)


func _nearer_center(a: Vector3i, b: Vector3i) -> bool:
	var da := Vector2(a.x, a.z).distance_squared_to(_center)
	var db := Vector2(b.x, b.z).distance_squared_to(_center)
	return da < db if da != db else _before(a, b)


## Порядок клеток — ряд за рядом: при равной цене решает он (раскладка совпадает от запуска к запуску).
static func _before(a: Vector3i, b: Vector3i) -> bool:
	if a.z != b.z:
		return a.z < b.z
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


static func _face_before(a: Vector4i, b: Vector4i) -> bool:
	if a.z != b.z:
		return a.z < b.z
	if a.x != b.x:
		return a.x < b.x
	return a.w < b.w
