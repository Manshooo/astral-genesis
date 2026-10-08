# res://src/ui/hud/mini_map.gd
## Мини-карта по кнопке (§10 «HUD — спека»): этаж, на котором сейчас игрок,
## поверх идущей игры.
##
## Не экран и не пауза, в отличие от полной карты (UI_ComplexMap): карту здесь
## не изучают, а сверяются с ней на ходу, и Распад под ней тикает. Поэтому это
## узел HUD, ввод он не перехватывает, а открывает и закрывает его UIManager по
## действию map_mini — там же проверка, есть ли связь с Архитектором.
##
## Показывает СКРОМНО и намеренно: комнаты и ветки коридора, где игрок был, плюс
## те, о существовании которых он знает — потому что видел ведущую туда дверь
## (MapKnowledge.known_nodes). Ветка коридора видна ЦЕЛИКОМ, как только
## известна: это тот же «сосед», что и комната, и дробить её на пройденные тайлы
## значило бы хранить их в сейве ради подробности, которую правильнее отдать
## улучшениям «Архитектора».
##
## Раскладку по плану слоя (вписывание, клетки, тайлы веток) берёт у общего
## UI_MapFloor, а рисует по-своему: язык «Отголосок» — тонкие контуры, коридоры
## бусами на нитке, рваная рамка вокруг, прорисовка от текущей комнаты наружу, а
## не заливка клеток, как на экране карты.
class_name UI_MiniMap
extends UI_MapFloor

const GROUP := &"mini_map"

## Клетка плана на экране (§4); этаж крупнее блока сжимается, а не обрезается:
## мини-карта отвечает на «где я среди того, что знаю», и обрезанный край
## спрятал бы ровно то, куда идти.
const CELL_PX := 34.0
## Доля клетки под комнатой. Комнаты на плане бывают соседями через стену, и без
## зазора их контуры слиплись бы в одну линию.
const ROOM_FILL := 0.9

## Появление (§6): контур прорисовывается за CONTOUR_SECONDS, каждый шаг графа
## от текущей комнаты — на STEP_DELAY позже; подписи — после первых контуров.
const CONTOUR_SECONDS := 0.45
const STEP_DELAY := 0.12
const LABEL_DELAY := 0.6
const LABEL_FADE := 0.35
const CLOSE_SECONDS := 0.25

## Вид (§10).
const ROOM_WIDTH := 1.3
const ROOM_ALPHA := 0.85
const VISITED_FILL := 0.05
const HERE_FILL := 0.14
const UNKNOWN_ALPHA := 0.28
const UNKNOWN_WIDTH := 1.0
const ARROW_WIDTH := 1.2
## Коридор — бусы на нитке, бусина на клетку: доля клетки под бусиной.
const TILE_SIZE := 0.32
const CORRIDOR_ALPHA := 0.55
const CORRIDOR_UNKNOWN_ALPHA := 0.3
## Квадраты коридора проступают по одному от того конца, откуда пришла волна.
const TILE_DELAY := 0.03
const TILE_FADE := 0.18
## Постоянная времени, с которой вписывание догоняет новый размер этажа.
const SCALE_TAU := 0.3
const DASH_PX := 3.0
const GAP_PX := 4.0
## Середина стороны комнаты гуляет на столько пикселей: от руки, а не по линейке.
const JITTER_PX := 0.8
const ARROW_ALPHA := 0.8
const DOT_RADIUS := 3.2
const RING_RADIUS := 9.0
const RING_PERIOD := 1.6
## Тень-пятно позади карты (§4).
const SHADOW_SIZE := Vector2(680.0, 520.0)
## Нить коридора — тоньше контура комнаты, чтобы бусы на ней читались главными.
const THREAD_WIDTH := 1.0
const THREAD_ALPHA := 0.45
const THREAD_UNKNOWN_ALPHA := 0.25
## Рамка вокруг всей карты (решено 02.10 при приёмке, поверх §10 «без рамки»):
## рвётся, как дуга распада (амплитуда 0.4 + 1.8T px), но тоньше и тише — она
## обрамляет, а не сообщает.
const FRAME_WIDTH := 1.0
const FRAME_ALPHA := 0.5
const FRAME_RAG_PX := 0.4
const FRAME_RAG_TURMOIL_PX := 1.2
## Горбов шума на обход: при ~1.5 тыс. px периметра старшая гармоника даёт
## излом каждые ~30 px — рвано, но не пилой.
const FRAME_WAVES := 4.0
const FRAME_RADIUS := 10.0
const FRAME_CORNER_STEPS := 6
const FRAME_MARGIN := Vector2(16.0, 12.0)
const FRAME_SECONDS := 0.6
## Высота строки подсказки под картой — нижний край рамки идёт под неё.
const HINT_HEIGHT := 20.0

