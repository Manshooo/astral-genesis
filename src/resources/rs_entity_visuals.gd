## res://src/resources/rs_entity_visuals.gd
## Как найти визуальную геометрию сущности — общее правило для обводки (O_OutlineVisual) и облика тела (O_BodyVisual). Только статика.
@tool
class_name RS_EntityVisuals
extends RefCounted


## Все меши сущности: сам узел, если геометрия, плюс поддерево (имя узла ничего не значит). С C_VisualRoot — от указанного узла.
static func geometries(entity: Entity) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	var root := _search_root(entity)
	if root == null:
		return found

	var self_geo := root as GeometryInstance3D
	if self_geo:
		found.append(self_geo)
	# owned=false: иначе меши из инстанцированной под-сцены (.glb) не находятся.
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		found.append(node as GeometryInstance3D)
	return found


## Основной меш — там, где красить «всё» бессмысленно (облик тела подменяет ОДИН меш рига).
static func primary(entity: Entity) -> GeometryInstance3D:
	var all := geometries(entity)
	return all[0] if not all.is_empty() else null


## Трансформ узла относительно корня: произведение локальных по цепочке. global_transform не годится — detached-инстанс
## (E_Body.visual_of_scene). Узел == корень → IDENTITY.
static func transform_relative_to(node: Node, root: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current := node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial:
			result = spatial.transform * result
		current = current.get_parent()
	return result


## Откуда начинать поиск: C_VisualRoot либо сама сущность.
static func _search_root(entity: Entity) -> Node:
	if entity == null:
		return null
	var override := entity.get_component(C_VisualRoot) as C_VisualRoot
	if override and not override.path.is_empty():
		var node := entity.get_node_or_null(override.path)
		if node:
			return node
		push_warning(
			"RS_EntityVisuals: у «%s» C_VisualRoot указывает на несуществующий узел «%s»"
			% [entity.name, override.path]
		)
	return entity
