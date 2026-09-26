extends "res://dev/check_harness.gd"
## Проверка комнат, собранных по маске сокетов (C_RoomShell, п. 4 карточки
## «Сетка уровня»). Ломаются они тихо: коробка, разошедшаяся с заявленным
## footprint, встаёт внахлёст на соседа или оставляет щель у стены; проп в зоне
## перед сокетом загораживает дверь, которую раскладка туда поставит; стена,
## повёрнутая не в ту сторону, ставит проём в глухую сторону. Ни одно из этого не
## падает с ошибкой.
##
## Три части:
##   1. коробка каждой сцены с C_RoomShell = footprint × клетка;
##   2. пропы не заходят в зоны перед сокетами ([[Метрики и кит]] §3, §5);
##   3. сборка на настоящих деталях кита P: план с комнатой 2×2×1 и веткой,
##      стены и торцы по маске — и лучи по коллизии, как у corridor_spawn_check.
##
## Запускать: godot --headless dev/room_shell_check.tscn

const ROOMS_DIR := "res://src/levels/procedural/rooms/"
const CONFIG_PATH := "res://data/world_gen_config.tres"
const KIT_P_ROOM := "res://src/levels/procedural/rooms/kit_p/room_p_2x2x1.tscn"
const KIT_P_CORRIDORS := "res://data/corridor_kit_p.tres"
## Клетка, под которую нарисован кит P. До п. 5 игра стоит на 18 м, и коробки P с
## её вложением не сойдутся; проверяются они на своём. После переключения вложения
## коробки из подбора сверяются с планом игры, как уже сейчас.
const KIT_P_CELL := 8.0
## Зона перед сокетом, свободная от пропов: 3 м вдоль стены, 2 м вглубь комнаты,
## от пола до верха рамки проёма (4.5 м) — [[Метрики и кит]] §2 п. 6, §3.
const SOCKET_ZONE := Vector3(3.0, 4.5, 2.0)
## Допуск сравнения габаритов: экспорт glTF кладёт вершины с погрешностью float.
const EPSILON := 0.01
const GEOMETRY_MASK := 1
const CHEST := 1.5
## Выше проёма (4.25), но ниже потолка коридора (5.0): здесь и стена комнаты, и
## торец коридора обязаны быть сплошными.
const ABOVE_OPENING := 4.8


func _ready() -> void:
	var shells := _shell_scenes()
	_check("в проекте есть хотя бы одна сборная комната", not shells.is_empty(), ROOMS_DIR)
	var pool := _generator_scenes()
	for path in shells:
		var plan := RS_LayerPlan.new() if pool.has(path) else _kit_p_plan()
		_check_box(path, plan)
		_check_zones(path, plan)
	_check_zone_detector()
	await _check_assembly()
	_finish()


# --- 1. Коробка = footprint × клетка -----------------------------------------


func _check_box(path: String, plan: RS_LayerPlan) -> void:
	var room := (load(path) as PackedScene).instantiate() as Node3D
	add_child(room)
	var shell := RS_RoomLayout.shell_of(room)
	var visual := room.get_node_or_null(^"Visual")
	var box := _merged_aabb(room, visual) if visual else AABB()
	var cell := plan.embedding.cell_size
	var want_x := shell.size.x * cell
	var want_z := shell.size.z * cell
	var fits := (
		absf(box.size.x - want_x) < EPSILON and absf(box.size.z - want_z) < EPSILON
		and absf(box.position.x + want_x * 0.5) < EPSILON and absf(box.position.z + want_z * 0.5) < EPSILON
		and absf(box.position.y) < EPSILON and box.end.y <= shell.size.y * plan.embedding.level_height + EPSILON
	)
	_check("%s: коробка = footprint %s × клетка %.0f м" % [path.get_file(), shell.size, cell], fits, str(box))
	room.queue_free()


## Общий AABB всей геометрии под [param root] в координатах [param room].
func _merged_aabb(room: Node3D, root: Node) -> AABB:
	var merged := AABB()
	var first := true
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		var box := room.global_transform.affine_inverse() * geometry.global_transform * geometry.get_aabb()
		merged = box if first else merged.merge(box)
		first = false
	return merged


# --- 2. Зоны перед сокетами ---------------------------------------------------


func _check_zones(path: String, plan: RS_LayerPlan) -> void:
	var room := (load(path) as PackedScene).instantiate() as Node3D
	add_child(room)
	var hits := _props_in_zones(room, plan)
	_check("%s: пропы не заходят в зоны перед сокетами" % path.get_file(), hits.is_empty(), ", ".join(hits))
	room.queue_free()


