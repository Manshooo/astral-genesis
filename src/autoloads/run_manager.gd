# res://src/autoloads/run_manager.gd
extends Node
## Управляет одним "забегом": граф уровня + загруженный СЛОЙ.
##
## Гранула стриминга — СЛОЙ (все узлы одной depth разом в дереве сцены), а не
## отдельная комната. Переход внутри слоя = телепорт игрока в уже стоящую
## комнату (ничего не грузится и не сносится); переход по вертикальному
## коннектору = деспавн всего слоя и спавн нового.
##
## Коридоров между комнатами нет: связь чисто логическая (двери ↔ рёбра графа),
## поэтому комнаты слоя просто расставляются по детерминированной сетке —
## см. _layer_layout.
##
## Двери и переходы: у дверей комнаты компонент C_DoorSlot, при спавне RunManager
## сопоставляет рёбра узла слотам и штампует на каждую дверь C_DoorPortal
## (target_node_id + locked_by) вместе с подсказкой. Лишние слоты запечатываются
## (_seal_door) — не выключаются, а объясняют игроку, что прохода нет.
##
## Прогресс забега: смена комнаты — контрольная точка (WorldSave.record_progress),
## вход в забег стартует с сохранённого узла, если забег не завершён.

signal complex_entered(graph: RS_LevelGraph)
signal room_changed(node_id: StringName)
## Загружен новый слой (все его комнаты уже в дереве). depth == -1 — слой снят.
signal layer_changed(depth: int)
## Игрок сбежал на поверхность — забег (и пока вся игра) окончен победой.
signal run_finished
## БФЖ распался: запас жизни иссяк, пока душа была развоплощена (проигрыш).
signal died

## Заглушка «игра окончена»: экрана концовки пока нет — уходим в меню, как и
## «выход в меню» из паузы.
const MENU_SCENE := "res://src/levels/menu_map/L_menu_map.tscn"
## Экран смерти: показывается после распада БФЖ (см. die).
const DEATH_SCENE := "res://src/ui/death_screen/death_screen.tscn"
## Сцена души-БФЖ. Спавним её скриптом при входе в забег, а не кладём в world.tscn:
## игрок должен появляться в уже сгенерированном мире, у входного узла графа.
const PLAYER_SCENE := "res://src/entities/player/e_player.tscn"

## Шаг сетки между соседними комнатами одного этажа (по X). Комната ~22 м в
## поперечнике (полотна дверей торчат до ±11), берём с запасом — комнаты не
## должны соприкасаться даже коллайдерами, иначе луч взаимодействия или капсула
## игрока могут зацепить соседнюю.
const ROOM_SPACING := 60.0
## Разнос этажей ОДНОГО слоя по высоте. Комната ~6 м высотой — 20 м даёт
## гарантированный зазор и делает раскладку читаемой в отладке.
const FLOOR_SPACING := 20.0
## "Слой не загружен". Глубины графа — 0..4 (RS_LevelGraph.DEPTHS), так что -1
## никогда не совпадёт с реальной.
const NO_DEPTH := -1

## Подсказки на дверях. Состояние двери известно только при биндинге рёбер,
## поэтому prompt_text проставляем здесь, а не в пресете комнаты (в сценах он у
## дверей пустой). Игрок должен отличать рабочую дверь от запертой и от
## запечатанного проёма ДО нажатия — иначе непонятно, декор это или баг.
const DOOR_PROMPT_OPEN := "Пройти"
const DOOR_PROMPT_LOCKED := "Заперто"
const DOOR_PROMPT_SEALED := "Прохода нет"

## Подсказки на вертикальных порталах. Вверх/вниз считаем по глубине цели, а не
## по знаку depth_delta: у слоёв номер РАСТЁТ вглубь, и знак читается наоборот.
const PORTAL_PROMPT_UP := "Подняться"
const PORTAL_PROMPT_DOWN := "Спуститься"
const PORTAL_PROMPT_LOCKED := "Портал заблокирован"
const PORTAL_PROMPT_DEAD := "Портал мёртв"


## Одна заспавненная комната слоя. Вложенные сущности держим отдельно от самой
## комнаты, т.к. add_entity(room) регистрирует ТОЛЬКО саму комнату (обхода дерева
## в поисках вложенных Entity в GECS нет), а remove_entity(room) их не снимает.
class SpawnedRoom:
	extends RefCounted

	var node_id: StringName
	var entity: Entity
	## Вложенные сущности комнаты (Incubator, двери, тела) — регистрируются и
	## снимаются явно, см. _register_room_children / _despawn_layer.
	var children: Array[Entity] = []
	## Подмножество children — двери (с C_DoorSlot). Нужно для поиска выхода,
	## ведущего обратно (_find_return_exit).
	var doors: Array[Entity] = []
	## Подмножество children — вертикальные порталы. Им достаются рёбра со сменой
	## глубины (см. _bind_portals); в остальном они такой же «выход», как дверь.
	var portals: Array[Entity] = []

	## Всё, что может нести C_DoorPortal, то есть вести в соседний узел графа.
	func exits() -> Array[Entity]:
		var all: Array[Entity] = doors.duplicate()
		all.append_array(portals)
		return all


