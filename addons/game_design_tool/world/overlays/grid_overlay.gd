## res://addons/game_design_tool/world/overlays/grid_overlay.gd
## Оверлей «Сетка»: клетки плана так, как их видит раскладка, — решётка слоя,
## footprint каждой комнаты и куда она повёрнута, её сокеты (дверь или глухой),
## тупики и стыки веток. Рисует узел сетки GridView (src/grid/); оверлей только
## переводит план в клетки и цвета — сам узел про комнаты не знает.
##
## Зачем рядом с «Геометрией» и «Коридорами»: меши показывают, что построено, но
## не почему. Какой сокет раскладка сделала дверью, как повёрнута коробка, где одна
## ветка переходит в другую — в мешах этого не видно вовсе, а в плане это главное.
##
## Линии лежат у пола уровня и прячутся под потолками комнат, как и плиты
## «Коридоров»: этажи слоя стоят друг над другом на тех же клетках, и схема,
## нарисованная поверх всего, сложила бы три этажа в одну кашу. Смотреть её —
## с выключенной «Геометрией».
@tool
extends Node3D

const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
const CorridorsOverlay := preload("res://addons/game_design_tool/world/overlays/corridors_overlay.gd")
## Цвет выделения — тот же, что у обводки комнаты и ветки в других оверлеях.
const SELECTED_COLOR := Color("#cfc61b")
const LATTICE_COLOR := Color(0.3, 0.33, 0.4)
const ROOM_COLOR := Color(0.92, 0.92, 0.95)
const BLANK_SOCKET_COLOR := Color(0.55, 0.55, 0.6)
const DEAD_END_COLOR := Color(0.95, 0.25, 0.2)
const JOINT_COLOR := Color(1.0, 0.35, 0.9)
## Решётка — на клетку шире всего, что стоит на уровне: видно, где кончается
## раскладка и куда сети было где пройти.
const LATTICE_MARGIN := 1
## Над плитами «Коридоров» (их верх — 0.43 м): иначе плита накрывала бы линии.
const LIFT := 0.5

## Сколько чего нарисовано на последней отрисовке — для проверки инструмента.
var rooms_outlined := 0
var door_marks := 0
var blank_socket_marks := 0
var dead_end_marks := 0
var joint_marks := 0
## Комната -> куда показала её стрелка поворота. Проверка сверяет его с поворотом
## корня комнаты — формулой, которой оверлей не пользуется.
var arrows: Dictionary[StringName, Vector3] = {}

var _grid := GridView.new()
var _view: LayerView
var _selected_id: StringName = &""


func _init() -> void:
	_grid.lift = LIFT
	add_child(_grid)


func rebuild(view: LayerView) -> void:
	_view = view
	_selected_id = &""
	_draw()


func set_selected(node_id: StringName) -> void:
	_selected_id = node_id
	_draw()


func grid() -> GridView:
	return _grid


## Перерисовывает всё: выделение меняет цвет контура, а меш у узла один. Слой —
## сотни отрезков, пересборка по клику ничего не стоит.
func _draw() -> void:
	_grid.clear()
	rooms_outlined = 0
	door_marks = 0
	blank_socket_marks = 0
	dead_end_marks = 0
	joint_marks = 0
	arrows.clear()
	if _view == null or _view.plan == null:
		_grid.commit()
		return
	var plan := _view.plan
	_grid.setup(plan.topology, plan.embedding)
	_draw_lattice(plan)
	for node_data: RS_LevelNode in _view.nodes:
		if not plan.cells.has(node_data.id):
			continue
		if node_data.role == RS_LevelNode.Role.CORRIDOR:
			if node_data.id == _selected_id:
				_grid.add_outline(_tiles_of(plan, node_data.id), SELECTED_COLOR)
			continue
		_draw_room(plan, node_data)
	for cell: Vector3i in plan.dead_ends:
		_grid.add_cell_mark(cell, DEAD_END_COLOR)
		dead_end_marks += 1
	_draw_joints(plan)
	_grid.commit()


