# res://src/ui/map/map_floor_view.gd
## Один этаж одного слоя в плане: комнаты, ветки коридора, пометки и маркер
## игрока.
##
## Рисовальщик общий для обеих карт — мини-карты в HUD (UI_HudMap) и панели
## этажа на экране карты (UI_ComplexMap). ЧТО показывать, решают они через
## MapKnowledge; этот контрол только кладёт отданные узлы на экран по плану слоя
## — тому же, по которому комнаты и тайлы расставлены в мире, поэтому «север на
## карте» и «север в игре» одно и то же. План считается без спавна, так что
## рисовать можно любой слой.
##
## После правки содержимого владелец сам зовёт queue_redraw(): мини-карта
## собирает содержимое прямо в _draw(), и перерисовка, запрошенная оттуда же,
## крутила бы контрол каждый кадр.
class_name UI_MapFloor
extends Control

## Курсор перешёл на другой узел; "" — ушёл с узлов.
signal node_hovered(node_id: StringName)
signal node_pressed(node_id: StringName)

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

@export_group("Пометки")
## Рамка вокруг выделенной комнаты — второго конца портала, на который навели.
@export var color_highlight: Color = Color(0.55, 0.9, 1.0, 1.0)
@export var color_portal: Color = Color(0.72, 0.6, 1.0, 1.0)
@export var color_locked: Color = Color(0.95, 0.4, 0.35, 1.0)
## Подложка значка содержимого. Значок ложится на заливку комнаты любого цвета,
## и светлый значок без подложки пропадает в текущей, почти белой, комнате.
@export var color_marker_back: Color = Color(0.08, 0.09, 0.11, 0.85)
@export var color_marker: Color = Color(0.9, 0.92, 0.96, 1.0)
## Уникальные комнаты (выход, Архитектор) — своим цветом: пока вместо иконок
## буквы, «А» Архитектора иначе не отличить от «А» арсенала.
@export var color_unique_marker: Color = Color(1.0, 0.8, 0.35, 1.0)

@export_group("Прочее")
## Подложка всего контрола. У мини-карты она своя (MapPanel), а на экране карты
## без неё два плана этажей рядом читаются как один.
@export var color_background: Color = Color(0, 0, 0, 0)
## Отступ от краёв контрола, чтобы комнаты не липли к рамке.
@export var padding: float = 8.0
## Потолок шага клетки в пикселях; 0 — без потолка. На экране карты этаж из
## двух известных комнат иначе раздуло бы на всю панель.
@export var max_step: float = 0.0

## План слоя, которому принадлежит этаж.
var plan: RS_LayerPlan
var floor_index: int = 0
## Что показано — уже отобранное владельцем (set_nodes).
var rooms: Array[RS_LevelNode] = []
var branches: Array[RS_LevelNode] = []
var here: StringName = &""
var visited: Array[StringName] = []
## Комната в рамке; "" — никого.
var highlighted: StringName = &""
## Пометки содержимого: node_id -> {"icon": Texture2D или null, "letter": String,
## "unique": bool}. Кто их получает, решает экран — на мини-карте их нет.
var markers: Dictionary[StringName, Dictionary] = {}
## Порталы: node_id -> {"up": bool, "locked": bool}.
var portals: Dictionary[StringName, Dictionary] = {}
## Маркер игрока. Позу снимает владелец: мини-карта опрашивает игрока на ходу,
## экран карты — один раз при открытии (мир на паузе).
var show_player: bool = false
var player_position: Vector3 = Vector3.ZERO
var player_forward: Vector2 = Vector2.DOWN

## Вписывание: сколько пикселей в клетке и где на экране нулевая клетка. Считается
## в fit() один раз на отрисовку и держится полями — им пользуются и комнаты, и
## коридоры, и маркер, и обратная проекция под курсором.
var _step := 0.0
var _origin := Vector2.ZERO
var _min_cell := Vector2.ZERO
var _hovered: StringName = &""


## Раскладывает узлы по комнатам и веткам. Чужие этажи отсеиваются здесь, чтобы
## экран мог отдать всем панелям один и тот же список слоя.
func set_nodes(nodes: Array[RS_LevelNode]) -> void:
	rooms.clear()
	branches.clear()
	if plan == null:
		return
	for node_data in nodes:
		if node_data.floor_index != floor_index:
			continue
		if node_data.role == RS_LevelNode.Role.CORRIDOR:
			branches.append(node_data)
		elif plan.cells.has(node_data.id):
			rooms.append(node_data)


