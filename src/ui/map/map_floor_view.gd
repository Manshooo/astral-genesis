# res://src/ui/map/map_floor_view.gd
## Один этаж одного слоя в плане: комнаты, ветки коридора, пометки и маркер
## игрока.
##
## Раскладка общая для обеих карт — мини-карты в HUD (UI_MiniMap) и панели
## этажа на экране карты (UI_ComplexMap); рисует так панель экрана, мини-карта
## рисует по-своему поверх той же раскладки. ЧТО показывать, решают они через
## MapKnowledge; этот контрол только кладёт отданные узлы на экран по плану слоя
## — тому же, по которому комнаты и тайлы расставлены в мире, поэтому «север на
## карте» и «север в игре» одно и то же. План считается без спавна, так что
## рисовать можно любой слой.
##
## Рисунок панели — язык «Отголосок» экрана карты (§9 «Меню — спека»): комната —
## рамка (посещённая — с сиреневой заливкой, неисследованная — пунктиром,
## лестница — со штриховкой), коридор — линия по оси, портал — кольцо со
## стрелкой, игрок — точка с дышащим ореолом там, где он стоит. Мини-карта
## рисует свой язык поверх той же раскладки (решение 02.10: полная карта — по
## спеке меню, а не языком мини-карты).
##
## После правки содержимого владелец сам зовёт queue_redraw(): перерисовка,
## запрошенная из самого _draw(), крутила бы контрол каждый кадр. Исключение —
## ореол игрока: он дышит, и пока игрок на панели, она перерисовывается сама.
class_name UI_MapFloor
extends Control

## Курсор перешёл на другой узел; "" — ушёл с узлов.
signal node_hovered(node_id: StringName)
signal node_pressed(node_id: StringName)

@export_group("Комнаты")
## Какую долю крайней клетки занимает комната у своего края. Комната занимает
## свои клетки целиком (стена — на границе клетки), зазор нужен, только чтобы
## соседние комнаты не слипались в пятно.
@export_range(0.1, 1.0) var room_fill: float = 0.82

@export_group("Коридоры")
## Толщина линии коридора, px: коридор на плане — ось, а не полоса, иначе
## клетки коридора и комнаты при шаге в 34 px читались бы одним пятном.
@export var corridor_width: float = 2.4

@export_group("Прочее")
## Подложка всего контрола. Мини-карте не нужна (у неё тень-пятно); экрану
## карты тоже — этажи разведены зазором и подписью, а не плашкой.
@export var color_background: Color = Color(0, 0, 0, 0)
## Отступ от краёв контрола, чтобы комнаты не липли к краю.
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
## экран мог отдать всем панелям один и тот же список слоя. Комната — на каждом
## этаже, который занимает её footprint, а не только на этаже узла: лестница
## числится нижним этажом, а коридор этажа выше упирается в её верхнюю дверь.
func set_nodes(nodes: Array[RS_LevelNode]) -> void:
	rooms.clear()
	branches.clear()
	if plan == null:
		return
	for node_data in nodes:
		if node_data.role == RS_LevelNode.Role.CORRIDOR:
			if node_data.floor_index == floor_index:
				branches.append(node_data)
		elif plan.cells.has(node_data.id) and _spans_floor(node_data.id):
			rooms.append(node_data)


func _spans_floor(node_id: StringName) -> bool:
	var bottom: int = plan.cells[node_id].y
	var height: int = plan.footprints.get(node_id, Vector3i.ONE).y
	return floor_index >= bottom and floor_index < bottom + height


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
		cells.append(_planar(plan.cells[node_data.id]))
		cells.append(_far_corner(node_data.id))
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
	_draw_markers()
	_draw_portals()
	_draw_player()


func _process(_delta: float) -> void:
	if show_player and is_visible_in_tree():
		queue_redraw()


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


## Точка на экране для мировой позиции: метры в клетки переводит вложение плана —
## то же, по которому комнаты и тайлы расставлены в мире.
func world_to_screen(world_position: Vector3) -> Vector2:
	var point := plan.embedding.grid_point(world_position)
	return to_screen(Vector2(point.x, point.z))


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
			tiles.append(_planar(cell))
	return tiles


## Клетка на плане этажа: карта — вид сверху, X клетки идёт вправо, Z — вниз.
static func _planar(cell: Vector3i) -> Vector2i:
	return Vector2i(cell.x, cell.z)


## Дальний от угловой клетки угол footprint комнаты на плане. У комнаты в одну
## клетку — та же клетка.
func _far_corner(node_id: StringName) -> Vector2i:
	var size: Vector3i = plan.footprints.get(node_id, Vector3i.ONE)
	return _planar(plan.cells[node_id]) + Vector2i(size.x - 1, size.z - 1)


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


