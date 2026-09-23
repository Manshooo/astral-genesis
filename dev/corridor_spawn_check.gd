extends Node
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
## Луч вдоль тайла: из центра до начала тамбура (7 м) и чуть дальше — внутри
## СВОЕЙ клетки. Стены тайла стоят в 3 м, так что поворот он различает, а
## чужая геометрия, зашедшая за грань клетки, до него не дотягивается: её
## ищет отдельный отчёт (_report_intrusions), потому что это вопрос арта, а не
## сборки.
const PROBE_LENGTH := 7.5
const PROBE_HEIGHT := 1.5
## Только статическая геометрия (слой static_colliders): объём прицеливания
## двери (interactives) шире самой двери и стенкой не является.
const GEOMETRY_MASK := 1
## Куда дотягивается отчёт о заходе за грань клетки: до грани и на полметра за
## неё — то, что стоит в тамбуре тайла.
const INTRUSION_PROBE := 9.0
const EXPECTED_ASSERTS := 17

var _ok := 0
var _fail := 0
var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave
var _base_config: RS_WorldGenConfig


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save
	_base_config = GameConfig.config.world_gen

	var world := World.new()
	add_child(world)
	ECS.world = world
	var presence := S_RoomPresence.new()
	presence.group = "gameplay"
	world.add_system(presence)
	var doors := S_DoorOpen.new()
	doors.group = "physics"
	world.add_system(doors)

	GameConfig.config.world_gen = _base_config.duplicate() as RS_WorldGenConfig
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	RunManager.enter_complex(RUN_SEED)
	await get_tree().physics_frame
	await get_tree().physics_frame

	_check_tiles()
	await _check_geometry()
	_check_doors_bound()
	_check_open_door()
	_check_hub_door()
	await _check_minimap()
	await _check_reload_in_corridor()

	RunManager._end_run()
	_restore()

	var ran := _ok + _fail
	_check("все блоки дошли до конца", ran == EXPECTED_ASSERTS,
		"ассертов %d из %d — какой-то блок упал на ошибке скрипта" % [ran, EXPECTED_ASSERTS])
	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------


func _check_tiles() -> void:
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	_check("у слоя есть тайлы коридора", not RunManager._corridor_tiles.is_empty(), "")
	var spawned := 0
	var wrong: Array[String] = []
	var kit := GameConfig.config.corridor_kit
	for branch: StringName in RunManager._corridor_tiles:
		for tile: Node3D in RunManager._corridor_tiles[branch]:
			spawned += 1
			var cell := _cell_of(tile.global_position)
			var base := _base_mask(kit, tile.scene_file_path)
			var turns := posmod(roundi(tile.rotation.y / (PI * 0.5)), 4)
			if RS_CorridorKit.rotate_mask(base, turns) != plan.corridor_tiles.get(cell, -1) \
					or plan.node_by_cell.get(cell, &"") != branch:
				wrong.append("%s %s" % [branch, cell])
	_check("на каждый тайл плана — ровно один кусок (%d)" % plan.corridor_tiles.size(),
		spawned == plan.corridor_tiles.size(), "поставлено %d" % spawned)
	_check("кусок под маску своего тайла и своей ветки", wrong.is_empty(), ", ".join(wrong.slice(0, 4)))


## Лучи по коллизии: открытая сторона пропускает, закрытая упирается; на стыке
## тайла с дверью комнаты под ногами пол (кроме хаба — у него проёма нет вовсе,
## см. door_teleports).
func _check_geometry() -> void:
	await get_tree().physics_frame
	var space := get_viewport().world_3d.direct_space_state
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	var walls_wrong: Array[String] = []
	var gaps: Array[String] = []
	var hub := RunManager.current_graph.entry_node_id
	for cell: Vector3i in plan.corridor_tiles:
		var center := plan.cell_position(Vector2i(cell.x, cell.z), cell.y)
		var mask: int = plan.corridor_tiles[cell]
		for side: StringName in RS_LayerPlan.SIDE_BITS:
			var offset: Vector2i = RS_RoomLayout.OFFSETS[side]
			var dir := Vector3(offset.x, 0.0, offset.y)
			var from := center + Vector3(0.0, PROBE_HEIGHT, 0.0)
			var hit := _ray(space, from, from + dir * PROBE_LENGTH)
			var open: bool = mask & RS_LayerPlan.SIDE_BITS[side] != 0
			if open == not hit.is_empty():
				walls_wrong.append("%s %s: %s" % [cell, side, "стена в проёме" if open else "дыра в стене"])
			if not open:
				continue
			# Пол по обе стороны грани клетки: щель на стыке — провал под мир.
			var neighbour := Vector3i(cell.x + offset.x, cell.y, cell.z + offset.y)
			if plan.node_by_cell.get(neighbour, &"") == hub:
				continue
			for along: float in [8.6, 9.4]:
				var foot := center + dir * along
				if _ray(space, foot + Vector3(0.0, 1.0, 0.0), foot + Vector3(0.0, -1.0, 0.0)).is_empty():
					gaps.append("%s %s +%.1f" % [cell, side, along])
	_check("проёмы и стены тайлов совпадают с маской — по коллизии", walls_wrong.is_empty(),
		", ".join(walls_wrong.slice(0, 4)))
	_check("на стыках тайлов и комнат под ногами пол", gaps.is_empty(), ", ".join(gaps.slice(0, 4)))
	_report_intrusions(space, plan)