## Подписи вокруг карты: заголовок над ней, подсказка под ней.
const TITLE_OFFSET := Vector2(0.0, -30.0)
const HINT_GAP := 12.0
const HINT_GAP_X := 18.0

## Насколько игрок должен сдвинуться (метры) или повернуться, чтобы карта
## пересобралась. Клетка карты — это 8 м мира, и шаг в треть метра на ней едва
## заметен; точку игрока при этом двигаем каждый кадр.
const REBUILD_MOVE := 0.3

var is_open := false

var _opened_at := -INF
var _closed_at := -INF
var _view: Dictionary = {}
var _dirty := true
var _last_position := Vector3.INF
## Волна прорисовки: через сколько секунд после открытия начинается каждый
## показанный узел и каким по счёту проступает каждый квадрат коридора.
var _start_at: Dictionary[StringName, float] = {}
var _tile_rank: Dictionary[Vector2i, int] = {}
var _wave_end := 0.0
## Вписывание: куда его тянет новая раскладка и где оно на экране сейчас. Точка
## клетки — anchor + cell · step.
var _target_step := 0.0
var _target_anchor := Vector2.ZERO
var _shown_step := 0.0
var _shown_anchor := Vector2.ZERO
var _snap := true
## Слой и этаж, по которым вписано: на другом этаже раскладка совсем другая, и
## перетекать в неё из прежней значило бы показывать полёт сквозь чужой план.
var _fitted_floor := Vector2i(-1, -1)
var _shadow_texture: Texture2D
var _title: Label
## Ранг «Карты комплекса» — снимается при открытии и пересборке: купить его можно
## только на экране Архитектора, а поверх экрана мини-карта не открыта.
var _level := MapKnowledge.LEVEL_NONE
var _hint_hide: UI_ThoughtLine
var _hint_full: UI_ThoughtLine


func _init() -> void:
	# В _init, а не в _ready: проверка спрашивает build_view у узла вне дерева.
	max_step = CELL_PX
	padding = 0.0
	room_fill = ROOM_FILL


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group(GROUP)
	visible = false
	_shadow_texture = UI_HudMood.thought_shadow_texture()

	_title = _add_label("HudMapLabel")
	_hint_hide = _add_hint()
	_hint_full = _add_hint()

	RunManager.room_changed.connect(_on_run_changed)
	RunManager.layer_changed.connect(_on_run_changed)
	RunManager.complex_entered.connect(_on_run_changed)
	SettingsManager.settings_changed.connect(_update_hint)
	ECS.world_changed.connect(_on_world_changed)


func _add_label(variation: StringName) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


func _add_hint() -> UI_ThoughtLine:
	var line := UI_ThoughtLine.new()
	line.style = UI_ThoughtLine.Style.MAP
	line.centered = false
	add_child(line)
	return line


func open() -> void:
	is_open = true
	_opened_at = UI_HudMood.now()
	_dirty = true
	_snap = true
	visible = true
	modulate.a = 1.0
	_update_hint()


