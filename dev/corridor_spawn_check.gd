extends "res://dev/check_harness.gd"
## Проверка сборки коридоров в игре (этап 4 карточки «Процедурные коридоры между
## комнатами»): настоящий RunManager, коридорный граф, тайлы кита в мире.
##
## Главное здесь не данные — их сверяют corridor_graph_check и
## corridor_layout_check, — а то, что из них вышло в мире, и ломается это тихо:
## кусок, повёрнутый не в ту сторону, ставит проём в стену и стену в проём;
## щель на стыке тайла с комнатой — провал под мир; дверь, которая вместо
## открытия переносит игрока, возвращает телепорт, от которого задача уходит.
## Поэтому поворот сверяется не своей же формулой, а ЛУЧАМИ по коллизии тайлов:
## в открытую сторону луч проходит, в закрытую упирается в стену.
##
## Запускать: godot --headless dev/corridor_spawn_check.tscn

const RUN_SEED := 424242
## Луч вдоль тайла — из центра до грани клетки без этого запаса, то есть внутри
## СВОЕЙ клетки. Стены коридора стоят ближе грани, так что поворот он различает,
## а рамка торца у двери (откос начинается в 0.35 м от грани) и закрытая дверь за
## ней до него не дотягиваются.
const PROBE_SHORT := 0.5
const PROBE_HEIGHT := 1.5
## Только статическая геометрия (слой static_colliders): объём прицеливания
## двери (interactives) шире самой двери и стенкой не является.
const GEOMETRY_MASK := 1
## Насколько по обе стороны грани клетки щупать пол на стыке: щель шире — уже
## провал под мир.
const SEAM_PROBE := 0.4

var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _base_config: RS_WorldGenConfig


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save
	_base_config = GameConfig.config.world_gen

	var world := _new_world()
	_add_systems(world, "gameplay", [S_RoomPresence.new()])
	_add_systems(world, "physics", [S_DoorOpen.new()])

	GameConfig.config.world_gen = _base_config.duplicate() as RS_WorldGenConfig
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check_tiles()
	_check_rooms_turned()
	await _check_geometry()
	_check_doors_bound()
	await _check_open_door()
	_check_hub_door()
	await _check_minimap()
	await _check_reload_in_corridor()

	RunManager._end_run()
	_restore()

	_finish()


# ---------------------------------------------------------------------------


func _check_tiles() -> void:
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	_check("у слоя есть тайлы коридора", not RunManager.layer.corridor_tiles.is_empty(), "")
	var spawned := 0
	var ends := 0
	var wrong: Array[String] = []
	var kit := GameConfig.config.corridor_kit
	for branch: StringName in RunManager.layer.corridor_tiles:
		for tile: Node3D in RunManager.layer.corridor_tiles[branch]:
			spawned += 1
			ends += 1 if kit.end and tile.scene_file_path == kit.end.resource_path else 0
			var cell := plan.embedding.cell_at(tile.global_position)
			var base := _base_mask(kit, tile.scene_file_path)
			var turns := posmod(roundi(tile.rotation.y / (PI * 0.5)), 4)
			if RS_CorridorKit.rotate_mask(base, turns) != plan.corridor_tiles.get(cell, -1) \
					or plan.node_by_cell.get(cell, &"") != branch:
				wrong.append("%s %s" % [branch, cell])
	_check("на каждый тайл плана — ровно один кусок (%d)" % plan.corridor_tiles.size(),
		spawned == plan.corridor_tiles.size(), "поставлено %d" % spawned)
	_check("кусок под маску своего тайла и своей ветки", wrong.is_empty(), ", ".join(wrong.slice(0, 4)))
	# Иначе лучи ниже не видели бы ни одного тупика, и перевёрнутый кусок тупика
	# прошёл бы молча.
	_check("тупики слоя встали куском тупика, и они есть (%d)" % ends,
		ends == plan.dead_ends.size() and ends > 0, "тупиков в плане %d" % plan.dead_ends.size())
	_check_tiles_in_cells(plan)