var current_graph: RS_LevelGraph
var current_node_id: StringName = &""
## Глубина загруженного слоя (NO_DEPTH — ничего не загружено).
var current_depth: int = NO_DEPTH
## node_id -> SpawnedRoom для ВСЕХ комнат текущего слоя, а не только той, где
## стоит игрок.
var _rooms: Dictionary[StringName, SpawnedRoom] = {}
## depth -> LayerPlan. План не зависит от того, загружен слой или нет, и
## детерминирован от графа — значит считается один раз за забег. Карта комплекса
## спрашивает планы слоёв, в которых игрок ещё не был.
var _plans: Dictionary[int, LayerPlan] = {}


## Точка входа в забег: генерирует комплекс и ставит игрока в стартовый узел.
## Комплекс НЕ читается из сейва покомнатно — он выводится из сида, а сейв даёт
## только точку, где игрок остановился (см. _start_node_id).
func enter_complex(run_seed: int = -1) -> void:
	if run_seed == -1:
		run_seed = WorldSave.save.run_seed()  # детерминированно из (world_seed, death_count)

	# Сносим состояние прошлой сессии ДО всего остального. RunManager — autoload и
	# переживает смену сцены, а «Выход в меню» из паузы забег не заканчивает: в
	# _rooms остаются комнаты, УЖЕ УБИТЫЕ вместе со старой сценой мира, и
	# current_depth от них же. Если сохранённый узел оказывался той же глубины,
	# _enter_node считал слой уже загруженным и лез в мёртвую комнату —
	# «Trying to cast a freed object» при загрузке сейва.
	_despawn_layer()
	current_node_id = &""
	_plans.clear()  # планы считаны от прошлого графа

	# Игрок появляется в уже сгенерированном мире: сперва спавним душу, затем граф,
	# затем входной слой — _enter_node → _place_player_in_room поставит её на место.
	_spawn_player()
	current_graph = RS_LevelGraph.new().generate_run(run_seed, GameConfig.config.room_preset_library)
	complex_entered.emit(current_graph)
	_restore_player_progress()
	_enter_node(_start_node_id())


## Узел, с которого начинается сессия: сохранённый (продолжение забега) или
## входной. Сейв мог быть сделан на другом сиде/версии графа — если узла в графе
## нет, молча откатываемся на вход, а не роняем забег.
func _start_node_id() -> StringName:
	var saved := WorldSave.save
	if saved.run_in_progress and current_graph.get_node_data(saved.current_node_id) != null:
		return saved.current_node_id
	if saved.run_in_progress:
		push_warning(
			"RunManager: сохранённый узел '%s' отсутствует в графе — старт с входного"
			% saved.current_node_id
		)
	return current_graph.entry_node_id


## Возвращает БФЖ то, что не выводится из сида: воплощение и остаток распада.
## Иначе загрузка работала бы как бесплатное восстановление (свежая E_Player
## несёт полный C_Lifespan) и как принудительное развоплощение.
##
## Запас распада НЕ обрезается по максимуму: с моделью «распад как ресурс» он
## законно бывает больше — излишек, вынесенный из тела при добровольном выходе,
## и утекает он быстрее обычного (S_Lifespan). Обрезка здесь молча съедала бы
## именно то, что игрок заработал, выйдя из тела вовремя.
func _restore_player_progress() -> void:
	var saved := WorldSave.save
	if not saved.run_in_progress:
		return
	var player := _get_player()
	if player == null:
		return

	_restore_embodiment(player, saved)

	var life := player.get_component(C_Lifespan) as C_Lifespan
	if life and saved.lifespan_remaining >= 0.0:
		life.current = saved.lifespan_remaining

	# Карман тела — тоже состояние: он убывает всё время, пока игрок в теле, и
	# потолок его правят скиллы. Компонент к этому моменту уже надет
	# (_restore_embodiment), on_worn открыл его ПОЛНЫМ — числами из сейва
	# поправляем на то, что было на самом деле.
	var decay := player.get_component(C_BodyDecay) as C_BodyDecay
	if decay:
		decay.maximum = saved.body_lifespan_max
		decay.remaining = saved.body_lifespan_remaining


## Возвращает душу в тело, в котором её сохранили. Свежая E_Player всегда
## призрак: её идентичность — только C_BodySnatch + C_Lifespan
## (define_components), а C_Embodied/C_Health/C_BodyVisual навешивает захват.
##
## Облик и характеристики читаются из сцены тела, а не из сейва: и меш, и числа
## пресета — часть сцены, писать их в .tres значило бы завести второй источник
## правды (см. E_Body.visual_of / traits_of_scene). Из сейва берётся только
## состояние: сколько HP и сколько запаса осталось — вместе с их потолками,
## потому что потолки правят скиллы.
func _restore_embodiment(player: Entity, saved: RS_WorldSave) -> void:
	if saved.body_scene_path.is_empty():
		return  # сохранились призраком — восстанавливать нечего

	var embodied := C_Embodied.new()
	embodied.body_scene_path = saved.body_scene_path
	player.add_component(embodied)

	# Характеристики надетого тела — из СЦЕНЫ, тем же общим механизмом, что и при
	# захвате: перечислять их здесь по именам значило бы завести вторую копию
	# правила переноса, которая молча отстанет от первой при добавлении стата.
	for worn in E_Body.traits_of_scene(saved.body_scene_path):
		if worn is C_BodyTrait:
			(worn as C_BodyTrait).on_worn()
		player.add_component(worn)

	# HP, наоборот, чистое состояние — числами из сейва поверх свежего компонента
	# (вместе с потолком: его правят скиллы).
	var health := player.get_component(C_Health) as C_Health
	if health:
		health.maximum = saved.body_health_max
		health.current = saved.body_health

	var visual := E_Body.visual_of_scene(saved.body_scene_path)
	if visual:
		player.add_component(visual)
	else:
		# Тело восстановлено по механике, но выглядит игрок призраком. Молчать
		# нельзя: обычно это значит, что сцену тела переименовали или удалили.
		push_warning(
			"RunManager: не удалось прочитать облик тела из «%s» — БФЖ во плоти, но без вида"
			% saved.body_scene_path
		)