## Растворяется за CLOSE_SECONDS, а не пропадает: резкое исчезновение посреди
## бега читалось бы как сбой.
func close() -> void:
	if not is_open:
		return
	is_open = false
	_closed_at = UI_HudMood.now()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


## Сразу и без растворения — мир, по которому строилась карта, ушёл.
func _on_world_changed(_world: World) -> void:
	is_open = false
	visible = false


func _on_run_changed(_arg: Variant = null) -> void:
	_dirty = true


func _update_hint(_arg: Variant = null) -> void:
	if _hint_hide == null:
		return
	_hint_hide.set_line(SettingsManager.action_display_name(&"map_mini"), tr("HUD_MAP_HIDE"))
	_hint_full.set_line(SettingsManager.action_display_name(&"map"), tr("HUD_MAP_FULL"))


func _process(delta: float) -> void:
	if not visible:
		return
	var t := UI_HudMood.now()
	if not is_open:
		var left := 1.0 - (t - _closed_at) / CLOSE_SECONDS
		if left <= 0.0:
			visible = false
			return
		modulate.a = left

	var player := UI_MapFloor.player_node()
	if player and player.global_position.distance_squared_to(_last_position) >= REBUILD_MOVE * REBUILD_MOVE:
		_last_position = player.global_position
		_dirty = true
	if _dirty:
		_dirty = false
		_level = ArchitectManager.map_level()
		_view = build_view()
		_plan_wave(_aim_scale())
	_ease_scale(delta)
	# Маркер живёт непрерывно, и пульс тоже: позу снимаем каждый кадр, а
	# раскладку пересобираем только по делу (выше).
	if player:
		player_position = player.global_position
	_layout_labels(t)
	queue_redraw()


## Запоминает вписывание, которое только что посчитал fit(), как цель. Открытие
## и смена этажа ставят его сразу — плавность нужна, когда этаж РАСТЁТ (узнали
## новую комнату), а не когда карту показывают впервые. true — вписано заново
## (открытие или другой этаж).
func _aim_scale() -> bool:
	if _view.is_empty():
		return true
	_target_step = _step
	_target_anchor = _origin + (Vector2(0.5, 0.5) - _min_cell) * _step
	var fitted := Vector2i(_view.depth, floor_index)
	var fresh := _snap or fitted != _fitted_floor
	if fresh:
		_shown_step = _target_step
		_shown_anchor = _target_anchor
	_snap = false
	_fitted_floor = fitted
	return fresh


## Тянет показанное вписывание к цели и подставляет его полям UI_MapFloor, через
## которые рисуются и комнаты, и квадраты, и точка игрока. Шаг и опорная точка
## тянутся вместе — по отдельности карта не масштабировалась бы, а ползла.
func _ease_scale(delta: float) -> void:
	if _view.is_empty():
		return
	var k := 1.0 - exp(-delta / SCALE_TAU)
	_shown_step = lerpf(_shown_step, _target_step, k)
	_shown_anchor = _shown_anchor.lerp(_target_anchor, k)
	_step = _shown_step
	_min_cell = Vector2.ZERO
	_origin = _shown_anchor - Vector2(0.5, 0.5) * _shown_step