## Комнаты стоят повёрнутыми так, как разыграл граф (RS_LevelNode.turns), — и
## повёрнутые в слое вообще есть: поворот, дошедший до плана, но не до корня
## комнаты, ставил бы стены и двери в стороны мира, а пропы — нет, и ни одна
## проверка лучами этого бы не заметила.
func _check_rooms_turned() -> void:
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	var wrong: Array[String] = []
	var turned := 0
	for id: StringName in RunManager.layer.rooms:
		var room := RunManager.layer.rooms[id].entity as Node as Node3D
		var want := plan.embedding.turn_basis(plan.turns.get(id, 0))
		if not room.global_transform.basis.is_equal_approx(want):
			wrong.append(String(id))
		if plan.turns.get(id, 0) % 4 != 0:
			turned += 1
	_check("корни комнат повёрнуты по плану, и повёрнутые в слое есть (%d)" % turned,
		wrong.is_empty() and turned > 0, ", ".join(wrong.slice(0, 4)))


## Контракт клетки ([[Метрики и кит]] §2 п. 4): ничего не выходит за footprint.
## Выступ даже на сантиметры при повороте переносится на другую сторону и
## складывается с погрешностью соседа — так завелись швы кита 18 м. Меряем
## геометрию каждого поставленного тайла вместе с торцами.
func _check_tiles_in_cells(plan: RS_LayerPlan) -> void:
	var outside: Array[String] = []
	var half := plan.embedding.cell_size * 0.5 + 0.01
	for branch: StringName in RunManager.layer.corridor_tiles:
		for tile: Node3D in RunManager.layer.corridor_tiles[branch]:
			var center := plan.embedding.cell_origin(plan.embedding.cell_at(tile.global_position))
			for node in tile.find_children("*", "GeometryInstance3D", true, false):
				var geometry := node as GeometryInstance3D
				var box := geometry.global_transform * geometry.get_aabb()
				if box.position.x < center.x - half or box.end.x > center.x + half \
						or box.position.z < center.z - half or box.end.z > center.z + half:
					outside.append("%s %s" % [tile.name, geometry.name])
	_check("геометрия тайлов не выходит за свою клетку", outside.is_empty(), ", ".join(outside.slice(0, 4)))


## Лучи по коллизии: открытая сторона пропускает, закрытая упирается; на стыке
## тайла с дверью комнаты под ногами пол.
func _check_geometry() -> void:
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	var walls_wrong: Array[String] = []
	var gaps: Array[String] = []
	for cell: Vector3i in plan.corridor_tiles:
		var center := plan.embedding.cell_origin(cell)
		var mask: int = plan.corridor_tiles[cell]
		for side in plan.topology.side_count(cell):
			var to_face := _to_face(plan, cell, side)
			var dir := to_face.normalized()
			var from := center + Vector3(0.0, PROBE_HEIGHT, 0.0)
			var hit := _ray(space, from, from + dir * (to_face.length() - PROBE_SHORT))
			var open: bool = mask & (1 << side) != 0
			var side_name := RS_RoomLayout.side_name(side)
			if open == not hit.is_empty():
				walls_wrong.append("%s %s: %s" % [cell, side_name, "стена в проёме" if open else "дыра в стене"])
			if not open:
				continue
			# Пол по обе стороны грани клетки: щель на стыке — провал под мир.
			var neighbour := plan.topology.neighbour(cell, side)
			var neighbour_id: StringName = plan.node_by_cell.get(neighbour, &"")
			var face := to_face.length()
			for along: float in [face - SEAM_PROBE, face + SEAM_PROBE]:
				var foot := center + dir * along
				if _ray(space, foot + Vector3(0.0, 1.0, 0.0), foot + Vector3(0.0, -1.0, 0.0)).is_empty():
					# Сцена соседа в выводе: щель почти всегда — меш комнаты без
					# коллизии, и искать её по клетке пришлось бы руками.
					var node := RunManager.current_graph.get_node_data(neighbour_id)
					var scene := node.room_scene_path.get_file() if node and node.room_scene_path else "коридор"
					gaps.append("%s %s +%.1f %s" % [cell, side_name, along, scene])
	_check("проёмы и стены тайлов совпадают с маской — по коллизии", walls_wrong.is_empty(),
		", ".join(walls_wrong.slice(0, 4)))
	_check("на стыках тайлов и комнат под ногами пол", gaps.is_empty(), ", ".join(gaps.slice(0, 4)))


