## res://src/resources/world_generator/rs_corridor_planner.gd
## Коридорная раскладка этажа: комнаты на решётке, сеть коридоров — дерево по
## клеткам сетки, связывающее все двери этажа, и петли с тупиками поверх него.
## Здесь же решается, в какую ветку ведёт каждая дверь: граф берёт эти рёбра из
## раскладки (RS_LevelGraph._lay_out_floor), а не диктует их ей.
##
## Почему решает раскладка, а не граф (п. 7 карточки «Сетка уровня»): пока граф
## заранее назначал двери веткам, укладки могло не существовать вовсе — двери в
## случайные ветки не трассировались на 8 % этажей, а лекарство «все двери комнаты
## в одну ветку» заставляло ветку обходить комнату кругом (42 % обволакиваемых
## комнат). Здесь сеть на этаже одна и растёт от двери к ближайшему уже
## проложенному коридору, поэтому трасса есть всегда; на ветки её режут уже
## готовой, и ветки ложатся туда, куда их положила геометрия. Подход «хребет с
## комнатами по сторонам» сравнивался с этим на тех же сидах — цифры в карточке.
##
## Работает только в клетках и сторонах топологии (карточка «Сетка уровня»): где
## клетка стоит в мире, решает вложение плана, и отсюда его не видно. Квадратная
## здесь только сама решётка комнат — ряды по X и Z; это свойство алгоритма
## раскладки, а не сетки.
##
## Случайность — только из переданного rng, своего потока этажа: раскладка
## разыгрывается внутри генерации графа, и общий поток сдвигался бы от любой
## правки здесь.
@tool
class_name RS_CorridorPlanner
extends RefCounted

## Запас клеток вокруг решётки комнат, по которому может пройти сеть: дверь,
## смотрящая наружу решётки, обходит комнаты по краю.
const ROUTE_MARGIN := 1
## Предел расширения запаса, если трасса не нашлась: дальше она уже не обходит
## препятствие, а значит, её заперли.
const MAX_ROUTE_MARGIN := 7
## Цена поворота сверх шага. Без неё первый же прогон дал 43 % поворотов.
const TURN_COST := 3
## Со скольких сторон комнаты ставятся двери, пока на этих сторонах хватает
## сокетов. Дверь на третьей стороне — это коридор с трёх сторон комнаты, то самое
## обволакивание; у коробки 2×2 на двух сторонах четыре сокета, этого хватает
## любой нынешней комнате.
const DOOR_SIDES := 2
## Петля, срезающая по сети меньше этого, — обход пары клеток, а не другой путь.
const MIN_LOOP_GAIN := 6
## Тупик — отросток не длиннее этого: длиннее он читается уже коридором, который
## куда-то ведёт.
const DEAD_END_LENGTH := 2

var _plan: RS_LayerPlan
var _topology: GridTopology
var _level := 0
## Клетка комнаты -> комната.
var _room_at: Dictionary[Vector3i, StringName] = {}
## Комната -> грани её дверей.
var _doors: Dictionary[StringName, Array] = {}
## Тайл сети -> соседние тайлы, с которыми он связан проёмом.
var _links: Dictionary[Vector3i, Array] = {}
## Тайл -> номер ветки (индекс в именах, которые заготовил граф).
var _owner: Dictionary[Vector3i, int] = {}
## Клетки перед дверями — концы, которые сеть обязана связать.
var _terminals: Array[Vector3i] = []
var _dead_ends: Array[Vector3i] = []
## Где ищутся петли и тупики: решётка с сетью и запасом вокруг.
var _area := Rect2i()
## Центр комнат этажа в клетках — к нему смотрят двери.
var _center := Vector2.ZERO


func _init(plan: RS_LayerPlan, level: int) -> void:
	_plan = plan
	_topology = plan.topology
	_level = level


## Раскладывает этаж [param floor_index] в [param plan]: комнаты, сеть, двери,
## петли и тупики. [param branch_ids] — имена веток, заготовленные графом; веток
## выходит не больше, чем дверей на этаже, и возвращается, сколько первых имён
## пошло в дело.
static func plan_floor(
	plan: RS_LayerPlan,
	rooms: Array[RS_LevelNode],
	branch_ids: Array[StringName],
	floor_index: int,
	config: RS_WorldGenConfig,
	rng: RandomNumberGenerator,
) -> int:
	var planner := RS_CorridorPlanner.new(plan, floor_index)
	planner._place_rooms(rooms, config.room_lattice_step, rng)
	for room in rooms:
		planner._choose_doors(room)
	planner._grow_network()
	var used := planner._split(mini(branch_ids.size(), planner._terminals.size()))
	planner._add_loops(config.corridor_loops)
	planner._add_dead_ends(config.dead_ends, rng)
	planner._write(rooms, branch_ids)
	return used