## Посещённое (и текущее) — изведано; про остальное известно лишь, что оно
## есть. От этого зависит, сплошная линия или пунктир.
func _explored(node_id: StringName) -> bool:
	return node_id == here or visited.has(node_id)


## Коридор — ось по трассе: из центра каждого тайла к каждому открытому проёму,
## до границы клетки. Рукав к двери комнаты упирается в её рамку, поэтому дверь
## на плане видна как место, где линия входит в комнату. Неисследованный —
## пунктиром 3:4, бледно.
func _draw_corridors() -> void:
	for branch in branches:
		var explored := _explored(branch.id)
		var color := Color(UI_MenuStyle.TEXT, 0.5) if explored else Color(UI_MenuStyle.TEXT, 0.2)
		for cell in tiles_of(branch.id):
			var center := to_screen(Vector2(cell))
			var tile := Vector3i(cell.x, floor_index, cell.y)
			var mask: int = plan.corridor_tiles[tile]
			for side in plan.topology.side_count(tile):
				if mask & (1 << side) == 0:
					continue
				var offset := Vector2(_planar(plan.topology.neighbour(tile, side)) - cell)
				var arm_end := center + offset * _step * 0.5
				if explored:
					draw_line(center, arm_end, color, corridor_width, true)
				else:
					_draw_plan_dash(center, arm_end, color, 2.0, 3.0, 4.0)


## Прямоугольник комнаты на весь её footprint: от центра угловой клетки до центра
## дальней, плюс доля клетки room_fill — зазор у края тот же, что у комнаты в клетку.
func _room_rect(node_id: StringName) -> Rect2:
	var first := to_screen(Vector2(_planar(plan.cells[node_id])))
	var last := to_screen(Vector2(_far_corner(node_id)))
	var room := (last - first) + Vector2(_step, _step) * room_fill
	return Rect2((first + last) * 0.5 - room * 0.5, room)


## Лестница — комната на два этажа и больше: так её и узнаём, по footprint, а не
## по имени сцены.
func _is_stairs(node_id: StringName) -> bool:
	return plan.footprints.get(node_id, Vector3i.ONE).y > 1


## Комната — рамка: посещённая — светлая с сиреневой заливкой, неисследованная
## — пунктиром; лестница — с вертикальной штриховкой, уникальная (с подписью на
## последнем уровне) — рамкой цвета клавиши. Наведённая — сиреневым с ореолом.
func _draw_rooms() -> void:
	for node_data in rooms:
		var rect := _room_rect(node_data.id)
		var explored := _explored(node_data.id)
		draw_rect(rect, Color(UI_MenuStyle.BG_VOID, 0.35), true)
		if explored:
			draw_rect(rect, Color(UI_HudMood.SOUL, 0.10), true)
		if _is_stairs(node_data.id):
			var x := rect.position.x + 2.5
			while x < rect.end.x - 1.0:
				draw_line(Vector2(x, rect.position.y + 1.0), Vector2(x, rect.end.y - 1.0),
						Color(UI_MenuStyle.TEXT, 0.28), 1.0)
				x += 5.0
		var unique: bool = markers.get(node_data.id, {}).get("unique", false)
		var border := Color(UI_MenuStyle.TEXT, 0.75) if explored else Color(UI_MenuStyle.TEXT, 0.30)
		if unique:
			border = UI_HudMood.SOUL_KEY
		if node_data.id == _hovered:
			draw_rect(rect.grow(3.0), Color(UI_HudMood.SOUL, 0.16), false, 3.0)
			border = UI_HudMood.SOUL
		if explored or unique or node_data.id == _hovered:
			draw_rect(rect, border, false, 1.0)
		else:
			_draw_plan_dash_rect(rect, border)


## Второй конец портала, на который навели или по которому кликнули: рамка в
## полную силу и ореол.
func _draw_highlight() -> void:
	if highlighted == &"" or not plan.cells.has(highlighted) or not shows(highlighted):
		return
	var rect := _room_rect(highlighted)
	draw_rect(rect.grow(2.0), Color(UI_HudMood.SOUL, 0.3), false, 6.0)
	draw_rect(rect, UI_HudMood.OVER, false, 1.0)