func _check_doors_bound() -> void:
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	var wrong: Array[String] = []
	var floor_portals_wrong: Array[String] = []
	for id: StringName in RunManager.layer.rooms:
		var room = RunManager.layer.rooms[id]
		var faces: Dictionary = plan.door_faces.get(id, {})
		var shell := RS_RoomLayout.shell_of(room.entity)
		for door: Entity in room.doors:
			# Грань запечённой двери считаем сами, по стене, — не той же функцией,
			# которой её привязал спавн. У сборной комнаты грань двери задал сам
			# спавн, и где она стоит, сверяет room_shell_check.
			var face: Vector4i = room.face_of(door) if shell else GridTopology.face(
				plan.cells[id], plan.topology.rotate_side(plan.cells[id],
					RS_RoomLayout.door_side(door as Node as Node3D, room.entity), -plan.turns.get(id, 0))
			)
			var portal := door.get_component(C_DoorPortal) as C_DoorPortal
			if portal == null or portal.target_node_id != faces.get(face, &"-"):
				wrong.append("%s:%s" % [id, face])
		var node := RunManager.current_graph.get_node_data(id)
		for conn: RS_LevelConnection in node.connections:
			var target := RunManager.current_graph.get_node_data(conn.target_node_id)
			if target.depth != node.depth or target.floor_index == node.floor_index:
				continue
			var bound := false
			for portal_entity in room.portals:
				var portal := (portal_entity as Entity).get_component(C_DoorPortal) as C_DoorPortal
				bound = bound or (portal != null and portal.target_node_id == target.id)
			if not bound:
				floor_portals_wrong.append("%s→%s" % [id, target.id])
	_check("каждая дверь ведёт в ветку своей стороны, заваренных нет", wrong.is_empty(),
		", ".join(wrong.slice(0, 4)))
	_check("переход между этажами слоя — порталом", floor_portals_wrong.is_empty(),
		", ".join(floor_portals_wrong.slice(0, 4)))