## Решётка — прямоугольник клеток каждого уровня вокруг всего, что на нём стоит.
## Прямоугольник — свойство нынешней раскладки (решётка комнат по X и Z), а не
## сетки, поэтому он здесь, а не в узле.
func _draw_lattice(plan: RS_LayerPlan) -> void:
	var bounds: Dictionary[int, Rect2i] = {}
	for cell: Vector3i in plan.node_by_cell:
		var point := Vector2i(cell.x, cell.z)
		bounds[cell.y] = bounds[cell.y].expand(point) if bounds.has(cell.y) else Rect2i(point, Vector2i.ZERO)
	for level: int in bounds:
		var rect := bounds[level].grow(LATTICE_MARGIN)
		var cells: Array[Vector3i] = []
		for z in range(rect.position.y, rect.end.y + 1):
			for x in range(rect.position.x, rect.end.x + 1):
				cells.append(Vector3i(x, level, z))
		_grid.add_cells(cells, LATTICE_COLOR)


## Контур footprint, стрелка поворота и сокеты комнаты. Стрелка показывает, куда
## смотрит север сцены (её −Z): сторона сцены s смотрит в мир стороной s − turns
## (RS_LevelNode.turns). Сокеты — грани периметра сборной комнаты: дверь цветом
## своей ветки, глухой — тускло. У комнаты с дверями в сцене сокетов нет, только
## её двери.
func _draw_room(plan: RS_LayerPlan, node_data: RS_LevelNode) -> void:
	var id := node_data.id
	var color := SELECTED_COLOR if id == _selected_id else ROOM_COLOR
	var cells := plan.room_cells(id)
	_grid.add_outline(cells, color)
	rooms_outlined += 1

	var anchor: Vector3i = plan.cells[id]
	var north := plan.topology.rotate_side(anchor, SquareGridTopology.Side.NORTH, -plan.turns.get(id, 0))
	# Чуть выше решётки: центр чётной коробки — перекрестье решётки, и древко,
	# лёжа на её линии, мерцало бы пунктиром.
	var from := plan.position_of(id) + Vector3(0.0, 0.05, 0.0)
	arrows[id] = _grid.add_arrow(from, anchor, north, plan.embedding.cell_size * 0.6, color)

	var doors: Dictionary = plan.door_faces.get(id, {})
	var faces: Array = doors.keys()
	if RS_RoomLayout.shell_of_scene(node_data.room_scene_path) != null:
		faces = plan.topology.perimeter(cells)
	for face: Vector4i in faces:
		var cell := GridTopology.face_cell(face)
		if doors.has(face):
			# Дверь — стрелкой внутрь, «вход сюда», цветом своей ветки: её плита в
			# «Коридорах» того же цвета, и черта вдоль грани рядом с ней терялась.
			_grid.add_face_arrow(cell, face.w, plan.embedding.cell_size * 0.25, CorridorsOverlay.branch_color(doors[face]))
			door_marks += 1
		else:
			_grid.add_face_mark(cell, face.w, BLANK_SOCKET_COLOR, 0.3, 0.35)
			blank_socket_marks += 1


## Стык веток — грань между тайлами разных веток с открытым проёмом: здесь одна
## ветка переходит в другую, место под будущий шлюз. Каждая грань один раз.
func _draw_joints(plan: RS_LayerPlan) -> void:
	for tile: Vector3i in plan.corridor_tiles:
		var mask: int = plan.corridor_tiles[tile]
		for side in plan.topology.side_count(tile):
			var next := plan.topology.neighbour(tile, side)
			if mask & (1 << side) == 0 or not plan.corridor_tiles.has(next) or next < tile:
				continue
			if plan.node_by_cell[tile] != plan.node_by_cell[next]:
				_grid.add_face_mark(tile, side, JOINT_COLOR, 0.9, 0.0)
				joint_marks += 1


func _tiles_of(plan: RS_LayerPlan, branch: StringName) -> Array[Vector3i]:
	var tiles: Array[Vector3i] = []
	for cell: Vector3i in plan.corridor_tiles:
		if plan.node_by_cell.get(cell, &"") == branch:
			tiles.append(cell)
	return tiles
