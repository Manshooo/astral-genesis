## res://src/resources/world_generator/rs_corridor_planner.gd
## Коридорная раскладка этажа: комнаты на решётке, коридоры трассируются между
## ними по клеткам кита (RS_LayerPlan.CELL_SIZE). Заполняет переданный план.
##
## Раскладка — СЛЕДСТВИЕ графа, а не его источник (карточка «Процедурные
## коридоры между комнатами»): что с чем связано, решил RS_LevelGraph; здесь
## только «где это стоит и как пройдёт трасса». Поэтому на вход идут одни
## клетки, стороны дверей и рёбра, а не сцены целиком, — такой планировщик
## переживёт перенос раскладки до подбора сцены из карточки рефакторинга
## генератора: стороны дверей тогда придут из требований узла, а не из сцены.
##
## Детерминирован от графа и без rng: разнообразие даёт сам граф (какие комнаты
## на какой ветке), а случайность здесь пришлось бы сеять заново и хранить.
@tool
class_name RS_CorridorPlanner
extends RefCounted

## Запас клеток вокруг решётки комнат, по которому может пройти трасса: дверь,
## смотрящая наружу решётки, обходит комнаты по краю.
const ROUTE_MARGIN := 3
## Предел расширения запаса, если трасса не нашлась: дальше она уже не
## обходит препятствие, а значит, ветку заперли чужие коридоры.
const MAX_ROUTE_MARGIN := 9
## Цена поворота сверх шага. Без неё все кратчайшие пути равны, и поиск выдаёт
## «лесенку» из поворотов — на ките это ряд угловых кусков вместо прямого
## коридора, и первый же прогон дал 43 % поворотов.
const TURN_COST := 3

## Стороны по индексу — у состояния поиска направление хранится числом.
const SIDE_ORDER: Array[StringName] = [&"north", &"east", &"south", &"west"]
## «Направления ещё нет» — стартовая клетка.
const NO_SIDE := 4

const OFFSETS := RS_RoomLayout.OFFSETS
const OPPOSITE := RS_RoomLayout.OPPOSITE


static func plan_floor(plan: RS_LayerPlan, floor_nodes: Array, floor_index: int, step: int) -> void:
	var rooms: Array[RS_LevelNode] = []
	var branches: Array[RS_LevelNode] = []
	var on_floor: Dictionary[StringName, RS_LevelNode] = {}
	for node: RS_LevelNode in floor_nodes:
		on_floor[node.id] = node
		if node.role == RS_LevelNode.Role.CORRIDOR:
			branches.append(node)
		else:
			rooms.append(node)
	# Порядок веток — порядок постройки их дерева: родитель всегда раньше.
	var rank: Dictionary[StringName, int] = {}
	for i in branches.size():
		rank[branches[i].id] = i

	var result := _layout(rooms, branches, on_floor, rank, step)
	plan.routing_failures.append_array(result["failures"])
	plan.door_sides.merge(result["door_sides"])
	var room_cells: Dictionary = result["room_cells"]
	var owner: Dictionary = result["owner"]
	var masks: Dictionary = result["masks"]
	for id: StringName in room_cells:
		_put(plan, id, room_cells[id], floor_index)
	for cell: Vector2i in owner:
		var id: StringName = owner[cell]
		plan.corridor_tiles[Vector3i(cell.x, floor_index, cell.y)] = masks[cell]
		plan.node_by_cell[Vector3i(cell.x, floor_index, cell.y)] = id
		if not plan.positions.has(id):
			plan.positions[id] = plan.cell_position(cell, floor_index)
			plan.cells[id] = cell


## Раскладка этажа в локальные словари: решётка, пары «дверь → ветка», трассы.
static func _layout(
	rooms: Array[RS_LevelNode],
	branches: Array[RS_LevelNode],
	on_floor: Dictionary[StringName, RS_LevelNode],
	rank: Dictionary[StringName, int],
	step: int,
) -> Dictionary:
	var failures: Array[String] = []
	var room_cells := _place_rooms(rooms, on_floor, rank, step)
	var taken: Dictionary[Vector2i, bool] = {}
	for id: StringName in room_cells:
		taken[room_cells[id]] = true

	# Клетка перед дверью -> { ветка, сторона тайла, смотрящая в комнату }.
	var door_at: Dictionary[Vector2i, Dictionary] = {}
	var door_sides: Dictionary[StringName, Dictionary] = {}
	for room in rooms:
		var sides := _sorted_sides(RS_RoomLayout.door_directions_of_scene(room.room_scene_path))
		var targets := _branch_edges(room, on_floor, rank)
		if sides.size() != targets.size():
			failures.append(
				"%s: сторон с дверью %d, рёбер в коридоры %d" % [room.id, sides.size(), targets.size()]
			)
		# Пары по порядку: у комнаты все двери в одной ветке (см.
		# RS_LevelGraph._hang_floor_on_corridors), и какая сторона кому — всё
		# равно. Появятся комнаты-перемычки — сюда придёт подбор пар по
		# направлению к ветке.
		var paired := {}
		for i in mini(sides.size(), targets.size()):
			paired[sides[i]] = targets[i]
		for side: StringName in paired:
			var cell: Vector2i = room_cells[room.id] + OFFSETS[side]
			door_at[cell] = {"branch": paired[side], "face": OPPOSITE[side]}
		door_sides[room.id] = paired

	var bounds := _bounds(room_cells.values())
	var owner: Dictionary[Vector2i, StringName] = {}
	var masks: Dictionary[Vector2i, int] = {}
	for branch in branches:
		_route_branch(failures, branch, on_floor, rank, taken, door_at, owner, masks, bounds)
	return {
		"failures": failures,
		"room_cells": room_cells,
		"door_sides": door_sides,
		"owner": owner,
		"masks": masks,
	}