## Инстанцирует душу-БФЖ и регистрирует её в мире, если её там ещё нет.
## Позиционирование — на совести _place_player_in_room (при входе в первый узел).
##
## Учёт WorldSave/новой игры: сид забега уже выведен в enter_complex из
## (world_seed, death_count); свежая E_Player несёт полный запас жизни — её
## идентичность (C_BodySnatch, C_Lifespan) навешивает define_components(), а не
## сцена, так что каждый новый забег стартует с непочатым C_Lifespan.
func _spawn_player() -> void:
	if _get_player() != null:
		return  # уже в мире (напр. повторный enter_complex в той же сцене)
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as E_Player
	ECS.world.add_entity(player)


## Побег на поверхность = ОКОНЧАНИЕ ИГРЫ (победа). Это НЕ возврат в хаб — тот
## происходит только при смерти (пока не реализовано, нужен death_count/состояния).
## Зовётся A_FinishRun из комнаты-выхода (тег level_exit).
func finish_run() -> void:
	if current_graph == null:
		return  # не в забеге — выходить неоткуда

	WorldSave.clear_run()  # забег завершён: «Загрузить» начнёт этот мир заново
	_end_run()
	run_finished.emit()

	# TODO: экран концовки/победы. Пока — в меню, как «выход в меню» из паузы.
	get_tree().change_scene_to_file(MENU_SCENE)


## Ручное сохранение (кнопка «Сохранить» в паузе). Контрольные точки и так
## ставятся на каждой смене комнаты, но распад тикает НЕПРЕРЫВНО — без этого
## в сейве остаётся запас на момент входа в комнату, а не на сейчас.
## false — сохранять нечего (не в забеге).
func save_progress() -> bool:
	if current_graph == null or current_node_id == &"":
		return false
	_checkpoint(current_node_id)
	return true


## Выход в меню из паузы. Забег НЕ заканчивается: в сейве остаётся
## run_in_progress, «Загрузить» вернёт игрока сюда же. Здесь только фиксируем
## контрольную точку на текущий момент и отпускаем мир — сцена всё равно уходит,
## а держать ссылки на её комнаты нельзя (см. про мёртвые комнаты в enter_complex).
func leave_to_menu() -> void:
	if current_graph == null:
		return
	save_progress()
	_end_run()


## Настоящая смерть БФЖ: запас распада иссяк, пока душа была РАЗВОПЛОЩЕНА
## (событие "run_ended" от S_Lifespan). В отличие от finish_run (побег = победа),
## смерть фиксируется в сейве — death_count++ меняет будущую генерацию — и уводит
## на экран смерти. Зовётся отложенно из O_RunEnded (нельзя сносить забег в
## середине прохода ECS по сущностям).
func die() -> void:
	if current_graph == null:
		return  # не в забеге — умирать некому

	WorldSave.record_death()  # death_count++ → следующий run_seed() иной
	_end_run()
	died.emit()

	# TODO: анимация распада/затемнение перед экраном. Пока — сразу экран смерти.
	get_tree().change_scene_to_file(DEATH_SCENE)


## Общий снос забега для finish_run/die: убрать загруженный слой и обнулить граф.
## Игрока и системы не трогаем — они уходят вместе со сценой мира при смене сцены.
func _end_run() -> void:
	_despawn_layer()
	current_graph = null
	current_node_id = &""


## Переход в другой узел графа (вызывается A_TravelThroughDoor).
func travel_to(node_id: StringName) -> void:
	if current_graph == null or current_graph.get_node_data(node_id) == null:
		push_warning("RunManager: некорректный переход в '%s'" % node_id)
		return
	_enter_node(node_id, current_node_id)


## Делает [param node_id] текущим узлом: догружает его слой, если игрок сменил
## глубину, и переставляет игрока в нужную комнату.
## [param came_from] узел, из которого пришли — чтобы поставить игрока к двери,
## ведущей обратно, а не в общий SpawnPoint. Пусто = первый вход в забег.
func _enter_node(node_id: StringName, came_from: StringName = &"") -> void:
	var node_data := current_graph.get_node_data(node_id)
	if node_data == null:
		push_error("RunManager: нет данных узла '%s'" % node_id)
		return

	# Слой уже в дереве — комната-цель стоит на месте, грузить нечего.
	if node_data.depth != current_depth:
		_despawn_layer()
		_spawn_layer(node_data.depth)

	var room: SpawnedRoom = _rooms.get(node_id)
	if room == null:
		push_error("RunManager: комната узла '%s' не заспавнилась" % node_id)
		return

	current_node_id = node_id
	# Смена комнаты — гранула сохранения забега: дальше игрок продолжит отсюда.
	_checkpoint(node_id)
	room_changed.emit(node_id)
	_place_player_in_room(room, came_from)


