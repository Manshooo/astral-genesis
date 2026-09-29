## res://src/resources/world_generator/rs_corridor_planner.gd
## Коридорная раскладка этажа: комнаты вразброс, сеть коридоров — дерево по
## клеткам сетки, связывающее все двери этажа, и петли с тупиками поверх него.
## Здесь же решается, какие в сети коридоры и в какой ведёт каждая дверь: граф
## берёт эти узлы и рёбра из раскладки (RS_LevelGraph._lay_out_floor), а не
## диктует их ей.
##
## Почему решает раскладка, а не граф (п. 7 карточки «Сетка уровня»): пока граф
## заранее назначал двери веткам, укладки могло не существовать вовсе — двери в
## случайные ветки не трассировались на 8 % этажей, а лекарство «все двери комнаты
## в одну ветку» заставляло ветку обходить комнату кругом (42 % обволакиваемых
## комнат). Здесь сеть на этаже одна и растёт от двери к ближайшему уже
## проложенному коридору, поэтому трасса есть всегда; на коридоры её режут уже
## готовой — по развилкам (карточка «Коридор — отдельный узел»). Подход «хребет с
## комнатами по сторонам» сравнивался с этим на тех же сидах — цифры в карточке
## «Сетка уровня».
##
## Работает только в клетках и сторонах топологии (карточка «Сетка уровня»): где
## клетка стоит в мире, решает вложение плана, и отсюда его не видно. Квадратная
## здесь только расстановка комнат — область этажа и footprint'ы как
## прямоугольники по X и Z; это свойство алгоритма раскладки, а не сетки.
##
## Случайность — только из переданного rng, своего потока этажа: раскладка
## разыгрывается внутри генерации графа, и общий поток сдвигался бы от любой
## правки здесь.
@tool
class_name RS_CorridorPlanner
extends RefCounted

## Запас клеток вокруг комнат этажа, по которому может пройти сеть: дверь,
## смотрящая наружу, обходит комнаты по краю.
const ROUTE_MARGIN := 1
## Предел расширения запаса, если трасса не нашлась: дальше она уже не обходит
## препятствие, а значит, её заперли.
const MAX_ROUTE_MARGIN := 7
## Цена поворота сверх шага. Без неё первый же прогон дал 43 % поворотов.
const TURN_COST := 3
## Со скольких сторон комнаты ставятся двери, пока на этих сторонах хватает
## сокетов. Дверь на третьей стороне — это коридор с трёх сторон комнаты, то самое
## обволакивание; у коробки 2×2 на двух сторонах четыре сокета, этого хватает
## любой нынешней комнате.
const DOOR_SIDES := 2
## Сколько случайных точек пробует каждая комната при разбросе (_place_rooms).
## Из годных выбор взвешен шумом, поэтому точек нужно больше одной: при одной
## шум ничего не решал бы.
const SCATTER_TRIES := 24
## Частота шума плотности в клетках: пятно — около 1 / 0.08 ≈ 12 клеток, то есть
## на этаж приходится одно-два сгущения комнат, а не рябь от клетки к клетке.
const NOISE_FREQUENCY := 0.08
## Насколько сильно шум тянет комнаты в сгущения: вес точки — шум в этой
## степени. При 1 разница между пятном и пустырём тонет в случайности броска.
const NOISE_SHARPNESS := 3.0
## Предел вытянутости области этажа (длинная сторона к короткой).
const MAX_ASPECT := 2.0
## Сколько раз ствол сети ищет обход комнаты, которую обволок (_route_around).
const ENVELOP_RETRIES := 3
## Петля, срезающая по сети меньше этого, — обход пары клеток, а не другой путь.
const MIN_LOOP_GAIN := 6
## Тупик — отросток не длиннее этого: длиннее он читается уже коридором, который
## куда-то ведёт.
const DEAD_END_LENGTH := 2

var _plan: RS_LayerPlan
var _topology: GridTopology
var _level := 0
## Клетка комнаты -> комната.
var _room_at: Dictionary[Vector3i, StringName] = {}
## Комната -> грани её дверей.
var _doors: Dictionary[StringName, Array] = {}
## Тайл сети -> соседние тайлы, с которыми он связан проёмом.
var _links: Dictionary[Vector3i, Array] = {}
## Тайл -> номер коридора. До разреза по развилкам (_segment) вся сеть — нулевой:
## петли и тупики ставятся раньше, и для них своя для комнаты — вся сеть.
var _owner: Dictionary[Vector3i, int] = {}
## Клетки перед дверями — концы, которые сеть обязана связать.
var _terminals: Array[Vector3i] = []
var _dead_ends: Array[Vector3i] = []
## Где ищутся петли и тупики: комнаты этажа с сетью и запасом вокруг.
var _area := Rect2i()
## Центр комнат этажа в клетках — к нему смотрят двери.
var _center := Vector2.ZERO


