## res://src/resources/world_generator/rs_layer_plan.gd
## План раскладки одного слоя: где физически стоит каждая комната, как идут
## тайлы веток коридора и какая дверь комнаты смотрит в какую ветку. Считает его
## RS_CorridorPlanner — комнаты на решётке, коридоры трассируются между ними.
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

## Клетка раскладки — шаг кита. Число задано артом, а не выбрано здесь: и
## комнаты (A/B/C, Архитектор), и тайлы SM_corridor_A_* — квадраты 18 м с
## проёмом 2.8 м по центру грани на ±9 м, поэтому комнаты и коридоры встают на
## ОДНУ сетку, и соседние клетки стыкуются проём в проём без переходников.
const CELL_SIZE := 18.0
## Разнос этажей ОДНОГО слоя по высоте. Комната до ~14.5 м высотой (комната
## Архитектора) — 20 м даёт гарантированный зазор.
const FLOOR_SPACING := 20.0
## На сколько ниже пола этажа точка ещё считается этим этажом (доля
## FLOOR_SPACING). Без запаса игрок, у которого origin чуть ниже пола (посадка
## капсулы, ступенька), на границе округления уезжал бы этажом ниже; сверху
## запаса хватает на всю высоту комнаты, включая полёт души под потолком.
const FLOOR_TOLERANCE := 0.25
## Шаг решётки комнат по умолчанию, если ручки не переданы (см.
## RS_WorldGenConfig.room_lattice_step).
const DEFAULT_LATTICE_STEP := 3

## Бит стороны в маске проёмов коридорного тайла. Порядок — как у OFFSETS.
const SIDE_BITS := {&"north": 1, &"east": 2, &"south": 4, &"west": 8}

## node_id -> мировая позиция комнаты. У ветки коридора — позиция её первого
## тайла: у неё нет одной точки, а инструментам нужна хоть какая-то.
var positions: Dictionary[StringName, Vector3] = {}
## node_id -> клетка сетки этажа. То же самое, что positions, но без масштаба
## и высоты: ровно то, что рисует карта.
var cells: Dictionary[StringName, Vector2i] = {}
## Клетка (x, этаж, z) -> node_id — и комнат, и тайлов коридора. Сетки этажей
## независимы, и одна и та же (x, z) на разных этажах — разные узлы. На ней
## держится node_at, а через него — «в каком узле стоит игрок».
var node_by_cell: Dictionary[Vector3i, StringName] = {}
## Клетка тайла (x, этаж, z) -> маска проёмов (SIDE_BITS). Чья это ветка — в
## node_by_cell. По маске сборка выбирает кусок кита: два противоположных проёма —
## прямой, два соседних — поворот, три — Т, четыре — крест. Проём ставится и к
## соседнему тайлу своей ветки, и к двери комнаты, и на стык с родительской
## веткой.
var corridor_tiles: Dictionary[Vector3i, int] = {}
## Комната -> { сторона двери: ветка }. Ключ — сторона, а не сосед: две двери
## комнаты законно ведут в одну и ту же ветку, и по id соседа их не различить
## (RS_LevelGraph._hang_floor_on_corridors).
var door_sides: Dictionary[StringName, Dictionary] = {}
## Сколько трасс не удалось проложить — ветка заперта чужими коридорами и
## комнатами. Раскладка при этом не падает; ноль сверяет проверка.
var routing_failures: Array[String] = []


## Строит план слоя. Этажи одного слоя разносятся по высоте и раскладываются
## независимо: связь между ними — только порталы, у которых нет направления в
## плоскости этажа. [param config] — только ради шага решётки.
static func build(layer_nodes: Array[RS_LevelNode], config: RS_WorldGenConfig = null) -> RS_LayerPlan:
	var plan := RS_LayerPlan.new()
	var by_floor: Dictionary[int, Array] = {}
	for node_data in layer_nodes:
		if not by_floor.has(node_data.floor_index):
			by_floor[node_data.floor_index] = []
		by_floor[node_data.floor_index].append(node_data)

	var step := config.room_lattice_step if config else DEFAULT_LATTICE_STEP
	for floor_index: int in by_floor:
		var floor_nodes: Array = by_floor[floor_index]
		# Порядок фиксируем по index_in_layer: раскладка обязана совпадать от
		# запуска к запуску при одном сиде — иначе сохранённая комната окажется в
		# другом месте.
		floor_nodes.sort_custom(func(a, b): return a.index_in_layer < b.index_in_layer)
		RS_CorridorPlanner.plan_floor(plan, floor_nodes, floor_index, step)
	return plan


## Мировая позиция центра клетки.
func cell_position(cell: Vector2i, floor_index: int) -> Vector3:
	return Vector3(cell.x * CELL_SIZE, floor_index * FLOOR_SPACING, cell.y * CELL_SIZE)


## Узел, в чьей клетке лежит мировая точка, или "" — точка вне раскладки
## (межэтажная пустота, провал под мир, пустая клетка между коридорами).
##
## Считается по клетке сетки, а не по коллайдерам или Area3D: как позиции
## комнат выводятся из плана, так из него же выводится и «где я» — без физики, в
## headless и для незагруженных слоёв.
func node_at(world_position: Vector3) -> StringName:
	var floor_index := floori(world_position.y / FLOOR_SPACING + FLOOR_TOLERANCE)
	var cell := Vector3i(
		roundi(world_position.x / CELL_SIZE),
		floor_index,
		roundi(world_position.z / CELL_SIZE),
	)
	return node_by_cell.get(cell, &"")
