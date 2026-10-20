## res://src/grid/grid_embedding.gd
## Вложение сетки в мир: где клетка в метрах и в какой клетке точка. Единственное место, где сетка знает о мире;
## смена размера клетки — подмена вложения. Вики: [[Цикл забега]] (сетка уровня).
@tool
@abstract
class_name GridEmbedding
extends RefCounted


## Точка мира клетки — центр её пола.
@abstract func cell_origin(cell: Vector3i) -> Vector3


## Клетка, в которой лежит точка мира.
@abstract func cell_at(world_position: Vector3) -> Vector3i


## Грань клетки за стороной side в мире — отрезок на полу, два конца. Концы знает только вложение (у гекса короче, на шаре кривая).
@abstract func face_edge(cell: Vector3i, side: int) -> PackedVector3Array