func _init(plan: RS_LayerPlan, level: int) -> void:
	_plan = plan
	_topology = plan.topology
	_level = level


## Раскладывает этаж [param floor_index] в [param plan]: комнаты, сеть, двери,
## петли, тупики и коридоры. Имя коридора — [param id_prefix] и номер; возвращает
## имена всех коридоров этажа — по ним граф заводит узлы.
static func plan_floor(
	plan: RS_LayerPlan,
	rooms: Array[RS_LevelNode],
	id_prefix: String,
	floor_index: int,
	config: RS_WorldGenConfig,
	rng: RandomNumberGenerator,
) -> Array[StringName]:
	var planner := RS_CorridorPlanner.new(plan, floor_index)
	planner._place_rooms(rooms, config.room_gap, config.room_density, rng)
	for room in rooms:
		planner._choose_doors(room)
	planner._grow_network()
	planner._add_loops(config.corridor_loops)
	planner._add_dead_ends(config.dead_ends, rng)
	var ids: Array[StringName] = []
	for k in planner._segment():
		ids.append(StringName("%s%d" % [id_prefix, k]))
	planner._write(rooms, ids)
	return ids


# ---------------------------------------------------------------------------
# Комнаты и двери
# ---------------------------------------------------------------------------


## Комнаты разбросаны по области этажа: каждая встаёт в случайную точку, где
## вокруг неё остаётся улица в [param gap] клеток, а из годных точек чаще
## выигрывают те, где выше шум плотности. Так комнаты сбиваются в кучки, а между
## кучками остаются пустыри. Решётка рядами, которая была до 29.09, давала
## одинаковые по форме этажи: 4 комнаты — всегда квадрат по углам (карточка «Хаос
## раскладки этажа»). Шум — ради пустырей: без него бросок равномерен по всей
## области, и пустыри выходят только случайно, а хаос комплекса — это и
## сгущения, и пустоты между ними.
##
## Цена разброса — длина коридоров: двери больше не смотрят друг на друга через
## ровную улицу, и тайлов на комнату при density 0.65 выходит 6.3 против 4.4 у
## решётки (замер 29.09, 30 сидов). Поднять density — коридоры короче, но
## пустырей меньше.
##
## Порядок перетасован: где встанет хаб или выход, решает сид этажа, а не
## порядковый номер узла. Клетка комнаты — угловая клетка её footprint, footprint
## — в осях мира: у комнаты, повёрнутой на нечётную четверть, ширина и длина
## меняются местами.
##
## Площадь области — сумма footprint'ов с улицами, делённая на [param density]:
## комнатам заранее есть где встать, и бросок не упирается в край. Если всё же
## упёрся, область растёт на клетку — раскладка не падает, а становится реже.
func _place_rooms(rooms: Array[RS_LevelNode], gap: int, density: float, rng: RandomNumberGenerator) -> void:
	var sizes: Dictionary[StringName, Vector3i] = {}
	var budget := 0
	for room in rooms:
		var size := RS_RoomLayout.footprint_of_scene(room.room_scene_path)
		sizes[room.id] = Vector3i(size.z, size.y, size.x) if room.turns % 2 else size
		budget += (sizes[room.id].x + gap) * (sizes[room.id].z + gap)
	var order := rooms.duplicate()
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var swap: RS_LevelNode = order[i]
		order[i] = order[j]
		order[j] = swap

	# Вытянутость области — тоже бросок: квадратная область при любом сиде давала бы
	# этажи одной формы, только с другой начинкой.
	var aspect := rng.randf_range(1.0 / MAX_ASPECT, MAX_ASPECT)
	var side := sqrt(budget / clampf(density, 0.05, 1.0))
	var area := Rect2i(0, 0, maxi(ceili(side * sqrt(aspect)), 1), maxi(ceili(side / sqrt(aspect)), 1))
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = NOISE_FREQUENCY

	var sum := Vector2.ZERO
	for room: RS_LevelNode in order:
		var size: Vector3i = sizes[room.id]
		var anchor := _scatter_anchor(size, gap, area, noise, rng)
		while anchor == Vector3i.MAX:
			area = area.grow_individual(0, 0, 1, 1)
			anchor = _scatter_anchor(size, gap, area, noise, rng)
		_put(room, anchor, size)
		sum += Vector2(anchor.x + (size.x - 1) * 0.5, anchor.z + (size.z - 1) * 0.5)
	_center = sum / maxi(order.size(), 1)