## Спавнит ВСЕ комнаты слоя [param depth] разом. Предполагает, что предыдущий
## слой уже снят (_despawn_layer) — иначе комнаты наложатся по сетке.
func _spawn_layer(depth: int) -> void:
	var layer_nodes := current_graph.get_nodes_by_depth(depth)
	if layer_nodes.is_empty():
		push_error("RunManager: в графе нет узлов глубины %d" % depth)
		return

	var plan := plan_for_depth(depth)
	for node_data in layer_nodes:
		var entity := _instantiate_room(node_data)
		if entity == null:
			continue
		var room := _spawn_room(node_data, entity, plan)
		if room:
			_rooms[node_data.id] = room

	current_depth = depth
	layer_changed.emit(depth)


## План слоя [param depth] — где стоит каждая комната и какое ребро уходит в
## какую дверь. Считается БЕЗ спавна (стороны дверей берутся из кэша по пути
## сцены), поэтому доступен и для незагруженных слоёв: на этом держится карта
## комплекса. Результат кэшируется на забег — план детерминирован от графа.
func plan_for_depth(depth: int) -> LayerPlan:
	if _plans.has(depth):
		return _plans[depth]
	var plan := _plan_layer(current_graph.get_nodes_by_depth(depth))
	_plans[depth] = plan
	return plan


## Инстанцирует сцену комнаты, НЕ добавляя её в мир. null — путь сцены невалиден.
func _instantiate_room(node_data: RS_LevelNode) -> Entity:
	if node_data.room_scene_path == "" or not ResourceLoader.exists(node_data.room_scene_path):
		push_error("RunManager: невалидная room_scene_path у узла '%s'" % node_data.id)
		return null
	return (load(node_data.room_scene_path) as PackedScene).instantiate() as Entity


## Ставит уже инстанцированную комнату на её место по плану и регистрирует всё
## её содержимое в мире.
func _spawn_room(node_data: RS_LevelNode, entity: Entity, plan: LayerPlan) -> SpawnedRoom:
	# Позицию ставим ДО add_entity: тот сам вносит узел в дерево, и комната должна
	# попасть туда сразу на своё место — иначе коллайдеры успевают
	# зарегистрироваться в начале координат и телепортируются следом.
	# Через Node: Entity наследует Node, и прямой каст Entity→Node3D анализатор
	# GDScript не пропускает (тот же приём, что в _arrival_transform_for_door).
	var spatial := entity as Node as Node3D
	if spatial:
		spatial.position = plan.positions.get(node_data.id, Vector3.ZERO)

	ECS.world.add_entity(entity)

	var ref := entity.get_component(C_LevelNode) as C_LevelNode
	if ref:
		ref.node_id = node_data.id

	var room := SpawnedRoom.new()
	room.node_id = node_data.id
	room.entity = entity
	room.children = _register_room_children(entity, node_data.id)
	room.doors = _bind_doors(room, node_data, plan)
	return room


# ---------------------------------------------------------------------------
# Раскладка слоя: комнаты стоят там, куда ведут их двери
# ---------------------------------------------------------------------------


## Геометрия комнат (где север, куда смещается клетка) живёт в RS_RoomLayout —
## одно правило на рантайм и на редакторский инструмент проверки сцен.
const DIRECTION_OFFSETS := RS_RoomLayout.OFFSETS
const OPPOSITE_DIRECTION := RS_RoomLayout.OPPOSITE


## План раскладки одного слоя.
class LayerPlan:
	extends RefCounted

	## node_id -> мировая позиция комнаты.
	var positions: Dictionary[StringName, Vector3] = {}
	## node_id -> клетка сетки этажа. То же самое, что positions, но без масштаба
	## и высоты: ровно то, что рисует карта.
	var cells: Dictionary[StringName, Vector2i] = {}
	## node_id -> { target_node_id: сторона }. Только рёбра, которым нашлась дверь
	## В НУЖНУЮ СТОРОНУ: сосед физически стоит за этой дверью. Остальные рёбра
	## (межэтажные, межслойные, не влезшие в сетку) раздаются по остаточному
	## принципу в _bind_doors.
	var direction_by_edge: Dictionary[StringName, Dictionary] = {}

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


## Строит план слоя: раскладывает комнаты каждого этажа по 2D-сетке обходом
## графа — сосед ставится ровно в ту клетку, куда смотрит связывающая их дверь.
## Иначе дверь «на север» уводила бы в комнату, стоящую совсем в другой стороне.
##
## Этажи одного слоя разносятся по высоте: связь между ними идёт через
## floor_hub-рёбра, у которых нет направления в плоскости этажа.
func _plan_layer(layer_nodes: Array[RS_LevelNode]) -> LayerPlan:
	var plan := LayerPlan.new()
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
		_plan_floor(floor_nodes, plan, floor_index)
	return plan