# ---------------------------------------------------------------------------
# Комнаты и двери
# ---------------------------------------------------------------------------


## Комнаты на решётке рядами в перетасованном порядке: где встанет хаб или выход,
## решает сид этажа, а не порядковый номер узла. Клетка комнаты — угловая клетка
## её footprint.
##
## Шаг решётки растёт на размер крупнейшей комнаты этажа: между footprint'ами
## остаётся тот же зазор, что между комнатами в одну клетку, и сети есть где
## пройти. Footprint — в осях мира: у комнаты, повёрнутой на нечётную четверть,
## ширина и длина меняются местами.
func _place_rooms(rooms: Array[RS_LevelNode], step: int, rng: RandomNumberGenerator) -> void:
	var sizes: Dictionary[StringName, Vector3i] = {}
	var largest := Vector3i.ONE
	for room in rooms:
		var size := RS_RoomLayout.footprint_of_scene(room.room_scene_path)
		sizes[room.id] = Vector3i(size.z, size.y, size.x) if room.turns % 2 else size
		largest = largest.max(sizes[room.id])
	var order := rooms.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: RS_LevelNode = order[i]
		order[i] = order[j]
		order[j] = swap
	var stride := Vector2i(step + largest.x - 1, step + largest.z - 1)
	var cols := maxi(ceili(sqrt(float(order.size()))), 1)
	var sum := Vector2.ZERO
	for i in order.size():
		var room: RS_LevelNode = order[i]
		var size: Vector3i = sizes[room.id]
		var anchor := Vector3i((i % cols) * stride.x, _level, (i / cols) * stride.y)
		_put(room, anchor, size)
		sum += Vector2(anchor.x + (size.x - 1) * 0.5, anchor.z + (size.z - 1) * 0.5)
	_center = sum / maxi(order.size(), 1)


## Ставит комнату в план: угловая клетка, footprint, поворот и все его клетки — на
## всех его уровнях, иначе node_at не узнал бы комнату под потолком высокого зала.
func _put(room: RS_LevelNode, anchor: Vector3i, size: Vector3i) -> void:
	_plan.cells[room.id] = anchor
	_plan.footprints[room.id] = size
	_plan.turns[room.id] = room.turns
	# Комната без дверей тоже ключ: по ключам door_faces считают комнаты метрики.
	_plan.door_faces[room.id] = {}
	for cell in SquareGridTopology.box(anchor, size):
		if _plan.node_by_cell.has(cell):
			_plan.routing_failures.append("%s: клетка %s уже занята %s" % [room.id, cell, _plan.node_by_cell[cell]])
		_plan.node_by_cell[cell] = room.id
		_room_at[cell] = room.id


## Грани под двери комнаты. У комнаты с дверями в сцене — стороны её дверей,
## повёрнутые вместе с комнатой: сцена в одну клетку, и грань — её сторона в мире.
## У собранной по сокетам — [member RS_LevelNode.socket_doors] сокетов, смотрящих
## внутрь решётки (_inward_sockets).
func _choose_doors(room: RS_LevelNode) -> void:
	var anchor: Vector3i = _plan.cells[room.id]
	var faces: Array[Vector4i] = []
	if room.socket_doors == 0:
		for side: int in RS_RoomLayout.door_sides_of_scene(room.room_scene_path):
			faces.append(GridTopology.face(anchor, _topology.rotate_side(anchor, side, -room.turns)))
	else:
		faces = _inward_sockets(_topology.perimeter(_plan.room_cells(room.id)), room.socket_doors)
	_doors[room.id] = faces
	for face in faces:
		_terminals.append(_front(face))


## [param count] сокетов, ближайших к центру комнат этажа, и не больше чем с
## DOOR_SIDES сторон, пока на них хватает сокетов. Двери внутрь решётки смотрят
## друг на друга через улицу, и сеть связывает их коротко; дверь наружу тянула бы
## коридор в обход, а дверь на третьей стороне — коридор вокруг комнаты.
func _inward_sockets(sockets: Array[Vector4i], count: int) -> Array[Vector4i]:
	var score: Dictionary[Vector4i, float] = {}
	for face in sockets:
		var front := _front(face)
		score[face] = Vector2(front.x, front.z).distance_squared_to(_center)
	sockets.sort_custom(func(a: Vector4i, b: Vector4i) -> bool:
		return score[a] < score[b] if score[a] != score[b] else _face_before(a, b))
	var sides: Array[int] = []
	for face in sockets:
		if not sides.has(face.w):
			sides.append(face.w)
	var allowed := mini(DOOR_SIDES, sides.size())
	while allowed < sides.size() and _sockets_on(sockets, sides.slice(0, allowed)) < count:
		allowed += 1
	var open := sides.slice(0, allowed)
	var picked: Array[Vector4i] = []
	for face in sockets:
		if picked.size() == count:
			break
		if open.has(face.w):
			picked.append(face)
	return picked