## Угловая клетка под footprint [param size] в [param area]: SCATTER_TRIES
## случайных точек, из годных — взвешенно по шуму. Vector3i.MAX — годных нет.
func _scatter_anchor(
	size: Vector3i, gap: int, area: Rect2i, noise: FastNoiseLite, rng: RandomNumberGenerator
) -> Vector3i:
	var fits: Array[Vector3i] = []
	var weights: Array[float] = []
	for t in SCATTER_TRIES:
		# Бросок тратится при любом исходе: иначе число бросков зависело бы от
		# того, какие точки оказались заняты, и сдвиг расползался бы по этажу.
		var anchor := Vector3i(
			rng.randi_range(area.position.x, maxi(area.end.x - size.x, area.position.x)),
			_level,
			rng.randi_range(area.position.y, maxi(area.end.y - size.z, area.position.y)),
		)
		if not _fits(anchor, size, gap, area):
			continue
		var centre := Vector2(anchor.x + size.x * 0.5, anchor.z + size.z * 0.5)
		fits.append(anchor)
		weights.append(pow((noise.get_noise_2dv(centre) + 1.0) * 0.5, NOISE_SHARPNESS))
	if fits.is_empty():
		return Vector3i.MAX
	if WeightedPick.total(weights) <= 0.0:
		return fits[0]
	return fits[WeightedPick.index(weights, rng.randf())]


## Встаёт ли footprint в области так, чтобы до любой занятой клетки плана на его
## уровнях оставалось не меньше [param gap] клеток. Смотрит в план, а не только
## в комнаты этажа: верх высокой комнаты этажа ниже тоже занимает клетку этого
## уровня, и встать на неё — наложение, которое раньше уходило в routing_failures.
func _fits(anchor: Vector3i, size: Vector3i, gap: int, area: Rect2i) -> bool:
	if anchor.x + size.x > area.end.x or anchor.z + size.z > area.end.y:
		return false
	var around := anchor - Vector3i(gap, 0, gap)
	for cell in SquareGridTopology.box(around, size + Vector3i(gap * 2, 0, gap * 2)):
		if _plan.node_by_cell.has(cell):
			return false
	return true


## Ставит комнату в план: угловая клетка, footprint, поворот и все его клетки — на
## всех его уровнях, иначе node_at не узнал бы комнату под потолком высокого зала.
func _put(room: RS_LevelNode, anchor: Vector3i, size: Vector3i) -> void:
	_plan.cells[room.id] = anchor
	_plan.footprints[room.id] = size
	_plan.turns[room.id] = room.turns
	# Комната без дверей тоже ключ: по ключам door_faces считают комнаты метрики.
	_plan.door_faces[room.id] = {}
	for cell in SquareGridTopology.box(anchor, size):
		if _plan.node_by_cell.has(cell):
			_plan.routing_failures.append("%s: клетка %s уже занята %s" % [room.id, cell, _plan.node_by_cell[cell]])
		_plan.node_by_cell[cell] = room.id
		_room_at[cell] = room.id


## Грани под двери комнаты. У комнаты с дверями в сцене — стороны её дверей,
## повёрнутые вместе с комнатой: сцена в одну клетку, и грань — её сторона в мире.
## У собранной по сокетам — [member RS_LevelNode.socket_doors] сокетов, смотрящих
## внутрь этажа (_inward_sockets).
func _choose_doors(room: RS_LevelNode) -> void:
	var anchor: Vector3i = _plan.cells[room.id]
	var faces: Array[Vector4i] = []
	if room.socket_doors == 0:
		for side: int in RS_RoomLayout.door_sides_of_scene(room.room_scene_path):
			faces.append(GridTopology.face(anchor, _topology.rotate_side(anchor, side, -room.turns)))
	else:
		faces = _inward_sockets(_topology.perimeter(_plan.room_cells(room.id)), room.socket_doors)
	_doors[room.id] = faces
	for face in faces:
		_terminals.append(_front(face))


