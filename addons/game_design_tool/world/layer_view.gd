## res://addons/game_design_tool/world/layer_view.gd
## GDT_LayerView — то, что оверлеи получают на отрисовку: граф, узлы показываемого
## слоя, их раскладка и подписи пресетов. Одна подпись rebuild() на все оверлеи.
## [[Редакторские инструменты]] §«Коридоры и сетка во вьюпорте».
@tool
extends RefCounted

var graph: RS_LevelGraph
var nodes: Array[RS_LevelNode] = []
var plan: RS_LayerPlan
## node_id -> имя подобранного пресета ("" — пресета нет).
var preset_labels: Dictionary = {}
## Кит, которым «Геометрия» застраивает тайлы; null — коридоры не ставятся.
var kit: RS_CorridorKit


func _init(
	p_graph: RS_LevelGraph = null,
	p_nodes: Array[RS_LevelNode] = [],
	p_plan: RS_LayerPlan = null,
	p_preset_labels: Dictionary = {}
) -> void:
	graph = p_graph
	nodes = p_nodes
	plan = p_plan
	preset_labels = p_preset_labels


## Узел слоя по id; линейный поиск — в слое десятки узлов.
func node_by_id(node_id: StringName) -> RS_LevelNode:
	if node_id == &"":
		return null
	for node_data: RS_LevelNode in nodes:
		if node_data.id == node_id:
			return node_data
	return null


func is_empty() -> bool:
	return nodes.is_empty() or plan == null