## Не ассерт, а отчёт: что из соседней клетки заходит в тамбур тайла. Правило
## стыка — ничего не выходит за грань клетки (±9 м), но у B-комнат и выхода
## рамки и двери стоят на 9.3–10 м, и полотно двери сидит в коридоре. Подрезка —
## решение за артом (22.09), и до неё красный ассерт в каждом прогоне был бы
## шумом. Когда арт поправят, отчёт обязан опустеть — тогда его место занять
## ассерту.
func _report_intrusions(space: PhysicsDirectSpaceState3D, plan: RS_LayerPlan) -> void:
	var found := {}
	for cell: Vector3i in plan.corridor_tiles:
		var center := plan.cell_position(Vector2i(cell.x, cell.z), cell.y) + Vector3(0.0, PROBE_HEIGHT, 0.0)
		for side: StringName in RS_LayerPlan.SIDE_BITS:
			if plan.corridor_tiles[cell] & RS_LayerPlan.SIDE_BITS[side] == 0:
				continue
			var offset: Vector2i = RS_RoomLayout.OFFSETS[side]
			var hit := _ray(space, center, center + Vector3(offset.x, 0.0, offset.y) * INTRUSION_PROBE)
			if hit.is_empty():
				continue
			var neighbour := Vector3i(cell.x + offset.x, cell.y, cell.z + offset.y)
			var room: StringName = plan.node_by_cell.get(neighbour, &"")
			var node := RunManager.current_graph.get_node_data(room)
			found[node.room_scene_path.get_file() if node else String(room)] = true
	if not found.is_empty():
		print("  арт  за грань клетки заходит геометрия комнат: %s" % ", ".join(found.keys()))


func _check_doors_bound() -> void:
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	var wrong: Array[String] = []
	var floor_portals_wrong: Array[String] = []
	for id: StringName in RunManager._rooms:
		var room = RunManager._rooms[id]
		var sides: Dictionary = plan.door_sides.get(id, {})
		for door: Entity in room.doors:
			var side := RS_RoomLayout.door_direction(door as Node as Node3D, room.entity)
			var portal := door.get_component(C_DoorPortal) as C_DoorPortal
			if portal == null or portal.target_node_id != sides.get(side, &"-"):
				wrong.append("%s:%s" % [id, side])
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
	for id: StringName in RunManager._rooms:
		if RunManager.current_graph.get_node_data(id).door_teleports:
			continue
		for candidate in RunManager._rooms[id].doors:
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
	var visual := door.get_node(^"Visual") as Node3D
	var lift := (door.get_component(C_DoorOpen) as C_DoorOpen).lift
	_check("полотно поднялось целиком", is_equal_approx(visual.position.y, lift),
		"y=%.2f из %.2f" % [visual.position.y, lift])


## Хаб (door_teleports): проёма за его дверью нет, и дверь ставит игрока на
## тайл перед собой — дальше узел меняет присутствие.
func _check_hub_door() -> void:
	var hub := RunManager.current_graph.entry_node_id
	var room = RunManager._rooms.get(hub)
	var door: Entity = room.doors[0] if room and not room.doors.is_empty() else null
	var portal := door.get_component(C_DoorPortal) as C_DoorPortal if door else null
	if portal == null:
		_check("у хаба есть привязанная дверь", false, "")
		return
	RunManager.use_door(door, portal.target_node_id)
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	_check("дверь хаба ставит игрока в его коридор",
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


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, mask: int = GEOMETRY_MASK) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	return space.intersect_ray(query)


func _cell_of(position: Vector3) -> Vector3i:
	return Vector3i(
		roundi(position.x / RS_LayerPlan.CELL_SIZE),
		roundi(position.y / RS_LayerPlan.FLOOR_SPACING),
		roundi(position.z / RS_LayerPlan.CELL_SIZE),
	)


func _base_mask(kit: RS_CorridorKit, scene_path: String) -> int:
	if kit.straight and scene_path == kit.straight.resource_path:
		return kit.straight_mask
	if kit.corner and scene_path == kit.corner.resource_path:
		return kit.corner_mask
	if kit.tee and scene_path == kit.tee.resource_path:
		return kit.tee_mask
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


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
