## res://src/resources/world_generator/rs_corridor_planner.gd
## Коридорная раскладка этажа: комнаты на решётке, коридоры трассируются между
## ними по клеткам сетки плана. Заполняет переданный план.
##
## Раскладка — СЛЕДСТВИЕ графа, а не его источник (карточка «Процедурные
## коридоры между комнатами»): что с чем связано, решил RS_LevelGraph; здесь
## только «где это стоит и как пройдёт трасса». Поэтому на вход идут одни
## клетки, стороны дверей и рёбра, а не сцены целиком, — такой планировщик
## переживёт перенос раскладки до подбора сцены из карточки рефакторинга
## генератора: стороны дверей тогда придут из требований узла, а не из сцены.
##
## Работает только в клетках и сторонах топологии (карточка «Сетка уровня»): где
## клетка стоит в мире, решает вложение плана, и отсюда его не видно. Квадратная
## здесь только сама решётка комнат — змейка по X и Z; это свойство нынешнего
## алгоритма раскладки, а не сетки.
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
## Цена поворота сверх шага. Без неё первый же прогон дал 43 % поворотов.
const TURN_COST := 3


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

	var result := _layout(plan.topology, rooms, branches, on_floor, rank, floor_index, step)
	plan.routing_failures.append_array(result["failures"])
	plan.door_sides.merge(result["door_sides"])
	var room_cells: Dictionary = result["room_cells"]
	var owner: Dictionary = result["owner"]
	var masks: Dictionary = result["masks"]
	for id: StringName in room_cells:
		_put(plan, id, room_cells[id])
	for cell: Vector3i in owner:
		var id: StringName = owner[cell]
		plan.corridor_tiles[cell] = masks[cell]
		plan.node_by_cell[cell] = id
		if not plan.cells.has(id):
			plan.cells[id] = cell


## Раскладка этажа в локальные словари: решётка, пары «дверь → ветка», трассы.
static func _layout(
	topology: GridTopology,
	rooms: Array[RS_LevelNode],
	branches: Array[RS_LevelNode],
	on_floor: Dictionary[StringName, RS_LevelNode],
	rank: Dictionary[StringName, int],
	floor_index: int,
	step: int,
) -> Dictionary:
	var failures: Array[String] = []
	var room_cells := _place_rooms(rooms, on_floor, rank, floor_index, step)
	var taken: Dictionary[Vector3i, bool] = {}
	for id: StringName in room_cells:
		taken[room_cells[id]] = true

	# Клетка перед дверью -> { ветка, сторона тайла, смотрящая в комнату }.
	var door_at: Dictionary[Vector3i, Dictionary] = {}
	var door_sides: Dictionary[StringName, Dictionary] = {}
	for room in rooms:
		var sides := RS_RoomLayout.door_sides_of_scene(room.room_scene_path).duplicate()
		sides.sort()
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
		var room_cell: Vector3i = room_cells[room.id]
		for side: int in paired:
			var cell := topology.neighbour(room_cell, side)
			door_at[cell] = {"branch": paired[side], "face": topology.back_side(room_cell, side)}
		door_sides[room.id] = paired

	var bounds := _bounds(room_cells.values())
	var owner: Dictionary[Vector3i, StringName] = {}
	var masks: Dictionary[Vector3i, int] = {}
	for branch in branches:
		_route_branch(topology, failures, branch, on_floor, rank, taken, door_at, owner, masks, bounds)
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
	floor_index: int,
	step: int,
) -> Dictionary[StringName, Vector3i]:
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
	var cells: Dictionary[StringName, Vector3i] = {}
	for i in ordered.size():
		var row := i / cols
		var col := i % cols
		if row % 2 == 1:
			col = cols - 1 - col
		cells[(ordered[i] as RS_LevelNode).id] = Vector3i(col * step, floor_index, row * step)
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


