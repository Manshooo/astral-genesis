extends "res://dev/check_harness.gd"
## Проверка комнат, собранных по маске сокетов (C_RoomShell, п. 4 карточки
## «Сетка уровня»). Ломаются они тихо: коробка, разошедшаяся с заявленным
## footprint, встаёт внахлёст на соседа или оставляет щель у стены; проп в зоне
## перед сокетом загораживает дверь, которую раскладка туда поставит; стена,
## повёрнутая не в ту сторону, ставит проём в глухую сторону. Ни одно из этого не
## падает с ошибкой.
##
## Четыре части:
##   1. все комнаты генератора — коробки, и коробка каждой = footprint × клетка;
##   2. пропы не заходят в зоны перед сокетами ([[Метрики и кит]] §3, §5) и не
##      выходят за footprint коробки (в толщу стены — можно);
##   3. сборка на настоящих деталях каждого кита в игре (P, X): план с комнатой
##      2×2×1 и веткой, стены и торцы по маске — и лучи по коллизии, как у
##      corridor_spawn_check; у коробки со стенами в меше — заглушки на
##      невыбранных сокетах и ни одной стены поверх нарисованных;
##   4. валидация пресета на такой коробке ловит то, что сборка молча стерпела бы.
##
## Запускать: godot --headless dev/room_shell_check.tscn

const ROOMS_DIR := "res://src/levels/"
const CONFIG_PATH := "res://data/world_gen_config.tres"
## Эталонная коробка кита P без содержимого — на ней проверяется детектор зон.
const KIT_P_ROOM := "res://src/levels/procedural/rooms/kit_p/room_p_2x2x1.tscn"
## Эталонные коробки китов, выгруженных в игру: сборка проверяется на каждой —
## стиль рисуется поверх P, и стык, целый у P, у стиля может разойтись. Коробка
## со стенами в меше — отдельной строкой: проём там рисует меш, а закрывает
## заглушка, и стык у них свой.
const KIT_ROOMS: Array[String] = [
	KIT_P_ROOM,
	"res://src/levels/procedural/rooms/kit_x/room_x_2x2x1.tscn",
	"res://src/levels/procedural/rooms/kit_p/room_p_walled_2x2x1.tscn",
]
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
	# Клетка 8 м: комната с запечённой дверью 18-метрового кита в подборе встала бы
	# внахлёст на соседей — все комнаты генератора обязаны быть коробками.
	var baked: Array[String] = []
	for path in _generator_scenes():
		if not shells.has(path):
			baked.append(path.get_file())
	_check("все комнаты генератора собираются по сокетам", baked.is_empty(), ", ".join(baked))
	var plan := RS_LayerPlan.new()
	for path in shells:
		_check_box(path, plan)
		_check_zones(path, plan)
		_check_socket_turns(path)
	_check_zone_detector()
	# Без поворота и на четверть: стены и двери обязаны встать в стороны мира при
	# любом повороте корня комнаты.
	for kit_room in KIT_ROOMS:
		for turns in [0, 1]:
			await _check_assembly(kit_room, turns)
	_check_walled_validation()
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
	# Содержимое, перенесённое из комнаты 18 м, могло остаться там, где теперь стена.
	var inside := _props_outside(room, plan)
	_check("%s: пропы не выходят за footprint коробки" % path.get_file(), inside.is_empty(), ", ".join(inside))
	room.queue_free()


## Пропы, чья геометрия в плане выходит за границу клеток коробки. Толща стены
## пропу разрешена — труба или кабель, уходящие в стену, и есть то, как проп
## к ней крепится. А за границей уже соседняя клетка: раскладка о пропе не знает
## и может провести там коридор, сквозь стену которого проп и прорастёт.
func _props_outside(room: Node3D, plan: RS_LayerPlan) -> Array[String]:
	var outside: Array[String] = []
	var shell := RS_RoomLayout.shell_of(room)
	var half := Vector2(shell.size.x, shell.size.z) * plan.embedding.cell_size * 0.5
	for geometry in _props(room):
		var box := room.global_transform.affine_inverse() * geometry.global_transform * geometry.get_aabb()
		if box.position.x < -half.x - EPSILON or box.end.x > half.x + EPSILON \
				or box.position.z < -half.y - EPSILON or box.end.z > half.y + EPSILON:
			outside.append("%s %s" % [geometry.name, box])
	return outside


