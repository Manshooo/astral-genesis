# res://src/ui/hud/hud_map.gd
## Мини-карта в HUD: этаж, на котором сейчас игрок.
##
## Показывает СКРОМНО и намеренно: комнаты и ветки коридора, где игрок был, плюс
## те, о существовании которых он знает — потому что видел ведущую туда дверь.
## Ветка коридора видна ЦЕЛИКОМ, как только известна: это тот же «сосед», что и
## комната, и дробить её на пройденные тайлы значило бы хранить их в сейве ради
## подробности, которую правильнее отдать улучшениям «Архитектора». Всё остальное
## не рисуется. Полная карта комплекса — отдельный экран на паузе (см. Карта
## комплекса).
##
## Геометрию берёт из RunManager.plan_for_depth(): тот же план, по которому
## комнаты и тайлы коридоров расставлены в мире, поэтому «север на карте» и
## «север в игре» — одно и то же. План считается без спавна, так что рисовать
## можно любой слой.
class_name UI_HudMap
extends Control

@export_group("Комнаты")
## Доля клетки, которую занимает комната. Клетка и есть комната (18 м, стык кита
## по грани), зазор нужен, только чтобы соседние комнаты не слипались в пятно.
@export_range(0.1, 1.0) var room_fill: float = 0.82
@export var color_current: Color = Color(1, 0.85, 0.4, 0.95)
@export var color_visited: Color = Color(0.65, 0.75, 0.85, 0.7)
## Комната, о которой известно, но где игрок не был, — только контур.
@export var color_known: Color = Color(0.65, 0.75, 0.85, 0.35)

@export_group("Коридоры")
## Ширина полосы коридора в долях клетки — сечение кита (6 м внутри) к 18 м.
@export_range(0.05, 0.6) var corridor_width: float = 0.34

@export_group("Маркер игрока")
## Размер маркера в долях клетки: вместе с картой он и масштабируется.
@export_range(0.05, 0.5) var marker_size: float = 0.22
@export var color_player: Color = Color(1, 1, 1, 0.95)
## Контур маркера. Комната под ним бывает светлой (текущая — почти белая), и без
## обводки треугольник в ней тонет.
@export var color_player_outline: Color = Color(0.1, 0.1, 0.12, 0.85)

@export_group("Прочее")
## Отступ от краёв контрола, чтобы комнаты не липли к рамке.
@export var padding: float = 8.0

## Насколько игрок должен сдвинуться (метры) или повернуться, чтобы карта
## перерисовалась. Перерисовывать вектор каждый кадр незачем: клетка карты — это
## 18 м мира, и шаг в полметра на ней едва виден.
const REDRAW_MOVE := 0.3
const REDRAW_TURN := 0.02  # ~1° по косинусу между направлениями

var _last_position := Vector3.INF
var _last_forward := Vector2.ZERO
## Вписывание: сколько пикселей в клетке и где на экране нулевая клетка. Считается
## в _fit один раз на отрисовку и держится полями — им пользуются и комнаты, и
## коридоры, и маркер.
var _step := 0.0
var _origin := Vector2.ZERO
var _min_cell := Vector2.ZERO


func _ready() -> void:
	RunManager.room_changed.connect(_on_run_changed)
	RunManager.layer_changed.connect(_on_run_changed)
	RunManager.complex_entered.connect(_on_run_changed)


func _on_run_changed(_arg: Variant = null) -> void:
	queue_redraw()


## Маркер игрока живёт непрерывно, а сигналов о том, что игрок прошёл два шага,
## нет — поэтому опрашиваем, как и остальной HUD (см. UI_HudVitals). Но карта
## рисуется вектором целиком, так что перерисовку просим только когда игрок
## реально сместился или повернулся.
func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var player := _player_node()
	if player == null:
		return

	var player_position := player.global_position
	var forward := _forward_of(player)
	var moved := player_position.distance_squared_to(_last_position) >= REDRAW_MOVE * REDRAW_MOVE
	var turned := forward.dot(_last_forward) <= 1.0 - REDRAW_TURN
	if not moved and not turned:
		return

	_last_position = player_position
	_last_forward = forward
	queue_redraw()