## [param count] сокетов, ближайших к центру комнат этажа, и не больше чем с
## DOOR_SIDES сторон, пока на них хватает сокетов. Двери внутрь этажа смотрят
## друг на друга через улицу, и сеть связывает их коротко; дверь наружу тянула бы
## коридор в обход, а дверь на третьей стороне — коридор вокруг комнаты.
func _inward_sockets(sockets: Array[Vector4i], count: int) -> Array[Vector4i]:
	var score: Dictionary[Vector4i, float] = {}
	for face in sockets:
		var front := _front(face)
		score[face] = Vector2(front.x, front.z).distance_squared_to(_center)
	sockets.sort_custom(func(a: Vector4i, b: Vector4i) -> bool:
		return score[a] < score[b] if score[a] != score[b] else _face_before(a, b))
	var sides: Array[int] = []
	for face in sockets:
		if not sides.has(face.w):
			sides.append(face.w)
	var allowed := mini(DOOR_SIDES, sides.size())
	while allowed < sides.size() and _sockets_on(sockets, sides.slice(0, allowed)) < count:
		allowed += 1
	var open := sides.slice(0, allowed)
	var picked: Array[Vector4i] = []
	for face in sockets:
		if picked.size() == count:
			break
		if open.has(face.w):
			picked.append(face)
	return picked


func _sockets_on(sockets: Array[Vector4i], sides: Array) -> int:
	var count := 0
	for face in sockets:
		if sides.has(face.w):
			count += 1
	return count


# ---------------------------------------------------------------------------
# Сеть и коридоры
# ---------------------------------------------------------------------------


## Сеть — дерево по клеткам, связывающее все клетки перед дверями: от двери,
## ближайшей к центру, и дальше каждый раз та дверь, что ближе всех к уже
## проложенному (Прим для дерева Штейнера). В заранее заданном порядке дальняя
## дверь тянула бы свой ряд вдоль чужого, пока сеть до неё не дошла, — на карте
## это «лесенка» параллельных коридоров.
func _grow_network() -> void:
	_terminals.sort_custom(_nearer_center)
	if _terminals.is_empty():
		_area = _bounds().grow(ROUTE_MARGIN)
		return
	var search := _bounds().grow(ROUTE_MARGIN)
	var to_network := func(cell: Vector3i) -> bool: return _links.has(cell)
	_links[_terminals[0]] = []
	var pending: Array[Vector3i] = []
	for terminal in _terminals:
		pending.append(terminal)
	while true:
		var left: Array[Vector3i] = []
		for terminal in pending:
			if not _links.has(terminal):
				left.append(terminal)
		pending = left
		if pending.is_empty():
			break
		# Нижняя оценка — путь по сетке до ближайшего тайла, без обходов: трассы ищутся
		# от ближних, и тем, кому уже не обогнать найденную, поиск не нужен.
		var bound: Dictionary[Vector3i, int] = {}
		for terminal in pending:
			var nearest := 1 << 30
			for cell: Vector3i in _links:
				nearest = mini(nearest, absi(cell.x - terminal.x) + absi(cell.z - terminal.z))
			bound[terminal] = nearest
		pending.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
			return bound[a] < bound[b] if bound[a] != bound[b] else _nearer_center(a, b))
		var best: Array[Vector3i] = []
		for terminal in pending:
			if not best.is_empty() and bound[terminal] >= best.size() - 1:
				break
			var path := _route_around(terminal, to_network, search)
			if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
				best = path
		if best.is_empty():
			for terminal in pending:
				_plan.routing_failures.append("этаж %d: дверь перед %s не связана с сетью" % [_level, terminal])
			break
		_claim(best)
	_area = _bounds().grow(ROUTE_MARGIN)