## Что и где рисовать — отдельно от рисования, чтобы проверка могла спросить
## карту без пикселей: известные комнаты и ветки ТЕКУЩЕГО этажа, план и вписывание
## показанных клеток в контрол. Пусто — рисовать нечего.
##
## Только свой этаж: этажи слоя разнесены по высоте и в одной плоскости соседями
## не являются — рисовать их вперемешку значит врать про геометрию.
func build_view() -> Dictionary:
	var graph := RunManager.current_graph
	var current_id := RunManager.current_node_id
	if graph == null or current_id == &"":
		return {}
	var current := graph.get_node_data(current_id)
	if current == null:
		return {}

	plan = RunManager.plan_for_depth(current.depth)
	floor_index = current.floor_index
	here = current_id
	visited = WorldSave.save.visited_node_ids

	var player := UI_MapFloor.player_node()
	show_player = player != null
	if player:
		player_position = player.global_position
		player_forward = UI_MapFloor.forward_of(player)
		# Этаж — под игроком, а не этаж узла: на верхней площадке лестницы узел её,
		# а она числится этажом ниже. Только если игрок и правда в клетке узла — в
		# кадр переноса между слоями он ещё стоит в старом плане.
		if plan and plan.node_at(player_position) == current_id:
			floor_index = plan.embedding.cell_at(player_position).y
	set_nodes(MapKnowledge.known_nodes(graph.get_nodes_by_depth(current.depth), visited))

	if not fit():
		return {}
	return {
		"plan": plan, "here": here, "floor": floor_index, "depth": current.depth,
		"rooms": rooms, "branches": branches,
	}


## Волна прорисовки от текущего узла наружу по показанным узлам. Узел
## начинается через STEP_DELAY после предыдущего на пути к нему, а
## коридор держит волну, пока по нему не пройдут все квадраты, — иначе комната
## за длинным коридором проступала бы раньше, чем к ней дошла цепочка. Поэтому
## это кратчайшие пути по времени (Дейкстра), а не по числу шагов. Не дошедшие
## (связаны только через другой этаж) прорисовываются последними.
##
## Пересчёт при открытой карте ([param fresh] = false) не перерисовывает уже
## показанное: игрок перешёл в соседний узел — волна оттуда не нужна. Узлы,
## о которых узнали только что, прорисовываются с этого момента, а не
## возникают готовыми.
func _plan_wave(fresh: bool) -> void:
	var starts_before: Dictionary = {} if fresh else _start_at.duplicate()
	var ranks_before: Dictionary = {} if fresh else _tile_rank.duplicate()
	_start_at.clear()
	_tile_rank.clear()
	_wave_end = 0.0
	var graph := RunManager.current_graph
	if _view.is_empty() or graph == null:
		return
	var came_from: Dictionary[StringName, StringName] = {}
	var settled: Dictionary[StringName, bool] = {}
	var pending: Array[StringName] = [here]
	_start_at[here] = 0.0
	while not pending.is_empty():
		var best := 0
		for i in pending.size():
			if _start_at[pending[i]] < _start_at[pending[best]]:
				best = i
		var node_id: StringName = pending.pop_at(best)
		settled[node_id] = true
		var node_data := graph.get_node_data(node_id)
		if node_data == null:
			continue
		var done := _start_at[node_id] + STEP_DELAY
		if node_data.role == RS_LevelNode.Role.CORRIDOR:
			done += _rank_tiles(node_id, came_from.get(node_id, &"")) * TILE_DELAY
		_wave_end = maxf(_wave_end, done)
		for conn: RS_LevelConnection in node_data.connections:
			var next := conn.target_node_id
			if settled.has(next) or not shows(next):
				continue
			if not _start_at.has(next):
				pending.append(next)
			elif done >= _start_at[next]:
				continue
			_start_at[next] = done
			came_from[next] = node_id
	for node_data in rooms + branches:
		if not settled.has(node_data.id):
			_start_at[node_data.id] = _wave_end
			if node_data.role == RS_LevelNode.Role.CORRIDOR:
				_rank_tiles(node_data.id, &"")
	if fresh:
		return
	var elapsed := UI_HudMood.now() - _opened_at
	for node_id: StringName in _start_at:
		_start_at[node_id] = starts_before[node_id] if starts_before.has(node_id) else maxf(_start_at[node_id], elapsed)
	for cell: Vector2i in ranks_before:
		_tile_rank[cell] = ranks_before[cell]


