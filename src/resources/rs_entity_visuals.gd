## res://src/resources/rs_entity_visuals.gd
## Как найти визуальную геометрию сущности. Общее место для всех, кто её красит:
## обводка (O_OutlineVisual) и облик захваченного тела (O_BodyVisual). Держать
## правило в одном месте важнее, чем сэкономить файл: два одинаковых
## `_find_geometry` в двух наблюдателях разъехались бы при первой же правке — так
## уже было с геометрией дверей, пока её не свели в RS_RoomLayout.
##
## Только статика — инстанцировать нечего.
@tool
class_name RS_EntityVisuals
extends RefCounted


## Все меши сущности: сам узел, если он геометрия, плюс всё поддерево.
##
## Раньше правило было «сам узел ИЛИ ребёнок строго с именем MeshInstance3D».
## Оно работало ровно потому, что все существующие интерактивы случайно
## оказались мешами в корне; на первом же импортированном .glb, где сущность —
## Node3D, а меши внутри, обводка пропадала бы МОЛЧА. Теперь имя узла не значит
## ничего, а составной объект (рама + полотно + ручка) красится целиком.
##
## Если на сущности есть C_VisualRoot с непустым путём — ищем не от неё, а от
## указанного узла (см. C_VisualRoot про то, когда это нужно).
static func geometries(entity: Entity) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	var root := _search_root(entity)
	if root == null:
		return found

	var self_geo := root as GeometryInstance3D
	if self_geo:
		found.append(self_geo)
	# owned=false — иначе меши, пришедшие из инстанцированной под-сцены (а это
	# ровно случай импортированных .glb), не находятся.
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		found.append(node as GeometryInstance3D)
	return found


## Основной меш сущности — тот, который представляет её саму. Нужен там, где
## красить «всё» бессмысленно: облик тела подменяет ОДИН меш рига.
static func primary(entity: Entity) -> GeometryInstance3D:
	var all := geometries(entity)
	return all[0] if not all.is_empty() else null


## Откуда начинать поиск: переопределение из C_VisualRoot либо сама сущность.
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