## Режет сеть на коридоры — отрезки между развилками (карточка «Коридор —
## отдельный узел»): поворот и дверь коридор не режут, развилка режет. Узлом
## графа был бы и каждый тайл, но тогда текущий узел и карта менялись бы каждые
## 8 м, а ветка из многих коридоров с развилками, как до этого, — не то место,
## которое игрок называет «коридором».
##
## Клетка развилки достаётся коридору, который идёт через неё прямо, а боковой к
## нему примыкает: длинный коридор с ответвлениями читается целиком, а стык —
## место под будущий шлюз — встаёт на входе в боковой. Отдельным узлом
## «перекрёсток» развилка не стала по той же причине. Разрез — только граница
## владения: проём на стыке открыт. Возвращает, сколько коридоров вышло;
## номера — по порядку дверей (нулевой — у двери ближе всех к центру), затем
## коридоры без дверей — перемычки и тупики.
##
## Коридоры собираются объединением, а не вырезанием боковых проёмов: петля может
## вернуть коридор к его же развилке сбоку (форма «Р»), и разрез бокового проёма
## тогда ничего не отделяет — коридор шёл бы через развилку и сам к ней
## примыкал. Такая развилка отпускает сперва одного прямого соседа, потом другого,
## а если и это не помогло — остаётся коридором в одну клетку.
func _segment() -> int:
	var keep: Dictionary[Vector3i, Array] = {}  # развилка -> прямые соседи, с кем она в одном коридоре
	for tile: Vector3i in _links:
		if (_links[tile] as Array).size() >= 3:
			keep[tile] = _through_pair(tile)
	var root := _join(keep)
	var looped := _self_joined(keep, root)
	while looped != Vector3i.MAX:
		var pair := _through_pair(looped)
		var kept: Array = keep[looped]
		if kept.size() == 2:
			keep[looped] = [pair[0]]
		elif kept.size() == 1 and kept[0] == pair[0]:
			keep[looped] = [pair[1]]
		else:
			keep[looped] = []
		root = _join(keep)
		looped = _self_joined(keep, root)
	_owner.clear()
	var number: Dictionary[Vector3i, int] = {}  # корень коридора -> номер
	var starts: Array[Vector3i] = []
	starts.append_array(_terminals)
	starts.append_array(_links.keys())
	for start in starts:
		if _links.has(start) and not number.has(root[start]):
			number[root[start]] = number.size()
	for tile: Vector3i in _links:
		_owner[tile] = number[root[tile]]
	return number.size()


## Коридоры как множества тайлов: тайл -> корень своего коридора. Проём
## объединяет двоих, только если каждый из них его принимает: обычный тайл —
## любой, развилка — только к своим прямым соседям ([param keep]).
func _join(keep: Dictionary[Vector3i, Array]) -> Dictionary[Vector3i, Vector3i]:
	var parent: Dictionary[Vector3i, Vector3i] = {}
	for tile: Vector3i in _links:
		parent[tile] = tile
	for tile: Vector3i in _links:
		for next: Vector3i in _links[tile]:
			if not _before(tile, next) or not _accepts(keep, tile, next) or not _accepts(keep, next, tile):
				continue
			var a := _find(parent, tile)
			var b := _find(parent, next)
			if a != b:
				parent[b] = a
	var root: Dictionary[Vector3i, Vector3i] = {}
	for tile: Vector3i in _links:
		root[tile] = _find(parent, tile)
	return root


## Развилка, оказавшаяся в одном коридоре с соседом, которого не принимала, —
## коридор вернулся к ней сбоку. Vector3i.MAX — таких нет.
func _self_joined(keep: Dictionary[Vector3i, Array], root: Dictionary[Vector3i, Vector3i]) -> Vector3i:
	for tile: Vector3i in keep:
		for next: Vector3i in _links[tile]:
			if not _accepts(keep, tile, next) and root[next] == root[tile]:
				return tile
	return Vector3i.MAX


func _accepts(keep: Dictionary[Vector3i, Array], tile: Vector3i, next: Vector3i) -> bool:
	return not keep.has(tile) or (keep[tile] as Array).has(next)


static func _find(parent: Dictionary[Vector3i, Vector3i], tile: Vector3i) -> Vector3i:
	while parent[tile] != tile:
		tile = parent[tile]
	return tile