## Детектор должен ловить нарушение, иначе зелёная часть 2 ничего не значит: у
## коробки P пропов нет вовсе. Ставим куб ровно в зону перед первым сокетом.
func _check_zone_detector() -> void:
	var plan := RS_LayerPlan.new()
	var room := (load(KIT_P_ROOM) as PackedScene).instantiate() as Node3D
	add_child(room)
	var zone: AABB = _socket_zones(RS_RoomLayout.shell_of(room), plan)[0]
	var prop := MeshInstance3D.new()
	prop.mesh = BoxMesh.new()
	prop.position = zone.get_center()
	room.add_child(prop)
	_check("детектор зон ловит проп перед сокетом", not _props_in_zones(room, plan).is_empty(), str(zone))
	room.queue_free()


func _props_in_zones(room: Node3D, plan: RS_LayerPlan) -> Array[String]:
	var hits: Array[String] = []
	var zones := _socket_zones(RS_RoomLayout.shell_of(room), plan)
	for geometry in _props(room):
		var box := room.global_transform.affine_inverse() * geometry.global_transform * geometry.get_aabb()
		for zone in zones:
			if box.intersects(zone):
				hits.append("%s в %s" % [geometry.name, zone])
	return hits


## Пропы — вся геометрия комнаты, кроме самой коробки (узел Visual).
func _props(room: Node3D) -> Array[GeometryInstance3D]:
	var props: Array[GeometryInstance3D] = []
	var visual := room.get_node(^"Visual")
	for node in room.find_children("*", "GeometryInstance3D", true, false):
		if not visual.is_ancestor_of(node):
			props.append(node as GeometryInstance3D)
	return props


## Зоны перед всеми сокетами коробки в координатах корня комнаты: корень стоит
## в центре footprint (RS_LayerPlan.position_of), как его поставит спавн. Сокеты —
## объявленные коробкой (у лестницы и на верхнем уровне, зона — от пола того
## уровня) или все грани нижнего уровня.
func _socket_zones(shell: C_RoomShell, plan: RS_LayerPlan) -> Array[AABB]:
	var zones: Array[AABB] = []
	var cells := SquareGridTopology.box(Vector3i.ZERO, shell.size)
	var far := Vector3i(shell.size.x - 1, 0, shell.size.z - 1)
	var center := (plan.embedding.cell_origin(Vector3i.ZERO) + plan.embedding.cell_origin(far)) * 0.5
	var sockets := shell.door_sockets if not shell.door_sockets.is_empty() else plan.topology.perimeter(cells)
	for face in sockets:
		var inside := plan.embedding.cell_origin(GridTopology.face_cell(face))
		var outside := plan.embedding.cell_origin(plan.topology.neighbour(GridTopology.face_cell(face), face.w))
		var inward := (inside - outside).normalized()
		var along := inward.cross(Vector3.UP).abs()
		var mid := (inside + outside) * 0.5 - center + inward * SOCKET_ZONE.z * 0.5
		var half := along * SOCKET_ZONE.x * 0.5 + inward.abs() * SOCKET_ZONE.z * 0.5
		zones.append(AABB(Vector3(mid.x - half.x, mid.y, mid.z - half.z), Vector3(half.x * 2.0, SOCKET_ZONE.y, half.z * 2.0)))
	return zones