func _sockets_on(sockets: Array[Vector4i], sides: Array) -> int:
	var count := 0
	for face in sockets:
		if sides.has(face.w):
			count += 1
	return count


# ---------------------------------------------------------------------------
# Сеть и ветки
# ---------------------------------------------------------------------------


## Сеть — дерево по клеткам, связывающее все клетки перед дверями: от двери,
## ближайшей к центру, и дальше каждый раз та дверь, что ближе всех к уже
## проложенному (Прим для дерева Штейнера). В заранее заданном порядке дальняя
## дверь тянула бы свой ряд вдоль чужого, пока сеть до неё не дошла, — на карте
## это «лесенка» параллельных коридоров.
func _grow_network() -> void:
	_terminals.sort_custom(_nearer_center)
	if _terminals.is_empty():
		_area = _bounds().grow(ROUTE_MARGIN)
		return
	var search := _bounds().grow(ROUTE_MARGIN)
	var to_network := func(cell: Vector3i) -> bool: return _links.has(cell)
	_links[_terminals[0]] = []
	var pending: Array[Vector3i] = []
	for terminal in _terminals:
		pending.append(terminal)
	while true:
		var left: Array[Vector3i] = []
		for terminal in pending:
			if not _links.has(terminal):
				left.append(terminal)
		pending = left
		if pending.is_empty():
			break
		# Нижняя оценка — путь по сетке до ближайшего тайла, без обходов: трассы ищутся
		# от ближних, и тем, кому уже не обогнать найденную, поиск не нужен.
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
			var path := _route(terminal, to_network, search)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if best.is_empty():
			for terminal in pending:
				_plan.routing_failures.append("этаж %d: дверь перед %s не связана с сетью" % [_level, terminal])
			break
		_claim(best, -1)
	_area = _bounds().grow(ROUTE_MARGIN)


## Режет дерево сети на [param count] веток, у каждой хоть одна дверь: ветка без
## двери — коридор в никуда. Режется ребро, делящее двери ровнее всего, при
## равенстве — у развилки: стык веток — место под будущий шлюз, и на развилке он
## читается как отходящий коридор, а не как дверь посреди прямого. Разрез — только
## граница владения, проём на стыке остаётся открытым. Возвращает, сколько веток
## вышло; нулевая — ветка первой двери.
func _split(count: int) -> int:
	var cut: Dictionary[String, bool] = {}
	var fronts: Dictionary[Vector3i, bool] = {}
	for terminal in _terminals:
		if _links.has(terminal):
			fronts[terminal] = true
	for k in count - 1:
		var best_key := ""
		var best_score := 0
		var best_fork := false
		for a: Vector3i in _links:
			for b: Vector3i in _links[a]:
				if not _before(a, b):
					continue
				var key := _edge_key(a, b)
				if cut.has(key):
					continue
				var part_a := _reach(a, cut, key)
				var part_b := _reach(b, cut, key)
				var score := mini(_count_in(part_a, fronts), _count_in(part_b, fronts))
				var fork: bool = (_links[a] as Array).size() >= 3 or (_links[b] as Array).size() >= 3
				if score > best_score or (score == best_score and score > 0 and fork and not best_fork):
					best_key = key
					best_score = score
					best_fork = fork
		if best_key == "":
			break
		cut[best_key] = true
	var next := 0
	for terminal in _terminals:
		if not _links.has(terminal) or _owner.has(terminal):
			continue
		for cell: Vector3i in _reach(terminal, cut, ""):
			_owner[cell] = next
		next += 1
	return next


# ---------------------------------------------------------------------------
# Петли и тупики
# ---------------------------------------------------------------------------


