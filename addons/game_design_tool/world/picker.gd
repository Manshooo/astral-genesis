## Аналитический пикинг комнат по AABB, без физических коллайдеров.
## Зачем AABB, а не рейкаст: [[Редакторские инструменты]] (пикинг по AABB).
@tool
extends RefCounted

## Запас AABB сверх расстояния до двери, м (стены, декор).
const HALF_EXTENT_PADDING := 2.0
## Габарит комнаты без дверей, м (half_extent_of_scene вернёт 0.0).
const HALF_EXTENT_FALLBACK := 6.0
## Границы коробки пикинга по высоте от пола, м — запас для клика.
const AABB_BELOW := 0.5
const AABB_ABOVE := 6.5


## AABB узла [param node_id]; пустой, если узла нет среди [param layer_nodes].
static func room_aabb(
	node_id: StringName, layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan
) -> AABB:
	for node_data: RS_LevelNode in layer_nodes:
		if node_data.id == node_id:
			var boxes := _aabbs_of(node_data, plan)
			var merged: AABB = boxes[0] if not boxes.is_empty() else AABB()
			for box: AABB in boxes:
				merged = merged.merge(box)
			return merged
	return AABB()


## Ближайший к [param ray_origin] узел под лучом; пустое имя, если ничего.
static func pick(
	ray_origin: Vector3, ray_dir: Vector3, layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan
) -> StringName:
	var best_id: StringName = &""
	var best_distance := INF
	for node_data: RS_LevelNode in layer_nodes:
		for aabb: AABB in _aabbs_of(node_data, plan):
			var hit = aabb.intersects_ray(ray_origin, ray_dir)
			if hit == null:
				continue
			var distance: float = (hit as Vector3).distance_to(ray_origin)
			if distance < best_distance:
				best_distance = distance
				best_id = node_data.id
	return best_id


## У ветки коридора коробка на каждый тайл: общая накрыла бы огибаемые комнаты.
static func _aabbs_of(node_data: RS_LevelNode, plan: RS_LayerPlan) -> Array[AABB]:
	if node_data.role != RS_LevelNode.Role.CORRIDOR:
		return [_aabb_of(node_data, plan)]
	var boxes: Array[AABB] = []
	var half := plan.embedding.cell_size * 0.5
	for cell: Vector3i in plan.corridor_tiles:
		if plan.node_by_cell.get(cell, &"") != node_data.id:
			continue
		var pos := plan.embedding.cell_origin(cell)
		boxes.append(AABB(
			Vector3(pos.x - half, pos.y - AABB_BELOW, pos.z - half),
			Vector3(half * 2.0, AABB_BELOW + AABB_ABOVE, half * 2.0)
		))
	return boxes


static func _aabb_of(node_data: RS_LevelNode, plan: RS_LayerPlan) -> AABB:
	var pos := plan.position_of(node_data.id)
	# У сборной комнаты в сцене нет дверей для габарита — меряем footprint'ом.
	if RS_RoomLayout.shell_of_scene(node_data.room_scene_path):
		var size: Vector3i = plan.footprints.get(node_data.id, Vector3i.ONE)
		var half := Vector2(size.x, size.z) * plan.embedding.cell_size * 0.5
		return AABB(
			Vector3(pos.x - half.x, pos.y - AABB_BELOW, pos.z - half.y),
			Vector3(half.x * 2.0, AABB_BELOW + AABB_ABOVE, half.y * 2.0)
		)
	var half_extent := RS_RoomLayout.half_extent_of_scene(node_data.room_scene_path)
	half_extent = (half_extent + HALF_EXTENT_PADDING) if half_extent > 0.0 else HALF_EXTENT_FALLBACK
	return AABB(
		Vector3(pos.x - half_extent, pos.y - AABB_BELOW, pos.z - half_extent),
		Vector3(half_extent * 2.0, AABB_BELOW + AABB_ABOVE, half_extent * 2.0)
	)
