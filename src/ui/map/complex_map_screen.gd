# res://src/ui/map/complex_map_screen.gd
## Экран карты комплекса: большая карта на паузе, которую надо заслужить.
##
## Мини-карта в HUD даёт базовую ориентацию всегда, а здесь покупается ЗНАНИЕ
## НАПЕРЁД: сколько именно, решает уровень улучшения у Архитектора
## (ArchitectManager.map_level(), уровни — MapKnowledge). Слева список слоёв,
## справа план выбранного слоя, все его этажи рядом, каждый своей панелью: в
## мире этажи разнесены по высоте и в одной плоскости соседями не являются.
## Связывает панели портал — наведение подсвечивает его второй конец, клик
## переносит к нему, в том числе на другой слой.
##
## Данные экран получает в setup(), а не берёт у автолоадов сам: так его можно
## собрать и проверить на любом сгенерированном графе, не запуская забег.
class_name UI_ComplexMap
extends Control

## Потолок клетки на экране, пикселей: этаж из двух известных комнат иначе
## раздуло бы на всю панель, и шаг карты скакал бы от слоя к слою.
const MAX_STEP := 44.0
## Подложка панели этажа — граница между этажами, иначе два плана рядом
## читаются как один.
const FLOOR_BACKGROUND := Color(1, 1, 1, 0.035)

@onready var _level_label: Label = %LevelLabel
@onready var _layers: VBoxContainer = %Layers
@onready var _floors_box: HBoxContainer = %Floors
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
## кнопка у него и так неактивна, а переход по порталу туда не ведёт.
func select_layer(depth: int) -> void:
	if not MapKnowledge.is_layer_open(_level, depth, _current_depth):
		return
	_selected_depth = depth
	for layer_depth: int in _layer_buttons:
		_layer_buttons[layer_depth].set_pressed_no_signal(layer_depth == depth)
	_build_floors()


func selected_layer() -> int:
	return _selected_depth


## Панели этажей выбранного слоя — для проверок: что показано и где.
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
			parts.append(tr("MAP_LOCKED") % A_TravelThroughDoor.KEY_NAMES.get(conn.locked_by, String(conn.locked_by)))
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


## Пометка содержимого комнаты для панели этажа, пусто — пометки нет. Только с
## четвёртого уровня: тип комнаты — это и есть «содержимое», которое он продаёт.
func marker_of(node_data: RS_LevelNode) -> Dictionary:
	if _level < MapKnowledge.LEVEL_CONTENTS or node_data.role != RS_LevelNode.Role.ROOM:
		return {}
	var unique: RS_UniqueRoom = _unique_by_scene.get(node_data.room_scene_path)
	if unique:
		return {"icon": unique.map_icon, "letter": _initial(tr(unique.map_label())), "unique": true}
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


## Слои сверху вниз, от поверхности: так они и лежат в комплексе. Закрытый на
## этом уровне слой остаётся в списке неактивным — игрок видит, что знание
## можно докупить, а не гадает, сколько слоёв вообще бывает.
func _build_layer_list() -> void:
	for child in _layers.get_children():
		_layers.remove_child(child)
		child.queue_free()
	_layer_buttons.clear()
	for depth: int in _depths_from_surface():
		var button := Button.new()
		button.toggle_mode = true
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_NONE
		var text := tr("MAP_LAYER") % depth
		if depth == _current_depth:
			text += " · " + tr("MAP_HERE")
		elif not MapKnowledge.is_layer_open(_level, depth, _current_depth):
			text += " · " + tr("MAP_LAYER_CLOSED")
		button.text = text
		button.disabled = not MapKnowledge.is_layer_open(_level, depth, _current_depth)
		button.pressed.connect(select_layer.bind(depth))
		_layers.add_child(button)
		_layer_buttons[depth] = button


func _first_open_layer() -> int:
	for depth: int in _depths_from_surface():
		if MapKnowledge.is_layer_open(_level, depth, _current_depth):
			return depth
	return -1


static func _depths_from_surface() -> Array:
	var depths: Array = RS_LevelGraph.DEPTHS.duplicate()
	depths.sort()
	return depths


## Панель на каждый этаж, где есть что показать. На первом уровне неизвестный
## этаж не рисуется вовсе: пустая панель выдала бы, сколько этажей на слое.
func _build_floors() -> void:
	for child in _floors_box.get_children():
		_floors_box.remove_child(child)
		child.queue_free()
	_floors.clear()
	_info.text = ""
	if _selected_depth == -1:
		return

	var nodes := MapKnowledge.visible_nodes(_graph, _selected_depth, _level, _current_depth, _visited)
	var floor_indices: Array[int] = []
	for node_data in nodes:
		if not floor_indices.has(node_data.floor_index):
			floor_indices.append(node_data.floor_index)
	floor_indices.sort()

	var plan: RS_LayerPlan = _plan_of.call(_selected_depth)
	var player := UI_MapFloor.player_node()
	var here_data := _graph.get_node_data(_here)
	for floor_index in floor_indices:
		var view := UI_MapFloor.new()
		view.plan = plan
		view.floor_index = floor_index
		view.here = _here
		view.visited = _visited
		view.max_step = MAX_STEP
		view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		view.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
		view.color_background = FLOOR_BACKGROUND
		view.node_hovered.connect(_on_node_hovered)
		view.node_pressed.connect(_on_node_pressed)
		_floors_box.add_child(_floor_column(floor_index, view))
		_floors.append(view)
	_set_highlight(_pinned)


func _floor_column(floor_index: int, view: UI_MapFloor) -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.text = tr("MAP_FLOOR") % (floor_index + 1)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(view)
	return column


func _on_node_hovered(node_id: StringName) -> void:
	_info.text = describe(node_id)
	var pair := portal_pair(node_id)
	_set_highlight(pair if pair != &"" else _pinned)


## Клик по порталу ведёт к его второму концу: другой слой открывается сам,
## второй конец остаётся в рамке, пока не кликнут по другому порталу.
func _on_node_pressed(node_id: StringName) -> void:
	var pair := portal_pair(node_id)
	if pair == &"":
		return
	_pinned = pair
	var target := _graph.get_node_data(pair)
	if target.depth != _selected_depth:
		# Отложенно: клик пришёл из _gui_input панели, которую пересборка
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
