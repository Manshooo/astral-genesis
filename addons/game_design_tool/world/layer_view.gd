## res://addons/game_design_tool/world/layer_view.gd
## GDT_LayerView — то, что оверлеи получают на отрисовку: граф целиком, узлы
## показываемого слоя, их раскладка и подписи пресетов.
##
## Заведено ради одной подписи rebuild() на все оверлеи. Раньше их было три
## разных (`rebuild(nodes, plan)`, `rebuild(graph, nodes, plan)`,
## `rebuild(nodes, plan, labels)`), и из-за этого GDT_ViewportHost звал каждый
## оверлей поимённо — то есть реестр оверлеев (overlay_registry.gd), заведённый
## как раз чтобы новый оверлей стоил ОДНОЙ строки данных, всё равно требовал
## правки в двух местах: строка в реестре плюс ветка в set_overlay_visible и
## вызов в show_layer. Теперь узел ходит по реестру циклом, и правка снова одна.
##
## Чистые данные, вычисляет их вкладка «Генератор мира»: оверлеи не генерируют
## и не подбирают ничего сами — [param preset_labels] тоже приходит готовым,
## иначе оверлею подписей пришлось бы знать про RS_RoomPresetLibrary.
@tool
extends RefCounted

var graph: RS_LevelGraph
var nodes: Array[RS_LevelNode] = []
var plan: RS_LayerPlan
## node_id -> имя подобранного пресета ("" — пресета нет, например у сцены вне
## библиотеки).
var preset_labels: Dictionary = {}


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


## Узел слоя по id — нужен и оверлею подписей, и пикингу; линейный поиск здесь
## честен: в слое десятки узлов, а не тысячи.
func node_by_id(node_id: StringName) -> RS_LevelNode:
	if node_id == &"":
		return null
	for node_data: RS_LevelNode in nodes:
		if node_data.id == node_id:
			return node_data
	return null


func is_empty() -> bool:
	return nodes.is_empty() or plan == null