## Дверь в коридор открывается на месте: игрок не переносится, узел не
## меняется, полотно уходит вверх, подсветка гаснет.
func _check_open_door() -> void:
	var door: Entity = null
	var target: StringName = &""
	for id: StringName in RunManager.layer.rooms:
		if RunManager.current_graph.get_node_data(id).door_teleports:
			continue
		for candidate in RunManager.layer.rooms[id].doors:
			var portal := (candidate as Entity).get_component(C_DoorPortal) as C_DoorPortal
			if portal and portal.target_node_id != &"":
				door = candidate
				target = portal.target_node_id
				break
		if door:
			break
	if door == null:
		_check("есть дверь в коридор для проверки", false, "")
		return

	var space := get_viewport().world_3d.direct_space_state
	var blocked_before := not _doorway_ray(space, door).is_empty()

	var player := _player()
	var before := player.global_position
	var node_before := RunManager.current_node_id
	RunManager.use_door(door, target)
	var inter := door.get_component(C_Interactable) as C_Interactable
	_check("дверь в коридор открывается на месте: игрок и узел не меняются",
		player.global_position == before and RunManager.current_node_id == node_before
			and door.has_component(C_DoorOpen) and inter != null and not inter.enabled, "")

	for i in 12:
		ECS.process(0.1, "physics")
	# Тело с sync_to_physics переносится шагом физики — даём ему шаг.
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Лучом, а не по положению узла: прежняя проверка смотрела на Visual и
	# зеленела, пока меш уезжал, а коллизия полотна оставалась в проёме. Куда
	# полотно обязано уехать, считает то же правило, что его двигает.
	var open := door.get_component(C_DoorOpen) as C_DoorOpen
	var leaves := S_DoorOpen.leaves_of(door)
	var moved := not leaves.is_empty()
	for leaf in leaves:
		var rest: Vector3 = leaf.get_meta(S_DoorOpen.REST_META, Vector3.INF)
		var want := rest + S_DoorOpen.open_offset(open, S_DoorOpen.leaf_side(leaf), leaves.size())
		moved = moved and leaf.position.distance_to(want) < 0.05
	var hit := _doorway_ray(space, door)
	_check("полотно открылось вместе с коллизией: проём свободен",
		blocked_before and moved and hit.is_empty(),
		"до открытия луч упирался: %s, полотно на месте: %s, упор после: %s" % [
			blocked_before, moved, hit.collider.name if not hit.is_empty() else "нет"])

	# Ради этого дверь и двустворчатая: открытое полотно не уходит в клетку
	# уровня выше, где может стоять коридор соседнего этажа.
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	var ceiling := (door as Node as Node3D).global_position.y + plan.embedding.level_height
	var above: Array[String] = []
	for node in (door as Node).find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if (geometry.global_transform * geometry.get_aabb()).end.y > ceiling + 0.01:
			above.append(String(geometry.name))
	_check("открытое полотно не выходит выше своего уровня", above.is_empty(), ", ".join(above))


## Хаб — коробка кита P с настоящим проёмом, и его дверь открывается на месте,
## как любая (прежний хаб 18 м проёма не имел и переставлял игрока). Дальше — шаг
## за дверь, который сделал бы сам игрок, и узел меняет присутствие.
func _check_hub_door() -> void:
	var hub := RunManager.current_graph.entry_node_id
	var room = RunManager.layer.rooms.get(hub)
	var door: Entity = room.doors[0] if room and not room.doors.is_empty() else null
	var portal := door.get_component(C_DoorPortal) as C_DoorPortal if door else null
	if portal == null:
		_check("у хаба есть привязанная дверь", false, "")
		return
	var before := _player().global_position
	RunManager.use_door(door, portal.target_node_id)
	_check("дверь хаба открывается на месте, как любая",
		door.has_component(C_DoorOpen) and _player().global_position == before, "")
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	PlayerPlacement.in_front_of(_player(), door, room, plan)
	_check("шаг за дверь хаба — в его коридоре",
		plan.node_at(_player().global_position) == portal.target_node_id,
		"клетка игрока '%s'" % plan.node_at(_player().global_position))
	ECS.process(0.016, "gameplay")
	_check("и присутствие делает коридор текущим узлом",
		RunManager.current_node_id == portal.target_node_id, RunManager.current_node_id)


## Мини-карта в коридоре (стоим в ветке хаба после _check_hub_door): ветка видна
## целиком как текущая, хаб — как посещённый, комнаты ветки — как соседи, а
## маркер игрока внутри карты. Спрашивается build_view — пикселей headless не
## рисует, а ломается карта тихо: ветка, не попавшая в «известные», просто не
## нарисуется, маркер за краем просто не виден.
func _check_minimap() -> void:
	var map := UI_HudMap.new()
	map.size = Vector2(240.0, 240.0)
	add_child(map)
	await get_tree().process_frame
	var view := map.build_view()
	var branch := RunManager.current_node_id
	var hub := RunManager.current_graph.entry_node_id
	var branch_ids: Array = view.get("branches", []).map(func(n: RS_LevelNode) -> StringName: return n.id)
	var room_ids: Array = view.get("rooms", []).map(func(n: RS_LevelNode) -> StringName: return n.id)
	_check("карта: текущая ветка и хаб известны", branch_ids.has(branch) and room_ids.has(hub),
		"ветки %s, комнаты %s" % [branch_ids, room_ids])
	var neighbours_known := true
	for conn: RS_LevelConnection in RunManager.current_graph.get_node_data(branch).connections:
		var target := RunManager.current_graph.get_node_data(conn.target_node_id)
		if target.role == RS_LevelNode.Role.ROOM:
			neighbours_known = neighbours_known and room_ids.has(target.id)
	_check("карта: комнаты на ветке известны как соседи", neighbours_known, str(room_ids))
	var marker := map.world_to_screen(_player().global_position)
	_check("карта: маркер игрока внутри карты", Rect2(Vector2.ZERO, map.size).has_point(marker), str(marker))
	map.queue_free()


