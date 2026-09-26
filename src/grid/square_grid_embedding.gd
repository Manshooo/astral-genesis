## res://src/grid/square_grid_embedding.gd
## Квадратная сетка в мире: клетка — квадрат cell_size по X и Z, уровни — друг
## над другом через level_height по Y. Горизонталь и вертикаль заданы порознь:
## у клетки-куба они совпадут, но сетка обязана уметь и уровни выше клетки.
@tool
class_name SquareGridEmbedding
extends GridEmbedding

## Сторона клетки в метрах.
var cell_size: float
## Шаг уровней по высоте в метрах.
var level_height: float
## На сколько ниже пола уровня точка ещё принадлежит ему — в долях
## level_height. То, что стоит на полу, своим origin бывает чуть ниже него, и без
## запаса на границе округления уезжало бы уровнем ниже.
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


## Точка мира в координатах сетки — дробная: центр клетки в целых, граница на
## половинах. Нужна тому, что рисует сетку в клетках, а живёт между ними, —
## маркеру игрока на карте.
func grid_point(world_position: Vector3) -> Vector3:
	return Vector3(
		world_position.x / cell_size, world_position.y / level_height, world_position.z / cell_size
	)
