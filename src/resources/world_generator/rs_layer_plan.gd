## res://src/resources/world_generator/rs_layer_plan.gd
## План раскладки одного слоя: где физически стоит каждая комната и какое ребро
## графа ушло в какую дверь. Комнаты этажа вкладываются в 2D-сетку обходом графа —
## сосед ставится ровно в ту клетку, куда смотрит связывающая их дверь. Иначе
## дверь «на север» уводила бы в комнату, стоящую совсем в другой стороне.
##
## Живёт ОТДЕЛЬНО от RunManager по той же причине, по которой отдельно живёт
## RS_RoomLayout: правило «куда встанет комната» обязано быть ОДНО на рантайм и на
## редакторские инструменты. RunManager — автолоад и не @tool, в редакторе его не
## существует вовсе, поэтому тул генератора спросить раскладку у него не может, а
## считать её собственной копией значило бы показывать не то, что делает игра.
##
## План детерминирован от графа и считается БЕЗ спавна комнат (стороны дверей
## берутся из кэша RS_RoomLayout по пути сцены), поэтому доступен и для слоёв,
## которые не загружены: на этом держатся карта комплекса и предпросмотр в туле.
@tool
class_name RS_LayerPlan
extends RefCounted

## Шаг сетки между соседними комнатами одного этажа (по X). Комната ~22 м в
## поперечнике (полотна дверей торчат до ±11), берём с запасом — комнаты не
## должны соприкасаться даже коллайдерами, иначе луч взаимодействия или капсула
## игрока могут зацепить соседнюю.
const ROOM_SPACING := 60.0
## Разнос этажей ОДНОГО слоя по высоте. Комната ~6 м высотой — 20 м даёт
## гарантированный зазор и делает раскладку читаемой в отладке.
const FLOOR_SPACING := 20.0

## Геометрия комнат (где север, куда смещается клетка) живёт в RS_RoomLayout —
## одно правило на раскладку, на раздачу рёбер по дверям и на проверку сцен.
const DIRECTION_OFFSETS := RS_RoomLayout.OFFSETS
const OPPOSITE_DIRECTION := RS_RoomLayout.OPPOSITE

## node_id -> мировая позиция комнаты.
var positions: Dictionary[StringName, Vector3] = {}
## node_id -> клетка сетки этажа. То же самое, что positions, но без масштаба
## и высоты: ровно то, что рисует карта.
var cells: Dictionary[StringName, Vector2i] = {}
## node_id -> { target_node_id: сторона }. Только рёбра, которым нашлась дверь
## В НУЖНУЮ СТОРОНУ: сосед физически стоит за этой дверью. Остальные рёбра
## (межэтажные, межслойные, не влезшие в сетку) раздаются по остаточному
## принципу при спавне — см. RunManager._bind_doors.
var direction_by_edge: Dictionary[StringName, Dictionary] = {}


## Строит план слоя. Этажи одного слоя разносятся по высоте: связь между ними
## идёт через floor_hub-рёбра, у которых нет направления в плоскости этажа.
static func build(layer_nodes: Array[RS_LevelNode]) -> RS_LayerPlan:
	var plan := RS_LayerPlan.new()
	var by_floor: Dictionary[int, Array] = {}
	for node_data in layer_nodes:
		if not by_floor.has(node_data.floor_index):
			by_floor[node_data.floor_index] = []
		by_floor[node_data.floor_index].append(node_data)

	for floor_index: int in by_floor:
		var floor_nodes: Array = by_floor[floor_index]
		# Порядок обхода фиксируем по index_in_layer: раскладка обязана совпадать
		# от запуска к запуску при одном сиде — иначе сохранённая комната окажется
		# в другом месте.
		floor_nodes.sort_custom(func(a, b): return a.index_in_layer < b.index_in_layer)
		plan._plan_floor(floor_nodes, floor_index)
	return plan


func direction_for(node_id: StringName, target_id: StringName) -> StringName:
	return direction_by_edge.get(node_id, {}).get(target_id, &"")