## Петли по коридору: короткая трасса по свободным клеткам между двумя тайлами,
## далёкими друг от друга по сети. Из всех берётся самая выгодная — сколько шагов
## по сети она срезает. Не ставится петля, которая обволокла бы комнату
## (_envelops), и петля впритык к ближней сети — это второй ряд вдоль того же
## коридора, а не обход. Поэтому на тесном этаже петель выходит меньше заявленного.
func _add_loops(count: int) -> void:
	for k in count:
		var best: Array[Vector3i] = []
		var best_gain := 0
		for a: Vector3i in _links.keys():
			var dist := _distances(a)
			var goal := func(cell: Vector3i) -> bool: return dist.get(cell, 0) >= MIN_LOOP_GAIN
			var passable := func(cell: Vector3i) -> bool: return _free(cell, _area) and not _near(cell, dist)
			for side in _topology.side_count(a):
				var start := _topology.neighbour(a, side)
				if not _free(start, _area):
					continue
				var path := GridRouter.find_path(_topology, start, goal, passable, TURN_COST)
				if path.is_empty():
					continue
				var gain: int = dist[path[-1]] - path.size()
				if gain <= best_gain:
					continue
				var loop: Array[Vector3i] = [a]
				loop.append_array(path)
				if _envelops(loop, _owner[a]):
					continue
				best = loop
				best_gain = gain
		if best.is_empty():
			return
		_claim(best, _owner[best[0]])


## Тупики: отросток в одну-две клетки от тайла в свободное место, лучше — не вдоль
## стены комнаты (там он читается недостроенным коридором к двери). Отросток не
## касается других тайлов — иначе это не тупик, а щель между коридорами — и не
## обволакивает комнату. Конец отмечается в плане (RS_LayerPlan.dead_ends): что в
## нём лежит, решает не генератор.
func _add_dead_ends(count: int, rng: RandomNumberGenerator) -> void:
	for k in count:
		var candidates: Array[Array] = []
		var best_score := 1 << 30
		for a: Vector3i in _links.keys():
			# С развилки отросток сделал бы крест, с конца тупика — удлинил бы его.
			if (_links[a] as Array).size() >= 3 or _dead_ends.has(a):
				continue
			for side in _topology.side_count(a):
				var stub: Array[Vector3i] = [a]
				var cell := _topology.neighbour(a, side)
				while stub.size() <= DEAD_END_LENGTH and _free(cell, _area) and not _touches_tiles(cell, stub[-1]):
					stub.append(cell)
					cell = _topology.neighbour(cell, side)
				if stub.size() < 2 or _envelops(stub, _owner[a]):
					continue
				var score := 0
				for i in range(1, stub.size()):
					if _touches_room(stub[i]):
						score += 1
				if score < best_score:
					best_score = score
					candidates.clear()
				if score == best_score:
					candidates.append(stub)
		if candidates.is_empty():
			return
		var stub: Array[Vector3i] = []
		stub.assign(candidates[rng.randi_range(0, candidates.size() - 1)])
		_claim(stub, _owner[stub[0]])
		_dead_ends.append(stub[-1])


## Обволокла бы комнату трасса [param path] ветки [param branch]: к комнате с трёх
## сторон подошли бы её собственные ветки — те, куда ведут её двери, как в
## RS_LayoutMetrics. Все свои вместе, а не каждая порознь: границ веток игрок не
## видит, и кольцо из двух веток вокруг комнаты — то же обволакивание.
func _envelops(path: Array[Vector3i], branch: int) -> bool:
	var added: Dictionary[Vector3i, bool] = {}
	for cell in path:
		added[cell] = true
	var rooms: Dictionary[StringName, bool] = {}
	for cell in path:
		for side in _topology.side_count(cell):
			var next := _topology.neighbour(cell, side)
			if _room_at.has(next):
				rooms[_room_at[next]] = true
	for room: StringName in rooms:
		var own: Dictionary[int, bool] = {}
		for face: Vector4i in _doors[room]:
			var front := _front(face)
			if _owner.has(front):
				own[_owner[front]] = true
			elif added.has(front):
				own[branch] = true
		if own.is_empty():
			continue
		var sides: Dictionary[int, bool] = {}
		for face in _topology.perimeter(_plan.room_cells(room)):
			var next := _front(face)
			if (added.has(next) and own.has(branch)) or (_owner.has(next) and own.has(_owner[next])):
				sides[face.w] = true
		if sides.size() >= 3:
			return true
	return false


# ---------------------------------------------------------------------------
# В план
# ---------------------------------------------------------------------------