## Детектор должен ловить нарушение, иначе зелёная часть 2 ничего не значит: у
## коробки P пропов нет вовсе. Ставим куб ровно в зону перед первым сокетом.
func _check_zone_detector() -> void:
	var plan := _kit_p_plan()
	var room := (load(KIT_P_ROOM) as PackedScene).instantiate() as Node3D
	add_child(room)
	var zone: AABB = _socket_zones(RS_RoomLayout.shell_of(room), plan)[0]
	var prop := MeshInstance3D.new()
	prop.mesh = BoxMesh.new()
	prop.position = zone.get_center()
	room.add_child(prop)
	_check("детектор зон ловит проп перед сокетом", not _props_in_zones(room, plan).is_empty(), str(zone))
	room.queue_free()


## Пропы — вся геометрия комнаты, кроме самой коробки (узел Visual).
func _props_in_zones(room: Node3D, plan: RS_LayerPlan) -> Array[String]:
	var hits: Array[String] = []
	var zones := _socket_zones(RS_RoomLayout.shell_of(room), plan)
	for node in room.find_children("*", "GeometryInstance3D", true, false):
		var geometry := node as GeometryInstance3D
		if room.get_node(^"Visual").is_ancestor_of(geometry):
			continue
		var box := room.global_transform.affine_inverse() * geometry.global_transform * geometry.get_aabb()
		for zone in zones:
			if box.intersects(zone):
				hits.append("%s в %s" % [geometry.name, zone])
	return hits


## Зоны перед всеми сокетами footprint в координатах корня комнаты: корень стоит
## в центре footprint (RS_LayerPlan.position_of), как его поставит спавн.
func _socket_zones(shell: C_RoomShell, plan: RS_LayerPlan) -> Array[AABB]:
	var zones: Array[AABB] = []
	var cells := SquareGridTopology.box(Vector3i.ZERO, shell.size)
	var far := Vector3i(shell.size.x - 1, 0, shell.size.z - 1)
	var center := (plan.embedding.cell_origin(Vector3i.ZERO) + plan.embedding.cell_origin(far)) * 0.5
	for face in plan.topology.perimeter(cells):
		var inside := plan.embedding.cell_origin(GridTopology.face_cell(face))
		var outside := plan.embedding.cell_origin(plan.topology.neighbour(GridTopology.face_cell(face), face.w))
		var inward := (inside - outside).normalized()
		var along := inward.cross(Vector3.UP).abs()
		var mid := (inside + outside) * 0.5 - center + inward * SOCKET_ZONE.z * 0.5
		var half := along * SOCKET_ZONE.x * 0.5 + inward.abs() * SOCKET_ZONE.z * 0.5
		zones.append(AABB(Vector3(mid.x - half.x, 0.0, mid.z - half.z), Vector3(half.x * 2.0, SOCKET_ZONE.y, half.z * 2.0)))
	return zones


# --- 3. Сборка на деталях кита P ---------------------------------------------


func _check_assembly() -> void:
	var room_node := RS_LevelNode.new()
	room_node.id = &"room"
	room_node.room_scene_path = KIT_P_ROOM
	room_node.socket_doors = 2
	var branch := RS_LevelNode.new()
	branch.id = &"branch"
	branch.role = RS_LevelNode.Role.CORRIDOR
	branch.index_in_layer = 1
	for i in room_node.socket_doors:
		_link(room_node, branch)
	var layer: Array[RS_LevelNode] = [room_node, branch]
	var plan := RS_LayerPlan.build(layer)
	plan.embedding = SquareGridEmbedding.new(KIT_P_CELL, KIT_P_CELL, 0.25)
	var faces: Dictionary = plan.door_faces.get(room_node.id, {})
	_check("план: у комнаты 2×2×1 ровно две двери, обе в сокетах",
		faces.size() == 2 and plan.routing_failures.is_empty(),
		"%s %s" % [faces, plan.routing_failures])

	var root := Node3D.new()
	add_child(root)
	var room := (load(KIT_P_ROOM) as PackedScene).instantiate() as Node3D
	room.position = plan.position_of(room_node.id)
	var walls := RS_RoomLayout.shell_of(room).walls
	var doors := walls.assemble(room, room_node.id, plan)
	root.add_child(room)
	var kit := load(KIT_P_CORRIDORS) as RS_CorridorKit
	var caps := 0
	for cell: Vector3i in plan.corridor_tiles:
		var tile := kit.instantiate(plan.corridor_tiles[cell], plan.door_mask(cell))
		tile.position = plan.embedding.cell_origin(cell)
		root.add_child(tile)
		for child in tile.get_children():
			caps += 1 if child.scene_file_path == kit.door_end.resource_path else 0

	var door_walls := 0
	var blank_walls := 0
	for child in room.get_children():
		door_walls += 1 if child.scene_file_path == walls.door_wall.resource_path else 0
		blank_walls += 1 if child.scene_file_path == walls.blank_wall.resource_path else 0
	_check("стен по граням периметра: 2 с проёмом и 6 глухих", door_walls == 2 and blank_walls == 6,
		"с проёмом %d, глухих %d" % [door_walls, blank_walls])
	_check("торец с проёмом — на каждый тайл перед дверью", caps == 2, "торцов %d" % caps)
	var misplaced: Array[String] = []
	for door: Node3D in doors:
		var face: Vector4i = doors[door]
		var cell := GridTopology.face_cell(face)
		var mid := (plan.embedding.cell_origin(cell) + plan.embedding.cell_origin(plan.topology.neighbour(cell, face.w))) * 0.5
		if door.global_position.distance_to(mid) > EPSILON:
			misplaced.append("%s: %s вместо %s" % [face, door.global_position, mid])
	_check("двери стоят на середине своих граней", doors.size() == 2 and misplaced.is_empty(), ", ".join(misplaced))

	for i in 3:
		await get_tree().physics_frame
	_check_assembly_rays(plan, room_node.id, doors)
	root.queue_free()