func is_direction_taken(node_id: StringName, direction: StringName) -> bool:
	return direction_by_edge.get(node_id, {}).values().has(direction)


func link(a: StringName, a_direction: StringName, b: StringName) -> void:
	if not direction_by_edge.has(a):
		direction_by_edge[a] = {}
	if not direction_by_edge.has(b):
		direction_by_edge[b] = {}
	direction_by_edge[a][b] = a_direction
	direction_by_edge[b][a] = OPPOSITE_DIRECTION[a_direction]


## Раскладывает один этаж. Клетки копятся в локальном floor_cells, а не сразу в
## cells: сетка у каждого этажа своя (этажи разнесены по высоте), и занятость
## клеток считается в пределах этажа, а не всего слоя.
func _plan_floor(floor_nodes: Array, floor_index: int) -> void:
	var dirs := {}  # node_id -> Array[StringName] сторон, с которых у комнаты есть дверь
	var on_floor := {}  # node_id -> RS_LevelNode, для быстрой проверки «сосед на этаже»
	for node_data: RS_LevelNode in floor_nodes:
		on_floor[node_data.id] = node_data
		dirs[node_data.id] = RS_RoomLayout.door_directions_of_scene(node_data.room_scene_path)

	var floor_cells: Dictionary[StringName, Vector2i] = {}
	var taken: Dictionary[Vector2i, StringName] = {}
	_place_at(floor_nodes[0].id, Vector2i.ZERO, floor_cells, taken)

	# 1. Обход в ширину: соседа ставим в клетку той двери, что к нему ведёт.
	var queue: Array[StringName] = [floor_nodes[0].id]
	while not queue.is_empty():
		var current_id: StringName = queue.pop_front()
		for conn: RS_LevelConnection in _by_room_freedom(on_floor[current_id].connections, dirs):
			var target_id := conn.target_node_id
			if not on_floor.has(target_id) or floor_cells.has(target_id):
				continue
			var direction := _pick_direction(current_id, target_id, floor_cells, taken, dirs)
			if direction == &"":
				continue  # ни одной подходящей свободной стороны — разместим ниже
			var cell: Vector2i = floor_cells[current_id] + DIRECTION_OFFSETS[direction]
			_place_at(target_id, cell, floor_cells, taken)
			link(current_id, direction, target_id)
			queue.append(target_id)

	# 2. Не разместившиеся (нет подходящих дверей, другой компонент связности):
	#    ставим рядом с любым уже размещённым соседом, иначе — в запасной ряд.
	for node_data: RS_LevelNode in floor_nodes:
		if floor_cells.has(node_data.id):
			continue
		var cell := _fallback_cell(node_data, floor_cells, taken, dirs)
		_place_at(node_data.id, cell, floor_cells, taken)

	# 3. Доп. рёбра (циклы) между уже размещёнными: если клетки оказались смежными
	#    и двери с обеих сторон свободны — тоже свяжем по направлению.
	for node_data: RS_LevelNode in floor_nodes:
		for conn: RS_LevelConnection in node_data.connections:
			var target_id := conn.target_node_id
			if not on_floor.has(target_id):
				continue
			if direction_for(node_data.id, target_id) != &"":
				continue
			var direction := _direction_between(floor_cells[node_data.id], floor_cells[target_id])
			if direction == &"" or not _direction_available(node_data.id, direction, dirs):
				continue
			if not _direction_available(target_id, OPPOSITE_DIRECTION[direction], dirs):
				continue
			link(node_data.id, direction, target_id)

	for node_id: StringName in floor_cells:
		var cell := floor_cells[node_id]
		cells[node_id] = cell
		positions[node_id] = Vector3(
			cell.x * ROOM_SPACING, floor_index * FLOOR_SPACING, cell.y * ROOM_SPACING
		)