func _plan_floor(floor_nodes: Array, plan: LayerPlan, floor_index: int) -> void:
	var dirs := {}  # node_id -> Array[StringName] сторон, с которых у комнаты есть дверь
	var on_floor := {}  # node_id -> RS_LevelNode, для быстрой проверки «сосед на этаже»
	for node_data: RS_LevelNode in floor_nodes:
		on_floor[node_data.id] = node_data
		dirs[node_data.id] = RS_RoomLayout.door_directions_of_scene(node_data.room_scene_path)

	var cells: Dictionary[StringName, Vector2i] = {}
	var taken: Dictionary[Vector2i, StringName] = {}
	_place_at(floor_nodes[0].id, Vector2i.ZERO, cells, taken)

	# 1. Обход в ширину: соседа ставим в клетку той двери, что к нему ведёт.
	var queue: Array[StringName] = [floor_nodes[0].id]
	while not queue.is_empty():
		var current_id: StringName = queue.pop_front()
		for conn: RS_LevelConnection in _by_room_freedom(on_floor[current_id].connections, dirs):
			var target_id := conn.target_node_id
			if not on_floor.has(target_id) or cells.has(target_id):
				continue
			var direction := _pick_direction(current_id, target_id, cells, taken, dirs, plan)
			if direction == &"":
				continue  # ни одной подходящей свободной стороны — разместим ниже
			_place_at(target_id, cells[current_id] + DIRECTION_OFFSETS[direction], cells, taken)
			plan.link(current_id, direction, target_id)
			queue.append(target_id)

	# 2. Не разместившиеся (нет подходящих дверей, другой компонент связности):
	#    ставим рядом с любым уже размещённым соседом, иначе — в запасной ряд.
	for node_data: RS_LevelNode in floor_nodes:
		if cells.has(node_data.id):
			continue
		_place_at(node_data.id, _fallback_cell(node_data, cells, taken, dirs, plan), cells, taken)

	# 3. Доп. рёбра (циклы) между уже размещёнными: если клетки оказались смежными
	#    и двери с обеих сторон свободны — тоже свяжем по направлению.
	for node_data: RS_LevelNode in floor_nodes:
		for conn: RS_LevelConnection in node_data.connections:
			var target_id := conn.target_node_id
			if not on_floor.has(target_id):
				continue
			if plan.direction_for(node_data.id, target_id) != &"":
				continue
			var direction := _direction_between(cells[node_data.id], cells[target_id])
			if direction == &"" or not _direction_available(node_data.id, direction, dirs, plan):
				continue
			if not _direction_available(target_id, OPPOSITE_DIRECTION[direction], dirs, plan):
				continue
			plan.link(node_data.id, direction, target_id)

	for node_id: StringName in cells:
		var cell := cells[node_id]
		plan.cells[node_id] = cell
		plan.positions[node_id] = Vector3(
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
	cells: Dictionary[StringName, Vector2i],
	taken: Dictionary[Vector2i, StringName],
) -> void:
	cells[node_id] = cell
	taken[cell] = node_id


## Сторона, с которой можно поставить соседа: у нас есть такая дверь и она ещё
## свободна, у соседа есть встречная, и клетка за ней не занята. Порядок перебора
## — из DIRECTION_OFFSETS, то есть детерминированный.
func _pick_direction(
	current_id: StringName,
	target_id: StringName,
	cells: Dictionary[StringName, Vector2i],
	taken: Dictionary[Vector2i, StringName],
	dirs: Dictionary,
	plan: LayerPlan,
) -> StringName:
	for direction: StringName in DIRECTION_OFFSETS:
		if not _direction_available(current_id, direction, dirs, plan):
			continue
		if not _direction_available(target_id, OPPOSITE_DIRECTION[direction], dirs, plan):
			continue
		if taken.has(cells[current_id] + DIRECTION_OFFSETS[direction]):
			continue
		return direction
	return &""


## Есть ли у комнаты дверь с этой стороны и не отдана ли она уже другому ребру.
func _direction_available(
	node_id: StringName, direction: StringName, dirs: Dictionary, plan: LayerPlan
) -> bool:
	var available: Array = dirs.get(node_id, [])
	return available.has(direction) and not plan.is_direction_taken(node_id, direction)


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
	cells: Dictionary[StringName, Vector2i],
	taken: Dictionary[Vector2i, StringName],
	dirs: Dictionary,
	plan: LayerPlan,
) -> Vector2i:
	var best := Vector2i.MAX
	var best_score := -1
	for conn: RS_LevelConnection in node_data.connections:
		if not cells.has(conn.target_node_id):
			continue
		for direction: StringName in DIRECTION_OFFSETS:
			var cell: Vector2i = cells[conn.target_node_id] + DIRECTION_OFFSETS[direction]
			if taken.has(cell):
				continue
			# Мы встаём в direction ОТ соседа, значит сосед для нас — со встречной.
			var score := 0
			if _direction_available(node_data.id, OPPOSITE_DIRECTION[direction], dirs, plan):
				score += 1
			if _direction_available(conn.target_node_id, direction, dirs, plan):
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


func _direction_of_door(door: Node3D, room: Node) -> StringName:
	return RS_RoomLayout.door_direction(door, room)


## Снимает ВЕСЬ загруженный слой. По каждой комнате сначала вложенные сущности
## (иначе после queue_free комнаты они остались бы битыми ссылками в реестре
## мира), затем саму комнату.
##
## Ссылки могут указывать на УЖЕ ОСВОБОЖДЁННЫЕ сущности: RunManager — autoload и
## переживает смену сцены, так что после «Выхода в меню» прошлый забег улетает
## вместе со сценой мира, а ссылки остаются битыми. remove_entity(entity: Entity)
## типизирован — freed-объект роняет проверку типа ещё ДО тела функции (там, где
## стоит is_instance_valid), поэтому отсеиваем невалидные заранее.
func _despawn_layer() -> void:
	for room: SpawnedRoom in _rooms.values():
		_remove_valid_entities(room.children)
		if is_instance_valid(room.entity):
			ECS.world.remove_entity(room.entity)
	_rooms.clear()
	if current_depth != NO_DEPTH:
		current_depth = NO_DEPTH
		layer_changed.emit(NO_DEPTH)