## Прокладывает ветку: сперва её первая дверь соединяется со стыком
## родительской ветки (у корня — просто встаёт первым тайлом), потом каждая
## следующая дверь — с уже проложенной частью. Трасса не заходит в комнаты, в
## чужие коридоры и в клетки перед чужими дверями: касание там открыло бы
## проход, которого в графе нет.
static func _route_branch(
	topology: GridTopology,
	failures: Array[String],
	branch: RS_LevelNode,
	on_floor: Dictionary[StringName, RS_LevelNode],
	rank: Dictionary[StringName, int],
	taken: Dictionary[Vector3i, bool],
	door_at: Dictionary[Vector3i, Dictionary],
	owner: Dictionary[Vector3i, StringName],
	masks: Dictionary[Vector3i, int],
	bounds: Rect2i,
) -> void:
	var terminals: Array[Vector3i] = []
	for cell: Vector3i in door_at:
		if door_at[cell]["branch"] == branch.id:
			terminals.append(cell)
	terminals.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.z < b.z if a.z != b.z else a.x < b.x)
	if terminals.is_empty():
		failures.append("%s: ни одной двери" % branch.id)
		return

	var parent := _parent_branch(branch, on_floor, rank)
	var passable := func(cell: Vector3i) -> bool:
		if taken.has(cell):
			return false
		if owner.has(cell) and owner[cell] != branch.id:
			return false
		return not door_at.has(cell) or door_at[cell]["branch"] == branch.id

	var start: Vector3i = terminals[0]
	if parent != &"":
		var path := _search(topology, start, func(c): return owner.get(c, &"") == parent, passable, bounds)
		if path.is_empty():
			failures.append("%s: не дотянулся до %s" % [branch.id, parent])
		else:
			_claim(topology, path, branch.id, owner, masks, true)
	else:
		_claim(topology, [start], branch.id, owner, masks, false)

	for i in range(1, terminals.size()):
		var terminal := terminals[i]
		if owner.get(terminal, &"") == branch.id:
			continue  # трасса уже прошла через эту клетку
		var path := _search(
			topology, terminal, func(c): return owner.get(c, &"") == branch.id, passable, bounds
		)
		if path.is_empty():
			failures.append("%s: не дотянулся до двери в %s" % [branch.id, terminal])
		else:
			_claim(topology, path, branch.id, owner, masks, true)

	# Проём к комнате — на каждой клетке перед дверью этой ветки.
	for cell in terminals:
		if owner.get(cell, &"") == branch.id:
			masks[cell] = masks.get(cell, 0) | (1 << (door_at[cell]["face"] as int))


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


## Трасса от [param start] до первой клетки, где [param goal] истинна
## (GridRouter.find_path). Сперва в пределах решётки с запасом ROUTE_MARGIN,
## затем запас растёт: обход по краю лучше, чем отказ.
static func _search(
	topology: GridTopology, start: Vector3i, goal: Callable, passable: Callable, bounds: Rect2i
) -> Array[Vector3i]:
	var margin := ROUTE_MARGIN
	while margin <= MAX_ROUTE_MARGIN:
		var area := bounds.grow(margin)
		var within := func(cell: Vector3i) -> bool:
			return area.has_point(Vector2i(cell.x, cell.z)) and passable.call(cell)
		var path := GridRouter.find_path(topology, start, goal, within, TURN_COST)
		if not path.is_empty():
			return path
		margin += 3
	return []


## Занимает клетки пути за веткой и открывает проёмы между соседними клетками
## пути. [param ends_in_existing] — последняя клетка уже чья-то (своя трасса или
## родительская ветка): её не занимаем, но проём к ней открываем с обеих
## сторон — это и есть стык.
static func _claim(
	topology: GridTopology,
	path: Array,
	branch_id: StringName,
	owner: Dictionary[Vector3i, StringName],
	masks: Dictionary[Vector3i, int],
	ends_in_existing: bool,
) -> void:
	var last_own := path.size() - (1 if ends_in_existing else 0)
	for i in last_own:
		owner[path[i]] = branch_id
		if not masks.has(path[i]):
			masks[path[i]] = 0
	for i in range(path.size() - 1):
		var a: Vector3i = path[i]
		var b: Vector3i = path[i + 1]
		var side := topology.side_toward(a, b)
		masks[a] = masks.get(a, 0) | (1 << side)
		masks[b] = masks.get(b, 0) | (1 << topology.back_side(a, side))


## Прямоугольник решётки комнат в плоскости этажа (X, Z) — от него отмеряется
## запас, по которому может пройти трасса.
static func _bounds(cells: Array) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var first: Vector3i = cells[0]
	var rect := Rect2i(Vector2i(first.x, first.z), Vector2i.ZERO)
	for cell: Vector3i in cells:
		rect = rect.expand(Vector2i(cell.x, cell.z))
	return rect


static func _put(plan: RS_LayerPlan, id: StringName, cell: Vector3i) -> void:
	plan.cells[id] = cell
	plan.node_by_cell[cell] = id
