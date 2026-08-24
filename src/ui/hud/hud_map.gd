# res://src/ui/hud/hud_map.gd
## Мини-карта в HUD: этаж, на котором сейчас игрок.
##
## Показывает СКРОМНО и намеренно: комнаты, где игрок был, плюс те, о
## существовании которых он знает — потому что видел ведущую туда дверь. Всё
## остальное не рисуется. Полная карта комплекса — это уже прокачка от
## «Архитектора», отдельный экран на паузе (см. Карта комплекса).
##
## Геометрию берёт из RunManager.plan_for_depth(): тот же план, по которому
## комнаты расставлены в мире, поэтому «север на карте» и «север в игре» — одно
## и то же. План считается без спавна, так что рисовать можно любой слой.
class_name UI_HudMap
extends Control

@export_group("Комнаты")
## Доля клетки, которую занимает комната. Остальное — промежуток под связи.
@export_range(0.1, 1.0) var room_fill: float = 0.62
@export var color_current: Color = Color(1, 0.85, 0.4, 0.95)
@export var color_visited: Color = Color(0.65, 0.75, 0.85, 0.7)
## Комната, о которой известно, но где игрок не был, — только контур.
@export var color_known: Color = Color(0.65, 0.75, 0.85, 0.35)

@export_group("Связи")
@export var color_link: Color = Color(0.6, 0.7, 0.8, 0.5)
@export var color_link_locked: Color = Color(0.9, 0.5, 0.35, 0.7)
@export var link_width: float = 2.0

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
## 60 м мира, и шаг в полметра на ней не виден.
const REDRAW_MOVE := 0.3
const REDRAW_TURN := 0.02  # ~1° по косинусу между направлениями

var _last_position := Vector3.INF
var _last_forward := Vector2.ZERO


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

	var position := player.global_position
	var forward := _forward_of(player)
	var moved := position.distance_squared_to(_last_position) >= REDRAW_MOVE * REDRAW_MOVE
	var turned := forward.dot(_last_forward) <= 1.0 - REDRAW_TURN
	if not moved and not turned:
		return

	_last_position = position
	_last_forward = forward
	queue_redraw()


func _draw() -> void:
	var graph := RunManager.current_graph
	var here := RunManager.current_node_id
	if graph == null or here == &"":
		return
	var current := graph.get_node_data(here)
	if current == null:
		return

	var plan := RunManager.plan_for_depth(current.depth)
	# Только СВОЙ этаж: этажи слоя разнесены по высоте и в одной плоскости
	# соседями не являются — рисовать их вперемешку значит врать про геометрию.
	var floor_nodes: Array[RS_LevelNode] = []
	for node_data in graph.get_nodes_by_depth(current.depth):
		if node_data.floor_index == current.floor_index and plan.cells.has(node_data.id):
			floor_nodes.append(node_data)
	if floor_nodes.is_empty():
		return

	var known := _known_nodes(floor_nodes)
	if known.is_empty():
		return

	var to_screen := _projector(known, plan)
	# Шаг сетки нужен и комнатам, и маркеру — считаем один раз.
	var step := _step_of(plan, known, to_screen)
	_draw_links(floor_nodes, known, plan, to_screen)
	_draw_rooms(known, plan, to_screen, here, step)
	_draw_player(current, plan, to_screen, step)


## Комнаты, которые игрок вправе видеть: посещённые плюс соседи посещённых —
## про соседа он знает, потому что видел дверь, ведущую туда.
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


## Замыкание «клетка → точка на экране»: вписывает показанные клетки в контрол,
## сохраняя пропорции, чтобы карта не растягивалась в кисель.
func _projector(known: Array[RS_LevelNode], plan) -> Callable:
	var min_cell := Vector2i(9999, 9999)
	var max_cell := Vector2i(-9999, -9999)
	for node_data in known:
		var cell: Vector2i = plan.cells[node_data.id]
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))

	var span := Vector2(max_cell - min_cell) + Vector2.ONE
	var area := size - Vector2(padding, padding) * 2.0
	var step: float = minf(area.x / span.x, area.y / span.y)
	# Центрируем: остаток площади делим поровну по краям.
	var origin := Vector2(padding, padding) + (area - span * step) * 0.5

	return func(cell: Vector2i) -> Vector2:
		return origin + (Vector2(cell - min_cell) + Vector2(0.5, 0.5)) * step


