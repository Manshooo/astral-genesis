## res://src/resources/world_generator/rs_layer_plan.gd
## План раскладки одного слоя: клетки комнат, тайлы коридоров, какая дверь смотрит в какой коридор. Считает RS_CorridorPlanner, хранит граф
## забега (RS_LevelGraph.layer_plan) — рёбра берутся из плана, а не сверяются с ним. Весь в клетках и сторонах топологии: мир даёт вложение
## (embedding). Живёт отдельно от RunManager (не @tool, в редакторе его нет): правило «куда встанет комната» одно на игру и инструменты.
## Детерминирован от сида и считается БЕЗ спавна комнат — доступен для незагруженных слоёв (карта, предпросмотр). Вики: [[Цикл забега]].
@tool
class_name RS_LayerPlan
extends RefCounted

## Топология плана. Этажи слоя — уровни сетки (.y); связывает их лестница (комната в два уровня) или портал; коридор между уровнями не ходит.
var topology := SquareGridTopology.new()
## Вложение плана в мир — ЕДИНСТВЕННОЕ место, где живёт размер клетки. Куб 8 м задан китом ([[Метрики и кит]] §1–2): комнаты и коридоры на ОДНОЙ сетке.
## Уровень равен клетке. Допуск 0.5 м вниз (1/16 уровня): origin игрока бывает чуть ниже пола; больше нельзя — origin души у потолка доходит до ~6.2 м.
var embedding := SquareGridEmbedding.new(8.0, 8.0, 0.0625)

## node_id -> клетка узла: у комнаты угловая клетка footprint, у коридора — первого тайла (одной клетки у него нет).
var cells: Dictionary[StringName, Vector3i] = {}
## Комната -> footprint в клетках (X, уровни Y, Z) в осях мира, уже с поворотом; у комнаты с дверями в сцене — одна клетка.
var footprints: Dictionary[StringName, Vector3i] = {}
## Комната -> поворот в четвертях вокруг Y (RS_LevelNode.turns): сторона сцены s смотрит в мир стороной s − turns.
var turns: Dictionary[StringName, int] = {}
## Клетка -> node_id (комнаты и тайлы коридора); на ней держится node_at — «в каком узле игрок».
var node_by_cell: Dictionary[Vector3i, StringName] = {}
## Клетка тайла -> маска проёмов (бит стороны — 1 << индекс); по ней сборка выбирает кусок кита. Проём — к соседнему тайлу, к двери комнаты и на стык коридоров.
var corridor_tiles: Dictionary[Vector3i, int] = {}
## Комната -> { грань двери: коридор }. Ключ — грань (клетка footprint и сторона), не сосед: две двери законно ведут в один коридор. Ключ есть у каждой комнаты слоя.
var door_faces: Dictionary[StringName, Dictionary] = {}
## Клетки-тупики: концы отростков, поставленные нарочно (RS_WorldGenConfig.dead_ends), единственные тайлы с одним проёмом; место под тайник.
var dead_ends: Dictionary[Vector3i, bool] = {}
## Двери выше этажа своей комнаты, ждущие сети (грань -> комната): верх лестницы кладёт сюда раскладка её этажа, забирает раскладка нужного уровня
## (_adopt_pending). После генерации остаток — routing_failures.
var pending_doors: Dictionary[Vector4i, StringName] = {}
## Трассы, которые не удалось проложить; раскладка не падает, ноль сверяет проверка.
var routing_failures: Array[String] = []
## Сколько разыгранных дверей раскладка не поставила (_join_spare_doors) — цифра для «Прогона сидов»: рост значит, что пресетам обещано больше дверей, чем помещается.
var dropped_doors := 0


