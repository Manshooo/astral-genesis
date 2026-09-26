## res://src/resources/world_generator/rs_layout_metrics.gd
## Метрики коридорной раскладки — то, чем карточка «Сетка уровня» меряет
## обволакивание комнат коридором. Снимаются на нынешнем генераторе, чтобы новому
## алгоритму раскладки было с чем сравниваться на тех же сидах.
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
## Со скольких сторон к комнате должна подходить её собственная ветка, чтобы
## комната считалась обволакиваемой: с трёх сторон из четырёх коридор уже обходит
## комнату, а не подходит к ней.
const ENVELOPED_SIDES := 3

## Этажей с хотя бы одним узлом.
var floors := 0
var rooms := 0
## Комнаты, к которым с ENVELOPED_SIDES и больше сторон подходит тайл их же ветки
## (веток, в которые ведут их двери).
var enveloped_rooms := 0
var tiles := 0
## Piece -> сколько тайлов.
var pieces: Dictionary[int, int] = {}
## Независимые циклы проходимого графа этажа (тайлы и комнаты, связи — проёмы и
## двери): столько раз можно обойти что-то по кругу, не возвращаясь по своим
## следам. Комната с двумя дверями в одну ветку — тоже петля: через неё можно
## пройти насквозь и вернуться коридором.
var loops := 0
## Те же петли, но только по коридору, без прохода через комнаты. Порознь потому,
## что у нынешнего генератора все петли — через комнаты (следствие «все двери
## комнаты в одну ветку»), а петли, которых ждёт карточка, — коридорные.
var corridor_loops := 0


## Метрики одного плана слоя.
static func of_plan(plan: RS_LayerPlan) -> RS_LayoutMetrics:
	var metrics := RS_LayoutMetrics.new()
	var floor_levels := {}
	for id: StringName in plan.cells:
		floor_levels[plan.cells[id].y] = true
	metrics.floors = floor_levels.size()

	for cell: Vector3i in plan.corridor_tiles:
		metrics.tiles += 1
		var piece := piece_of(plan.corridor_tiles[cell])
		metrics.pieces[piece] = metrics.pieces.get(piece, 0) + 1

	# Комнаты — ключи door_faces: планировщик пишет туда каждую комнату слоя, даже
	# без дверей в коридор.
	for room: StringName in plan.door_faces:
		metrics.rooms += 1
		if _own_branch_sides(plan, room) >= ENVELOPED_SIDES:
			metrics.enveloped_rooms += 1

	metrics.loops = _cycle_rank(plan, true)
	metrics.corridor_loops = _cycle_rank(plan, false)
	return metrics


## Прибавляет метрики другого плана — сумма по прогону сидов.
func add(other: RS_LayoutMetrics) -> void:
	floors += other.floors
	rooms += other.rooms
	enveloped_rooms += other.enveloped_rooms
	tiles += other.tiles
	loops += other.loops
	corridor_loops += other.corridor_loops
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


func piece_share(piece: Piece) -> float:
	return float(pieces.get(piece, 0)) / maxi(tiles, 1)


func loops_per_floor() -> float:
	return float(loops) / maxi(floors, 1)


func corridor_loops_per_floor() -> float:
	return float(corridor_loops) / maxi(floors, 1)


## Сводка строками — одна и та же в туле и в выводе проверки.
func report_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("обволакиваемых комнат  %5.1f%%  (%d из %d; своя ветка с %d+ сторон)" % [
		100.0 * enveloped_share(), enveloped_rooms, rooms, ENVELOPED_SIDES
	])
	lines.append("тайлов на комнату      %5.2f   (на этаж %.1f)" % [tiles_per_room(), tiles_per_floor()])
	lines.append("петель на этаж         %5.2f   (по коридору, без комнат, %.2f)" % [
		loops_per_floor(), corridor_loops_per_floor()
	])
	for piece in Piece.values():
		lines.append("%-10s %6d  %5.1f%%" % [PIECE_NAMES[piece], pieces.get(piece, 0), 100.0 * piece_share(piece)])
	return lines


## Со скольких сторон к комнате подходит тайл ветки, в которую ведут её двери. По
## сторонам, а не по клеткам: у комнаты в несколько клеток на одной стороне
## несколько соседей, а обволакивание — это коридор вокруг, а не вдоль одной стены.
static func _own_branch_sides(plan: RS_LayerPlan, room: StringName) -> int:
	var own: Array = (plan.door_faces[room] as Dictionary).values()
	var sides := {}
	for face in plan.topology.perimeter(plan.room_cells(room)):
		var next := plan.topology.neighbour(GridTopology.face_cell(face), face.w)
		if plan.corridor_tiles.has(next) and own.has(plan.node_by_cell.get(next, &"")):
			sides[face.w] = true
	return sides.size()


## Цикломатическое число проходимого графа слоя: рёбер − вершин + компонент.
## Вершины — тайлы (и комнаты, если [param with_rooms]), рёбра — открытые проёмы
## между тайлами и двери комнат в тайлы. Этажи между собой по сетке не связаны
## (порталы — не проёмы), так что сумма по слою — это сумма по его этажам.
static func _cycle_rank(plan: RS_LayerPlan, with_rooms: bool) -> int:
	var links: Dictionary[Vector3i, Array] = {}  # вершина -> соседи по проёмам
	for cell: Vector3i in plan.corridor_tiles:
		if not links.has(cell):
			links[cell] = []
		var mask: int = plan.corridor_tiles[cell]
		for side in plan.topology.side_count(cell):
			var next := plan.topology.neighbour(cell, side)
			if mask & (1 << side) and plan.corridor_tiles.has(next):
				links[cell].append(next)
	# Дверь — связь комнаты с тайлом перед ней. Комната — одна вершина, её угловая
	# клетка: у комнаты клетки свои, поэтому вершины тайлов и комнат не путаются.
	var rooms: Array = plan.door_faces.keys() if with_rooms else []
	for room: StringName in rooms:
		var cell: Vector3i = plan.cells[room]
		if not links.has(cell):
			links[cell] = []
		for face: Vector4i in plan.door_faces[room]:
			var front := plan.topology.neighbour(GridTopology.face_cell(face), face.w)
			if plan.corridor_tiles.has(front):
				links[cell].append(front)
				links[front].append(cell)

	var edges := 0
	for cell: Vector3i in links:
		edges += links[cell].size()
	edges /= 2  # каждая связь записана с обоих концов

	var components := 0
	var seen := {}
	for start: Vector3i in links:
		if seen.has(start):
			continue
		components += 1
		seen[start] = true
		var stack: Array[Vector3i] = [start]
		while not stack.is_empty():
			var cell: Vector3i = stack.pop_back()
			for next: Vector3i in links[cell]:
				if not seen.has(next):
					seen[next] = true
					stack.append(next)
	return edges - links.size() + components