## remove_entities только для живых сущностей — см. про freed-ссылки в
## _despawn_layer.
func _remove_valid_entities(list: Array[Entity]) -> void:
	var valid: Array[Entity] = []
	for e in list:
		if is_instance_valid(e):
			valid.append(e)
	if not valid.is_empty():
		ECS.world.remove_entities(valid)


## Регистрирует в мире все вложенные сущности комнаты (Incubator, двери и т.п.).
## Нужно, т.к. add_entity(room) кладёт в мир ТОЛЬКО саму комнату — обхода дерева
## в поисках вложенных Entity в GECS нет.
##
## Здесь же отсеиваются УЖЕ ПОГЛОЩЁННЫЕ тела: комната приходит из сцены целой,
## сколько бы раз игрок в ней ни вселялся, потому что комплекс восстанавливается
## из сида, а не из сейва.
func _register_room_children(room: Entity, node_id: StringName) -> Array[Entity]:
	var children: Array[Entity] = []
	# owned=false — иначе сущности, вставленные как инстансы под-сцены, не находятся.
	for node in room.find_children("*", "Entity", true, false):
		var e := node as Entity
		if e == null:
			continue
		var body := e as E_Body
		if body and WorldSave.save.consumed_body_ids.has(_body_id(node_id, room, body)):
			# Тело съедено захватом — иначе рядом с игроком встанет копия того,
			# в ком он сидит. В мир его не регистрируем, поэтому одного кадра до
			# освобождения узла ни одна система не увидит.
			body.queue_free()
			continue
		children.append(e)
	if not children.is_empty():
		ECS.world.add_entities(children)

	# Происхождение штампуем ПОСЛЕ регистрации — как и рёбра дверям (_bind_doors):
	# правка состава компонентов должна дойти до архетипов уже живой сущности.
	for e in children:
		var body := e as E_Body
		if body:
			var origin := C_BodyOrigin.new()
			origin.body_id = _body_id(node_id, room, body)
			body.add_component(origin)

	return children


## Стабильный id авторского тела: узел графа плюс путь узла внутри комнаты.
## Сцена тела своего id не знает и знать не может — один и тот же e_body.tscn
## стоит в разных комнатах, а сид одинаково восстанавливает их все.
func _body_id(node_id: StringName, room: Entity, body: Node) -> StringName:
	return StringName("%s/%s" % [node_id, room.get_path_to(body)])


## Штампует C_DoorPortal на двери комнаты (подмножество room.children с
## C_DoorSlot) по рёбрам узла. Сами двери уже зарегистрированы в мире
## _register_room_children — здесь только биндинг рёбер к слотам.
##
## Сначала раздаём рёбра, которым план назначил СТОРОНУ: за такой дверью сосед
## реально стоит (см. _plan_floor). Что осталось — межэтажные, межслойные и не
## влезшие в сетку рёбра — раздаём по остаточному принципу в детерминированном
## порядке слотов. Лишние двери запечатываются.
func _bind_doors(room: SpawnedRoom, node_data: RS_LevelNode, plan: LayerPlan) -> Array[Entity]:
	var doors: Array[Entity] = []
	for e in room.children:
		if e.has_component(C_DoorSlot):
			doors.append(e)

	# Вертикальные рёбра (смена глубины) забирают ПОРТАЛЫ — ради этого они в
	# комнате и стоят. Оставшиеся вертикальные рёбра (порталов меньше, чем таких
	# рёбер) падают дальше в общий котёл и достаются двери.
	var connections := _bind_portals(room, node_data)
	if doors.is_empty():
		if not connections.is_empty():
			push_warning(
				"RunManager: у узла '%s' не осталось дверей под %d рёбер"
				% [node_data.id, connections.size()]
			)
		return doors

	# Детерминированный порядок независимо от раскладки нод в дереве.
	# Через String(): StringName сравнивается по внутреннему указателю, не лексикографически.
	doors.sort_custom(func(a, b): return String(_slot_id_of(a)) < String(_slot_id_of(b)))

	# Стороны считаем той же геометрией, что и при раскладке слоя, — иначе дверь
	# и план разъедутся (см. _direction_of_door).
	var door_by_direction: Dictionary[StringName, Entity] = {}
	for door in doors:
		var direction := _direction_of_door(door as Node as Node3D, room.entity)
		if direction != &"" and not door_by_direction.has(direction):
			door_by_direction[direction] = door

	var bound: Dictionary[Entity, bool] = {}
	var pending: Array[RS_LevelConnection] = []
	for conn: RS_LevelConnection in connections:
		var direction := plan.direction_for(node_data.id, conn.target_node_id)
		var door: Entity = door_by_direction.get(direction)
		if door != null and not bound.has(door):
			_stamp_portal(door, conn)
			bound[door] = true
		else:
			pending.append(conn)

	# Остатки (межэтажные, межслойные и не влезшие в сетку рёбра) раздаём не как
	# попало: если целевая комната всё же есть в этом слое, берём дверь, которая
	# смотрит в её сторону ближе всего. Точного совпадения тут может не быть —
	# у пресета просто нет двери с нужной стены.
	while not pending.is_empty():
		var conn: RS_LevelConnection = pending.pop_front()
		var door := _closest_free_door(doors, bound, door_by_direction, node_data, conn, plan)
		if door == null:
			pending.push_front(conn)  # свободных дверей не осталось
			break
		_stamp_portal(door, conn)
		bound[door] = true

	for door in doors:
		if not bound.has(door):
			_seal_door(door)  # рёбер меньше, чем проёмов — лишние запечатываем

	if not pending.is_empty():
		push_warning(
			"RunManager: у узла '%s' рёбер (%d) больше, чем дверей (%d) — часть недостижима"
			% [node_data.id, node_data.connections.size(), doors.size()]
		)
	return doors