## Переносит сеть в план: маски проёмов (к соседним тайлам и к дверям), чья ветка,
## грани дверей с их ветками, тупики. Клетка ветки — её первый тайл: у ветки нет
## одной клетки, а инструментам нужна хоть какая-то.
func _write(rooms: Array[RS_LevelNode], branch_ids: Array[StringName]) -> void:
	for tile: Vector3i in _links:
		var mask := 0
		for next: Vector3i in _links[tile]:
			mask |= 1 << _topology.side_toward(tile, next)
		var branch := branch_ids[_owner[tile]]
		_plan.corridor_tiles[tile] = mask
		_plan.node_by_cell[tile] = branch
		if not _plan.cells.has(branch):
			_plan.cells[branch] = tile
	for room in rooms:
		var faces := {}
		for face: Vector4i in _doors[room.id]:
			var front := _front(face)
			if not _owner.has(front):
				continue  # сеть до двери не дотянулась — это уже в routing_failures
			faces[face] = branch_ids[_owner[front]]
			_plan.corridor_tiles[front] |= 1 << _topology.back_side(GridTopology.face_cell(face), face.w)
		_plan.door_faces[room.id] = faces
	for cell in _dead_ends:
		_plan.dead_ends[cell] = true


# ---------------------------------------------------------------------------
# Мелочь
# ---------------------------------------------------------------------------


## Трасса от [param start] до первой клетки, где [param goal] истинна
## (GridRouter.find_path). Сперва в [param area], затем запас растёт: обход по
## краю лучше, чем отказ.
func _route(start: Vector3i, goal: Callable, area: Rect2i) -> Array[Vector3i]:
	var margin := 0
	while margin <= MAX_ROUTE_MARGIN - ROUTE_MARGIN:
		var grown := area.grow(margin)
		var passable := func(cell: Vector3i) -> bool: return _free(cell, grown)
		var path := GridRouter.find_path(_topology, start, goal, passable, TURN_COST)
		if not path.is_empty():
			return path
		margin += 2
	return []


## Занимает клетки пути за веткой [param branch] (−1 — ещё не разрезано) и
## открывает проёмы между соседними клетками пути.
func _claim(path: Array[Vector3i], branch: int) -> void:
	for cell in path:
		if not _links.has(cell):
			_links[cell] = []
			if branch >= 0:
				_owner[cell] = branch
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		if not (_links[a] as Array).has(b):
			_links[a].append(b)
			_links[b].append(a)


## Свободна ли клетка под трассу: на своём уровне, в области, не комната (в том
## числе верх высокой комнаты этажа ниже) и не тайл.
func _free(cell: Vector3i, area: Rect2i) -> bool:
	return (
		cell.y == _level
		and area.has_point(Vector2i(cell.x, cell.z))
		and not _plan.node_by_cell.has(cell)
		and not _links.has(cell)
	)


## Касается ли клетка тайла ближней сети — ближе MIN_LOOP_GAIN шагов от начала петли.
func _near(cell: Vector3i, dist: Dictionary) -> bool:
	for side in _topology.side_count(cell):
		var next := _topology.neighbour(cell, side)
		if _links.has(next) and dist.get(next, 0) < MIN_LOOP_GAIN:
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


## Расстояния по сети (в шагах по проёмам) от тайла [param start].
func _distances(start: Vector3i) -> Dictionary[Vector3i, int]:
	var dist: Dictionary[Vector3i, int] = {start: 0}
	var queue: Array[Vector3i] = [start]
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		for next: Vector3i in _links[cell]:
			if not dist.has(next):
				dist[next] = dist[cell] + 1
				queue.append(next)
	return dist


## Тайлы, достижимые от [param start] по проёмам, кроме разрезанных.
func _reach(start: Vector3i, cut: Dictionary[String, bool], also_cut: String) -> Dictionary[Vector3i, bool]:
	var seen: Dictionary[Vector3i, bool] = {start: true}
	var stack: Array[Vector3i] = [start]
	while not stack.is_empty():
		var cell: Vector3i = stack.pop_back()
		for next: Vector3i in _links[cell]:
			var key := _edge_key(cell, next)
			if seen.has(next) or cut.has(key) or key == also_cut:
				continue
			seen[next] = true
			stack.append(next)
	return seen


func _count_in(part: Dictionary[Vector3i, bool], fronts: Dictionary[Vector3i, bool]) -> int:
	var count := 0
	for cell: Vector3i in part:
		if fronts.has(cell):
			count += 1
	return count


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


## Порядок клеток — ряд за рядом: при равной цене решает он, и раскладка обязана
## совпадать от запуска к запуску.
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


static func _edge_key(a: Vector3i, b: Vector3i) -> String:
	return "%s|%s" % ([a, b] if _before(a, b) else [b, a])
