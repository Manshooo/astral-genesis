## res://src/resources/world_generator/rs_layer_plan.gd
## План раскладки одного слоя: какие клетки сетки занимает каждая комната, как
## идут тайлы веток коридора и какая дверь комнаты смотрит в какую ветку. Считает
## его RS_CorridorPlanner — комнаты на решётке, коридоры трассируются между ними.
##
## План — слой размещения карточки «Сетка уровня»: он весь в клетках и сторонах
## топологии, а в мир его переводит вложение (embedding). Мировые координаты
## здесь не хранятся вовсе — ни планировщик, ни данные плана их не видят, и
## спавн, карта и инструменты спрашивают их у вложения в момент, когда ставят
## или меряют.
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

## Шаг решётки комнат по умолчанию, если ручки не переданы (см.
## RS_WorldGenConfig.room_lattice_step).
const DEFAULT_LATTICE_STEP := 3

## Топология плана: кто чей сосед и через какую сторону. Этажи слоя — уровни
## сетки (.y клетки); между собой они связаны только порталами, у которых нет
## стороны в плоскости этажа, поэтому трассы идут по каждому уровню отдельно.
var topology := SquareGridTopology.new()
## Вложение плана в мир — ЕДИНСТВЕННОЕ место, где живёт размер клетки.
##
## Куб 8 м задан китом, а не выбран здесь ([[Метрики и кит]] §1–2): коробки комнат
## и куски коридора кратны клетке, сокет стоит по центру её грани, поэтому комнаты
## и коридоры встают на ОДНУ сетку и стыкуются проём в проём без переходников.
## Уровень равен клетке: этаж — уровень 3D-сетки, и комната этажом выше стоит
## прямо на потолке нижней. Запас 0.5 м вниз (1/16 уровня) — у игрока origin
## бывает чуть ниже пола (посадка капсулы, ступенька), и без него он на границе
## округления уезжал бы этажом ниже. Больше нельзя: всё, что выше уровня минус
## запас, уже числится этажом выше, а origin души у потолка 8-метровой комнаты
## доходит до ~6.2 м (потолок минус рост капсулы).
var embedding := SquareGridEmbedding.new(8.0, 8.0, 0.0625)

## node_id -> клетка узла. У комнаты — угловая клетка footprint (наименьшая по
## всем осям), у ветки коридора — клетка её первого тайла: у ветки нет одной
## клетки, а инструментам нужна хоть какая-то.
var cells: Dictionary[StringName, Vector3i] = {}
## Комната -> footprint в клетках (ширина по X, уровней по Y, длина по Z). У
## комнаты с дверями в сцене — одна клетка.
var footprints: Dictionary[StringName, Vector3i] = {}
## Клетка -> node_id — и всех клеток комнат, и тайлов коридора. Одна и та же
## (x, z) на разных этажах — разные клетки и разные узлы. На ней держится node_at,
## а через него — «в каком узле стоит игрок».
var node_by_cell: Dictionary[Vector3i, StringName] = {}
## Клетка тайла -> маска проёмов: бит стороны — 1 << её индекс в топологии. Чья
## это ветка — в node_by_cell. По маске сборка выбирает кусок кита: два
## противоположных проёма — прямой, два соседних — поворот, три — Т, четыре —
## крест. Проём ставится и к соседнему тайлу своей ветки, и к двери комнаты, и
## на стык с родительской веткой.
var corridor_tiles: Dictionary[Vector3i, int] = {}
## Комната -> { грань двери: ветка }. Грань — клетка footprint и её сторона
## (GridTopology.face): у комнаты в несколько клеток на одной стороне несколько
## сокетов. Ключ — грань, а не сосед: две двери комнаты законно ведут в одну и ту
## же ветку, и по id соседа их не различить (RS_LevelGraph._hang_floor_on_corridors).
var door_faces: Dictionary[StringName, Dictionary] = {}
## Сколько трасс не удалось проложить — ветка заперта чужими коридорами и
## комнатами. Раскладка при этом не падает; ноль сверяет проверка.
var routing_failures: Array[String] = []


## Строит план слоя. Этажи раскладываются независимо: связь между ними — только
## порталы, у которых нет направления в плоскости этажа. [param config] — только
## ради шага решётки.
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


## Мировая точка узла: у комнаты — центр footprint в плане на уровне пола (origin
## сцены по контракту клетки, [[Метрики и кит]] §2), у ветки — центр первого тайла.
## Vector3.ZERO, если узла в плане нет.
func position_of(node_id: StringName) -> Vector3:
	if not cells.has(node_id):
		return Vector3.ZERO
	var anchor: Vector3i = cells[node_id]
	var size: Vector3i = footprints.get(node_id, Vector3i.ONE)
	if size.x == 1 and size.z == 1:
		return embedding.cell_origin(anchor)
	var far := anchor + Vector3i(size.x - 1, 0, size.z - 1)
	return (embedding.cell_origin(anchor) + embedding.cell_origin(far)) * 0.5


## Все клетки комнаты — footprint на всех его уровнях.
func room_cells(node_id: StringName) -> Array[Vector3i]:
	return SquareGridTopology.box(cells[node_id], footprints.get(node_id, Vector3i.ONE))


## Какие проёмы тайла ведут в дверь комнаты, а не в соседний тайл: маска, как у
## corridor_tiles. Отдельно не хранится — проём в пустоту раскладка не выдаёт
## (corridor_layout_check), так что всё открытое не в тайл и есть дверь. Нужна
## сборке: сторону, упёршуюся в дверь, тайл закрывает своим торцом с проёмом.
func door_mask(tile: Vector3i) -> int:
	var open: int = corridor_tiles.get(tile, 0)
	var doors := 0
	for side in topology.side_count(tile):
		if open & (1 << side) and not corridor_tiles.has(topology.neighbour(tile, side)):
			doors |= 1 << side
	return doors


## Узел, в чьей клетке лежит мировая точка, или "" — точка вне раскладки
## (межэтажная пустота, провал под мир, пустая клетка между коридорами).
##
## Считается по клетке сетки, а не по коллайдерам или Area3D: как позиции
## комнат выводятся из плана, так из него же выводится и «где я» — без физики, в
## headless и для незагруженных слоёв.
func node_at(world_position: Vector3) -> StringName:
	return node_by_cell.get(embedding.cell_at(world_position), &"")