## Раздаёт ВЕРТИКАЛЬНЫЕ рёбра (те, что меняют глубину) порталам комнаты и
## возвращает рёбра, оставшиеся дверям. Портал без ребра «глушится» так же, как
## лишняя дверь: остаётся интерактивным, но объясняет, что никуда не ведёт.
##
## Почему порталы, а не двери: узлы-коннекторы (`vertical_hub`) для того и несут
## сцену с порталом, чтобы спуск/подъём между слоями выглядел спуском, а не ещё
## одной дверью в стене.
func _bind_portals(room: SpawnedRoom, node_data: RS_LevelNode) -> Array[RS_LevelConnection]:
	var portals: Array[Entity] = []
	for e in room.children:
		if e is E_VerticalPortal:
			portals.append(e)
	room.portals = portals
	if portals.is_empty():
		return node_data.connections.duplicate()

	# Порядок фиксируем по имени узла: раздача рёбер обязана быть детерминированной.
	portals.sort_custom(func(a, b): return String(a.name) < String(b.name))

	var rest: Array[RS_LevelConnection] = []
	var free_portals := portals.duplicate()
	for conn: RS_LevelConnection in node_data.connections:
		var target := current_graph.get_node_data(conn.target_node_id)
		var is_vertical := target != null and target.depth != node_data.depth
		if is_vertical and not free_portals.is_empty():
			var portal: Entity = free_portals.pop_front()
			_stamp_portal(portal, conn)
			_set_door_prompt(portal, _portal_prompt(node_data, target, conn))
		else:
			rest.append(conn)

	for portal in free_portals:
		_seal_door(portal)
		_set_door_prompt(portal, PORTAL_PROMPT_DEAD, false)
	return rest


## Куда ведёт портал — вверх (к поверхности, depth меньше) или вниз.
func _portal_prompt(
	node_data: RS_LevelNode, target: RS_LevelNode, conn: RS_LevelConnection
) -> String:
	if conn.locked_by != &"":
		return PORTAL_PROMPT_LOCKED
	return PORTAL_PROMPT_UP if target.depth < node_data.depth else PORTAL_PROMPT_DOWN


## Свободная дверь, смотрящая в сторону цели ребра. Если позиции цели в этом
## слое нет (другая глубина) — просто первая свободная в порядке slot_id.
func _closest_free_door(
	doors: Array[Entity],
	bound: Dictionary[Entity, bool],
	door_by_direction: Dictionary[StringName, Entity],
	node_data: RS_LevelNode,
	conn: RS_LevelConnection,
	plan: LayerPlan,
) -> Entity:
	var here: Vector3 = plan.positions.get(node_data.id, Vector3.ZERO)
	var there = plan.positions.get(conn.target_node_id)
	if there != null:
		var delta: Vector3 = (there as Vector3) - here
		var to_target := Vector2(delta.x, delta.z)
		if to_target.length_squared() > 0.0:
			to_target = to_target.normalized()
			var best: Entity = null
			var best_score := -INF
			for direction: StringName in door_by_direction:
				var door: Entity = door_by_direction[direction]
				if bound.has(door):
					continue
				var offset: Vector2i = DIRECTION_OFFSETS[direction]
				var score := Vector2(offset.x, offset.y).dot(to_target)
				if score > best_score:
					best_score = score
					best = door
			if best:
				return best

	for door in doors:
		if not bound.has(door):
			return door
	return null


func _stamp_portal(door: Entity, conn: RS_LevelConnection) -> void:
	var portal := C_DoorPortal.new()
	portal.target_node_id = conn.target_node_id
	portal.locked_by = conn.locked_by
	door.add_component(portal)
	_set_door_prompt(door, DOOR_PROMPT_LOCKED if portal.is_locked() else DOOR_PROMPT_OPEN)


## Запечатанная дверь: ребра под этот слот нет, идти некуда. Интеракцию НЕ
## выключаем (раньше выключали): выключенную дверь S_InteractionDetector
## игнорирует — она не подсвечивается и молчит, и игрок не отличает «прохода
## нет» от бага. Вместо этого штампуем ПУСТОЙ C_DoorPortal (пустой
## target_node_id = «запечатан», см. C_DoorPortal) и объясняем подсказкой;
## A_TravelThroughDoor по тому же признаку никуда не ведёт.
## Визуальное «заваривание» — на совести арта/будущей системы.
func _seal_door(door: Entity) -> void:
	door.add_component(C_DoorPortal.new())  # target_node_id == &"" — прохода нет
	# Нажимать бессмысленно, поэтому и клавишу в подсказке не предлагаем.
	_set_door_prompt(door, DOOR_PROMPT_SEALED, false)


func _set_door_prompt(door: Entity, prompt: String, show_key_hint: bool = true) -> void:
	var inter := door.get_component(C_Interactable) as C_Interactable
	if inter == null:
		return
	inter.prompt_text = prompt
	inter.show_key_hint = show_key_hint


