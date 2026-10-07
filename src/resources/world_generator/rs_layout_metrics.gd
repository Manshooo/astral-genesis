## res://src/resources/world_generator/rs_layout_metrics.gd
## Метрики коридорной раскладки — то, чем карточка «Сетка уровня» меряет
## обволакивание комнат коридором, обходные пути и тупики. По ним выбиралась
## раскладка сетью (п. 7) и по ним же ловится правка, от которой стало хуже.
##
## Одно место счёта на прогон сидов «Генератора мира» и на corridor_layout_check:
## посчитай они каждый по-своему — и цифры в туле разошлись бы с порогом проверки.
##
## Считается по плану слоя, без спавна и мира: только клетки, стороны топологии и
## маски проёмов. Метрики одного плана складываются в сумму по прогону (add).
@tool
class_name RS_LayoutMetrics
extends RefCounted

## Кусок кита, который встанет на тайл, — по числу и взаимному положению проёмов.
enum Piece { END, STRAIGHT, CORNER, TEE, CROSS }

const PIECE_NAMES: Array[String] = ["тупик", "прямой", "поворот", "Т", "крест"]
## Со скольких сторон кусок коридора в поясе комнаты её огибает (wraps): с трёх
## сторон из четырёх коридор уже обходит комнату, а не подходит к ней.
const WRAP_SIDES := 3

## Этажей с хотя бы одним узлом.
var floors := 0
var rooms := 0
## Комнаты, которые коридор огибает вплотную (wraps): кусок сети в поясе вокруг
## комнаты связывает две её двери или подходит к ней с трёх сторон.
##
## До 08.10 считались комнаты, к которым с трёх сторон подходят её коридоры, все
## вместе. Цифра держалась на 0 %, а игрок видел обратное: у 61 % комнат свой
## коридор огибал угол и связывал две соседние двери — с двух сторон, мимо
## порога. А с дверью на каждую сторону коридоры с трёх сторон — это уже
## перекрёсток, а не обволакивание.
var enveloped_rooms := 0
## Сквозные комнаты: двери на противоположных сторонах ведут в разные коридоры —
## вошёл в одну, вышел из другой в другое место.
var through_rooms := 0
## Двери, разыгранные пресетом, которые раскладка не поставила
## (RS_LayerPlan.dropped_doors).
var dropped_doors := 0
var tiles := 0
## Коридоров — узлов графа: отрезков сети между развилками (карточка «Коридор —
## отдельный узел»).
var corridors := 0
## Piece -> сколько тайлов.
var pieces: Dictionary[int, int] = {}
## Обходные пути: независимые циклы графа узлов этажа — комнаты и коридоры, связи
## — «комната–коридор» (сколько бы дверей ни вело в один коридор, это одна связь) и
## стыки коридоров. Столько раз можно прийти в место другой дорогой, не
## возвращаясь по своим следам. Две двери комнаты в один коридор петлёй здесь не
## считаются: вошёл в одну, вышел в соседнюю — это не другой путь (до п. 7 карточки
## «Сетка уровня» считались, и такие «петли» были почти все).
var loops := 0
## Петли по самому коридору — циклы тайлов по проёмам, без прохода через комнаты.
## Петля по сети проходит хотя бы через две развилки, а с тех пор как коридор —
## отрезок между развилками, она попадает и в loops.
var corridor_loops := 0
## Тупики — отмеченные раскладкой концы отростков (RS_LayerPlan.dead_ends).
var dead_ends := 0


## Метрики одного плана слоя.
static func of_plan(plan: RS_LayerPlan) -> RS_LayoutMetrics:
	var metrics := RS_LayoutMetrics.new()
	var floor_levels := {}
	for id: StringName in plan.cells:
		floor_levels[plan.cells[id].y] = true
	metrics.floors = floor_levels.size()

	var corridor_ids := {}
	for cell: Vector3i in plan.corridor_tiles:
		metrics.tiles += 1
		corridor_ids[plan.node_by_cell[cell]] = true
		var piece := piece_of(plan.corridor_tiles[cell])
		metrics.pieces[piece] = metrics.pieces.get(piece, 0) + 1
	metrics.corridors = corridor_ids.size()

	# Комнаты — ключи door_faces: планировщик пишет туда каждую комнату слоя, даже
	# без дверей в коридор.
	for room: StringName in plan.door_faces:
		metrics.rooms += 1
		if wrapped_in_plan(plan, room):
			metrics.enveloped_rooms += 1
		if _is_through(plan, room):
			metrics.through_rooms += 1
	metrics.dropped_doors = plan.dropped_doors

	metrics.loops = _node_loops(plan)
	metrics.corridor_loops = _tile_loops(plan)
	metrics.dead_ends = plan.dead_ends.size()
	return metrics


## Прибавляет метрики другого плана — сумма по прогону сидов.
func add(other: RS_LayoutMetrics) -> void:
	floors += other.floors
	rooms += other.rooms
	enveloped_rooms += other.enveloped_rooms
	through_rooms += other.through_rooms
	dropped_doors += other.dropped_doors
	tiles += other.tiles
	corridors += other.corridors
	loops += other.loops
	corridor_loops += other.corridor_loops
	dead_ends += other.dead_ends
	for piece: int in other.pieces:
		pieces[piece] = pieces.get(piece, 0) + other.pieces[piece]


