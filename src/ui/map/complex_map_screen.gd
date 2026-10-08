# res://src/ui/map/complex_map_screen.gd
## Экран карты комплекса: большая карта на паузе, которую надо заслужить.
##
## Мини-карта в HUD даёт ориентацию на ходу, а здесь покупается ЗНАНИЕ
## НАПЕРЁД: сколько именно, решает уровень улучшения у Архитектора
## (ArchitectManager.map_level(), уровни — MapKnowledge).
##
## Вид — язык «Отголосок» (§9 «Меню — спека»). Слева — срез комплекса: слои
## сверху вниз полосами (UI_MapStratum), на каждой этажи линиями и комнаты
## штрихами, порталы между слоями — пунктиром через границу; срез заменил
## список слоёв кнопками — он показывает сам комплекс, а не только имена.
## Справа — этажи выбранного слоя сеткой планов (UI_MapFloor): в мире этажи
## разнесены по высоте и в одной плоскости соседями не являются. Связывает
## планы портал — наведение подсвечивает его второй конец, клик переносит к
## нему, в том числе на другой слой.
##
## Данные экран получает в setup(), а не берёт у автолоадов сам: так его можно
## собрать и проверить на любом сгенерированном графе, не запуская забег.
class_name UI_ComplexMap
extends UI_MenuScreen

## Потолок клетки плана на экране, пикселей (§4): этаж из двух известных комнат
## иначе раздуло бы на всю область, и шаг карты скакал бы от слоя к слою.
const MAX_STEP := 34.0
## Зазор между планами этажей и место под подпись этажа над планом.
const PLAN_GAP := 28.0
const PLAN_TITLE := 24.0

@onready var _level_label: Label = %LevelLabel
@onready var _slice: VBoxContainer = %Slice
@onready var _slice_links: Control = %SliceLinks
@onready var _plans: Control = %Plans
@onready var _layer_title: Label = %LayerTitle
@onready var _info: Label = %Info

var _graph: RS_LevelGraph
var _level := MapKnowledge.LEVEL_NONE
var _here: StringName = &""
var _visited: Array[StringName] = []
var _plan_of: Callable
var _current_depth := -1
var _selected_depth := -1
## Второй конец портала, по которому кликнули: держится, пока курсор гуляет
## по другим комнатам, иначе после переноса на слой было бы не найти, куда попал.
var _pinned: StringName = &""
var _floors: Array[UI_MapFloor] = []
var _layer_buttons: Dictionary[int, Button] = {}
## Уникальные комнаты по пути сцены: узел графа знает только сцену, а роль
## («выход», «Архитектор») и значок лежат в RS_UniqueRoom конфига генерации.
var _unique_by_scene: Dictionary[String, RS_UniqueRoom] = {}
var _types: RS_RoomTypeCatalog
## Порталы между соседними слоями для пунктира среза: [{ "depth", "x" }].
var _slice_portals: Array[Dictionary] = []


func _ready() -> void:
	super._ready()
	_slice_links.draw.connect(_draw_slice_links)
	_slice.sort_children.connect(_slice_links.queue_redraw)


## [param plan_of] — план слоя по глубине (в игре RunManager.plan_for_depth: тот
## же кэш, по которому стоят комнаты). Остальное — состояние забега на момент
## открытия: мир на паузе, пока экран открыт, и меняться оно не успевает.
func setup(
	graph: RS_LevelGraph, level: int, here: StringName, visited: Array[StringName], plan_of: Callable
) -> void:
	_graph = graph
	_level = clampi(level, MapKnowledge.LEVEL_NONE, MapKnowledge.LEVEL_CONTENTS)
	_here = here
	_visited = visited
	_plan_of = plan_of
	var here_data := graph.get_node_data(here) if graph else null
	_current_depth = here_data.depth if here_data else -1
	_collect_content_sources()

	_level_label.text = tr("MAP_LEVEL") % [_level, MapKnowledge.LEVEL_CONTENTS]
	_build_layer_list()
	select_layer(_current_depth if _current_depth != -1 else _first_open_layer())