## Нумерует квадраты ветки от входа волны: от клетки игрока, если он в ней, от
## стыка с узлом, из которого волна пришла, иначе — от первой клетки. Возвращает
## длину ветки в квадратах.
func _rank_tiles(branch: StringName, entered_from: StringName) -> int:
	var tiles := tiles_of(branch)
	if tiles.is_empty():
		return 0
	var seeds: Array[Vector2i] = []
	if branch == here and show_player:
		var cell := plan.embedding.cell_at(player_position)
		if tiles.has(_planar(cell)):
			seeds.append(_planar(cell))
	if seeds.is_empty() and entered_from != &"":
		for cell in tiles:
			for neighbour in _open_neighbours(cell):
				if plan.node_by_cell.get(neighbour, &"") == entered_from:
					seeds.append(cell)
					break
	if seeds.is_empty():
		seeds.append(tiles[0])

	var queue: Array[Vector2i] = []
	for start in seeds:
		_tile_rank[start] = 0
		queue.append(start)
	var longest := 1
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		for neighbour in _open_neighbours(cell):
			var next := _planar(neighbour)
			if plan.node_by_cell.get(neighbour, &"") != branch or _tile_rank.has(next):
				continue
			_tile_rank[next] = _tile_rank[cell] + 1
			longest = maxi(longest, _tile_rank[next] + 1)
			queue.append(next)
	return longest


## Клетки за открытыми проёмами тайла коридора.
func _open_neighbours(cell: Vector2i) -> Array[Vector3i]:
	var tile := Vector3i(cell.x, floor_index, cell.y)
	var mask: int = plan.corridor_tiles.get(tile, 0)
	var result: Array[Vector3i] = []
	for side in plan.topology.side_count(tile):
		if mask & (1 << side):
			result.append(plan.topology.neighbour(tile, side))
	return result


func _starts_at(node_id: StringName) -> float:
	return _start_at.get(node_id, _wave_end)


## Доля прорисовки узла 0…1 к моменту [param t].
func progress_of(node_id: StringName, t: float = UI_HudMood.now()) -> float:
	return clampf((t - _opened_at - _starts_at(node_id)) / CONTOUR_SECONDS, 0.0, 1.0)


## Проступил ли квадрат коридора: 0…1 к моменту [param t].
func tile_progress(branch: StringName, cell: Vector2i, t: float = UI_HudMood.now()) -> float:
	var rank: int = _tile_rank.get(cell, 0)
	var start := _starts_at(branch) + rank * TILE_DELAY
	return clampf((t - _opened_at - start) / TILE_FADE, 0.0, 1.0)


func _labels_alpha(t: float) -> float:
	return clampf((t - _opened_at - LABEL_DELAY) / LABEL_FADE, 0.0, 1.0)


func _layout_labels(t: float) -> void:
	var shown := not _view.is_empty()
	var alpha := _labels_alpha(t)
	for label: CanvasItem in [_title, _hint_hide, _hint_full]:
		label.visible = shown
		label.modulate.a = alpha
	# «[M] Вся карта» — только когда M и правда откроет карту: ниже последнего
	# ранга она даёт строку про терминал, и подсказка обещала бы неправду.
	_hint_full.visible = shown and UIManager.full_map_by_key()
	if not shown:
		return

	_title.text = title_text()
	_title.position = TITLE_OFFSET
	_hint_hide.position = Vector2(0.0, size.y + HINT_GAP)
	_hint_full.position = _hint_hide.position + Vector2(_hint_hide.width() + HINT_GAP_X, 0.0)


## Заголовок: этаж всегда, глубина слоя — с ранга LEVEL_LAYER. Ранги «Карты
## комплекса» дают мини-карте то же, что экрану карты, в её масштабе: второй —
## знание слоя (на какой ты глубине), третий — связи между этажами и слоями.
func title_text() -> String:
	var floor_text: String = tr("MAP_FLOOR") % (floor_index + 1)
	if _level < MapKnowledge.LEVEL_LAYER or _view.is_empty():
		return floor_text
	return "%s · %s" % [tr("MAP_LAYER") % _view.depth, floor_text]