## Рёбра в порядке «сначала самые зажатые соседи»: комнату с одной дверью
## (lab_room, vertical_hub_1) надо ставить, пока нужная сторона ещё свободна —
## иначе ей достанется случайное место, а её единственная дверь будет вести
## куда-то вбок. Тай-брейк по id — раскладка обязана быть детерминированной.
func _by_room_freedom(connections: Array[RS_LevelConnection], dirs: Dictionary) -> Array:
	var sorted := connections.duplicate()
	sorted.sort_custom(
		func(a: RS_LevelConnection, b: RS_LevelConnection) -> bool:
			var a_doors: int = (dirs.get(a.target_node_id, []) as Array).size()
			var b_doors: int = (dirs.get(b.target_node_id, []) as Array).size()
			if a_doors != b_doors:
				return a_doors < b_doors
			return String(a.target_node_id) < String(b.target_node_id)
	)
	return sorted


func _place_at(
	node_id: StringName,
	cell: Vector2i,
	floor_cells: Dictionary[StringName, Vector2i],
	taken: Dictionary[Vector2i, StringName],
) -> void:
	floor_cells[node_id] = cell
	taken[cell] = node_id


## Сторона, с которой можно поставить соседа: у нас есть такая дверь и она ещё
## свободна, у соседа есть встречная, и клетка за ней не занята. Порядок перебора
## — из DIRECTION_OFFSETS, то есть детерминированный.
func _pick_direction(
	current_id: StringName,
	target_id: StringName,
	floor_cells: Dictionary[StringName, Vector2i],
	taken: Dictionary[Vector2i, StringName],
	dirs: Dictionary,
) -> StringName:
	for direction: StringName in DIRECTION_OFFSETS:
		if not _direction_available(current_id, direction, dirs):
			continue
		if not _direction_available(target_id, OPPOSITE_DIRECTION[direction], dirs):
			continue
		if taken.has(floor_cells[current_id] + DIRECTION_OFFSETS[direction]):
			continue
		return direction
	return &""


## Есть ли у комнаты дверь с этой стороны и не отдана ли она уже другому ребру.
func _direction_available(node_id: StringName, direction: StringName, dirs: Dictionary) -> bool:
	var available: Array = dirs.get(node_id, [])
	return available.has(direction) and not is_direction_taken(node_id, direction)


## Направление от клетки [param from] к [param to], если они смежные. Иначе "".
func _direction_between(from: Vector2i, to: Vector2i) -> StringName:
	for direction: StringName in DIRECTION_OFFSETS:
		if from + DIRECTION_OFFSETS[direction] == to:
			return direction
	return &""


## Клетка для комнаты, которой не нашлось направления на первом проходе: встаём
## вплотную к уже размещённому соседу, предпочитая сторону, куда у нас САМИХ
## смотрит свободная дверь. Идеальной пары (двери с обеих сторон) тут уже быть не
## может — её забрал бы _pick_direction, — но хотя бы наша дверь будет вести к
## соседу. Совсем некуда — уходим в запасной ряд под сеткой.
func _fallback_cell(
	node_data: RS_LevelNode,
	floor_cells: Dictionary[StringName, Vector2i],
	taken: Dictionary[Vector2i, StringName],
	dirs: Dictionary,
) -> Vector2i:
	var best := Vector2i.MAX
	var best_score := -1
	for conn: RS_LevelConnection in node_data.connections:
		if not floor_cells.has(conn.target_node_id):
			continue
		for direction: StringName in DIRECTION_OFFSETS:
			var cell: Vector2i = floor_cells[conn.target_node_id] + DIRECTION_OFFSETS[direction]
			if taken.has(cell):
				continue
			# Мы встаём в direction ОТ соседа, значит сосед для нас — со встречной.
			var score := 0
			if _direction_available(node_data.id, OPPOSITE_DIRECTION[direction], dirs):
				score += 1
			if _direction_available(conn.target_node_id, direction, dirs):
				score += 1
			if score > best_score:
				best_score = score
				best = cell
	if best_score >= 0:
		return best

	var overflow_row := 2
	for cell: Vector2i in taken:
		overflow_row = maxi(overflow_row, cell.y + 2)
	var column := 0
	while taken.has(Vector2i(column, overflow_row)):
		column += 1
	return Vector2i(column, overflow_row)
