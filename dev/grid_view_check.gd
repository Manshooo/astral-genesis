extends "res://dev/check_harness.gd"
## Проверка узла сетки (GridView) и грани клетки во вложении
## (GridEmbedding.face_edge) — п. 8 карточки «Сетка уровня». Без плана и без
## игры: узел знает только топологию и вложение, и проверяется так же.
##
## Ломается это молча — схема рисует не то: грань, сдвинутая на полклетки,
## выглядит такой же решёткой, двойная линия на общей грани не видна глазу, а
## стрелка, повёрнутая не в ту сторону, показывает поворот комнаты неверно.
##
## Запускать: godot --headless dev/grid_view_check.tscn

const CELL := 8.0


func _ready() -> void:
	var topology := SquareGridTopology.new()
	var embedding := SquareGridEmbedding.new(CELL, CELL)
	_check_face_edges(topology, embedding)
	_check_view(topology, embedding)
	_finish()


## Грань — на полпути к соседу, длиной в клетку, поперёк направления к соседу; на
## уровне пола своей клетки.
func _check_face_edges(topology: SquareGridTopology, embedding: SquareGridEmbedding) -> void:
	var wrong: Array[String] = []
	var cell := Vector3i(2, 1, -3)
	for side in topology.side_count(cell):
		var edge := embedding.face_edge(cell, side)
		var toward := embedding.cell_origin(topology.neighbour(cell, side)) - embedding.cell_origin(cell)
		var mid := (edge[0] + edge[1]) * 0.5
		var ok := edge.size() == 2
		ok = ok and mid.is_equal_approx(embedding.cell_origin(cell) + toward * 0.5)
		ok = ok and is_equal_approx(edge[0].distance_to(edge[1]), CELL)
		ok = ok and is_zero_approx((edge[1] - edge[0]).dot(toward))
		ok = ok and is_equal_approx(edge[0].y, embedding.cell_origin(cell).y)
		if not ok:
			wrong.append("%s: %s" % [RS_RoomLayout.side_name(side), edge])
	_check("грань клетки — на полпути к соседу, длиной в клетку, поперёк", wrong.is_empty(), ", ".join(wrong))


func _check_view(topology: SquareGridTopology, embedding: SquareGridEmbedding) -> void:
	var view := GridView.new()
	add_child(view)
	view.setup(topology, embedding)

	# Прямоугольник 3×2 (3 по X, 2 по Z), общие грани — по разу: граней поперёк X
	# (3 + 1) · 2 и поперёк Z (2 + 1) · 3, всего 17. Без склейки общих было бы 24.
	var rect: Array[Vector3i] = []
	for z in 2:
		for x in 3:
			rect.append(Vector3i(x, 0, z))
	view.add_cells(rect, Color.WHITE)
	_check("решётка 3×2 — 17 отрезков, общая грань один раз", view.segment_count() == 17, str(view.segment_count()))

	view.clear()
	view.add_outline(rect, Color.WHITE)
	_check("контур 3×2 — 10 граней периметра", view.segment_count() == 10, str(view.segment_count()))

	view.clear()
	var turned: Array[String] = []
	for side in topology.side_count(Vector3i.ZERO):
		var direction := view.add_arrow(Vector3.ZERO, Vector3i.ZERO, side, 4.0, Color.WHITE)
		if not direction.is_equal_approx(Vector3(SquareGridTopology.OFFSETS[side])):
			turned.append("%s: %s" % [RS_RoomLayout.side_name(side), direction])
	_check("стрелка смотрит в сторону соседа за своей стороной", turned.is_empty(), ", ".join(turned))

	view.clear()
	view.add_face_arrow(Vector3i.ZERO, SquareGridTopology.Side.EAST, 2.0, Color.WHITE)
	var start := view._points[0] - Vector3(0.0, view.lift, 0.0)
	var tip := view._points[1] - Vector3(0.0, view.lift, 0.0)
	var edge := embedding.face_edge(Vector3i.ZERO, SquareGridTopology.Side.EAST)
	_check("стрелка грани — с её середины внутрь клетки",
		view.segment_count() == 3 and start.is_equal_approx((edge[0] + edge[1]) * 0.5)
			and (tip - start).normalized().is_equal_approx(Vector3.LEFT),
		"%s → %s" % [start, tip])

	view.clear()
	view.add_cell_mark(Vector3i.ZERO, Color.RED)
	view.add_face_mark(Vector3i.ZERO, SquareGridTopology.Side.NORTH, Color.GREEN)
	_check("отметки клетки и грани, по цветам",
		view.segments_of_color(Color.RED) == 4 and view.segments_of_color(Color.GREEN) == 1,
		"красных %d, зелёных %d" % [view.segments_of_color(Color.RED), view.segments_of_color(Color.GREEN)])
	view.commit()
	var mesh := view.get_child(0) as MeshInstance3D
	_check("commit собирает меш линий из всех отрезков",
		mesh.mesh != null and mesh.mesh.get_surface_count() == 1
			and (mesh.mesh as ArrayMesh).surface_get_array_len(0) == 10,
		"")
	view.clear()
	view.commit()
	_check("пустой узел — без меша", mesh.mesh == null, "")
	view.free()