## Показывает слой [param depth]. Закрытый на этом уровне слой не выбирается —
## полоса у него и так неактивна, а переход по порталу туда не ведёт.
func select_layer(depth: int) -> void:
	if not MapKnowledge.is_layer_open(_level, depth, _current_depth):
		return
	_selected_depth = depth
	for layer_depth: int in _layer_buttons:
		(_layer_buttons[layer_depth] as UI_MapStratum).selected = layer_depth == depth
	_layer_title.text = _layer_name(depth)
	_build_floors()
	if _layer_buttons.has(depth):
		first_focus = _layer_buttons[depth]


func selected_layer() -> int:
	return _selected_depth


## Планы этажей выбранного слоя — для проверок: что показано и где.
func floor_views() -> Array[UI_MapFloor]:
	return _floors


## Строка про узел — то, что экран пишет под картой при наведении. Отдельно от
## обработчика, чтобы проверка могла спросить текст без мыши.
func describe(node_id: StringName) -> String:
	var node_data := _graph.get_node_data(node_id) if _graph else null
	if node_data == null:
		return ""
	var parts := PackedStringArray()
	if node_data.role == RS_LevelNode.Role.CORRIDOR:
		parts.append(tr("MAP_CORRIDOR"))
	else:
		parts.append(_room_name(node_data))

	if node_id == _here:
		parts.append(tr("MAP_HERE"))
	elif _visited.has(node_id):
		parts.append(tr("MAP_VISITED"))
	else:
		parts.append(tr("MAP_UNEXPLORED"))

	var conn := MapKnowledge.portal_of(_graph, node_data)
	if conn:
		var target := _graph.get_node_data(conn.target_node_id)
		var portal := tr("MAP_PORTAL_UP") if _leads_up(node_data, target) else tr("MAP_PORTAL_DOWN")
		if MapKnowledge.is_layer_open(_level, target.depth, _current_depth):
			portal += " " + tr("MAP_PORTAL_TARGET") % [target.depth, target.floor_index + 1]
		parts.append(portal)
		if _level >= MapKnowledge.LEVEL_CONTENTS and conn.is_locked():
			parts.append(tr("MAP_LOCKED") % tr(A_TravelThroughDoor.KEY_NAMES.get(conn.locked_by, String(conn.locked_by))))
	return " · ".join(parts)


## Второй конец портала узла, если он виден на этом уровне; иначе "".
func portal_pair(node_id: StringName) -> StringName:
	var node_data := _graph.get_node_data(node_id) if _graph else null
	if node_data == null:
		return &""
	var conn := MapKnowledge.portal_of(_graph, node_data)
	if conn == null:
		return &""
	var target := _graph.get_node_data(conn.target_node_id)
	var shown := MapKnowledge.visible_nodes(_graph, target.depth, _level, _current_depth, _visited)
	return target.id if shown.has(target) else &""


## Пометка содержимого комнаты для плана этажа, пусто — пометки нет. Только с
## четвёртого уровня: тип комнаты — это и есть «содержимое», которое он продаёт.
## Уникальная комната подписывается целиком (§9: «Выход», «Архитектор»), у
## обычной — значок типа или его первая буква.
func marker_of(node_data: RS_LevelNode) -> Dictionary:
	if _level < MapKnowledge.LEVEL_CONTENTS or node_data.role != RS_LevelNode.Role.ROOM:
		return {}
	var unique: RS_UniqueRoom = _unique_by_scene.get(node_data.room_scene_path)
	if unique:
		var label := tr(unique.map_label())
		return {"icon": unique.map_icon, "letter": _initial(label), "label": label, "unique": true}
	var type := _types.by_id(node_data.room_type) if _types and node_data.room_type != &"" else null
	if type:
		return {"icon": type.map_icon, "letter": _initial(tr(type.label())), "unique": false}
	return {}


func _collect_content_sources() -> void:
	_unique_by_scene.clear()
	var config := GameConfig.config
	var world_gen := config.world_gen if config else null
	if world_gen:
		for unique: RS_UniqueRoom in world_gen.unique_rooms:
			if unique and unique.preset and unique.preset.scene:
				_unique_by_scene[unique.preset.scene.resource_path] = unique
	var library := config.room_preset_library if config else null
	_types = library.type_catalog if library else null


# --- Срез -------------------------------------------------------------------


