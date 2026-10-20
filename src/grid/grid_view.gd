## res://src/grid/grid_view.gd
## Узел сетки: рисует клетки топологии там, где их ставит вложение — решётку, контуры, отметки, стрелки. Представление
## поверх данных: комнат и коридоров не знает, что рисовать — говорит оверлей «Сетка». Концы граней даёт вложение
## (face_edge). Линии одним мешем (clear → add_* → commit): решётка слоя — сотни отрезков и пересобирается на каждый клик.
@tool
class_name GridView
extends Node3D

## Подъём линий над полом уровня, м: вровень мерцали бы.
@export var lift := 0.05

var topology: GridTopology
var embedding: GridEmbedding

var _points := PackedVector3Array()
var _colors := PackedColorArray()
var _mesh_instance := MeshInstance3D.new()


func _init() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	# Цвета заданы в sRGB: без флага читались бы линейными и выходили белёсыми.
	material.vertex_color_is_srgb = true
	_mesh_instance.material_override = material
	add_child(_mesh_instance)


func setup(p_topology: GridTopology, p_embedding: GridEmbedding) -> void:
	topology = p_topology
	embedding = p_embedding


## Забывает добавленное; меш прежний до commit().
func clear() -> void:
	_points.clear()
	_colors.clear()


## Собирает добавленное в меш; пусто — меша нет.
func commit() -> void:
	if _points.is_empty():
		_mesh_instance.mesh = null
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _points
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	_mesh_instance.mesh = mesh


## Все грани клеток — решётка; общая грань двух клеток — один отрезок.
func add_cells(cells: Array[Vector3i], color: Color) -> void:
	var inside: Dictionary[Vector3i, bool] = {}
	for cell in cells:
		inside[cell] = true
	for cell in cells:
		for side in topology.side_count(cell):
			var next := topology.neighbour(cell, side)
			if inside.has(next) and next < cell:
				continue  # общую грань уже нарисовала клетка с меньшим индексом
			_add_edge(cell, side, color)


## Контур группы клеток (GridTopology.perimeter).
func add_outline(cells: Array[Vector3i], color: Color) -> void:
	for face in topology.perimeter(cells):
		_add_edge(GridTopology.face_cell(face), face.w, color)


## Отметка вдоль грани длиной share, сдвинутая внутрь на inset м, чтобы не лечь на контур.
func add_face_mark(cell: Vector3i, side: int, color: Color, share := 0.5, inset := 0.3) -> void:
	var edge := embedding.face_edge(cell, side)
	var mid := (edge[0] + edge[1]) * 0.5
	var inward := embedding.cell_origin(cell) - mid
	inward.y = 0.0
	inward = inward.normalized() * inset
	var half := (edge[1] - edge[0]) * 0.5 * share
	_add_segment(mid - half + inward, mid + half + inward, color)


## Отметка клетки — лучи от центра к серединам граней (углы у топологии не спрашиваются).
func add_cell_mark(cell: Vector3i, color: Color, share := 0.6) -> void:
	var center := embedding.cell_origin(cell)
	for side in topology.side_count(cell):
		var edge := embedding.face_edge(cell, side)
		var mid := (edge[0] + edge[1]) * 0.5
		_add_segment(center, center.lerp(mid, share), color)


## Стрелка длиной length м из точки from в сторону side клетки; возвращает направление — для проверок.
func add_arrow(from: Vector3, cell: Vector3i, side: int, length: float, color: Color) -> Vector3:
	var direction := embedding.cell_origin(topology.neighbour(cell, side)) - embedding.cell_origin(cell)
	direction.y = 0.0
	direction = direction.normalized()
	_add_arrow(from, direction, length, color)
	return direction


## Стрелка с середины грани внутрь клетки — «вход сюда»; отличается формой, не только цветом.
func add_face_arrow(cell: Vector3i, side: int, length: float, color: Color) -> void:
	var edge := embedding.face_edge(cell, side)
	var mid := (edge[0] + edge[1]) * 0.5
	var inward := embedding.cell_origin(cell) - mid
	inward.y = 0.0
	_add_arrow(mid, inward.normalized(), length, color)


## Сколько отрезков добавлено с clear() — для проверок.
func segment_count() -> int:
	return _points.size() / 2


## Сколько отрезков такого цвета — для проверок выделения.
func segments_of_color(color: Color) -> int:
	var count := 0
	for i in range(0, _colors.size(), 2):
		if _colors[i].is_equal_approx(color):
			count += 1
	return count


func _add_arrow(from: Vector3, direction: Vector3, length: float, color: Color) -> void:
	var tip := from + direction * length
	var across := direction.cross(Vector3.UP) * length * 0.2
	_add_segment(from, tip, color)
	_add_segment(tip, tip - direction * length * 0.3 + across, color)
	_add_segment(tip, tip - direction * length * 0.3 - across, color)


func _add_edge(cell: Vector3i, side: int, color: Color) -> void:
	var edge := embedding.face_edge(cell, side)
	_add_segment(edge[0], edge[1], color)


func _add_segment(a: Vector3, b: Vector3, color: Color) -> void:
	var up := Vector3(0.0, lift, 0.0)
	_points.append(a + up)
	_points.append(b + up)
	_colors.append(color)
	_colors.append(color)
