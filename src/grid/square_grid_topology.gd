## res://src/grid/square_grid_topology.gd
## Квадратная сетка: четыре стороны у каждой клетки, соседи по осям X и Z.
@tool
class_name SquareGridTopology
extends GridTopology

## Стороны по часовой сверху: −Z, +X, +Z, −X. Порядок — контракт: бит стороны в маске проёмов — 1 << индекс (data/corridor_kit.tres).
enum Side { NORTH, EAST, SOUTH, WEST }

const SIDE_COUNT := 4
## Смещение клетки за стороной — по индексу стороны.
const OFFSETS: Array[Vector3i] = [
	Vector3i(0, 0, -1),
	Vector3i(1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(-1, 0, 0),
]


func side_count(_cell: Vector3i) -> int:
	return SIDE_COUNT


func neighbour(cell: Vector3i, side: int) -> Vector3i:
	return cell + OFFSETS[side]


func back_side(_cell: Vector3i, side: int) -> int:
	return (side + 2) % SIDE_COUNT


func opposite(_cell: Vector3i, side: int) -> int:
	return (side + 2) % SIDE_COUNT


func side_toward(cell: Vector3i, other: Vector3i) -> int:
	return OFFSETS.find(other - cell)


## Манхэттен в плоскости уровня.
func min_steps(from: Vector3i, to: Vector3i) -> int:
	return absi(to.x - from.x) + absi(to.z - from.z)


## Клетки footprint size (X, уровни Y, Z) от угловой anchor; порядок (уровни, Z, X) держит порядок сокетов (GridTopology.perimeter).
static func box(anchor: Vector3i, size: Vector3i) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for y in size.y:
		for z in size.z:
			for x in size.x:
				cells.append(anchor + Vector3i(x, y, z))
	return cells
