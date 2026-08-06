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

@export_group("Прочее")
## Отступ от краёв контрола, чтобы комнаты не липли к рамке.
@export var padding: float = 8.0


func _ready() -> void:
	RunManager.room_changed.connect(_on_run_changed)
	RunManager.layer_changed.connect(_on_run_changed)
	RunManager.complex_entered.connect(_on_run_changed)


func _on_run_changed(_arg: Variant = null) -> void:
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
	_draw_links(floor_nodes, known, plan, to_screen)
	_draw_rooms(known, plan, to_screen, here)


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
	known: Array[RS_LevelNode], plan, to_screen: Callable, here: StringName
) -> void:
	var visited := WorldSave.save.visited_node_ids
	# Сторона комнаты — доля шага сетки; шаг восстанавливаем из двух соседних
	# клеток, чтобы не тащить его отдельным параметром.
	var step := _step_of(plan, known, to_screen)
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