## Слои сверху вниз, от поверхности: так они и лежат в комплексе. Закрытый на
## этом уровне слой остаётся в срезе штриховкой — игрок видит, что знание можно
## докупить, а не гадает, сколько слоёв вообще бывает.
func _build_layer_list() -> void:
	for child in _slice.get_children():
		_slice.remove_child(child)
		child.queue_free()
	_layer_buttons.clear()
	_slice_portals.clear()
	var depths := _depths_from_surface()
	for depth: int in depths:
		var stratum := UI_MapStratum.new()
		_slice.add_child(stratum)
		var is_open := MapKnowledge.is_layer_open(_level, depth, _current_depth)
		var subtitle := ""
		if not is_open:
			subtitle = tr("MAP_LAYER_CLOSED")
		elif depth == depths.front():
			subtitle = tr("MAP_LAYER_SURFACE")
		elif depth == depths.back():
			subtitle = tr("MAP_LAYER_DEPTH")
		stratum.setup(depth, is_open, subtitle)
		if is_open:
			_fill_stratum(stratum)
		stratum.pressed.connect(select_layer.bind(depth))
		_layer_buttons[depth] = stratum
	_slice_links.queue_redraw()


## Этажи слоя линиями, на них комнаты — по их ширине в плане слоя. Показано то
## же, что на планах этого уровня (MapKnowledge.visible_nodes): срез не выдаёт
## больше, чем куплено.
func _fill_stratum(stratum: UI_MapStratum) -> void:
	var depth := stratum.depth
	var plan: RS_LayerPlan = _plan_of.call(depth)
	if plan == null:
		return
	var floor_count := 1
	for node_data in _graph.get_nodes_by_depth(depth):
		floor_count = maxi(floor_count, node_data.floor_index + 1)
	var span := _plan_span_x(plan)
	var floors: Array = []
	for i in floor_count:
		floors.append({"rooms": []})
	for node_data in MapKnowledge.visible_nodes(_graph, depth, _level, _current_depth, _visited):
		if node_data.role == RS_LevelNode.Role.CORRIDOR or not plan.cells.has(node_data.id):
			continue
		var cell: Vector3i = plan.cells[node_data.id]
		var footprint: Vector3i = plan.footprints.get(node_data.id, Vector3i.ONE)
		var floor_index := clampi(node_data.floor_index, 0, floor_count - 1)
		floors[floor_index]["rooms"].append({
			"from": (cell.x - span.x) / maxf(span.y, 1.0),
			"to": (cell.x + footprint.x - span.x) / maxf(span.y, 1.0),
			"explored": node_data.id == _here or _visited.has(node_data.id),
		})
		var conn := MapKnowledge.portal_of(_graph, node_data)
		if conn:
			var target := _graph.get_node_data(conn.target_node_id)
			if target and target.depth != depth \
					and MapKnowledge.is_layer_open(_level, target.depth, _current_depth):
				_slice_portals.append({
					"from": depth, "to": target.depth,
					"x": (cell.x + footprint.x * 0.5 - span.x) / maxf(span.y, 1.0),
				})
	stratum.floors = floors
	if depth == _current_depth:
		var here_data := _graph.get_node_data(_here)
		stratum.player_floor = here_data.floor_index if here_data else -1
		stratum.player_x = _player_x(plan, span)


## Левая клетка и ширина слоя по X — по комнатам и коридорам плана: полосы
## среза нормированы каждая на свой слой, у слоёв разная ширина.
func _plan_span_x(plan: RS_LayerPlan) -> Vector2:
	var low := INF
	var high := -INF
	for node_id: StringName in plan.cells:
		var cell: Vector3i = plan.cells[node_id]
		var footprint: Vector3i = plan.footprints.get(node_id, Vector3i.ONE)
		low = minf(low, cell.x)
		high = maxf(high, cell.x + footprint.x)
	for tile: Vector3i in plan.corridor_tiles:
		low = minf(low, tile.x)
		high = maxf(high, tile.x + 1)
	if low > high:
		return Vector2(0.0, 1.0)
	return Vector2(low, high - low)


## Где игрок по X в срезе: по позе, если игрок есть, иначе — середина его узла.
func _player_x(plan: RS_LayerPlan, span: Vector2) -> float:
	var player := UI_MapFloor.player_node()
	var x := 0.0
	if player and plan.embedding:
		x = plan.embedding.grid_point(player.global_position).x + 0.5
	elif plan.cells.has(_here):
		var cell: Vector3i = plan.cells[_here]
		x = cell.x + plan.footprints.get(_here, Vector3i.ONE).x * 0.5
	return clampf((x - span.x) / maxf(span.y, 1.0), 0.0, 1.0)