## Кусок кита под маску проёмов (бит стороны — 1 << её индекс).
static func piece_of(mask: int) -> Piece:
	var open := 0
	for side in SquareGridTopology.SIDE_COUNT:
		if mask & (1 << side):
			open += 1
	match open:
		1:
			return Piece.END
		2:
			# Противоположные стороны квадрата — индексы через один.
			var straight := (1 << SquareGridTopology.Side.NORTH) | (1 << SquareGridTopology.Side.SOUTH)
			var across := (1 << SquareGridTopology.Side.EAST) | (1 << SquareGridTopology.Side.WEST)
			return Piece.STRAIGHT if mask == straight or mask == across else Piece.CORNER
		3:
			return Piece.TEE
	return Piece.CROSS


func enveloped_share() -> float:
	return float(enveloped_rooms) / maxi(rooms, 1)


func through_share() -> float:
	return float(through_rooms) / maxi(rooms, 1)


func tiles_per_room() -> float:
	return float(tiles) / maxi(rooms, 1)


func tiles_per_floor() -> float:
	return float(tiles) / maxi(floors, 1)


func corridors_per_floor() -> float:
	return float(corridors) / maxi(floors, 1)


func piece_share(piece: Piece) -> float:
	return float(pieces.get(piece, 0)) / maxi(tiles, 1)


func loops_per_floor() -> float:
	return float(loops) / maxi(floors, 1)


func corridor_loops_per_floor() -> float:
	return float(corridor_loops) / maxi(floors, 1)


func dead_ends_per_floor() -> float:
	return float(dead_ends) / maxi(floors, 1)


## Сводка строками — одна и та же в туле и в выводе проверки.
func report_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("обволакиваемых комнат  %5.1f%%  (%d из %d; коридор вплотную вокруг: две её двери или %d+ стороны)" % [
		100.0 * enveloped_share(), enveloped_rooms, rooms, WRAP_SIDES
	])
	lines.append("сквозных комнат        %5.1f%%  (двери напротив друг друга, в разные коридоры)" % [
		100.0 * through_share()
	])
	lines.append("снято дверей           %5d   (запасной двери некуда вести)" % dropped_doors)
	lines.append("тайлов на комнату      %5.2f   (на этаж %.1f)" % [tiles_per_room(), tiles_per_floor()])
	lines.append("коридоров на этаж      %5.2f   (тайлов в коридоре %.1f)" % [
		corridors_per_floor(), float(tiles) / maxi(corridors, 1)
	])
	lines.append(
		"обходов по графу       %5.2f   на этаж (комната на двух коридорах, кольцо коридоров)" % loops_per_floor()
	)
	lines.append("петель по коридору     %5.2f   на этаж" % corridor_loops_per_floor())
	lines.append("тупиков                %5.2f   на этаж" % dead_ends_per_floor())
	for piece in Piece.values():
		lines.append("%-10s %6d  %5.1f%%" % [PIECE_NAMES[piece], pieces.get(piece, 0), 100.0 * piece_share(piece)])
	return lines


## Пояс комнаты на уровне [param level]: клетки перед её наружными гранями (->
## сторона грани) и углы между ними (-> GridTopology.NO_SIDE) — всё, что вплотную
## к комнате. Угол — клетка снаружи, соседняя с двумя клетками перед гранями:
## через неё коридор огибает комнату, ни разу не встав перед её гранью.
static func ring_of(topology: GridTopology, cells: Array[Vector3i], level: int) -> Dictionary[Vector3i, int]:
	var inside: Dictionary[Vector3i, bool] = {}
	for cell in cells:
		inside[cell] = true
	var ring: Dictionary[Vector3i, int] = {}
	for cell in cells:
		if cell.y != level:
			continue
		for side in topology.side_count(cell):
			var next := topology.neighbour(cell, side)
			if not inside.has(next):
				ring[next] = side
	var touches: Dictionary[Vector3i, int] = {}
	for cell: Vector3i in ring:
		for side in topology.side_count(cell):
			var next := topology.neighbour(cell, side)
			if not inside.has(next) and not ring.has(next):
				touches[next] = touches.get(next, 0) + 1
	for cell: Vector3i in touches:
		if touches[cell] >= 2:
			ring[cell] = GridTopology.NO_SIDE
	return ring


