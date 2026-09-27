## res://src/grid/grid_topology.gd
## Топология сетки: какие у клетки стороны и кто за какой стороной сосед. Ни
## размера клетки, ни мировых координат здесь нет — это вложение (GridEmbedding),
## и генерация, которая работает только с топологией, мира не видит вовсе.
##
## Клетка — Vector3i: .y — уровень, .x и .z — место в плоскости уровня, и как их
## толковать, решает конкретная топология. Соседи — только в плоскости уровня:
## уровни между собой сетка не связывает, это дело того, что на ней стоит.
##
## Сторона — индекс внутри клетки, а не «север». Интерфейс писался с запасом на
## гексы на шаре, где у двенадцати клеток пять сторон, а глобального севера нет
## вовсе, поэтому число сторон спрашивается у клетки, а «прямо» — это
## противоположная сторона той же клетки, а не тот же шаг ещё раз.
##
## Папка src/grid/ не знает об игре — ни узлов графа, ни автолоадов, — чтобы её
## можно было вынести в аддон.
@tool
@abstract
class_name GridTopology
extends RefCounted

## Стороны нет: сосед не граничит, напротив ничего.
const NO_SIDE := -1


## Сколько сторон у клетки.
@abstract func side_count(cell: Vector3i) -> int


## Клетка за стороной [param side].
@abstract func neighbour(cell: Vector3i, side: int) -> Vector3i


## Сторона соседа за [param side], которой он смотрит обратно на [param cell].
@abstract func back_side(cell: Vector3i, side: int) -> int


## Сторона той же клетки напротив [param side] — выход «прямо» для того, кто
## вошёл через side. NO_SIDE — напротив ничего нет, и любой выход считается
## поворотом.
@abstract func opposite(cell: Vector3i, side: int) -> int


## Сторона [param side] клетки после поворота на [param steps] шагов — сдвиг
## индекса по кругу сторон, в порядке их индексов; отрицательные шаги — в
## обратную сторону. Сколько шагов в полном обороте, решает число сторон клетки:
## на квадрате четыре, на гексе шесть. NO_SIDE остаётся NO_SIDE.
func rotate_side(cell: Vector3i, side: int, steps: int) -> int:
	if side == NO_SIDE:
		return NO_SIDE
	return posmod(side + steps, side_count(cell))


## Сторона [param cell], за которой лежит [param other], или NO_SIDE, если они не
## соседи.
func side_toward(cell: Vector3i, other: Vector3i) -> int:
	for side in side_count(cell):
		if neighbour(cell, side) == other:
			return side
	return NO_SIDE


## Грани нижнего уровня набора клеток, смотрящие наружу: сторона клетки, за
## которой уже не этот набор. Для размещения это сокеты footprint — места, где
## может быть проём. Порядок — порядок клеток, внутри клетки — порядок сторон: от
## него зависит, какие сокеты займёт размещение, а оно обязано быть одним и тем же
## от запуска к запуску.
func perimeter(cells: Array[Vector3i]) -> Array[Vector4i]:
	var faces: Array[Vector4i] = []
	if cells.is_empty():
		return faces
	var bottom := cells[0].y
	for cell in cells:
		bottom = mini(bottom, cell.y)
	for cell in cells:
		if cell.y != bottom:
			continue
		for side in side_count(cell):
			if not cells.has(neighbour(cell, side)):
				faces.append(face(cell, side))
	return faces


## Грань — сторона конкретной клетки. Vector4i, а не пара, чтобы грань, как и
## клетка, годилась ключом словаря.
static func face(cell: Vector3i, side: int) -> Vector4i:
	return Vector4i(cell.x, cell.y, cell.z, side)


static func face_cell(face_key: Vector4i) -> Vector3i:
	return Vector3i(face_key.x, face_key.y, face_key.z)