## Порталы между слоями — сиреневый пунктир 2:3 через границу полос (§9).
func _draw_slice_links() -> void:
	for portal in _slice_portals:
		var a: UI_MapStratum = _layer_buttons.get(portal["from"])
		var b: UI_MapStratum = _layer_buttons.get(portal["to"])
		if a == null or b == null:
			continue
		var upper := a if a.position.y < b.position.y else b
		var lower := b if upper == a else a
		var x := _slice.position.x + UI_MapStratum.LINES_X \
				+ float(portal["x"]) * (upper.size.x - UI_MapStratum.LINES_X - 8.0)
		var top := _slice.position.y + upper.position.y + upper.size.y - 18.0
		var bottom := _slice.position.y + lower.position.y + 20.0
		var y := top
		while y < bottom:
			_slice_links.draw_line(Vector2(x, y), Vector2(x, minf(y + 2.0, bottom)), Color(UI_HudMood.SOUL, 0.7), 1.2)
			y += 5.0


func _first_open_layer() -> int:
	for depth: int in _depths_from_surface():
		if MapKnowledge.is_layer_open(_level, depth, _current_depth):
			return depth
	return -1


static func _depths_from_surface() -> Array:
	var depths: Array = RS_LevelGraph.DEPTHS.duplicate()
	depths.sort()
	return depths


func _layer_name(depth: int) -> String:
	var depths := _depths_from_surface()
	var title := tr("MAP_LAYER") % depth
	if depth == depths.front():
		title += " · " + tr("MAP_LAYER_SURFACE")
	elif depth == depths.back():
		title += " · " + tr("MAP_LAYER_DEPTH")
	return title


# --- Планы этажей ---------------------------------------------------------------


## План на каждый этаж, где есть что показать. На первом уровне неизвестный
## этаж не рисуется вовсе: пустой план выдал бы, сколько этажей на слое.
## Планы — сеткой: число колонок выбирается так, чтобы клетка плана вышла
## крупнее (§9), а не всегда в ряд — два этажа рядом в узкой полосе были бы
## мельче, чем один над другим.
func _build_floors() -> void:
	for child in _plans.get_children():
		_plans.remove_child(child)
		child.queue_free()
	_floors.clear()
	_info.text = tr("MAP_HINT")
	if _selected_depth == -1:
		return

	var nodes := MapKnowledge.visible_nodes(_graph, _selected_depth, _level, _current_depth, _visited)
	var floor_indices: Array[int] = []
	for node_data in nodes:
		if not floor_indices.has(node_data.floor_index):
			floor_indices.append(node_data.floor_index)
	floor_indices.sort()
	if floor_indices.is_empty():
		return

	var plan: RS_LayerPlan = _plan_of.call(_selected_depth)
	var grid := _plan_grid(floor_indices.size(), plan)
	var player := UI_MapFloor.player_node()
	var here_data := _graph.get_node_data(_here)
	for i in floor_indices.size():
		var floor_index := floor_indices[i]
		var view := UI_MapFloor.new()
		view.plan = plan
		view.floor_index = floor_index
		view.here = _here
		view.visited = _visited
		view.max_step = MAX_STEP
		view.set_nodes(nodes)
		for node_data in view.rooms:
			var marker := marker_of(node_data)
			if not marker.is_empty():
				view.markers[node_data.id] = marker
			var conn := MapKnowledge.portal_of(_graph, node_data)
			if conn:
				view.portals[node_data.id] = {
					"up": _leads_up(node_data, _graph.get_node_data(conn.target_node_id)),
					"locked": _level >= MapKnowledge.LEVEL_CONTENTS and conn.is_locked(),
				}
		# Мир на паузе, так что позу хватает снять один раз.
		if player and here_data and here_data.depth == _selected_depth and here_data.floor_index == floor_index:
			view.show_player = true
			view.player_position = player.global_position
			view.player_forward = UI_MapFloor.forward_of(player)
		view.node_hovered.connect(_on_node_hovered)
		view.node_pressed.connect(_on_node_pressed)

		var columns: int = grid["columns"]
		var cell: Vector2 = grid["cell"]
		var origin := Vector2((i % columns) * (cell.x + PLAN_GAP), (i / columns) * (cell.y + PLAN_GAP))
		var title := Label.new()
		title.theme_type_variation = &"MenuMapLabel"
		title.uppercase = true
		title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		title.text = tr("MAP_FLOOR") % (floor_index + 1)
		title.position = origin
		_plans.add_child(title)
		view.position = origin + Vector2(0.0, PLAN_TITLE)
		view.size = cell - Vector2(0.0, PLAN_TITLE)
		_plans.add_child(view)
		_floors.append(view)
	_set_highlight(_pinned)