func _draw() -> void:
	var view := build_view()
	if view.is_empty():
		return
	var plan: RS_LayerPlan = view["plan"]
	var here: StringName = view["here"]
	_draw_corridors(view["branches"], plan, view["floor"], here)
	_draw_rooms(view["rooms"], plan, here)
	_draw_player()


## Что и где рисовать — отдельно от рисования, чтобы проверка могла спросить
## карту без пикселей: известные комнаты и ветки ТЕКУЩЕГО этажа, план и вписывание
## показанных клеток в контрол. Пусто — рисовать нечего.
##
## Только свой этаж: этажи слоя разнесены по высоте и в одной плоскости соседями
## не являются — рисовать их вперемешку значит врать про геометрию.
func build_view() -> Dictionary:
	var graph := RunManager.current_graph
	var here := RunManager.current_node_id
	if graph == null or here == &"":
		return {}
	var current := graph.get_node_data(here)
	if current == null:
		return {}

	var plan := RunManager.plan_for_depth(current.depth)
	var floor_nodes: Array[RS_LevelNode] = []
	for node_data in graph.get_nodes_by_depth(current.depth):
		if node_data.floor_index == current.floor_index:
			floor_nodes.append(node_data)

	var rooms: Array[RS_LevelNode] = []
	var branches: Array[RS_LevelNode] = []
	var cells: Array[Vector2i] = []
	for node_data in _known_nodes(floor_nodes):
		if node_data.role == RS_LevelNode.Role.CORRIDOR:
			branches.append(node_data)
			cells.append_array(_tiles_of(plan, node_data.id, current.floor_index))
		elif plan.cells.has(node_data.id):
			rooms.append(node_data)
			cells.append(plan.cells[node_data.id])
	if cells.is_empty():
		return {}

	_fit(cells)
	return {"plan": plan, "here": here, "floor": current.floor_index, "rooms": rooms, "branches": branches}


## Комнаты и ветки, которые игрок вправе видеть: посещённые плюс соседи
## посещённых — про соседа он знает, потому что видел дверь, ведущую туда.
func _known_nodes(floor_nodes: Array[RS_LevelNode]) -> Array[RS_LevelNode]:
	var visited := WorldSave.save.visited_node_ids
	var known: Array[RS_LevelNode] = []
	for node_data in floor_nodes:
		if visited.has(node_data.id):
			known.append(node_data)
			continue
		for conn: RS_LevelConnection in node_data.connections:
			if visited.has(conn.target_node_id):
				known.append(node_data)
				break
	return known


## Вписывает показанные клетки в контрол, сохраняя пропорции, чтобы карта не
## растягивалась в кисель.
func _fit(cells: Array[Vector2i]) -> void:
	var min_cell := Vector2i(cells[0])
	var max_cell := Vector2i(cells[0])
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var span := Vector2(max_cell - min_cell) + Vector2.ONE
	var area := size - Vector2(padding, padding) * 2.0
	_step = minf(area.x / span.x, area.y / span.y)
	# Центрируем: остаток площади делим поровну по краям.
	_origin = Vector2(padding, padding) + (area - span * _step) * 0.5
	_min_cell = Vector2(min_cell)


## Точка на экране для клетки — дробной: маркер игрока живёт между клетками.
## Центр клетки (x, z) — это (x, z) + 0.5 шага от угла вписанной области.
func to_screen(cell: Vector2) -> Vector2:
	return _origin + (cell - _min_cell + Vector2(0.5, 0.5)) * _step


## Точка на экране для мировой позиции: клетка кита — шаг плана, поэтому метры
## просто делятся на него.
func world_to_screen(world_position: Vector3) -> Vector2:
	return to_screen(Vector2(world_position.x, world_position.z) / RS_LayerPlan.CELL_SIZE)


