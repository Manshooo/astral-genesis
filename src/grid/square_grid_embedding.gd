## res://src/grid/square_grid_embedding.gd
## Квадратная сетка в мире: клетка cell_size по X и Z, уровни через level_height по Y (у куба совпадут, но заданы порознь).
@tool
class_name SquareGridEmbedding
extends GridEmbedding

## Сторона клетки в метрах.
var cell_size: float
## Шаг уровней по высоте в метрах.
var level_height: float
## Допуск ниже пола уровня, в долях level_height: origin стоящего на полу бывает чуть ниже.
var level_tolerance: float


func _init(p_cell_size: float, p_level_height: float, p_level_tolerance: float = 0.0) -> void:
	cell_size = p_cell_size
	level_height = p_level_height
	level_tolerance = p_level_tolerance


func cell_origin(cell: Vector3i) -> Vector3:
	return Vector3(cell.x * cell_size, cell.y * level_height, cell.z * cell_size)


func cell_at(world_position: Vector3) -> Vector3i:
	var point := grid_point(world_position)
	return Vector3i(roundi(point.x), floori(point.y + level_tolerance), roundi(point.z))


## Грань — сторона квадрата: середина на полпути к соседу, концы по полклетки вдоль; стороны те же, что у SquareGridTopology.OFFSETS.
func face_edge(cell: Vector3i, side: int) -> PackedVector3Array:
	var offset := Vector3(SquareGridTopology.OFFSETS[side])
	var mid := cell_origin(cell) + offset * cell_size * 0.5
	var along := Vector3(-offset.z, 0.0, offset.x) * cell_size * 0.5
	return PackedVector3Array([mid - along, mid + along])


## Точка мира в координатах сетки (дробная: центр клетки — целые) — маркеру игрока на карте.
func grid_point(world_position: Vector3) -> Vector3:
	return Vector3(
		world_position.x / cell_size, world_position.y / level_height, world_position.z / cell_size
	)


## Поворот на turns четвертей против часовой сверху (как rotation.y = turns·π/2); стороны топологии идут по часовой, поэтому в rotate_side −turns.
func turn_basis(turns: int) -> Basis:
	return Basis(Vector3.UP, turns * PI * 0.5)
