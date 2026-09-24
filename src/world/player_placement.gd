# res://src/world/player_placement.gd
# Куда поставить игрока после перехода: к двери, ведущей обратно, на тайл
# коридора, в SpawnPoint комнаты.
#
# Это чистая геометрия над уже заспавненным слоем — ни графа, ни сейва, ни
# состояния забега ей не нужно, поэтому она не живёт ни в RunManager (автомат
# забега), ни в LayerStreamer (что лежит в дереве). Раньше полторы сотни строк
# векторной математики лежали посреди автомата и делали его тысячестрочным.
#
# Общее правило всех функций: поворот игрока НЕ трогаем, кроме входа в забег
# через SpawnPoint. Игрок мог взаимодействовать с дверью под углом, и доворачивать
# его за него — дезориентирует; тангаж живёт на камере (S_FPSLook) и сюда вообще
# не попадает.
class_name PlayerPlacement
extends RefCounted

## Высота над полом тайла, на которую ставится игрок: капсула не должна родиться
## в полу, а с полуметра она просто сядет.
const TILE_ARRIVAL_HEIGHT := 0.5
## На сколько метров вглубь комнаты отступать от двери, чтобы коллайдер игрока не
## оказался в стене/проёме (радиус ~0.55, проём ~2.8 в ширину).
const ARRIVAL_OFFSET := 1.5


## Ставит игрока в комнату. Пришли через выход — появляемся ПЕРЕД тем выходом
## этой комнаты, что ведёт обратно (вошёл в северную дверь A → вышел из южной
## двери B). SpawnPoint — только для входа не через дверь (старт забега, загрузка
## сейва): там авторский поворот как раз уместен.
static func in_room(player: Node3D, room: LayerStreamer.SpawnedRoom, came_from: StringName) -> void:
	var room_node := room.entity as Node as Node3D
	var spawn_point := room.entity.get_node_or_null(^"SpawnPoint") as Node3D

	var exit_entity := return_exit(room, came_from)
	if exit_entity:
		# Меняем ТОЛЬКО origin: basis (рыскание) остаётся игроков.
		player.global_position = arrival_point(exit_entity, room_node, spawn_point)
		return

	if spawn_point:
		player.global_transform = spawn_point.global_transform
	else:
		player.global_transform = room_node.global_transform


## Загрузка сейва, сделанного в коридоре: у ветки нет ни SpawnPoint, ни двери
## «обратно», и игрок встаёт на её первый тайл.
static func in_corridor(player: Node3D, tiles: Array) -> void:
	if tiles.is_empty():
		return
	var tile := tiles[0] as Node3D
	player.global_position = tile.global_position + Vector3(0.0, TILE_ARRIVAL_HEIGHT, 0.0)


## На тайл коридора за дверью [param door] — для комнат, у которых проёма за
## дверью нет (RS_LevelNode.door_teleports).
static func in_front_of(
	player: Node3D, door: Entity, room: LayerStreamer.SpawnedRoom, plan: RS_LayerPlan, floor_index: int
) -> void:
	var side := RS_RoomLayout.door_direction(door as Node as Node3D, room.entity)
	var cell: Vector2i = (
		plan.cells.get(room.node_id, Vector2i.ZERO) + RS_RoomLayout.OFFSETS.get(side, Vector2i.ZERO)
	)
	player.global_position = (
		plan.cell_position(cell, floor_index) + Vector3(0.0, TILE_ARRIVAL_HEIGHT, 0.0)
	)


## Безопасная точка прибытия перед дверью [param door]: отступаем от полотна
## перпендикулярно ЕГО СТЕНЕ вглубь комнаты, высоту берём от SpawnPoint (пол).
##
## Не трансформ самой двери: её origin лежит в плоскости стены и на высоте центра
## полотна (~2.3 м) — игрока там зажало бы в геометрии. Направление берём из
## стороны двери (RS_RoomLayout), а не из вектора «на центр комнаты»: так игрок
## встаёт ровно напротив проёма, а не наискосок от него.
static func arrival_point(door: Entity, room_node: Node3D, spawn_point: Node3D) -> Vector3:
	var door_node := door as Node as Node3D
	var door_origin := door_node.global_transform.origin
	var room_origin := room_node.global_transform.origin

	var into_room := Vector3.ZERO
	# У портала стены нет — он стоит посреди комнаты, и «перпендикулярно стене»
	# для него бессмысленно. Отходим от него к центру комнаты.
	var direction := &"" if door is E_VerticalPortal else RS_RoomLayout.door_direction(door_node, room_node)
	if direction != &"":
		var offset: Vector2i = RS_RoomLayout.OFFSETS[direction]
		into_room = -Vector3(offset.x, 0.0, offset.y)  # внутрь = против стороны двери
	else:
		# Сторону определить не вышло — отступаем к центру комнаты.
		into_room = room_origin - door_origin
		into_room.y = 0.0
	if into_room.length() < 0.001:
		into_room = -door_node.global_transform.basis.z  # последний запасной вариант
	into_room = into_room.normalized()

	var point := door_origin + into_room * ARRIVAL_OFFSET
	point.y = spawn_point.global_transform.origin.y if spawn_point else room_origin.y
	return point


## Выход комнаты [param room] (дверь ИЛИ портал), ведущий обратно в came_from —
## чтобы игрок появился у него, а не в общем SpawnPoint. null, если пришли не
## через выход (вход в забег, загрузка сейва).
##
## Две двери комнаты законно ведут в одну ветку коридора; тогда берётся первая по
## обходу сцены — обе на этой ветке, и перенос к любой из них честен.
static func return_exit(room: LayerStreamer.SpawnedRoom, came_from: StringName) -> Entity:
	if came_from == &"":
		return null
	for exit_entity in room.exits():
		var portal := exit_entity.get_component(C_DoorPortal) as C_DoorPortal
		if portal and portal.target_node_id == came_from:
			return exit_entity
	return null