## Комнаты на решётке змейкой: ряд за рядом, чётные слева направо, нечётные
## справа налево — соседние по порядку комнаты всегда соседние на решётке.
## Порядок — по первой ветке комнаты: комнаты одной ветки встают кучно, и её
## трасса выходит короткой.
static func _place_rooms(
	rooms: Array[RS_LevelNode],
	on_floor: Dictionary[StringName, RS_LevelNode],
	rank: Dictionary[StringName, int],
	step: int,
) -> Dictionary[StringName, Vector2i]:
	var ordered := rooms.duplicate()
	var first_branch := func(room: RS_LevelNode) -> int:
		var best := rank.size()
		for id in _branch_edges(room, on_floor, rank):
			best = mini(best, rank[id])
		return best
	ordered.sort_custom(
		func(a: RS_LevelNode, b: RS_LevelNode) -> bool:
			var ra: int = first_branch.call(a)
			var rb: int = first_branch.call(b)
			return ra < rb if ra != rb else a.index_in_layer < b.index_in_layer
	)
	var cols := maxi(ceili(sqrt(float(ordered.size()))), 1)
	var cells: Dictionary[StringName, Vector2i] = {}
	for i in ordered.size():
		var row := i / cols
		var col := i % cols
		if row % 2 == 1:
			col = cols - 1 - col
		cells[(ordered[i] as RS_LevelNode).id] = Vector2i(col * step, row * step)
	return cells


## Ветки, в которые смотрят двери комнаты, — с повторами, если в одну ветку
## ведут две двери. Отсортированы по порядку веток: пары «сторона → ветка»
## обязаны быть одинаковыми от запуска к запуску.
static func _branch_edges(
	room: RS_LevelNode, on_floor: Dictionary[StringName, RS_LevelNode], rank: Dictionary[StringName, int]
) -> Array[StringName]:
	var targets: Array[StringName] = []
	for conn: RS_LevelConnection in room.connections:
		if rank.has(conn.target_node_id) and on_floor.has(conn.target_node_id):
			targets.append(conn.target_node_id)
	targets.sort_custom(func(a, b): return rank[a] < rank[b])
	return targets


static func _sorted_sides(sides: Array[StringName]) -> Array[StringName]:
	var ordered: Array[StringName] = []
	for side: StringName in OFFSETS:
		if sides.has(side):
			ordered.append(side)
	return ordered


## Прокладывает ветку: сперва её первая дверь соединяется со стыком
## родительской ветки (у корня — просто встаёт первым тайлом), потом каждая
## следующая дверь — с уже проложенной частью. Трасса не заходит в комнаты, в
## чужие коридоры и в клетки перед чужими дверями: касание там открыло бы
## проход, которого в графе нет.
static func _route_branch(
	failures: Array[String],
	branch: RS_LevelNode,
	on_floor: Dictionary[StringName, RS_LevelNode],
	rank: Dictionary[StringName, int],
	taken: Dictionary[Vector2i, bool],
	door_at: Dictionary[Vector2i, Dictionary],
	owner: Dictionary[Vector2i, StringName],
	masks: Dictionary[Vector2i, int],
	bounds: Rect2i,
) -> void:
	var terminals: Array[Vector2i] = []
	for cell: Vector2i in door_at:
		if door_at[cell]["branch"] == branch.id:
			terminals.append(cell)
	terminals.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x)
	if terminals.is_empty():
		failures.append("%s: ни одной двери" % branch.id)
		return

	var parent := _parent_branch(branch, on_floor, rank)
	var passable := func(cell: Vector2i) -> bool:
		if taken.has(cell):
			return false
		if owner.has(cell) and owner[cell] != branch.id:
			return false
		return not door_at.has(cell) or door_at[cell]["branch"] == branch.id

	var start: Vector2i = terminals[0]
	if parent != &"":
		var path := _search(start, func(c): return owner.get(c, &"") == parent, passable, bounds)
		if path.is_empty():
			failures.append("%s: не дотянулся до %s" % [branch.id, parent])
		else:
			_claim(path, branch.id, owner, masks, true)
	else:
		_claim([start], branch.id, owner, masks, false)

	for i in range(1, terminals.size()):
		var terminal := terminals[i]
		if owner.get(terminal, &"") == branch.id:
			continue  # трасса уже прошла через эту клетку
		var path := _search(
			terminal, func(c): return owner.get(c, &"") == branch.id, passable, bounds
		)
		if path.is_empty():
			failures.append("%s: не дотянулся до двери в %s" % [branch.id, terminal])
		else:
			_claim(path, branch.id, owner, masks, true)

	# Проём к комнате — на каждой клетке перед дверью этой ветки.
	for cell in terminals:
		if owner.get(cell, &"") == branch.id:
			masks[cell] = masks.get(cell, 0) | RS_LayerPlan.SIDE_BITS[door_at[cell]["face"]]