func _tiles_of(plan: RS_LayerPlan, branch: StringName, floor_index: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for cell: Vector3i in plan.corridor_tiles:
		if cell.y == floor_index and plan.node_by_cell.get(cell, &"") == branch:
			tiles.append(Vector2i(cell.x, cell.z))
	return tiles


## Ветка — полосой по трассе: квадрат в центре тайла и рукав к каждому открытому
## проёму, как рисует оверлей «Коридоры» в «Генераторе мира». Рукав к двери
## комнаты упирается в её прямоугольник, поэтому дверь на карте видна как место,
## где коридор входит в комнату.
func _draw_corridors(
	branches: Array[RS_LevelNode], plan: RS_LayerPlan, floor_index: int, here: StringName
) -> void:
	var visited := WorldSave.save.visited_node_ids
	var width := _step * corridor_width
	for branch in branches:
		var color := color_current if branch.id == here else (
			color_visited if visited.has(branch.id) else color_known
		)
		for cell in _tiles_of(plan, branch.id, floor_index):
			var center := to_screen(Vector2(cell))
			draw_rect(Rect2(center - Vector2(width, width) * 0.5, Vector2(width, width)), color, true)
			var mask: int = plan.corridor_tiles[Vector3i(cell.x, floor_index, cell.y)]
			for side: StringName in RS_LayerPlan.SIDE_BITS:
				if mask & RS_LayerPlan.SIDE_BITS[side] == 0:
					continue
				var offset := Vector2(RS_RoomLayout.OFFSETS[side])
				var arm_end := center + offset * _step * 0.5
				var arm := Rect2(center, Vector2.ZERO).expand(arm_end)
				draw_rect(arm.grow_individual(
					width * 0.5 if offset.x == 0 else 0.0, width * 0.5 if offset.y == 0 else 0.0,
					width * 0.5 if offset.x == 0 else 0.0, width * 0.5 if offset.y == 0 else 0.0
				), color, true)


func _draw_rooms(rooms: Array[RS_LevelNode], plan: RS_LayerPlan, here: StringName) -> void:
	var visited := WorldSave.save.visited_node_ids
	var room := Vector2(_step, _step) * room_fill
	for node_data in rooms:
		var center := to_screen(Vector2(plan.cells[node_data.id]))
		var rect := Rect2(center - room * 0.5, room)
		if node_data.id == here:
			draw_rect(rect, color_current, true)
		elif visited.has(node_data.id):
			draw_rect(rect, color_visited, true)
		else:
			# Знаем, что есть, но не были — только контур.
			draw_rect(rect, color_known, false, 1.5)


## Маркер игрока: где он и куда смотрит. Позиция — прямо из мира через шаг
## клетки: комнаты и коридоры лежат на одной сетке, и игрок законно бывает
## между ними (в тамбуре, на стыке), так что зажимать маркер в своей комнате,
## как в прежней раскладке, больше нечем и незачем.
func _draw_player() -> void:
	var player := _player_node()
	if player == null:
		return
	var center := world_to_screen(player.global_position)

	var forward := _forward_of(player)
	var side := Vector2(-forward.y, forward.x)
	var radius := _step * marker_size
	var points := PackedVector2Array(
		[
			center + forward * radius,
			center - forward * radius * 0.55 + side * radius * 0.6,
			center - forward * radius * 0.55 - side * radius * 0.6,
		]
	)
	draw_colored_polygon(points, color_player)

	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, color_player_outline, 1.0)


## Куда смотрит игрок, в осях карты. Клетка — это Vector2i(x, z) (RS_RoomLayout),
## поэтому мировые X и Z ложатся на экранные X и Y напрямую. Направление берём из
## базиса узла, а не собираем из угла рыскания: «вперёд» у Node3D — это −Z, и
## складывать это из синусов руками значит один раз ошибиться знаком.
##
## Рыскание живёт на самой сущности (S_FPSLook зовёт player.rotate_y), тангаж — на
## камере, так что взгляд вверх маркер не заваливает.
func _forward_of(player: Node3D) -> Vector2:
	var forward := -player.global_basis.z
	var flat := Vector2(forward.x, forward.z)
	return flat.normalized() if flat.length_squared() > 0.000001 else Vector2.DOWN


## Игрок как узел сцены. HUD опрашивает мир напрямую — та же схема, что в
## UI_HudVitals. Через Node: Entity наследует Node, и прямой каст Entity→Node3D
## анализатор GDScript не пропускает (тот же приём, что в RunManager).
func _player_node() -> Node3D:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as Node as Node3D