## Пары коридоров, между тайлами которых открыт проём (каждая раз): по ним граф ставит рёбра; где коридор переходит в соседний, решает раскладка (_segment).
func branch_joints() -> Array[Array]:
	var seen: Dictionary[String, bool] = {}
	var joints: Array[Array] = []
	for tile: Vector3i in corridor_tiles:
		var mask: int = corridor_tiles[tile]
		for side in topology.side_count(tile):
			var next := topology.neighbour(tile, side)
			if mask & (1 << side) == 0 or not corridor_tiles.has(next):
				continue
			var a: StringName = node_by_cell[tile]
			var b: StringName = node_by_cell[next]
			if a == b:
				continue
			var pair: Array = [a, b] if String(a) < String(b) else [b, a]
			var key := "%s|%s" % pair
			if not seen.has(key):
				seen[key] = true
				joints.append(pair)
	return joints


## Мировая точка узла: центр footprint на уровне пола у комнаты, центр первого тайла у ветки; ZERO — узла нет.
func position_of(node_id: StringName) -> Vector3:
	if not cells.has(node_id):
		return Vector3.ZERO
	var anchor: Vector3i = cells[node_id]
	var size: Vector3i = footprints.get(node_id, Vector3i.ONE)
	if size.x == 1 and size.z == 1:
		return embedding.cell_origin(anchor)
	var far := anchor + Vector3i(size.x - 1, 0, size.z - 1)
	return (embedding.cell_origin(anchor) + embedding.cell_origin(far)) * 0.5


## Где и как повёрнутой стоит комната: центр footprint и поворот; один на спавн и предпросмотр.
func room_transform(node_id: StringName) -> Transform3D:
	return Transform3D(embedding.turn_basis(turns.get(node_id, 0)), position_of(node_id))


## Все клетки комнаты — footprint на всех уровнях.
func room_cells(node_id: StringName) -> Array[Vector3i]:
	return SquareGridTopology.box(cells[node_id], footprints.get(node_id, Vector3i.ONE))


## Какие проёмы тайла ведут в дверь комнаты (маска как у corridor_tiles); отдельно не хранится — проём в пустоту раскладка не выдаёт. Нужна сборке для торца.
func door_mask(tile: Vector3i) -> int:
	var open: int = corridor_tiles.get(tile, 0)
	var doors := 0
	for side in topology.side_count(tile):
		if open & (1 << side) and not corridor_tiles.has(topology.neighbour(tile, side)):
			doors |= 1 << side
	return doors


## Можно ли пройти и посмотреть из клетки через сторону: проём тайла, дверь в тайл или соседняя клетка той же комнаты. Между двумя комнатами проходов нет.
func opens(cell: Vector3i, side: int) -> bool:
	var next := topology.neighbour(cell, side)
	if not node_by_cell.has(next):
		return false
	if corridor_tiles.has(cell):
		return corridor_tiles[cell] & (1 << side) != 0
	if corridor_tiles.has(next):
		return corridor_tiles[next] & (1 << topology.back_side(cell, side)) != 0
	return node_by_cell[cell] == node_by_cell[next]


## Узлы, видимые из узла по прямой: из КАЖДОЙ его клетки по каждой открытой стороне до первой стены (сквозь чужие коридоры и комнаты) плюс клетка вбок для косого взгляда
## через боковой проём. Консервативно — из любой клетки узла, чтобы при смене узла ничего не моргало. Граф этого не заменяет (LayerStreamer.reveal_around).
func in_sight_of(node_id: StringName) -> Dictionary[StringName, bool]:
	var seen: Dictionary[StringName, bool] = {}
	for cell: Vector3i in node_by_cell:
		if node_by_cell[cell] != node_id:
			continue
		for side in topology.side_count(cell):
			var at := cell
			while opens(at, side):
				at = topology.neighbour(at, side)
				seen[node_by_cell[at]] = true
				for aside in topology.side_count(at):
					if aside != side and aside != topology.opposite(at, side) and opens(at, aside):
						seen[node_by_cell[topology.neighbour(at, aside)]] = true
	return seen


## Узел в чьей клетке лежит точка или "" (межэтажная пустота, провал, пустая клетка). По клетке сетки, не по физике — работает headless и для незагруженных слоёв.
func node_at(world_position: Vector3) -> StringName:
	return node_by_cell.get(embedding.cell_at(world_position), &"")