func _draw_links(
	floor_nodes: Array[RS_LevelNode], known: Array[RS_LevelNode], plan, to_screen: Callable
) -> void:
	var shown := {}
	for node_data in known:
		shown[node_data.id] = true

	var drawn := {}  # чтобы двустороннее ребро не рисовалось дважды
	for node_data in floor_nodes:
		if not shown.has(node_data.id):
			continue
		for conn: RS_LevelConnection in node_data.connections:
			if not shown.has(conn.target_node_id):
				continue
			var key := (
				"%s|%s" % [node_data.id, conn.target_node_id]
				if String(node_data.id) < String(conn.target_node_id)
				else "%s|%s" % [conn.target_node_id, node_data.id]
			)
			if drawn.has(key):
				continue
			drawn[key] = true
			draw_line(
				to_screen.call(plan.cells[node_data.id]),
				to_screen.call(plan.cells[conn.target_node_id]),
				color_link_locked if conn.locked_by != &"" else color_link,
				link_width
			)


func _draw_rooms(
	known: Array[RS_LevelNode], plan, to_screen: Callable, here: StringName, step: float
) -> void:
	var visited := WorldSave.save.visited_node_ids
	# Сторона комнаты — доля шага сетки.
	var room := Vector2(step, step) * room_fill

	for node_data in known:
		var center: Vector2 = to_screen.call(plan.cells[node_data.id])
		var rect := Rect2(center - room * 0.5, room)
		if node_data.id == here:
			draw_rect(rect, color_current, true)
		elif visited.has(node_data.id):
			draw_rect(rect, color_visited, true)
		else:
			# Знаем, что есть, но не были — только контур.
			draw_rect(rect, color_known, false, 1.5)


## Маркер игрока: где он ВНУТРИ комнаты и куда смотрит. Подсветки одной лишь
## комнаты мало — на карте из комнат и дверей вопрос обычно звучит «в какую дверь
## я сейчас упёрся», а на него отвечает именно направление взгляда.
##
## Смещение внутри комнаты мерим ГАБАРИТОМ комнаты, а не шагом сетки. Величины
## разные: между центрами комнат RS_LayerPlan.ROOM_SPACING = 60 м, а сама комната
## около 20 м. По шагу сетки игрок, упёршийся в северную дверь, рисовался бы у
## середины клетки — и маркер не отвечал бы на тот единственный вопрос, ради
## которого он есть. Габарит считает RS_RoomLayout по положению дверей.
##
## Начало координат комнаты — её центр, а to_screen возвращает центр клетки,
## поэтому смещение просто складывается. limit_length держит маркер внутри своей
## комнаты: развоплощённый БФЖ пролезает сквозь решётки, и заезжать на соседнюю
## клетку маркер не должен.
func _draw_player(current: RS_LevelNode, plan, to_screen: Callable, step: float) -> void:
	var player := _player_node()
	var here := current.id
	if player == null or not plan.positions.has(here) or not plan.cells.has(here):
		return

	var center: Vector2 = to_screen.call(plan.cells[here])
	var extent := RS_RoomLayout.half_extent_of_scene(current.room_scene_path)
	if extent > 0.0:
		var offset: Vector3 = player.global_position - plan.positions[here]
		center += Vector2(offset.x, offset.z).limit_length(extent) / extent * step * room_fill * 0.5

	var forward := _forward_of(player)
	var side := Vector2(-forward.y, forward.x)
	var radius := step * marker_size
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


## Длина шага сетки в экранных пикселях. Берём разницу между двумя соседними по
## оси клетками; если показана всего одна комната — опираемся на размер контрола.
func _step_of(plan, known: Array[RS_LevelNode], to_screen: Callable) -> float:
	if known.size() > 1:
		var first: Vector2i = plan.cells[known[0].id]
		for node_data in known:
			var cell: Vector2i = plan.cells[node_data.id]
			if cell != first:
				var delta: Vector2 = to_screen.call(cell) - to_screen.call(first)
				var cells := Vector2(cell - first).abs()
				if cells.x > 0.0:
					return absf(delta.x) / cells.x
				if cells.y > 0.0:
					return absf(delta.y) / cells.y
	return minf(size.x, size.y) - padding * 2.0