## Объявленные сокеты (C_RoomShell.door_sockets) встают в плане туда, где их
## поставит спавн, при любом повороте. Сверка — не той же функцией: середина
## грани сокета берётся в осях сцены и переводится в мир корнем комнаты
## (RS_LayerPlan.room_transform, им комнату ставит спавн), а сравнивается с
## гранью из RS_RoomLayout.sockets_in_plan, по которой раскладка тянет коридор.
## Разойдись они — дверь раскладки упёрлась бы в стену, а проём сборки — в
## пустоту, и у лестницы верхний вход оказался бы не у площадки.
func _check_socket_turns(path: String) -> void:
	var shell := RS_RoomLayout.shell_of_scene(path)
	if shell == null or shell.door_sockets.is_empty():
		return
	var plan := RS_LayerPlan.new()
	var size := plan.embedding.cell_size
	var wrong: Array[String] = []
	for turns in SquareGridTopology.SIDE_COUNT:
		var anchor := Vector3i(3, 1, -2)
		plan.cells[&"room"] = anchor
		plan.footprints[&"room"] = Vector3i(shell.size.z, shell.size.y, shell.size.x) if turns % 2 else shell.size
		plan.turns[&"room"] = turns
		var faces := RS_RoomLayout.sockets_in_plan(path, turns, anchor)
		for i in shell.door_sockets.size():
			var socket := shell.door_sockets[i]
			var local := Vector3(
				(socket.x + 0.5 - shell.size.x * 0.5) * size,
				socket.y * plan.embedding.level_height,
				(socket.z + 0.5 - shell.size.z * 0.5) * size,
			) + Vector3(SquareGridTopology.OFFSETS[socket.w]) * size * 0.5
			var want := plan.room_transform(&"room") * local
			var cell := GridTopology.face_cell(faces[i])
			var got := (plan.embedding.cell_origin(cell) + plan.embedding.cell_origin(plan.topology.neighbour(cell, faces[i].w))) * 0.5
			if not got.is_equal_approx(want):
				wrong.append("поворот %d, сокет %s: %s вместо %s" % [turns, socket, got, want])
	_check("%s: объявленные сокеты встают в плане туда же, куда их ставит спавн" % path.get_file(),
		wrong.is_empty(), ", ".join(wrong.slice(0, 3)))


# --- 3. Сборка на деталях китов ----------------------------------------------


