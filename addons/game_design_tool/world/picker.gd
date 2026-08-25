## res://addons/game_design_tool/world/picker.gd
## Аналитический пикинг по AABB комнаты — без единого физического коллайдера.
## Позиция берётся из RS_LayerPlan (та же раскладка, что и у игры), габарит —
## из RS_RoomLayout.half_extent_of_scene (тот же кэш, которым меряется карта).
##
## Физический рейкаст сюда сознательно не пошёл: в редакторском SubViewport
## живое физическое пространство не гарантировано (Jolt на отдельном потоке, а
## тул — не игра), а AABB работает одинаково для обоих оверлеев и даже для
## незагруженного слоя — см. [[world-generator-tool-spec]] §3.2.
##
## Только статика — инстанцировать нечего, как и RS_RoomLayout, на котором это
## построено.
@tool
extends RefCounted

## Насколько AABB шире фактического расстояния до двери: двери стоят у самой
## стены, а видимый габарит комнаты чуть больше (потолок, выступы декора).
const HALF_EXTENT_PADDING := 2.0
## Габарит-заглушка для комнат без дверей вовсе (half_extent_of_scene вернёт
## 0.0) — иначе такая комната не пикалась бы никогда.
const HALF_EXTENT_FALLBACK := 6.0
## Высота коробки пикинга. Комната ~6 м, берём с запасом сверху и снизу — это
## эвристика для клика, не игровой инвариант о габаритах комнат.
const AABB_BELOW := 0.5
const AABB_ABOVE := 6.5


## AABB комнаты узла [param node_id] по плану [param plan]. Пустой AABB, если
## узла нет среди [param layer_nodes] — так теряется молча, а не падает.
static func room_aabb(
	node_id: StringName, layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan
) -> AABB:
	for node_data: RS_LevelNode in layer_nodes:
		if node_data.id == node_id:
			return _aabb_of(node_data, plan)
	return AABB()


## Ближайший к [param ray_origin] узел, чей AABB пересекает луч. Пустая
## StringName, если луч ничего не задел.
static func pick(
	ray_origin: Vector3, ray_dir: Vector3, layer_nodes: Array[RS_LevelNode], plan: RS_LayerPlan
) -> StringName:
	var best_id: StringName = &""
	var best_distance := INF
	for node_data: RS_LevelNode in layer_nodes:
		var aabb := _aabb_of(node_data, plan)
		var hit = aabb.intersects_ray(ray_origin, ray_dir)
		if hit == null:
			continue
		var distance: float = (hit as Vector3).distance_to(ray_origin)
		if distance < best_distance:
			best_distance = distance
			best_id = node_data.id
	return best_id


static func _aabb_of(node_data: RS_LevelNode, plan: RS_LayerPlan) -> AABB:
	var pos: Vector3 = plan.positions.get(node_data.id, Vector3.ZERO)
	var half_extent := RS_RoomLayout.half_extent_of_scene(node_data.room_scene_path)
	half_extent = (half_extent + HALF_EXTENT_PADDING) if half_extent > 0.0 else HALF_EXTENT_FALLBACK
	return AABB(
		Vector3(pos.x - half_extent, pos.y - AABB_BELOW, pos.z - half_extent),
		Vector3(half_extent * 2.0, AABB_BELOW + AABB_ABOVE, half_extent * 2.0)
	)