func _slot_id_of(door: Entity) -> StringName:
	var slot := door.get_component(C_DoorSlot) as C_DoorSlot
	return slot.slot_id if slot else &""


func _get_player() -> E_Player:
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as E_Player


## Контрольная точка: снимает с БФЖ всё, что не выводится из сида, и отдаёт
## сейву числами. Разбор компонентов живёт здесь, а не в WorldSave: автолоад
## сохранения про ECS ничего не знает и знать не должен.
func _checkpoint(node_id: StringName) -> void:
	var lifespan_left := -1.0
	var body_scene_path := ""
	var body_health := 0.0
	var body_health_max := 0.0
	var body_lifespan_left := 0.0
	var body_lifespan_max := 0.0

	var player := _get_player()
	if player:
		var life := player.get_component(C_Lifespan) as C_Lifespan
		if life:
			lifespan_left = life.current
		# Карман тела есть только во плоти — вместе с самим телом.
		var decay := player.get_component(C_BodyDecay) as C_BodyDecay
		if decay:
			body_lifespan_left = decay.remaining
			body_lifespan_max = decay.maximum
		var embodied := player.get_component(C_Embodied) as C_Embodied
		if embodied:
			body_scene_path = embodied.body_scene_path
		# C_Health есть только во плоти: развоплощённая душа живёт по C_Lifespan.
		var health := player.get_component(C_Health) as C_Health
		if health:
			body_health = health.current
			body_health_max = health.maximum

	WorldSave.record_progress(
		node_id,
		lifespan_left,
		body_scene_path,
		body_health,
		body_health_max,
		body_lifespan_left,
		body_lifespan_max
	)


## На сколько метров вглубь комнаты отступать от двери, чтобы коллайдер игрока не
## оказался в стене/проёме (радиус ~0.55, проём ~2.8 в ширину).
const ARRIVAL_OFFSET := 1.5


## Ставит игрока в комнату. Пришли через дверь — появляемся ПЕРЕД той дверью
## этой комнаты, что ведёт обратно (вошёл в северную дверь A → вышел из южной
## двери B), и **не трогаем поворот**: игрок мог взаимодействовать с дверью под
## углом, и доворачивать его за него — дезориентирует.
## SpawnPoint остаётся только для входа не через дверь (старт забега, загрузка
## сейва) — там авторский поворот как раз уместен.
func _place_player_in_room(room: SpawnedRoom, came_from: StringName) -> void:
	var player := _get_player()
	if player == null:
		return

	var player_node := player as Node as Node3D
	var room_node := room.entity as Node as Node3D
	var spawn_point := room.entity.get_node_or_null(^"SpawnPoint") as Node3D

	var return_exit := _find_return_exit(room, came_from)
	if return_exit:
		# Меняем ТОЛЬКО origin: basis (рыскание) остаётся игроков. Тангаж живёт
		# на камере (S_FPSLook) и сюда вообще не попадает.
		player_node.global_position = _arrival_point(return_exit, room_node, spawn_point)
		return

	if spawn_point:
		player_node.global_transform = spawn_point.global_transform
	else:
		player_node.global_transform = room_node.global_transform


## Безопасная точка прибытия перед дверью [param door]: отступаем от полотна
## перпендикулярно ЕГО СТЕНЕ вглубь комнаты, высоту берём от SpawnPoint (пол).
##
## Не трансформ самой двери: её origin лежит в плоскости стены и на высоте центра
## полотна (~2.3 м) — игрока там зажало бы в геометрии. Направление берём из
## стороны двери (RS_RoomLayout), а не из вектора «на центр комнаты»: так игрок
## встаёт ровно напротив проёма, а не наискосок от него.
func _arrival_point(door: Entity, room_node: Node3D, spawn_point: Node3D) -> Vector3:
	var door_node := door as Node as Node3D
	var door_origin := door_node.global_transform.origin
	var room_origin := room_node.global_transform.origin

	var into_room := Vector3.ZERO
	# У портала стены нет — он стоит посреди комнаты, и «перпендикулярно стене»
	# для него бессмысленно. Отходим от него к центру комнаты.
	var direction := &"" if door is E_VerticalPortal else RS_RoomLayout.door_direction(door_node, room_node)
	if direction != &"":
		var offset: Vector2i = RS_RoomLayout.OFFSETS[direction]
		into_room = -Vector3(offset.x, 0.0, offset.y)  # внутрь = против стороны двери
	else:
		# Сторону определить не вышло — отступаем к центру комнаты.
		into_room = room_origin - door_origin
		into_room.y = 0.0
	if into_room.length() < 0.001:
		into_room = -door_node.global_transform.basis.z  # последний запасной вариант
	into_room = into_room.normalized()

	var point := door_origin + into_room * ARRIVAL_OFFSET
	point.y = spawn_point.global_transform.origin.y if spawn_point else room_origin.y
	return point


## Выход комнаты [param room] (дверь ИЛИ портал), ведущий обратно в came_from —
## чтобы игрок появился у него, а не в общем SpawnPoint. null, если пришли не
## через выход (вход в забег, загрузка сейва).
func _find_return_exit(room: SpawnedRoom, came_from: StringName) -> Entity:
	if came_from == &"":
		return null
	for exit_entity in room.exits():
		var portal := exit_entity.get_component(C_DoorPortal) as C_DoorPortal
		if portal and portal.target_node_id == came_from:
			return exit_entity
	return null