## Стрелки лестниц и порталов — с ранга LEVEL_COMPLEX, того же, с которого
## экран карты показывает связи между слоями.
func shows_arrows() -> bool:
	return _level >= MapKnowledge.LEVEL_COMPLEX


func _draw() -> void:
	if _view.is_empty() or plan == null:
		return
	var t := UI_HudMood.now()
	var center := size * 0.5
	draw_texture_rect(_shadow_texture, Rect2(center - SHADOW_SIZE * 0.5, SHADOW_SIZE), false)
	_draw_frame(t)
	_draw_corridor_beads(t)
	_draw_room_contours(t)
	_draw_dot(t)


## Коридор — «бусы на нитке»: квадрат на клетку и тонкая нить по оси через
## открытые проёмы. Одних квадратов мало: соседние ветки, идущие вплотную, но
## не соединённые, читались одной сеткой точек. Нить идёт только там, где проход
## есть, — к соседней клетке и до контура комнаты за дверью, — и связи видны
## сами. Пройденная ветка — сплошной нитью и залитыми квадратами, известная по
## двери — пунктиром и контурами.
##
## Квадраты проступают по одному от того конца, откуда пришла волна; рукава нити
## — вместе со своим квадратом, так что нить тянется вслед за цепочкой.
func _draw_corridor_beads(t: float) -> void:
	var side := _step * TILE_SIZE
	var reach := 0.5 + (1.0 - room_fill) * 0.5
	for branch in branches:
		var known := branch.id == here or visited.has(branch.id)
		for cell in tiles_of(branch.id):
			var progress := tile_progress(branch.id, cell, t)
			if progress <= 0.0:
				continue
			var center := to_screen(Vector2(cell))
			var thread := UI_HudMood.SOUL
			thread.a = (THREAD_ALPHA if known else THREAD_UNKNOWN_ALPHA) * progress
			for neighbour in _open_neighbours(cell):
				var offset := Vector2(_planar(neighbour) - cell)
				var end := center + offset * _step * (0.5 if plan.corridor_tiles.has(neighbour) else reach)
				# От края бусины, а не от центра: пустая бусина ветки, известной
				# лишь по двери, иначе перечёркивалась бы нитью крестом.
				var start := center + offset * side * 0.5
				if known:
					draw_line(start, end, thread, THREAD_WIDTH, true)
				else:
					_draw_dashed(PackedVector2Array([start, end]), thread, THREAD_WIDTH)

			var color := UI_HudMood.SOUL
			color.a = (CORRIDOR_ALPHA if known else CORRIDOR_UNKNOWN_ALPHA) * progress
			# Квадрат чуть дорастает, проступая: появление по одному читается
			# движением вдоль цепочки, а не миганием.
			var grown := side * lerpf(0.6, 1.0, progress)
			var square := Rect2(center - Vector2(grown, grown) * 0.5, Vector2(grown, grown))
			if known:
				draw_rect(square, color, true)
			else:
				draw_rect(square, color, false, UNKNOWN_WIDTH, true)


## Рамка вокруг всей мини-карты — заголовка, плана и подсказки: тонкий
## скруглённый контур, рваный тем же шумом, что дуга распада (UI_HudMood.noise),
## и с той же амплитудой от смятения T, только вдвое тоньше. Рамка не
## «прибор»: она дрожит, как край мысли, и тем отделяет карту от мира без
## подложки. Прорисовывается пером при открытии, раньше контуров комнат.
func _draw_frame(t: float) -> void:
	var outline := _frame_outline(t)
	var reveal := clampf((t - _opened_at) / FRAME_SECONDS, 0.0, 1.0)
	var color := UI_HudMood.SOUL
	color.a = FRAME_ALPHA
	draw_polyline(_partial(outline, reveal), color, FRAME_WIDTH, true)