## Два соседа развилки [param tile], через которых коридор идёт прямо: стороны
## напротив друг друга (GridTopology.opposite — «прямо» по топологии, а не по
## осям). У креста прямых два — клетку берёт тот, что длиннее прямо в обе
## стороны, при равенстве — с меньшей стороной. Прямого нет (развилка из трёх
## сторон вразнобой, на квадрате не бывает) — пусто: клетка остаётся отдельным
## коридором.
func _through_pair(tile: Vector3i) -> Array[Vector3i]:
	var linked: Array = _links[tile]
	var best: Array[Vector3i] = []
	var best_run := -1
	for side in _topology.side_count(tile):
		var back := _topology.opposite(tile, side)
		if back <= side:
			continue
		var ahead := _topology.neighbour(tile, side)
		var behind := _topology.neighbour(tile, back)
		if not linked.has(ahead) or not linked.has(behind):
			continue
		var run := _straight_run(tile, side) + _straight_run(tile, back)
		if run > best_run:
			best_run = run
			best = [ahead, behind]
	return best


## Сколько тайлов подряд сеть идёт прямо от [param from] через сторону
## [param side]: на каждом следующем «прямо» — сторона напротив той, через
## которую вошли.
func _straight_run(from: Vector3i, side: int) -> int:
	var run := 0
	var cell := from
	var out := side
	while run < _links.size():
		var next := _topology.neighbour(cell, out)
		if not (_links[cell] as Array).has(next):
			break
		run += 1
		out = _topology.opposite(next, _topology.back_side(cell, out))
		cell = next
	return run


# ---------------------------------------------------------------------------
# Петли и тупики
# ---------------------------------------------------------------------------


## Петли по коридору: короткая трасса по свободным клеткам между двумя тайлами,
## далёкими друг от друга по сети. Из всех берётся самая выгодная — сколько шагов
## по сети она срезает. Не ставится петля, которая обволокла бы комнату
## (_envelops), и петля впритык к ближней сети — это второй ряд вдоль того же
## коридора, а не обход. Поэтому на тесном этаже петель выходит меньше заявленного.
func _add_loops(count: int) -> void:
	for k in count:
		var best: Array[Vector3i] = []
		var best_gain := 0
		for a: Vector3i in _links.keys():
			var dist := _distances(a)
			var goal := func(cell: Vector3i) -> bool: return dist.get(cell, 0) >= MIN_LOOP_GAIN
			var passable := func(cell: Vector3i) -> bool: return _free(cell, _area) and not _near(cell, dist)
			for side in _topology.side_count(a):
				var start := _topology.neighbour(a, side)
				if not _free(start, _area):
					continue
				var path := GridRouter.find_path(_topology, start, goal, passable, TURN_COST)
				if path.is_empty():
					continue
				var gain: int = dist[path[-1]] - path.size()
				if gain <= best_gain:
					continue
				var loop: Array[Vector3i] = [a]
				loop.append_array(path)
				if _envelops(loop):
					continue
				best = loop
				best_gain = gain
		if best.is_empty():
			return
		_claim(best)


## Тупики: отросток в одну-две клетки от тайла в свободное место, лучше — не вдоль
## стены комнаты (там он читается недостроенным коридором к двери). Отросток не
## касается других тайлов — иначе это не тупик, а щель между коридорами — и не
## обволакивает комнату. Конец отмечается в плане (RS_LayerPlan.dead_ends): что в
## нём лежит, решает не генератор.
func _add_dead_ends(count: int, rng: RandomNumberGenerator) -> void:
	for k in count:
		var candidates: Array[Array] = []
		var best_score := 1 << 30
		for a: Vector3i in _links.keys():
			# С развилки отросток сделал бы крест, с конца тупика — удлинил бы его.
			if (_links[a] as Array).size() >= 3 or _dead_ends.has(a):
				continue
			for side in _topology.side_count(a):
				var stub: Array[Vector3i] = [a]
				var cell := _topology.neighbour(a, side)
				while stub.size() <= DEAD_END_LENGTH and _free(cell, _area) and not _touches_tiles(cell, stub[-1]):
					stub.append(cell)
					cell = _topology.neighbour(cell, side)
				if stub.size() < 2 or _envelops(stub):
					continue
				var score := 0
				for i in range(1, stub.size()):
					if _touches_room(stub[i]):
						score += 1
				if score < best_score:
					best_score = score
					candidates.clear()
				if score == best_score:
					candidates.append(stub)
		if candidates.is_empty():
			return
		var stub: Array[Vector3i] = []
		stub.assign(candidates[rng.randi_range(0, candidates.size() - 1)])
		_claim(stub)
		_dead_ends.append(stub[-1])


