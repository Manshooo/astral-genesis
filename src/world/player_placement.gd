# res://src/world/player_placement.gd
# Куда поставить игрока после перехода: к двери, ведущей обратно, на тайл коридора, в SpawnPoint. Чистая геометрия над заспавненным слоем — не в RunManager и не в LayerStreamer. Поворот игрока НЕ трогаем (кроме входа
# через SpawnPoint): доворот при взаимодействии под углом дезориентирует; тангаж на камере (S_FPSLook).
class_name PlayerPlacement
extends RefCounted

## Высота над полом тайла для игрока: в полу капсула не должна родиться.
const TILE_ARRIVAL_HEIGHT := 0.5
## Отступ вглубь комнаты от двери, м: коллайдер игрока (радиус ~0.55, проём ~2.8) не должен оказаться в стене.
const ARRIVAL_OFFSET := 1.5


## Ставит игрока в комнату: пришли через выход — ПЕРЕД тем выходом, что ведёт обратно (вошёл в северную дверь A → вышел из южной B). SpawnPoint — только для входа не через дверь, там авторский поворот уместен.
static func in_room(player: Node3D, room: LayerStreamer.SpawnedRoom, came_from: StringName) -> void:
	var room_node := room.entity as Node as Node3D
	var spawn_point := room.entity.get_node_or_null(^"SpawnPoint") as Node3D

	var exit_entity := return_exit(room, came_from)
	if exit_entity:
		# Меняем ТОЛЬКО origin: basis (рыскание) остаётся игроков.
		player.global_position = arrival_point(exit_entity, room.face_of(exit_entity).w, room_node, spawn_point)
		return

	if spawn_point:
		player.global_transform = spawn_point.global_transform
	else:
		player.global_transform = room_node.global_transform


## Загрузка сейва в коридоре: у ветки нет SpawnPoint и двери «обратно» — игрок на её первый тайл.
static func in_corridor(player: Node3D, tiles: Array) -> void:
	if tiles.is_empty():
		return
	var tile := tiles[0] as Node3D
	player.global_position = tile.global_position + Vector3(0.0, TILE_ARRIVAL_HEIGHT, 0.0)


## На тайл коридора за дверью door — для комнат без проёма за дверью (RS_LevelNode.door_teleports).
static func in_front_of(
	player: Node3D, door: Entity, room: LayerStreamer.SpawnedRoom, plan: RS_LayerPlan
) -> void:
	var face := room.face_of(door)
	var cell: Vector3i = plan.cells.get(room.node_id, Vector3i.ZERO)
	if face.w != GridTopology.NO_SIDE:
		cell = plan.topology.neighbour(GridTopology.face_cell(face), face.w)
	player.global_position = (
		plan.embedding.cell_origin(cell) + Vector3(0.0, TILE_ARRIVAL_HEIGHT, 0.0)
	)


## Безопасная точка перед дверью: отступаем перпендикулярно ЕЁ СТЕНЕ вглубь комнаты (origin двери — в плоскости стены на высоте полотна), высота от SpawnPoint. Направление — по стороне грани [param side]
## (LayerStreamer.SpawnedRoom.face_of), не по вектору на центр комнаты (у вытянутой комнаты сторона вышла бы не та).
static func arrival_point(door: Entity, side: int, room_node: Node3D, spawn_point: Node3D) -> Vector3:
	var door_node := door as Node as Node3D
	var door_origin := door_node.global_transform.origin
	var room_origin := room_node.global_transform.origin

	var into_room := Vector3.ZERO
	# У портала стены нет: отходим от него к центру комнаты.
	if door is E_VerticalPortal:
		side = GridTopology.NO_SIDE
	if side != GridTopology.NO_SIDE:
		into_room = -Vector3(SquareGridTopology.OFFSETS[side])  # внутрь = против стороны двери
	else:
		# Сторону определить не вышло — к центру комнаты.
		into_room = room_origin - door_origin
		into_room.y = 0.0
	if into_room.length() < 0.001:
		into_room = -door_node.global_transform.basis.z  # последний запасной вариант
	into_room = into_room.normalized()

	var point := door_origin + into_room * ARRIVAL_OFFSET
	point.y = spawn_point.global_transform.origin.y if spawn_point else room_origin.y
	return point


## Выход комнаты (дверь ИЛИ портал), ведущий обратно в came_from; null, если пришли не через выход. Две двери в одну ветку — берётся первая по обходу сцены.
static func return_exit(room: LayerStreamer.SpawnedRoom, came_from: StringName) -> Entity:
	if came_from == &"":
		return null
	for exit_entity in room.exits():
		var portal := exit_entity.get_component(C_DoorPortal) as C_DoorPortal
		if portal and portal.target_node_id == came_from:
			return exit_entity
	return null