## Сетка планов, при которой клетка плана крупнее всего:
## { "columns": int, "cell": Vector2 — место под один план с подписью }.
func _plan_grid(count: int, plan: RS_LayerPlan) -> Dictionary:
	var cols := 1.0
	var rows := 1.0
	if plan:
		var low := Vector2(INF, INF)
		var high := Vector2(-INF, -INF)
		for node_id: StringName in plan.cells:
			var cell: Vector3i = plan.cells[node_id]
			var footprint: Vector3i = plan.footprints.get(node_id, Vector3i.ONE)
			low = low.min(Vector2(cell.x, cell.z))
			high = high.max(Vector2(cell.x + footprint.x, cell.z + footprint.z))
		for tile: Vector3i in plan.corridor_tiles:
			low = low.min(Vector2(tile.x, tile.z))
			high = high.max(Vector2(tile.x + 1, tile.z + 1))
		if low.x <= high.x:
			cols = maxf(high.x - low.x, 1.0)
			rows = maxf(high.y - low.y, 1.0)
	var best := {"columns": 1, "cell": _plans.size}
	var best_step := -1.0
	for columns in range(1, count + 1):
		var lines := ceili(float(count) / columns)
		var cell_size := Vector2(
			(_plans.size.x - PLAN_GAP * (columns - 1)) / columns,
			(_plans.size.y - PLAN_GAP * (lines - 1)) / lines
		)
		var step := minf(MAX_STEP, minf((cell_size.x - 16.0) / cols, (cell_size.y - PLAN_TITLE - 16.0) / rows))
		if step > best_step + 0.01:
			best_step = step
			best = {"columns": columns, "cell": cell_size}
	return best


func _on_node_hovered(node_id: StringName) -> void:
	_info.text = describe(node_id) if node_id != &"" else tr("MAP_HINT")
	var pair := portal_pair(node_id)
	_set_highlight(pair if pair != &"" else _pinned)
	for view in _floors:
		view.queue_redraw()


## Клик по порталу ведёт к его второму концу: другой слой открывается сам,
## второй конец остаётся в рамке, пока не кликнут по другому порталу.
func _on_node_pressed(node_id: StringName) -> void:
	var pair := portal_pair(node_id)
	if pair == &"":
		return
	_pinned = pair
	var target := _graph.get_node_data(pair)
	if target.depth != _selected_depth:
		# Отложенно: клик пришёл из _gui_input плана, который пересборка
		# слоя сейчас удалит.
		select_layer.call_deferred(target.depth)
	else:
		_set_highlight(pair)


func _set_highlight(node_id: StringName) -> void:
	for view in _floors:
		view.highlighted = node_id
		view.queue_redraw()


func _room_name(node_data: RS_LevelNode) -> String:
	if _level >= MapKnowledge.LEVEL_CONTENTS:
		var unique: RS_UniqueRoom = _unique_by_scene.get(node_data.room_scene_path)
		if unique:
			return tr(unique.map_label())
		var type := _types.by_id(node_data.room_type) if _types and node_data.room_type != &"" else null
		if type:
			return tr(type.label())
	return tr("MAP_ROOM")


## Вверх — к поверхности (меньшая глубина) или, в пределах слоя, на этаж выше:
## этажи слоя стоят один над другим по возрастанию индекса (RS_LayerPlan).
static func _leads_up(from: RS_LevelNode, to: RS_LevelNode) -> bool:
	if to.depth != from.depth:
		return to.depth < from.depth
	return to.floor_index > from.floor_index


static func _initial(label: String) -> String:
	return label.substr(0, 1).to_upper() if label != "" else "?"


func _on_close_pressed() -> void:
	UIManager.close_top()