## Прямоугольник рамки в координатах узла: от заголовка над планом до подсказки
## под ним.
func frame_rect() -> Rect2:
	var top := TITLE_OFFSET.y - FRAME_MARGIN.y
	var bottom := size.y + HINT_GAP + HINT_HEIGHT + FRAME_MARGIN.y
	return Rect2(-FRAME_MARGIN.x, top, size.x + FRAME_MARGIN.x * 2.0, bottom - top)


## Замкнутая ломаная рамки, сдвинутая по нормали шумом. Шаг 2 px: на нём шум с
## частотой в несколько горбов на сторону гладок, а точек на кадр — несколько сот.
func _frame_outline(t: float) -> PackedVector2Array:
	var rect := frame_rect()
	var radius := FRAME_RADIUS
	var inner := rect.grow(-radius)
	var corners := [
		[Vector2(inner.end.x, inner.position.y), -PI * 0.5],
		[inner.end, 0.0],
		[Vector2(inner.position.x, inner.end.y), PI * 0.5],
		[inner.position, PI],
	]
	# Опорные точки по часовой от левого конца верхней стороны: прямые отрезки и
	# четверти скруглений; дальше нарезаем их на шаг 2 px.
	var base := PackedVector2Array()
	var normals := PackedVector2Array()
	for corner in corners:
		var c: Vector2 = corner[0]
		var from: float = corner[1]
		for i in FRAME_CORNER_STEPS + 1:
			var a := from + PI * 0.5 * i / FRAME_CORNER_STEPS
			var n := Vector2(cos(a), sin(a))
			base.append(c + n * radius)
			normals.append(n)
	base.append(base[0])
	normals.append(normals[0])

	var perimeter := 0.0
	for i in base.size() - 1:
		perimeter += base[i].distance_to(base[i + 1])
	var amp := FRAME_RAG_PX + FRAME_RAG_TURMOIL_PX * UI_HudMood.turmoil()
	var outline := PackedVector2Array()
	var walked := 0.0
	for i in base.size() - 1:
		var length := base[i].distance_to(base[i + 1])
		var pieces := maxi(1, ceili(length / 2.0))
		for k in pieces:
			var f := float(k) / pieces
			var u := (walked + length * f) / perimeter
			var n := normals[i].lerp(normals[i + 1], f).normalized()
			outline.append(base[i].lerp(base[i + 1], f) + n * amp * UI_HudMood.noise(u * TAU * FRAME_WAVES, t * 0.6))
		walked += length
	outline.append(outline[0])
	return outline


func _draw_room_contours(t: float) -> void:
	for node_data in rooms:
		var progress := progress_of(node_data.id, t)
		if progress <= 0.0:
			continue
		var outline := _room_outline(node_data.id)
		var color := UI_HudMood.SOUL
		if node_data.id == here or visited.has(node_data.id):
			color.a = (HERE_FILL if node_data.id == here else VISITED_FILL) * progress
			draw_colored_polygon(outline.slice(0, outline.size() - 1), color)
			color.a = ROOM_ALPHA
			draw_polyline(_partial(outline, progress), color, ROOM_WIDTH, true)
		else:
			color.a = UNKNOWN_ALPHA * progress
			_draw_dashed(outline, color, UNKNOWN_WIDTH)
		if shows_arrows():
			_draw_arrows(node_data, progress)


