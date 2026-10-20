## res://addons/game_design_tool/world/overlays/grid_overlay.gd
## Оверлей «Сетка»: клетки плана — решётка слоя, footprint и поворот комнат,
## сокеты, тупики и стыки веток. Рисует GridView (src/grid/), оверлей только
## переводит план в клетки и цвета; смотреть с выключенной «Геометрией».
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
@tool
extends Node3D

const LayerView := preload("res://addons/game_design_tool/world/layer_view.gd")
const CorridorsOverlay := preload("res://addons/game_design_tool/world/overlays/corridors_overlay.gd")
## Как у обводки в selection_outline.tres.
const SELECTED_COLOR := Color("#cfc61b")
const LATTICE_COLOR := Color(0.3, 0.33, 0.4)
const ROOM_COLOR := Color(0.92, 0.92, 0.95)
const BLANK_SOCKET_COLOR := Color(0.55, 0.55, 0.6)
const DEAD_END_COLOR := Color(0.95, 0.25, 0.2)
const JOINT_COLOR := Color(1.0, 0.35, 0.9)
## Решётка шире занятых клеток на столько клеток.
const LATTICE_MARGIN := 1
## Выше плит «Коридоров» (верх 0.43 м), иначе они накроют линии.
const LIFT := 0.5

## Счётчики последней отрисовки — для проверки инструмента.
var rooms_outlined := 0
var door_marks := 0
var blank_socket_marks := 0
var dead_end_marks := 0
var joint_marks := 0
## Комната -> куда показала стрелка поворота; проверка сверяет её с поворотом корня.
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


## Перерисовывает всё: меш у узла один, слой — сотни отрезков.
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


## Прямоугольник — свойство нынешней раскладки, а не сетки, поэтому он здесь, а не в узле.
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


## Стрелка — куда смотрит север сцены: сторона s смотрит в мир стороной s − turns.
## У комнаты с дверями в сцене сокетов нет, только её двери.
func _draw_room(plan: RS_LayerPlan, node_data: RS_LevelNode) -> void:
	var id := node_data.id
	var color := SELECTED_COLOR if id == _selected_id else ROOM_COLOR
	var cells := plan.room_cells(id)
	_grid.add_outline(cells, color)
	rooms_outlined += 1

	var anchor: Vector3i = plan.cells[id]
	var north := plan.topology.rotate_side(anchor, SquareGridTopology.Side.NORTH, -plan.turns.get(id, 0))
	# Выше решётки: на её линии древко мерцало бы пунктиром.
	var from := plan.position_of(id) + Vector3(0.0, 0.05, 0.0)
	arrows[id] = _grid.add_arrow(from, anchor, north, plan.embedding.cell_size * 0.6, color)

	var doors: Dictionary = plan.door_faces.get(id, {})
	var faces: Array = doors.keys()
	if RS_RoomLayout.shell_of_scene(node_data.room_scene_path) != null:
		faces = RS_RoomLayout.sockets_in_plan(node_data.room_scene_path, node_data.turns, anchor)
	for face: Vector4i in faces:
		var cell := GridTopology.face_cell(face)
		if doors.has(face):
			# Стрелка, не черта: черта вдоль грани терялась рядом с плитой того же цвета.
			_grid.add_face_arrow(cell, face.w, plan.embedding.cell_size * 0.25, CorridorsOverlay.branch_color(doors[face]))
			door_marks += 1
		else:
			_grid.add_face_mark(cell, face.w, BLANK_SOCKET_COLOR, 0.3, 0.35)
			blank_socket_marks += 1


## Стык веток — открытая грань между тайлами разных веток; каждая — один раз.
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