## Показан ли узел — комнатой или веткой.
func shows(node_id: StringName) -> bool:
	for node_data in rooms:
		if node_data.id == node_id:
			return true
	for node_data in branches:
		if node_data.id == node_id:
			return true
	return false


## Вписывает показанное в контрол. false — показывать нечего.
func fit() -> bool:
	if plan == null:
		return false
	var cells: Array[Vector2i] = []
	for branch in branches:
		cells.append_array(tiles_of(branch.id))
	for node_data in rooms:
		cells.append(plan.cells[node_data.id])
	if cells.is_empty():
		return false
	_fit(cells)
	return true


func _draw() -> void:
	if color_background.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), color_background, true)
	if not fit():
		return
	_draw_corridors()
	_draw_rooms()
	_draw_highlight()
	_draw_portals()
	_draw_markers()
	_draw_player()


## Вписывает клетки в контрол, сохраняя пропорции, чтобы карта не растягивалась
## в кисель.
func _fit(cells: Array[Vector2i]) -> void:
	var min_cell := Vector2i(cells[0])
	var max_cell := Vector2i(cells[0])
	for cell in cells:
		min_cell = Vector2i(mini(min_cell.x, cell.x), mini(min_cell.y, cell.y))
		max_cell = Vector2i(maxi(max_cell.x, cell.x), maxi(max_cell.y, cell.y))
	var span := Vector2(max_cell - min_cell) + Vector2.ONE
	var area := size - Vector2(padding, padding) * 2.0
	_step = minf(area.x / span.x, area.y / span.y)
	if max_step > 0.0:
		_step = minf(_step, max_step)
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


## Показанный узел под точкой контрола или "". Обратная to_screen: клетка ищется
## в том же плане, по которому рисовали, — отдельной геометрии под курсор нет.
func node_at_point(point: Vector2) -> StringName:
	if plan == null or _step <= 0.0:
		return &""
	var cell := (point - _origin) / _step + _min_cell - Vector2(0.5, 0.5)
	var node_id: StringName = plan.node_by_cell.get(Vector3i(roundi(cell.x), floor_index, roundi(cell.y)), &"")
	return node_id if node_id != &"" and shows(node_id) else &""


