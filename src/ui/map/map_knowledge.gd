# res://src/ui/map/map_knowledge.gd
## Что игрок вправе видеть на карте комплекса — одно правило на обе карты: мини-карта — «посещённое плюс соседи» своего этажа, экран — то же или больше по купленному у Архитектора.
## Статика и данные графа без сцены и плана — проверяется без UI.
class_name MapKnowledge
extends RefCounted

## Уровни экрана карты — значения ArchitectManager.map_level(); таблица — в карточке «Экран карты комплекса».
const LEVEL_NONE := 0  # экрана нет вовсе
const LEVEL_VISITED := 1  # посещённое и соседи — на всех этажах своего слоя
const LEVEL_LAYER := 2  # свой слой целиком
const LEVEL_COMPLEX := 3  # все слои и порталы между ними
const LEVEL_CONTENTS := 4  # типы комнат, уникальные комнаты, замки


## Узлы, о которых игрок знает: посещённые и их соседи (видел дверь или портал).
static func known_nodes(nodes: Array[RS_LevelNode], visited: Array[StringName]) -> Array[RS_LevelNode]:
	var known: Array[RS_LevelNode] = []
	for node_data in nodes:
		if visited.has(node_data.id):
			known.append(node_data)
			continue
		for conn: RS_LevelConnection in node_data.connections:
			if visited.has(conn.target_node_id):
				known.append(node_data)
				break
	return known


## Слой-поверхность — самый верхний (L0); через него карта подписывает «выход».
static func surface_depth() -> int:
	return RS_LevelGraph.DEPTHS.min()


static func is_surface(depth: int) -> bool:
	return depth == surface_depth()


## Открыт ли слой depth на этом уровне; чужие — только с третьего.
static func is_layer_open(level: int, depth: int, current_depth: int) -> bool:
	if level >= LEVEL_COMPLEX:
		return true
	return level >= LEVEL_VISITED and depth == current_depth


## Узлы слоя depth, которые экран вправе показать на уровне level (первый — правило мини-карты по всем этажам слоя).
static func visible_nodes(
	graph: RS_LevelGraph, depth: int, level: int, current_depth: int, visited: Array[StringName]
) -> Array[RS_LevelNode]:
	if graph == null or not is_layer_open(level, depth, current_depth):
		return []
	var layer := graph.get_nodes_by_depth(depth)
	if level == LEVEL_VISITED:
		return known_nodes(layer, visited)
	return layer


## Портал комнаты — ребро переноса на другой этаж или слой; null — нет (в комнате ровно один, LayerStreamer._bind_portals). По типу ребра (is_portal), не по depth_delta и не по направлению: верхняя дверь лестницы не портал.
static func portal_of(graph: RS_LevelGraph, node_data: RS_LevelNode) -> RS_LevelConnection:
	for conn: RS_LevelConnection in node_data.connections:
		if conn.is_portal() and graph.get_node_data(conn.target_node_id):
			return conn
	return null