## Сейв в коридоре: загрузка ставит игрока на тайл той же ветки, а комплекс
## строится по снимку ручек забега — тем же, даже если база с тех пор поменялась
## (улучшение Архитектора посреди забега).
func _check_reload_in_corridor() -> void:
	var branch := RunManager.current_node_id
	var nodes_before := RunManager.current_graph.nodes.size()
	var changed := _base_config.duplicate() as RS_WorldGenConfig
	changed.rooms_per_floor = _base_config.rooms_per_floor + 3
	GameConfig.config.world_gen = changed
	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	_check("загрузка в коридоре: тот же комплекс по снимку, а не по новой базе",
		RunManager.current_graph.nodes.size() == nodes_before and RunManager.current_node_id == branch,
		"узлов %d из %d, узел '%s'" % [RunManager.current_graph.nodes.size(), nodes_before, RunManager.current_node_id])
	_check("и игрок стоит на тайле своей ветки", plan.node_at(_player().global_position) == branch, "")


# ---------------------------------------------------------------------------


## Луч сквозь проём двери на высоте груди, поперёк полотна — во что упрётся
## идущий через дверь. Не по оси проёма: у двустворчатой там щель между
## створками, и закрытая дверь пропускала бы луч.
func _doorway_ray(space: PhysicsDirectSpaceState3D, door: Node) -> Dictionary:
	var body := door as Node3D
	var normal := body.global_transform.basis.z.normalized()
	var along := body.global_transform.basis.x.normalized() * 0.4
	var center := body.global_position + Vector3(0.0, PROBE_HEIGHT, 0.0) + along
	return _ray(space, center - normal * 1.5, center + normal * 1.5)


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int = GEOMETRY_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return space.intersect_ray(query)


## От центра клетки до середины её грани за стороной [param side]. Грань — на
## полпути к центру соседа: так пробы знают размер клетки из вложения плана, а
## не из числа, зашитого в проверку.
func _to_face(plan: RS_LayerPlan, cell: Vector3i, side: int) -> Vector3:
	var next := plan.topology.neighbour(cell, side)
	return (plan.embedding.cell_origin(next) - plan.embedding.cell_origin(cell)) * 0.5


func _base_mask(kit: RS_CorridorKit, scene_path: String) -> int:
	if kit.straight and scene_path == kit.straight.resource_path:
		return kit.straight_mask
	if kit.corner and scene_path == kit.corner.resource_path:
		return kit.corner_mask
	if kit.tee and scene_path == kit.tee.resource_path:
		return kit.tee_mask
	if kit.end and scene_path == kit.end.resource_path:
		return kit.end_mask
	return kit.cross_mask


func _player() -> Node3D:
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as Node as Node3D


func _restore() -> void:
	GameConfig.config.world_gen = _base_config
	WorldSave.save = _save_object
	if _had_save:
		var file := FileAccess.open(WorldSave.SAVE_PATH, FileAccess.WRITE)
		if file:
			file.store_buffer(_save_backup)
			file.close()
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(WorldSave.SAVE_PATH))
	_check("сейв разработчика возвращён на место",
		FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH) == _save_backup, "")
