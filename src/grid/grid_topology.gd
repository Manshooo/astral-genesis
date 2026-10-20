## res://src/grid/grid_topology.gd
## Топология сетки: стороны клетки и соседи за ними, без размера и мировых координат (это GridEmbedding).
## Клетка — Vector3i (.y — уровень), соседи только в плоскости уровня. Сторона — индекс, не «север»: число сторон
## спрашивается у клетки, «прямо» — противоположная сторона. src/grid/ не знает об игре. Вики: [[Цикл забега]].
@tool
@abstract
class_name GridTopology
extends RefCounted

## Стороны нет.
const NO_SIDE := -1


## Сколько сторон у клетки.
@abstract func side_count(cell: Vector3i) -> int


## Клетка за стороной [param side].
@abstract func neighbour(cell: Vector3i, side: int) -> Vector3i


## Сторона соседа за side, смотрящая обратно на cell.
@abstract func back_side(cell: Vector3i, side: int) -> int


## Сторона напротив side — выход «прямо»; NO_SIDE — напротив ничего, любой выход поворот.
@abstract func opposite(cell: Vector3i, side: int) -> int


## Нижняя оценка шагов между клетками; 0 верна на любой сетке, точная позволяет отбросить заведомо длинную трассу.
func min_steps(_from: Vector3i, _to: Vector3i) -> int:
	return 0


## Сторона после поворота на steps шагов по кругу сторон (отрицательные — назад); NO_SIDE остаётся NO_SIDE.
func rotate_side(cell: Vector3i, side: int, steps: int) -> int:
	if side == NO_SIDE:
		return NO_SIDE
	return posmod(side + steps, side_count(cell))


## Сторона cell, за которой лежит other, или NO_SIDE.
func side_toward(cell: Vector3i, other: Vector3i) -> int:
	for side in side_count(cell):
		if neighbour(cell, side) == other:
			return side
	return NO_SIDE


## Грани нижнего уровня набора клеток, смотрящие наружу — сокеты footprint. Порядок (клетки, затем стороны)
## определяет, какие сокеты займёт размещение, и обязан быть стабильным.
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


## Грань — сторона конкретной клетки; Vector4i, чтобы годилась ключом словаря.
static func face(cell: Vector3i, side: int) -> Vector4i:
	return Vector4i(cell.x, cell.y, cell.z, side)


static func face_cell(face_key: Vector4i) -> Vector3i:
	return Vector3i(face_key.x, face_key.y, face_key.z)