func _check_assembly(kit_room: String, turns: int) -> void:
	var room_node := RS_LevelNode.new()
	room_node.id = &"room"
	room_node.room_scene_path = kit_room
	room_node.socket_doors = 2
	room_node.turns = turns
	# В подписи — кит: проверки у P и X одни и те же, и по повороту не понять, чья
	# сборка упала.
	var tag := "%s, поворот %d" % [kit_room.get_file().get_basename(), turns]
	# Слой раскладывает сам планировщик: план рождается в генерации графа, а графа
	# здесь нет. Без петель и тупиков — проверяется сборка комнаты. Соседи — чтобы
	# дверям было куда вести: одинокой комнате раскладка оставляет одну дверь
	# (RS_CorridorPlanner._join_spare_doors). Сколько дверей встало, решает
	# раскладка, поэтому сборка сверяется с планом, а не с числом.
	var rooms: Array[RS_LevelNode] = [room_node]
	for i in 2:
		var neighbour := RS_LevelNode.new()
		neighbour.id = StringName("neighbour_%d" % i)
		neighbour.room_scene_path = KIT_P_ROOM
		neighbour.socket_doors = 1
		rooms.append(neighbour)
	var config := RS_WorldGenConfig.new()
	config.corridor_loops = 0
	config.dead_ends = 0
	var plan := RS_LayerPlan.new()
	RS_CorridorPlanner.plan_floor(plan, rooms, "corridor_", 0, config, RandomNumberGenerator.new())
	var faces: Dictionary = plan.door_faces.get(room_node.id, {})
	var sockets := RS_RoomLayout.sockets_in_plan(kit_room, turns, plan.cells[room_node.id])
	var total_doors := 0
	for room_id: StringName in plan.door_faces:
		total_doors += (plan.door_faces[room_id] as Dictionary).size()
	_check("%s: у комнаты 2×2×1 есть двери (%d), и все в сокетах" % [tag, faces.size()],
		not faces.is_empty() and faces.keys().all(func(f: Vector4i) -> bool: return sockets.has(f))
		and plan.routing_failures.is_empty(),
		"%s %s" % [faces, plan.routing_failures])
	var perimeter := plan.topology.perimeter(plan.room_cells(room_node.id)).size()

	var root := Node3D.new()
	add_child(root)
	var room := (load(kit_room) as PackedScene).instantiate() as Node3D
	room.transform = plan.room_transform(room_node.id)
	var walls := RS_RoomLayout.shell_of(room).walls
	var doors := walls.assemble(room, room_node.id, plan)
	root.add_child(room)
	var kit := GameConfig.config.corridor_kit
	var caps := 0
	for cell: Vector3i in plan.corridor_tiles:
		var tile := kit.instantiate(plan.corridor_tiles[cell], plan.door_mask(cell))
		tile.position = plan.embedding.cell_origin(cell)
		root.add_child(tile)
		for child in tile.get_children():
			caps += 1 if child.scene_file_path == kit.door_end.resource_path else 0

	if RS_RoomLayout.shell_of(room).walls_in_shell:
		_check_walled_pieces(room, room_node, plan, doors, tag)
	else:
		var door_walls := 0
		var blank_walls := 0
		for child in room.get_children():
			door_walls += 1 if child.scene_file_path == walls.door_wall.resource_path else 0
			blank_walls += 1 if child.scene_file_path == walls.blank_wall.resource_path else 0
		_check("%s: стен по граням периметра — с проёмом на каждую дверь, глухих на остальные" % tag,
			door_walls == faces.size() and blank_walls == perimeter - faces.size(),
			"с проёмом %d, глухих %d" % [door_walls, blank_walls])
	_check("%s: торец с проёмом — на каждый тайл перед дверью" % tag, caps == total_doors,
		"торцов %d, дверей %d" % [caps, total_doors])
	var misplaced: Array[String] = []
	for door: Node3D in doors:
		var face: Vector4i = doors[door]
		var cell := GridTopology.face_cell(face)
		var mid := (plan.embedding.cell_origin(cell) + plan.embedding.cell_origin(plan.topology.neighbour(cell, face.w))) * 0.5
		if door.global_position.distance_to(mid) > EPSILON:
			misplaced.append("%s: %s вместо %s" % [face, door.global_position, mid])
	_check("%s: двери стоят на середине своих граней" % tag, doors.size() == faces.size() and misplaced.is_empty(),
		", ".join(misplaced))

	for i in 3:
		await get_tree().physics_frame
	_check_assembly_rays(plan, room_node.id, doors, tag)
	# Сразу, а не в конце кадра: следующая сборка встаёт на то же место, и её лучи
	# не должны задеть коллизию этой.
	root.free()


## Коробка со стенами в меше: сборка не ставит ни одной стены — ни с проёмом, ни
## глухой, иначе стена встала бы поверх нарисованной, — а каждый невыбранный
## сокет закрыт заглушкой, повёрнутой к своей грани. Грань заглушки выводится из
## того, куда она встала в мире, а не из плана: так ловится и заглушка, ушедшая
## на соседнюю грань, и заглушка, развёрнутая не в ту сторону. Что она держит —
## проверяют лучи (_check_assembly_rays).
func _check_walled_pieces(room: Node3D, room_node: RS_LevelNode, plan: RS_LayerPlan, doors: Dictionary, tag: String) -> void:
	var walls := RS_RoomLayout.shell_of(room).walls
	var sockets := RS_RoomLayout.sockets_in_plan(room_node.room_scene_path, room_node.turns, plan.cells[room_node.id])
	var door_faces: Dictionary = plan.door_faces[room_node.id]
	var want: Array[Vector4i] = []
	for face in sockets:
		if not door_faces.has(face):
			want.append(face)
	var got: Array[Vector4i] = []
	var stray: Array[String] = []
	for child: Node in room.get_children():
		if child.scene_file_path == walls.plug.resource_path:
			var plug := child as Node3D
			var cell := plan.embedding.cell_at(plug.global_position)
			var facing := -plug.global_basis.z * plan.embedding.cell_size * 0.75
			var side := plan.topology.side_toward(cell, plan.embedding.cell_at(plug.global_position + facing))
			got.append(GridTopology.face(cell, side))
		elif child.scene_file_path in [walls.door_wall.resource_path, walls.blank_wall.resource_path]:
			stray.append(child.name)
	_check("%s: стен поверх нарисованных нет" % tag, stray.is_empty(), ", ".join(stray))
	want.sort()
	got.sort()
	_check("%s: заглушки — ровно на %d невыбранных сокетах из %d" % [tag, want.size(), sockets.size()],
		got == want and doors.size() + want.size() == sockets.size(), "нужно %s, стоят %s" % [want, got])