## Контур комнаты замкнутой ломаной из восьми точек: углы и середины сторон,
## середины чуть сдвинуты поперёк стороны. Сдвиг — от id узла, а не случайный
## на кадр: дрожащий контур читался бы помехой, а не рукой.
func _room_outline(node_id: StringName) -> PackedVector2Array:
	var rect := _room_rect(node_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(node_id)
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	var normals := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var points := PackedVector2Array()
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		points.append(a)
		points.append((a + b) * 0.5 + normals[i] * rng.randf_range(-JITTER_PX, JITTER_PX))
	points.append(corners[0])
	return points


## Лестница — две стрелки, вверх и вниз: она связывает этажи, и именно по ней
## мини-карта, показывающая один этаж, говорит, что над ним есть ещё. Портал на
## другой слой — одна стрелка в его сторону.
func _draw_arrows(node_data: RS_LevelNode, progress: float) -> void:
	var k := _step / CELL_PX
	var center := _room_rect(node_data.id).get_center()
	var color := UI_HudMood.SOUL
	color.a = ARROW_ALPHA * progress
	if _joins_floors(node_data.id):
		_draw_chevron(center + Vector2(0.0, -4.0) * k, -1.0, k, color)
		_draw_chevron(center + Vector2(0.0, 2.0) * k, 1.0, k, color)
		return
	var conn := MapKnowledge.portal_of(RunManager.current_graph, node_data)
	if conn == null:
		return
	var target := RunManager.current_graph.get_node_data(conn.target_node_id)
	var up := target.depth < node_data.depth
	_draw_chevron(center + Vector2(0.0, 3.0 if up else -3.0) * k, -1.0 if up else 1.0, k, color)


## Связывает ли комната этажи — есть ли у неё дверь выше её нижнего уровня. По
## высоте footprint не судить: зал Архитектора тоже в два уровня, но дверь у него
## одна, внизу, и стрелки «есть этаж выше» на нём были бы враньём.
func _joins_floors(node_id: StringName) -> bool:
	var bottom: int = plan.cells[node_id].y
	for face: Vector4i in plan.door_faces.get(node_id, {}):
		if face.y != bottom:
			return true
	return false


## Галка «^» ([param direction] −1) или «v» (+1) с основанием в [param base].
func _draw_chevron(base: Vector2, direction: float, k: float, color: Color) -> void:
	draw_polyline(PackedVector2Array([
		base + Vector2(-6.0, 0.0) * k, base + Vector2(0.0, 6.0 * direction) * k, base + Vector2(6.0, 0.0) * k,
	]), color, ARROW_WIDTH, true)


## Игрок — пульсирующая точка с расходящимся кольцом. Появляется с контуром
## текущего узла: с него волна прорисовки и начинается.
func _draw_dot(t: float) -> void:
	if not show_player:
		return
	var alpha := progress_of(here, t)
	var center := world_to_screen(player_position)
	var color := UI_HudMood.OVER
	color.a = alpha
	draw_circle(center, DOT_RADIUS, color, true, -1.0, true)
	var phase := fmod(t - _opened_at, RING_PERIOD) / RING_PERIOD
	color.a = 0.6 * (1.0 - phase) * alpha
	draw_arc(center, RING_RADIUS * lerpf(0.6, 1.6, phase), 0.0, TAU, 32, color, 1.2, true)


## Начало ломаной длиной в долю [param fraction] её полной длины —
## прорисовка контура «пером».
static func _partial(points: PackedVector2Array, fraction: float) -> PackedVector2Array:
	if fraction >= 1.0:
		return points
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var left := total * fraction
	var result := PackedVector2Array([points[0]])
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		if length >= left:
			result.append(points[i].lerp(points[i + 1], left / maxf(length, 0.0001)))
			break
		result.append(points[i + 1])
		left -= length
	return result


## Пунктир 3:4 вдоль ломаной. Свой, а не draw_dashed_line: у того штрих и
## пробел равны, и узор рвался бы на каждом углу.
func _draw_dashed(points: PackedVector2Array, color: Color, width: float) -> void:
	var drawing := true
	var left := DASH_PX
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length <= 0.0:
			continue
		var direction := (b - a) / length
		var at := 0.0
		while at < length:
			var run := minf(left, length - at)
			if drawing:
				draw_line(a + direction * at, a + direction * (at + run), color, width, true)
			at += run
			left -= run
			if left <= 0.0:
				drawing = not drawing
				left = DASH_PX if drawing else GAP_PX
