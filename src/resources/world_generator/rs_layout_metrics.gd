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
## Со скольких сторон к комнате должны подходить её собственные коридоры, чтобы
## комната считалась обволакиваемой: с трёх сторон из четырёх коридор уже обходит
## комнату, а не подходит к ней.
const ENVELOPED_SIDES := 3

## Этажей с хотя бы одним узлом.
var floors := 0
var rooms := 0
## Комнаты, к которым с ENVELOPED_SIDES и больше сторон подходят их же коридоры
## (те, в которые ведут их двери), — все вместе, а не каждый порознь.
var enveloped_rooms := 0
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
		if _own_branch_sides(plan, room) >= ENVELOPED_SIDES:
			metrics.enveloped_rooms += 1

	metrics.loops = _node_loops(plan)
	metrics.corridor_loops = _tile_loops(plan)
	metrics.dead_ends = plan.dead_ends.size()
	return metrics


## Прибавляет метрики другого плана — сумма по прогону сидов.
func add(other: RS_LayoutMetrics) -> void:
	floors += other.floors
	rooms += other.rooms
	enveloped_rooms += other.enveloped_rooms
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
	lines.append("обволакиваемых комнат  %5.1f%%  (%d из %d; свои коридоры с %d+ сторон)" % [
		100.0 * enveloped_share(), enveloped_rooms, rooms, ENVELOPED_SIDES
	])
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


## Со скольких сторон к комнате подходят тайлы коридоров, в которые ведут её двери.
## По сторонам, а не по клеткам: у комнаты в несколько клеток на одной стороне
## несколько соседей, а обволакивание — это коридор вокруг, а не вдоль одной стены.
static func _own_branch_sides(plan: RS_LayerPlan, room: StringName) -> int:
	var own: Array = (plan.door_faces[room] as Dictionary).values()
	var sides := {}
	for face in plan.topology.perimeter(plan.room_cells(room)):
		var next := plan.topology.neighbour(GridTopology.face_cell(face), face.w)
		if plan.corridor_tiles.has(next) and own.has(plan.node_by_cell.get(next, &"")):
			sides[face.w] = true
	return sides.size()


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