## Обволокла бы комнату трасса [param path]: сеть вместе с ней подошла бы к
## комнате с трёх сторон. Петли и тупики ставятся до разреза на коридоры, так что
## своя для комнаты здесь — вся сеть, чей бы ни был коридор. Это строже, чем «её
## коридоры» в RS_LayoutMetrics, и как раз то, что видит игрок: коридор с трёх
## сторон комнаты, как его ни режь на узлы. Комната без дверей не в счёт — у неё
## своих коридоров нет вовсе.
func _envelops(path: Array[Vector3i]) -> bool:
	return not _enveloped(path).is_empty()


## Комнаты, которые обволокла бы трасса [param path] (см. _envelops).
func _enveloped(path: Array[Vector3i]) -> Array[StringName]:
	var enveloped: Array[StringName] = []
	var added: Dictionary[Vector3i, bool] = {}
	for cell in path:
		added[cell] = true
	var rooms: Dictionary[StringName, bool] = {}
	for cell in path:
		for side in _topology.side_count(cell):
			var next := _topology.neighbour(cell, side)
			if _room_at.has(next):
				rooms[_room_at[next]] = true
	for room: StringName in rooms:
		if (_doors[room] as Array).is_empty():
			continue
		var sides: Dictionary[int, bool] = {}
		for face in _topology.perimeter(_plan.room_cells(room)):
			var next := _front(face)
			if added.has(next) or _links.has(next):
				sides[face.w] = true
		if sides.size() >= 3:
			enveloped.append(room)
	return enveloped


# ---------------------------------------------------------------------------
# В план
# ---------------------------------------------------------------------------


## Переносит сеть в план: маски проёмов (к соседним тайлам и к дверям), чей
## коридор, грани дверей с их коридорами, тупики. Клетка коридора — его первый
## тайл: одной клетки у коридора нет, а инструментам нужна хоть какая-то.
func _write(rooms: Array[RS_LevelNode], corridor_ids: Array[StringName]) -> void:
	for tile: Vector3i in _links:
		var mask := 0
		for next: Vector3i in _links[tile]:
			mask |= 1 << _topology.side_toward(tile, next)
		var corridor := corridor_ids[_owner[tile]]
		_plan.corridor_tiles[tile] = mask
		_plan.node_by_cell[tile] = corridor
		if not _plan.cells.has(corridor):
			_plan.cells[corridor] = tile
	for room in rooms:
		var faces := {}
		for face: Vector4i in _doors[room.id]:
			var front := _front(face)
			if not _owner.has(front):
				continue  # сеть до двери не дотянулась — это уже в routing_failures
			faces[face] = corridor_ids[_owner[front]]
			_plan.corridor_tiles[front] |= 1 << _topology.back_side(GridTopology.face_cell(face), face.w)
		_plan.door_faces[room.id] = faces
	for cell in _dead_ends:
		_plan.dead_ends[cell] = true


# ---------------------------------------------------------------------------
# Мелочь
# ---------------------------------------------------------------------------


## Трасса от [param start] до первой клетки, где [param goal] истинна
## (GridRouter.find_path). Сперва в [param area], затем запас растёт: обход по
## краю лучше, чем отказ.
func _route(
	start: Vector3i, goal: Callable, area: Rect2i, avoid: Dictionary[Vector3i, bool] = {}
) -> Array[Vector3i]:
	var margin := 0
	while margin <= MAX_ROUTE_MARGIN - ROUTE_MARGIN:
		var grown := area.grow(margin)
		var passable := func(cell: Vector3i) -> bool: return _free(cell, grown) and not avoid.has(cell)
		var path := GridRouter.find_path(_topology, start, goal, passable, TURN_COST)
		if not path.is_empty():
			return path
		margin += 2
	return []


## Трасса от двери к сети, которая не обволакивает комнат: подошла к комнате с
## третьей стороны — клетки трассы вдоль стен этой комнаты запрещаются, и трасса
## ищется заново, не больше ENVELOP_RETRIES раз. Петлям и тупикам такая трасса
## просто не ставится (_envelops), а ствол обязан дойти, поэтому ему — обход.
## На решётке хватало дверей, смотрящих внутрь: улицы шли ровно между рядами. При
## разбросе комнаты стоят вразбег, и кратчайший путь к соседней то и дело идёт
## вдоль чужой стены — без обхода так обволакивалось 0.6 % комнат при 8 на этаж и
## 1.2 % при 12 (замер 29.09 при density 0.5), с обходом — снова 0.
## Обхода не нашлось — остаётся первая трасса: дверь без сети хуже коридора с
## трёх сторон.
func _route_around(start: Vector3i, goal: Callable, area: Rect2i) -> Array[Vector3i]:
	var avoid: Dictionary[Vector3i, bool] = {}
	var path := _route(start, goal, area)
	for attempt in ENVELOP_RETRIES:
		var rooms := _enveloped(path)
		if rooms.is_empty():
			break
		for cell in path:
			if not _terminals.has(cell) and _touches_any(cell, rooms):
				avoid[cell] = true
		var detour := _route(start, goal, area, avoid)
		if detour.is_empty():
			break
		path = detour
	return path