## Ветка, к которой эта пристыкована: соседняя по графу и раньше по порядку.
## У корня — "".
static func _parent_branch(
	branch: RS_LevelNode, on_floor: Dictionary[StringName, RS_LevelNode], rank: Dictionary[StringName, int]
) -> StringName:
	for conn: RS_LevelConnection in branch.connections:
		var id := conn.target_node_id
		if rank.has(id) and on_floor.has(id) and rank[id] < rank[branch.id]:
			return id
	return &""


## Самый дешёвый путь от [param start] до первой клетки, где [param goal]
## истинна: шаг стоит 1, поворот — TURN_COST сверху. Путь — от start до этой
## клетки ВКЛЮЧИТЕЛЬНО; пустой — не
## нашлось. Сперва в пределах решётки с запасом ROUTE_MARGIN, затем запас
## растёт: обход по краю лучше, чем отказ.
##
## Дейкстра по состояниям (клетка, откуда пришли) — иначе цену поворота не
## посчитать; очередь — вёдрами по цене, цены здесь мелкие целые.
static func _search(start: Vector2i, goal: Callable, passable: Callable, bounds: Rect2i) -> Array[Vector2i]:
	var margin := ROUTE_MARGIN
	while margin <= MAX_ROUTE_MARGIN:
		var path := _search_within(start, goal, passable, bounds.grow(margin))
		if not path.is_empty():
			return path
		margin += 3
	return []


static func _search_within(start: Vector2i, goal: Callable, passable: Callable, area: Rect2i) -> Array[Vector2i]:
	var origin := Vector3i(start.x, start.y, NO_SIDE)
	var best: Dictionary[Vector3i, int] = {origin: 0}
	var came: Dictionary[Vector3i, Vector3i] = {}
	var buckets: Array[Array] = [[origin]]
	var cost := 0
	while cost < buckets.size():
		var bucket: Array = buckets[cost]
		for state: Vector3i in bucket:
			if best[state] != cost:
				continue  # устаревшая запись: сюда уже дошли дешевле
			var cell := Vector2i(state.x, state.y)
			if state != origin and goal.call(cell):
				return _unwind(came, origin, state)
			for d in SIDE_ORDER.size():
				var next: Vector2i = cell + OFFSETS[SIDE_ORDER[d]]
				var is_goal: bool = goal.call(next)
				if not is_goal and (not area.has_point(next) or not passable.call(next)):
					continue
				var step := 1
				if state.z != NO_SIDE and state.z != d:
					step += TURN_COST
				var next_state := Vector3i(next.x, next.y, d)
				var total := cost + step
				if best.has(next_state) and best[next_state] <= total:
					continue
				best[next_state] = total
				came[next_state] = state
				while buckets.size() <= total:
					buckets.append([])
				buckets[total].append(next_state)
		cost += 1
	return []


static func _unwind(came: Dictionary[Vector3i, Vector3i], origin: Vector3i, last: Vector3i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [Vector2i(last.x, last.y)]
	var state := last
	while state != origin:
		state = came[state]
		path.push_front(Vector2i(state.x, state.y))
	return path


## Занимает клетки пути за веткой и открывает проёмы между соседними клетками
## пути. [param ends_in_existing] — последняя клетка уже чья-то (своя трасса или
## родительская ветка): её не занимаем, но проём к ней открываем с обеих
## сторон — это и есть стык.
static func _claim(
	path: Array,
	branch_id: StringName,
	owner: Dictionary[Vector2i, StringName],
	masks: Dictionary[Vector2i, int],
	ends_in_existing: bool,
) -> void:
	var last_own := path.size() - (1 if ends_in_existing else 0)
	for i in last_own:
		owner[path[i]] = branch_id
		if not masks.has(path[i]):
			masks[path[i]] = 0
	for i in range(path.size() - 1):
		var a: Vector2i = path[i]
		var b: Vector2i = path[i + 1]
		for side: StringName in OFFSETS:
			if a + OFFSETS[side] == b:
				masks[a] = masks.get(a, 0) | RS_LayerPlan.SIDE_BITS[side]
				masks[b] = masks.get(b, 0) | RS_LayerPlan.SIDE_BITS[OPPOSITE[side]]


static func _bounds(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var rect := Rect2i(cells[0], Vector2i.ZERO)
	for cell: Vector2i in cells:
		rect = rect.expand(cell)
	return rect


static func _put(plan: RS_LayerPlan, id: StringName, cell: Vector2i, floor_index: int) -> void:
	plan.cells[id] = cell
	plan.positions[id] = plan.cell_position(cell, floor_index)
	plan.node_by_cell[Vector3i(cell.x, floor_index, cell.y)] = id