## Лучи по коллизии деталей: глухая грань держит изнутри комнаты; через дверь луч
## проходит насквозь — сквозь проём стены и проём торца — до центра тайла; над
## проёмом упирается и стена комнаты, и торец коридора. Полотна дверей из луча
## исключены: закрытая дверь проём и должна закрывать.
func _check_assembly_rays(plan: RS_LayerPlan, room_id: StringName, doors: Dictionary) -> void:
	var space := get_viewport().world_3d.direct_space_state
	var exclude: Array[RID] = []
	for door: Node in doors:
		for body in door.find_children("*", "CollisionObject3D", true, false):
			exclude.append((body as CollisionObject3D).get_rid())
	var door_faces: Dictionary = plan.door_faces[room_id]
	var wrong: Array[String] = []
	for face in plan.topology.perimeter(plan.room_cells(room_id)):
		var cell := GridTopology.face_cell(face)
		var inside := plan.embedding.cell_origin(cell)
		var outside := plan.embedding.cell_origin(plan.topology.neighbour(cell, face.w))
		var up := Vector3(0.0, CHEST, 0.0)
		var hit := _ray(space, inside + up, outside + up, exclude)
		if door_faces.has(face):
			if not hit.is_empty():
				wrong.append("%s: дверной проём закрыт у %s" % [face, hit.position])
			var high := Vector3(0.0, ABOVE_OPENING, 0.0)
			if _ray(space, inside + high, outside + high, exclude).is_empty():
				wrong.append("%s: над проёмом изнутри комнаты пусто" % face)
			if _ray(space, outside + high, inside + high, exclude).is_empty():
				wrong.append("%s: над проёмом со стороны коридора пусто — нет торца" % face)
		else:
			var reach: float = inside.distance_to((hit.get("position", outside) as Vector3) - up)
			if hit.is_empty() or reach > plan.embedding.cell_size * 0.5:
				wrong.append("%s: глухая стена не держит (до стены %.2f м)" % [face, reach])
	_check("стены и торцы по коллизии: проёмы там, где двери, глухо везде ещё",
		wrong.is_empty(), ", ".join(wrong.slice(0, 4)))


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, GEOMETRY_MASK, exclude)
	return space.intersect_ray(query)


# -----------------------------------------------------------------------------


func _link(a: RS_LevelNode, b: RS_LevelNode) -> void:
	var forward := RS_LevelConnection.new()
	forward.target_node_id = b.id
	forward.type = RS_LevelConnection.Type.CORRIDOR
	a.connections.append(forward)
	var backward := RS_LevelConnection.new()
	backward.target_node_id = a.id
	backward.type = RS_LevelConnection.Type.CORRIDOR
	b.connections.append(backward)


func _kit_p_plan() -> RS_LayerPlan:
	var plan := RS_LayerPlan.new()
	plan.embedding = SquareGridEmbedding.new(KIT_P_CELL, KIT_P_CELL, 0.25)
	return plan


## Все сцены комнат с C_RoomShell под ROOMS_DIR.
func _shell_scenes() -> Array[String]:
	var found: Array[String] = []
	var dirs: Array[String] = [ROOMS_DIR]
	while not dirs.is_empty():
		var dir := dirs.pop_back() as String
		for sub in DirAccess.get_directories_at(dir):
			dirs.append(dir.path_join(sub))
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() == "tscn" and RS_RoomLayout.shell_of_scene(dir.path_join(file)):
				found.append(dir.path_join(file))
	found.sort()
	return found


## Сцены, которые генератор реально может поставить: пул подбора, запасная и
## уникальные комнаты конфига.
func _generator_scenes() -> Array[String]:
	var scenes: Array[String] = []
	var library: RS_RoomPresetLibrary = GameConfig.config.room_preset_library
	var presets: Array = library.presets.duplicate()
	presets.append(library.fallback)
	var config := load(CONFIG_PATH) as RS_WorldGenConfig
	for unique: RS_UniqueRoom in config.unique_rooms:
		if unique:
			presets.append(unique.preset)
	for preset: RS_RoomPreset in presets:
		if preset and preset.scene:
			scenes.append(preset.scene.resource_path)
	return scenes