## Портал — кольцо Ø22 со стрелкой в углу комнаты: центр занят подписью. Вверх
## — к поверхности или на этаж выше. Запертый — пунктирным кольцом: красного в
## меню нет, красный в игре — тело и кровь (§2).
func _draw_portals() -> void:
	var radius := minf(11.0, _step * 0.45)
	for node_data in rooms:
		if not portals.has(node_data.id):
			continue
		var info: Dictionary = portals[node_data.id]
		var rect := _room_rect(node_data.id)
		var center := Vector2(rect.end.x - radius * 0.4, rect.position.y + radius * 0.4)
		draw_circle(center, radius, UI_MenuStyle.BG_VOID)
		if info.get("locked", false):
			var a := 0.0
			while a < TAU:
				draw_arc(center, radius, a, a + 0.3, 4, UI_HudMood.SOUL, 1.0, true)
				a += 0.6
		else:
			draw_arc(center, radius, 0.0, TAU, 32, UI_HudMood.SOUL, 1.0, true)
		# Экранная ось Y смотрит вниз, поэтому «вверх» — это минус.
		var tip := -1.0 if info.get("up", false) else 1.0
		var k := radius / 11.0
		draw_line(center + Vector2(0, -tip * 4.5 * k), center + Vector2(0, tip * 4.5 * k), UI_HudMood.SOUL, 1.4, true)
		draw_polyline(PackedVector2Array([
			center + Vector2(-3.5 * k, tip * 1.0 * k),
			center + Vector2(0, tip * 4.5 * k),
			center + Vector2(3.5 * k, tip * 1.0 * k),
		]), UI_HudMood.SOUL, 1.4, true)


## Содержимое комнаты на последнем уровне карты. Уникальная (выход, Архитектор,
## хаб) — подписью по центру, как в макете; обычная — значком типа или, пока
## нет арта, первой буквой: заглушка обязана быть различимой.
func _draw_markers() -> void:
	var font := get_theme_font(&"font", &"MenuMapUnique")
	var font_size := get_theme_font_size(&"font_size", &"MenuMapUnique")
	for node_data in rooms:
		if not markers.has(node_data.id):
			continue
		var info: Dictionary = markers[node_data.id]
		var rect := _room_rect(node_data.id)
		var center := rect.get_center()
		var unique: bool = info.get("unique", false)
		var label: String = info.get("label", "") if unique else ""
		if label != "" and font:
			var shown := label
			while shown.length() > 1 and font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > rect.size.x - 4.0:
				shown = shown.substr(0, shown.length() - 1)
			var width := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			var baseline := center.y + (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5
			draw_string(font, Vector2(center.x - width * 0.5, baseline), shown,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI_HudMood.SOUL_KEY)
			continue
		var tint := UI_HudMood.SOUL_KEY if unique else UI_MenuStyle.TEXT_DIM
		var icon: Texture2D = info.get("icon")
		var side := minf(rect.size.x, rect.size.y) * 0.5
		if icon:
			draw_texture_rect(icon, Rect2(center - Vector2(side, side) * 0.5, Vector2(side, side)), false, tint)
		elif font:
			var letter: String = info.get("letter", "")
			var letter_size := maxi(int(side * 0.8), 8)
			var width := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, letter_size).x
			var baseline := center.y + (font.get_ascent(letter_size) - font.get_descent(letter_size)) * 0.5
			draw_string(font, Vector2(center.x - width * 0.5, baseline), letter,
					HORIZONTAL_ALIGNMENT_LEFT, -1, letter_size, tint)


## Игрок — точка прицела HUD с дышащим ореолом (§7, цикл 3.2 с) там, где он
## стоит, а не в центре комнаты: в коридоре и на стыке иначе нечем показать, где
## ты (то же решение, что у мини-карты).
func _draw_player() -> void:
	if not show_player:
		return
	var center := world_to_screen(player_position)
	var k := 0.5 + 0.5 * sin(TAU * UI_HudMood.now() / 3.2)
	draw_circle(center, 10.0 * lerpf(0.92, 1.08, k), Color(UI_HudMood.DOT, lerpf(0.10, 0.16, k)))
	draw_circle(center, 4.2, UI_HudMood.DOT)


func _draw_plan_dash(from: Vector2, to: Vector2, color: Color, width: float, dash: float, gap: float) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var d := 0.0
	while d < length:
		draw_line(from + direction * d, from + direction * minf(d + dash, length), color, width)
		d += dash + gap


func _draw_plan_dash_rect(rect: Rect2, color: Color) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for i in 4:
		_draw_plan_dash(corners[i], corners[(i + 1) % 4], color, 1.0, 3.0, 3.0)


## Игрок как узел сцены. Через Node: Entity наследует Node, и прямой каст
## Entity→Node3D анализатор GDScript не пропускает (тот же приём, что в RunManager).
static func player_node() -> Node3D:
	return E_Player.find() as Node as Node3D


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