## Огибает ли коридор комнату вплотную: связный по проёмам кусок сети в её поясе
## [param ring] (ring_of) связывает две её двери (клетки перед ними —
## [param door_fronts]) или подходит к ней с WRAP_SIDES сторон. [param is_tile] —
## клетка ли сети, [param linked] — открыт ли проём между двумя клетками сети.
##
## По поясу, а не по тому, со скольких сторон подходят её коридоры: у комнаты с
## дверью на каждой стороне коридоры с четырёх сторон — перекрёсток, а коридор,
## обогнувший угол от двери к соседней двери, касается только двух — и именно его
## игрок видит обволакиванием. Одно правило на раскладку
## (RS_CorridorPlanner._envelops) и на метрику, иначе раскладка сторожила бы не
## то, что меряет порог проверки.
static func wraps(ring: Dictionary[Vector3i, int], door_fronts: Array[Vector3i], is_tile: Callable, linked: Callable) -> bool:
	var seen: Dictionary[Vector3i, bool] = {}
	for start: Vector3i in ring:
		if seen.has(start) or not is_tile.call(start):
			continue
		seen[start] = true
		var piece: Array[Vector3i] = [start]
		var i := 0
		while i < piece.size():
			var cell := piece[i]
			i += 1
			for next: Vector3i in ring:
				if not seen.has(next) and linked.call(cell, next):
					seen[next] = true
					piece.append(next)
		var sides: Dictionary[int, bool] = {}
		var doors := 0
		for cell in piece:
			if ring[cell] != GridTopology.NO_SIDE:
				sides[ring[cell]] = true
			if door_fronts.has(cell):
				doors += 1
		if doors >= 2 or sides.size() >= WRAP_SIDES:
			return true
	return false


## wraps по готовому плану: на каждом уровне комнаты, где у неё есть двери.
static func wrapped_in_plan(plan: RS_LayerPlan, room: StringName) -> bool:
	var faces: Dictionary = plan.door_faces.get(room, {})
	var by_level: Dictionary[int, Array] = {}
	for face: Vector4i in faces:
		by_level.get_or_add(face.y, []).append(plan.topology.neighbour(GridTopology.face_cell(face), face.w))
	var is_tile := func(cell: Vector3i) -> bool: return plan.corridor_tiles.has(cell)
	var linked := func(a: Vector3i, b: Vector3i) -> bool:
		if not plan.corridor_tiles.has(a) or not plan.corridor_tiles.has(b):
			return false
		var side := plan.topology.side_toward(a, b)
		return side != GridTopology.NO_SIDE and plan.corridor_tiles[a] & (1 << side) != 0
	for level: int in by_level:
		var fronts: Array[Vector3i] = []
		fronts.assign(by_level[level])
		if wraps(ring_of(plan.topology, plan.room_cells(room), level), fronts, is_tile, linked):
			return true
	return false


## Сквозная ли комната: две двери на противоположных сторонах ведут в разные
## коридоры.
static func _is_through(plan: RS_LayerPlan, room: StringName) -> bool:
	var faces: Dictionary = plan.door_faces.get(room, {})
	for a: Vector4i in faces:
		for b: Vector4i in faces:
			if a.y == b.y and faces[a] != faces[b] \
					and plan.topology.opposite(GridTopology.face_cell(a), a.w) == b.w:
				return true
	return false


## Обходные пути слоя (см. loops): цикломатическое число графа узлов — рёбер −
## вершин + компонент. Вершины — комнаты и ветки, рёбра — пары «комната–ветка» без
## повторов и стыки веток. Этажи между собой по сетке не связаны (порталы — не
## проёмы), так что сумма по слою — это сумма по его этажам.
static func _node_loops(plan: RS_LayerPlan) -> int:
	var vertices: Dictionary[StringName, bool] = {}
	var edges: Dictionary[String, Array] = {}
	for room: StringName in plan.door_faces:
		vertices[room] = true
		for branch: StringName in (plan.door_faces[room] as Dictionary).values():
			vertices[branch] = true
			edges["%s|%s" % [room, branch]] = [room, branch]
	for tile: Vector3i in plan.corridor_tiles:
		vertices[plan.node_by_cell[tile]] = true
	for joint: Array in plan.branch_joints():
		edges["%s|%s" % joint] = joint
	var links: Dictionary = {}
	for key: String in edges:
		var pair: Array = edges[key]
		links.get_or_add(pair[0], []).append(pair[1])
		links.get_or_add(pair[1], []).append(pair[0])
	return edges.size() - vertices.size() + _components(vertices.keys(), links)


## Петли по коридору: цикломатическое число графа тайлов, рёбра — проёмы между
## соседними тайлами.
static func _tile_loops(plan: RS_LayerPlan) -> int:
	var links: Dictionary = {}
	var edges := 0
	for cell: Vector3i in plan.corridor_tiles:
		var mask: int = plan.corridor_tiles[cell]
		for side in plan.topology.side_count(cell):
			var next := plan.topology.neighbour(cell, side)
			if mask & (1 << side) and plan.corridor_tiles.has(next):
				links.get_or_add(cell, []).append(next)
				edges += 1
	edges /= 2  # каждый проём записан с обоих концов
	return edges - plan.corridor_tiles.size() + _components(plan.corridor_tiles.keys(), links)


## Сколько связных кусков у графа: вершины [param vertices], соседи — [param links].
static func _components(vertices: Array, links: Dictionary) -> int:
	var components := 0
	var seen := {}
	for start in vertices:
		if seen.has(start):
			continue
		components += 1
		seen[start] = true
		var stack: Array = [start]
		while not stack.is_empty():
			var vertex = stack.pop_back()
			for next in links.get(vertex, []):
				if not seen.has(next):
					seen[next] = true
					stack.append(next)
	return components