## Лучи по коллизии деталей: глухая грань держит изнутри комнаты; через дверь луч
## проходит насквозь — сквозь проём стены и проём торца — до центра тайла; над
## проёмом упирается и стена комнаты, и торец коридора. Полотна дверей из луча
## исключены: закрытая дверь проём и должна закрывать.
func _check_assembly_rays(plan: RS_LayerPlan, room_id: StringName, doors: Dictionary, tag: String) -> void:
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
	_check("%s: стены и торцы по коллизии — проёмы там, где двери, глухо везде ещё" % tag,
		wrong.is_empty(), ", ".join(wrong.slice(0, 4)))


func _ray(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, exclude: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, GEOMETRY_MASK, exclude)
	return space.intersect_ray(query)


# --- 4. Валидация пресета на коробке со стенами в меше ------------------------


## Монолит ломается в данных тихо, и ловит это только валидация пресета: без
## объявленных сокетов раскладка поведёт коридор в глухую стену меша, без
## заглушки в ките невыбранный проём останется дырой. Заодно — правило «дверь на
## сторону» для любой коробки: у обычной 2×2 сокетов восемь, а сторон четыре, и
## пятая дверь встала бы второй на сторону — коридором вдоль стены от двери к двери.
func _check_walled_validation() -> void:
	var library := RS_RoomPresetLibrary.new()
	var scene := load(KIT_ROOMS[-1]) as PackedScene
	_check("эталон монолита с дверями 1..4 валиден — по двери на сторону", _walled_problems(library, scene, 4).is_empty(),
		", ".join(_walled_problems(library, scene, 4)))
	var box := load(KIT_P_ROOM) as PackedScene
	_check("коробка 2×2 с дверями 1..5 ловится: сторон с сокетами четыре",
		_walled_problems(library, box, 5).any(func(p: String) -> bool: return "сторон с сокетами" in p), "")

	var no_sockets := _walled_variant(scene, func(shell: C_RoomShell) -> void: shell.door_sockets = [])
	_check("монолит без объявленных сокетов ловится",
		_walled_problems(library, no_sockets, 2).any(func(p: String) -> bool: return "сокеты не объявлены" in p), "")
	var no_plug := _walled_variant(scene, func(shell: C_RoomShell) -> void:
		shell.walls = shell.walls.duplicate()
		shell.walls.plug = null)
	_check("монолит без заглушки в ките ловится",
		_walled_problems(library, no_plug, 2).any(func(p: String) -> bool: return "plug" in p), "")


func _walled_problems(library: RS_RoomPresetLibrary, scene: PackedScene, doors_max: int) -> Array[String]:
	var preset := RS_RoomPreset.new()
	preset.display_name = "монолит"
	preset.scene = scene
	preset.doors_min = 1
	preset.doors_max = doors_max
	return library.validate_preset(preset)


## Копия сцены монолита с поправленным C_RoomShell: компонент — подресурс сцены,
## поэтому правится его копия, иначе правка ушла бы в кэш загруженного эталона.
func _walled_variant(scene: PackedScene, edit: Callable) -> PackedScene:
	var room := scene.instantiate() as Entity
	var shell := RS_RoomLayout.shell_of(room).duplicate() as C_RoomShell
	edit.call(shell)
	var components: Array[Component] = [shell]
	room.component_resources = components
	var packed := PackedScene.new()
	packed.pack(room)
	room.free()
	return packed


# -----------------------------------------------------------------------------


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
	presets.append(config.floor_stairs)
	for preset: RS_RoomPreset in presets:
		if preset and preset.scene:
			scenes.append(preset.scene.resource_path)
	return scenes