## Клетки тайлов ветки на этом этаже.
func tiles_of(branch: StringName) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for cell: Vector3i in plan.corridor_tiles:
		if cell.y == floor_index and plan.node_by_cell.get(cell, &"") == branch:
			tiles.append(Vector2i(cell.x, cell.z))
	return tiles


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouse
	if mouse == null:
		return
	var node_id := node_at_point(mouse.position)
	if node_id != _hovered:
		_hovered = node_id
		node_hovered.emit(node_id)
	var button := event as InputEventMouseButton
	if button and button.pressed and button.button_index == MOUSE_BUTTON_LEFT and node_id != &"":
		# До сигнала: обработчик вправе пересобрать экран, и после него контрола
		# может уже не быть в дереве.
		accept_event()
		node_pressed.emit(node_id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered != &"":
		_hovered = &""
		node_hovered.emit(&"")


func _color_of(node_id: StringName) -> Color:
	if node_id == here:
		return color_current
	return color_visited if visited.has(node_id) else color_known


## Ветка — полосой по трассе: квадрат в центре тайла и рукав к каждому открытому
## проёму, как рисует оверлей «Коридоры» в «Генераторе мира». Рукав к двери
## комнаты упирается в её прямоугольник, поэтому дверь на карте видна как место,
## где коридор входит в комнату.
func _draw_corridors() -> void:
	var width := _step * corridor_width
	for branch in branches:
		var color := _color_of(branch.id)
		for cell in tiles_of(branch.id):
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


func _room_rect(node_id: StringName) -> Rect2:
	var room := Vector2(_step, _step) * room_fill
	var center := to_screen(Vector2(plan.cells[node_id]))
	return Rect2(center - room * 0.5, room)


func _draw_rooms() -> void:
	for node_data in rooms:
		var rect := _room_rect(node_data.id)
		if node_data.id == here or visited.has(node_data.id):
			draw_rect(rect, _color_of(node_data.id), true)
		else:
			# Знаем, что есть, но не были — только контур.
			draw_rect(rect, color_known, false, 1.5)


func _draw_highlight() -> void:
	if highlighted == &"" or not plan.cells.has(highlighted) or not shows(highlighted):
		return
	draw_rect(_room_rect(highlighted).grow(_step * 0.08), color_highlight, false, 2.0)


## Портал — ромб в углу комнаты со стрелкой: центр занят значком содержимого.
## Вверх — к поверхности или на этаж выше; запертый — другим цветом.
func _draw_portals() -> void:
	var radius := _step * 0.15
	for node_data in rooms:
		if not portals.has(node_data.id):
			continue
		var info: Dictionary = portals[node_data.id]
		var rect := _room_rect(node_data.id)
		var center := Vector2(rect.end.x - radius * 1.2, rect.position.y + radius * 1.2)
		var diamond := PackedVector2Array([
			center + Vector2(0, -radius), center + Vector2(radius, 0),
			center + Vector2(0, radius), center + Vector2(-radius, 0),
		])
		draw_colored_polygon(diamond, color_locked if info.get("locked", false) else color_portal)
		var closed := PackedVector2Array(diamond)
		closed.append(diamond[0])
		draw_polyline(closed, color_player_outline, 1.0)
		# Экранная ось Y смотрит вниз, поэтому «вверх» — это минус.
		var tip := -1.0 if info.get("up", false) else 1.0
		draw_colored_polygon(PackedVector2Array([
			center + Vector2(0, tip * radius * 0.6),
			center + Vector2(radius * 0.45, -tip * radius * 0.3),
			center + Vector2(-radius * 0.45, -tip * radius * 0.3),
		]), color_marker_back)


## Значок содержимого по центру комнаты. Пока нет арта, вместо иконки —
## первая буква названия: заглушка обязана быть различимой, иначе четвёртый
## уровень карты до прихода иконок ничего бы не показывал.
func _draw_markers() -> void:
	var font := get_theme_default_font()
	for node_data in rooms:
		if not markers.has(node_data.id):
			continue
		var info: Dictionary = markers[node_data.id]
		var center := _room_rect(node_data.id).get_center()
		var radius := _step * room_fill * 0.3
		var tint: Color = color_unique_marker if info.get("unique", false) else color_marker
		draw_circle(center, radius, color_marker_back)
		var icon: Texture2D = info.get("icon")
		if icon:
			var side := radius * 1.5
			draw_texture_rect(icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)
		elif font:
			var letter: String = info.get("letter", "")
			var font_size := maxi(int(radius * 1.2), 6)
			var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			draw_string(font, Vector2(center.x - width * 0.5, baseline), letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, tint)
		draw_arc(center, radius, 0.0, TAU, 24, tint, 1.0)


## Маркер игрока: где он и куда смотрит. Позиция — прямо из мира через шаг
## клетки: комнаты и коридоры лежат на одной сетке, и игрок законно бывает
## между ними (в тамбуре, на стыке), так что зажимать маркер в своей комнате,
## как в прежней раскладке, больше нечем и незачем.
func _draw_player() -> void:
	if not show_player:
		return
	var center := world_to_screen(player_position)
	var side := Vector2(-player_forward.y, player_forward.x)
	var radius := _step * marker_size
	var points := PackedVector2Array(
		[
			center + player_forward * radius,
			center - player_forward * radius * 0.55 + side * radius * 0.6,
			center - player_forward * radius * 0.55 - side * radius * 0.6,
		]
	)
	draw_colored_polygon(points, color_player)

	var outline := PackedVector2Array(points)
	outline.append(points[0])
	draw_polyline(outline, color_player_outline, 1.0)


## Игрок как узел сцены. Карты опрашивают мир напрямую — та же схема, что в
## UI_HudVitals. Через Node: Entity наследует Node, и прямой каст Entity→Node3D
## анализатор GDScript не пропускает (тот же приём, что в RunManager).
static func player_node() -> Node3D:
	if ECS.world == null:
		return null
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as Node as Node3D


## Куда смотрит игрок, в осях карты. Клетка — это Vector2i(x, z) (RS_RoomLayout),
## поэтому мировые X и Z ложатся на экранные X и Y напрямую. Направление берём из
## базиса узла, а не собираем из угла рыскания: «вперёд» у Node3D — это −Z, и
## складывать это из синусов руками значит один раз ошибиться знаком.
##
## Рыскание живёт на самой сущности (S_FPSLook зовёт player.rotate_y), тангаж — на
## камере, так что взгляд вверх маркер не заваливает.
static func forward_of(player: Node3D) -> Vector2:
	var forward := -player.global_basis.z
	var flat := Vector2(forward.x, forward.z)
	return flat.normalized() if flat.length_squared() > 0.000001 else Vector2.DOWN