func _touches_any(cell: Vector3i, rooms: Array[StringName]) -> bool:
	for side in _topology.side_count(cell):
		if rooms.has(_room_at.get(_topology.neighbour(cell, side), &"")):
			return true
	return false


## Занимает клетки пути под сеть и открывает проёмы между соседними клетками пути.
## Чей это коридор, решает потом разрез (_segment).
func _claim(path: Array[Vector3i]) -> void:
	for cell in path:
		if not _links.has(cell):
			_links[cell] = []
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		if not (_links[a] as Array).has(b):
			_links[a].append(b)
			_links[b].append(a)


## Свободна ли клетка под трассу: на своём уровне, в области, не комната (в том
## числе верх высокой комнаты этажа ниже) и не тайл.
func _free(cell: Vector3i, area: Rect2i) -> bool:
	return (
		cell.y == _level
		and area.has_point(Vector2i(cell.x, cell.z))
		and not _plan.node_by_cell.has(cell)
		and not _links.has(cell)
	)


## Касается ли клетка тайла ближней сети — ближе MIN_LOOP_GAIN шагов от начала петли.
func _near(cell: Vector3i, dist: Dictionary) -> bool:
	for side in _topology.side_count(cell):
		var next := _topology.neighbour(cell, side)
		if _links.has(next) and dist.get(next, 0) < MIN_LOOP_GAIN:
			return true
	return false


func _touches_tiles(cell: Vector3i, except: Vector3i) -> bool:
	for side in _topology.side_count(cell):
		var next := _topology.neighbour(cell, side)
		if next != except and _links.has(next):
			return true
	return false


func _touches_room(cell: Vector3i) -> bool:
	for side in _topology.side_count(cell):
		if _room_at.has(_topology.neighbour(cell, side)):
			return true
	return false


## Расстояния по сети (в шагах по проёмам) от тайла [param start].
func _distances(start: Vector3i) -> Dictionary[Vector3i, int]:
	var dist: Dictionary[Vector3i, int] = {start: 0}
	var queue: Array[Vector3i] = [start]
	var i := 0
	while i < queue.size():
		var cell := queue[i]
		i += 1
		for next: Vector3i in _links[cell]:
			if not dist.has(next):
				dist[next] = dist[cell] + 1
				queue.append(next)
	return dist


## Прямоугольник комнат и тайлов этажа в плоскости (X, Z).
func _bounds() -> Rect2i:
	var rect := Rect2i()
	var first := true
	for cell: Vector3i in _room_at:
		if first:
			rect = Rect2i(Vector2i(cell.x, cell.z), Vector2i.ZERO)
			first = false
		else:
			rect = rect.expand(Vector2i(cell.x, cell.z))
	for cell: Vector3i in _links:
		rect = rect.expand(Vector2i(cell.x, cell.z))
	return rect


func _front(face: Vector4i) -> Vector3i:
	return _topology.neighbour(GridTopology.face_cell(face), face.w)


func _nearer_center(a: Vector3i, b: Vector3i) -> bool:
	var da := Vector2(a.x, a.z).distance_squared_to(_center)
	var db := Vector2(b.x, b.z).distance_squared_to(_center)
	return da < db if da != db else _before(a, b)


## Порядок клеток — ряд за рядом: при равной цене решает он, и раскладка обязана
## совпадать от запуска к запуску.
static func _before(a: Vector3i, b: Vector3i) -> bool:
	if a.z != b.z:
		return a.z < b.z
	if a.x != b.x:
		return a.x < b.x
	return a.y < b.y


static func _face_before(a: Vector4i, b: Vector4i) -> bool:
	if a.z != b.z:
		return a.z < b.z
	if a.x != b.x:
		return a.x < b.x
	return a.w < b.w
