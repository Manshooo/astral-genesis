# res://src/ui/map/map_knowledge.gd
## Что игрок вправе видеть на карте комплекса — одно правило на обе карты.
##
## Мини-карта в HUD и экран карты показывают разное, но из одного источника:
## мини-карта — «посещённое плюс соседи» на своём этаже, всегда; экран — то же
## или больше, смотря сколько куплено у Архитектора. Правило держится в одном
## месте, потому что разъедься копии — экран на первом уровне показывал бы
## меньше мини-карты, и покупка улучшения выглядела бы потерей.
##
## Только статика и только данные графа: ни сцены, ни плана, поэтому правило
## проверяется без UI и без загруженного слоя.
class_name MapKnowledge
extends RefCounted

## Уровни экрана карты — значения ArchitectManager.map_level(). Таблица и
## обоснование — в карточке «Экран карты комплекса».
const LEVEL_NONE := 0  # экрана нет вовсе
const LEVEL_VISITED := 1  # посещённое и соседи — на всех этажах своего слоя
const LEVEL_LAYER := 2  # свой слой целиком
const LEVEL_COMPLEX := 3  # все слои и порталы между ними
const LEVEL_CONTENTS := 4  # типы комнат, уникальные комнаты, замки


## Узлы, о которых игрок знает: посещённые плюс соседи посещённых — про соседа
## он знает, потому что видел ведущую туда дверь или портал.
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


## Открыт ли слой [param depth] на этом уровне. Чужие слои — только с третьего:
## до него карта знает лишь то, где игрок стоит.
static func is_layer_open(level: int, depth: int, current_depth: int) -> bool:
	if level >= LEVEL_COMPLEX:
		return true
	return level >= LEVEL_VISITED and depth == current_depth


## Узлы слоя [param depth], которые экран карты вправе показать на уровне
## [param level]. Первый уровень — ровно правило мини-карты, только по всем
## этажам слоя, а не по своему.
static func visible_nodes(
	graph: RS_LevelGraph, depth: int, level: int, current_depth: int, visited: Array[StringName]
) -> Array[RS_LevelNode]:
	if graph == null or not is_layer_open(level, depth, current_depth):
		return []
	var layer := graph.get_nodes_by_depth(depth)
	if level == LEVEL_VISITED:
		return known_nodes(layer, visited)
	return layer


## Портал комнаты — ребро на другой этаж или слой; null — портала нет. Первого
## найденного достаточно: портал в комнате ровно один (RunManager._bind_portals).
##
## Узнаётся по тому, КУДА ведёт ребро, а не по depth_delta: у перехода между
## этажами одного слоя он нулевой, как и у двери в коридор.
static func portal_of(graph: RS_LevelGraph, node_data: RS_LevelNode) -> RS_LevelConnection:
	for conn: RS_LevelConnection in node_data.connections:
		var target := graph.get_node_data(conn.target_node_id)
		if target and (target.depth != node_data.depth or target.floor_index != node_data.floor_index):
			return conn
	return null
