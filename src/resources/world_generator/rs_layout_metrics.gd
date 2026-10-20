## res://src/resources/world_generator/rs_layout_metrics.gd
## Метрики коридорной раскладки (обволакивание комнат, обходные пути, тупики; карточка «Сетка уровня»): по ним выбиралась раскладка и ловится
## регресс. Одно место счёта на прогон сидов «Генератора мира» и corridor_layout_check — иначе цифры разошлись бы с порогом.
## Считается по плану слоя без спавна; метрики планов складываются (add).
@tool
class_name RS_LayoutMetrics
extends RefCounted

## Кусок кита по числу и взаимному положению проёмов.
enum Piece { END, STRAIGHT, CORNER, TEE, CROSS }

const PIECE_NAMES: Array[String] = ["тупик", "прямой", "поворот", "Т", "крест"]
## Со скольких сторон кусок в поясе комнаты её огибает (wraps).
const WRAP_SIDES := 3

## Этажей с хотя бы одним узлом.
var floors := 0
var rooms := 0
## Комнаты, которые коридор огибает вплотную (wraps): кусок сети в поясе связывает две её двери или подходит с трёх сторон. До 08.10 считались
## коридоры с трёх сторон — цифра держалась на 0 %, а у 61 % комнат коридор огибал угол между соседними дверями.
var enveloped_rooms := 0
## Сквозные комнаты: двери на противоположных сторонах ведут в разные коридоры.
var through_rooms := 0
## Двери, разыгранные пресетом, но не поставленные (RS_LayerPlan.dropped_doors).
var dropped_doors := 0
var tiles := 0
## Коридоров — узлов графа (отрезков сети между развилками).
var corridors := 0
## Piece -> сколько тайлов.
var pieces: Dictionary[int, int] = {}
## Обходные пути: независимые циклы графа узлов этажа (комнаты, коридоры; связи «комната–коридор» без повторов и стыки коридоров). Две двери комнаты
## в один коридор петлёй не считаются — это не другой путь.
var loops := 0
## Петли по самому коридору — циклы тайлов по проёмам; такая петля проходит ≥2 развилок и попадает и в loops.
var corridor_loops := 0
## Тупики — концы отростков, отмеченные раскладкой.
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

	# Комнаты — ключи door_faces: планировщик пишет туда каждую, даже без дверей.
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


## Кусок кита под маску проёмов (бит стороны — 1 << индекс).
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


## Пояс комнаты на уровне level: клетки перед её наружными гранями (-> сторона) и углы (-> NO_SIDE) — всё вплотную к комнате; через угол коридор огибает комнату.
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


## Огибает ли коридор комнату вплотную: связный по проёмам кусок сети в поясе ring связывает две двери (door_fronts) или подходит с WRAP_SIDES сторон.
## По поясу, а не по числу сторон (с четырёх — перекрёсток). Одно правило на раскладку (RS_CorridorPlanner._envelops) и метрику.
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


## Сквозная ли комната: двери на противоположных сторонах ведут в разные коридоры.
static func _is_through(plan: RS_LayerPlan, room: StringName) -> bool:
	var faces: Dictionary = plan.door_faces.get(room, {})
	for a: Vector4i in faces:
		for b: Vector4i in faces:
			if a.y == b.y and faces[a] != faces[b] \
					and plan.topology.opposite(GridTopology.face_cell(a), a.w) == b.w:
				return true
	return false


## Обходные пути слоя: цикломатическое число графа узлов (рёбра − вершины + компоненты); этажи по сетке не связаны, сумма по слою — по этажам.
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


## Петли по коридору: цикломатическое число графа тайлов по проёмам.
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


## Сколько связных кусков у графа: вершины vertices, соседи — links.
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
