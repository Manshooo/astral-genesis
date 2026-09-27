extends "res://dev/check_harness.gd"
## Проверка коридорной раскладки (этап 3 карточки «Процедурные коридоры между
## комнатами», с п. 7 карточки «Сетка уровня» — сетью): комнаты на решётке, сеть
## коридоров по клеткам кита, ветки, петли и тупики.
##
## Это второй путь валидации, про который карточка предупреждала: gen_verifier
## сверяет двери ПО СЦЕНЕ, а у собранного из тайлов коридора сцены нет — без
## проверки по плану коридоры просто перестали бы попадать в проверки, не сказав
## ни слова. И ломается раскладка тихо: проём в пустоту, стык двух веток, которых
## в графе нет, дверь, за которой не тот коридор, — всё это не ошибки, а
## проходы, которых нет в графе, или графовые рёбра, которых нет в мире.
##
## Запускать: godot --headless dev/corridor_layout_check.tscn

const SEEDS := 30
const CONFIG_PATH := "res://data/world_gen_config.tres"
## Потолок доли комнат, которые коридор обволакивает своими же ветками
## (RS_LayoutMetrics). Раскладка сетью (п. 7 карточки «Сетка уровня», 27.09) даёт
## на этих сидах 0 %: петлю и тупик, которые обволокли бы комнату, она не ставит,
## а двери смотрят не больше чем с двух сторон. До неё было 42 %, до сборных комнат
## — 55 %. Порог — по замеру, а не с запасом: он ловит правку ручек или раскладки,
## от которой стало хуже, и с запасом ничего бы не сторожил.
const MAX_ENVELOPED_SHARE := 0.01
## Второй прогон — на крупных этажах: предохранители раскладки от обволакивания
## работают там. На 4 комнатах двери и так смотрят внутрь решётки, и раскладка без
## предохранителей давала бы те же 0 %, а на 8 — 15 % (мутация 27.09).
const STRESS_ROOMS := 8
const STRESS_SEEDS := 10


func _ready() -> void:
	var library: RS_RoomPresetLibrary = GameConfig.config.room_preset_library
	var config := (load(CONFIG_PATH) as RS_WorldGenConfig).duplicate() as RS_WorldGenConfig
	_sweep(library, config, SEEDS, "")
	var stress := config.duplicate() as RS_WorldGenConfig
	stress.rooms_per_floor = STRESS_ROOMS
	_sweep(library, stress, STRESS_SEEDS, ", %d комнат на этаж" % STRESS_ROOMS)
	_check_determinism(library, config)
	_finish()


func _sweep(library: RS_RoomPresetLibrary, config: RS_WorldGenConfig, seeds: int, label: String) -> void:
	var problems := {
		"все трассы проложены": [],
		"комнаты не делят клетку, тайлы не встают на комнаты": [],
		"двери — ровно двери сцены или сокеты, ветки — ровно рёбра графа": [],
		"перед каждой дверью — тайл её ветки с проёмом в комнату": [],
		"проёмы взаимны, в пустоту не ведёт ни один": [],
		"стык веток есть ровно там, где в графе ребро между ними": [],
		"тайлы ветки связны": [],
		"тайл с одним проёмом — ровно отмеченный тупик": [],
		"тупиков на этаже не больше ручки": [],
		"node_at узнаёт комнаты и коридоры": [],
	}
	var layout := RS_LayoutMetrics.new()
	var multi_branch := 0
	for s in seeds:
		var graph := RS_LevelGraph.new().generate_run(s, library, config)
		for depth: int in RS_LevelGraph.DEPTHS:
			var layer := graph.get_nodes_by_depth(depth)
			var plan := graph.layer_plan(depth)
			layout.add(RS_LayoutMetrics.of_plan(plan))
			_collect(graph, layer, plan, s, depth, config, problems)
			for room: StringName in plan.door_faces:
				var branches := {}
				for branch: StringName in (plan.door_faces[room] as Dictionary).values():
					branches[branch] = true
				multi_branch += 1 if branches.size() >= 2 else 0

	var where := "%d сидов%s" % [seeds, label]
	for what: String in problems:
		var list: Array = problems[what]
		_check("%s (%s)" % [what, where], list.is_empty(), ", ".join(list.slice(0, 4)))

	print("  раскладка (%s), %d этажей:" % [where, layout.floors])
	for line in layout.report_lines():
		print("    " + line)
	_check("обволакиваемых комнат не больше %d%% (%s)" % [roundi(MAX_ENVELOPED_SHARE * 100.0), where],
		layout.enveloped_share() <= MAX_ENVELOPED_SHARE, "%.1f%%" % (layout.enveloped_share() * 100.0))
	# Ради этого правило «одна ветка на комнату» и снято: без комнат на двух
	# ветках и петель по коридору раскладка — снова дерево без обходных путей.
	_check("комнаты на двух ветках есть (%d, %s)" % [multi_branch, where], multi_branch > 0, "")
	_check("петли по коридору есть (%d, %s)" % [layout.corridor_loops, where], layout.corridor_loops > 0, "")
	_check("тупики есть (%d, %s)" % [layout.dead_ends, where], layout.dead_ends > 0, "")


func _collect(
	graph: RS_LevelGraph,
	layer: Array[RS_LevelNode],
	plan: RS_LayerPlan,
	s: int,
	depth: int,
	config: RS_WorldGenConfig,
	problems: Dictionary,
) -> void:
	var tag := "сид %d L%d" % [s, depth]
	for failure in plan.routing_failures:
		problems["все трассы проложены"].append("%s: %s" % [tag, failure])

	var dead_per_level := {}
	for cell: Vector3i in plan.dead_ends:
		dead_per_level[cell.y] = dead_per_level.get(cell.y, 0) + 1
	for level: int in dead_per_level:
		if dead_per_level[level] > config.dead_ends:
			problems["тупиков на этаже не больше ручки"].append("%s этаж %d: %d" % [tag, level, dead_per_level[level]])

	var room_at: Dictionary[Vector3i, StringName] = {}
	for node in layer:
		if node.role != RS_LevelNode.Role.ROOM:
			continue
		for cell in plan.room_cells(node.id):
			if room_at.has(cell) or plan.corridor_tiles.has(cell):
				problems["комнаты не делят клетку, тайлы не встают на комнаты"].append("%s %s" % [tag, node.id])
			room_at[cell] = node.id

	for node in layer:
		if node.role != RS_LevelNode.Role.ROOM:
			continue
		_check_room_doors(graph, node, plan, tag, problems)
		# Ближе к углу комнаты, чем к центру, — в долях footprint, а не в метрах: так
		# проба остаётся внутри комнаты при любой клетке.
		var size: Vector3i = plan.footprints.get(node.id, Vector3i.ONE)
		var corner := Vector3(size.x, 0.0, -size.z) * plan.embedding.cell_size * 0.3 + Vector3(0.0, 1.7, 0.0)
		if plan.node_at(plan.position_of(node.id) + corner) != node.id:
			problems["node_at узнаёт комнаты и коридоры"].append("%s %s" % [tag, node.id])

	var adjacent_branches := {}  # "a|b" (a<b) -> есть ли открытый стык
	for cell: Vector3i in plan.corridor_tiles:
		var mask: int = plan.corridor_tiles[cell]
		var owner: StringName = plan.node_by_cell[cell]
		# Тупик в ките есть, но случайный тупик — это обрыв сети, а не место под
		# награду: одним проёмом кончается только то, что раскладка отметила.
		if (RS_LayoutMetrics.piece_of(mask) == RS_LayoutMetrics.Piece.END) != plan.dead_ends.has(cell):
			problems["тайл с одним проёмом — ровно отмеченный тупик"].append("%s %s" % [tag, cell])
		var off_center := Vector3(0.3, 0.0, 0.3) * plan.embedding.cell_size + Vector3(0.0, 1.7, 0.0)
		if plan.node_at(plan.embedding.cell_origin(cell) + off_center) != owner:
			problems["node_at узнаёт комнаты и коридоры"].append("%s тайл %s" % [tag, cell])
		for side in plan.topology.side_count(cell):
			if mask & (1 << side) == 0:
				continue
			var next := plan.topology.neighbour(cell, side)
			var facing := plan.topology.back_side(cell, side)
			if plan.corridor_tiles.has(next):
				if plan.corridor_tiles[next] & (1 << facing) == 0:
					problems["проёмы взаимны, в пустоту не ведёт ни один"].append(
						"%s %s→%s" % [tag, cell, RS_RoomLayout.side_name(side)]
					)
				var other: StringName = plan.node_by_cell[next]
				if other != owner:
					var key := "%s|%s" % ([owner, other] if String(owner) < String(other) else [other, owner])
					adjacent_branches[key] = true
			elif room_at.has(next):
				var room: StringName = room_at[next]
				if plan.door_faces.get(room, {}).get(GridTopology.face(next, facing), &"") != owner:
					problems["проёмы взаимны, в пустоту не ведёт ни один"].append("%s %s→%s" % [tag, cell, room])
			else:
				problems["проёмы взаимны, в пустоту не ведёт ни один"].append("%s %s→пустота" % [tag, cell])

	# Рёбра между ветками лежат на обоих концах — ключи собираются множеством, а
	# не вычёркиваются по одному: иначе второй конец того же ребра считался бы
	# «стыка нет».
	var expected_joints := {}
	for node in layer:
		if node.role != RS_LevelNode.Role.CORRIDOR:
			continue
		if not _connected(plan, node.id, node.floor_index):
			problems["тайлы ветки связны"].append("%s %s" % [tag, node.id])
		for conn: RS_LevelConnection in node.connections:
			var target := graph.get_node_data(conn.target_node_id)
			if target.role == RS_LevelNode.Role.CORRIDOR:
				var ids := [node.id, target.id] if String(node.id) < String(target.id) else [target.id, node.id]
				expected_joints["%s|%s" % ids] = true
	for key in expected_joints:
		if not adjacent_branches.has(key):
			problems["стык веток есть ровно там, где в графе ребро между ними"].append("%s нет %s" % [tag, key])
	for key in adjacent_branches:
		if not expected_joints.has(key):
			problems["стык веток есть ровно там, где в графе ребро между ними"].append("%s лишний %s" % [tag, key])


func _check_room_doors(
	graph: RS_LevelGraph, room: RS_LevelNode, plan: RS_LayerPlan, tag: String, problems: Dictionary
) -> void:
	var faces: Dictionary = plan.door_faces.get(room.id, {})
	var planned: Array = faces.values()
	var expected: Array = []
	for conn: RS_LevelConnection in room.connections:
		var target := graph.get_node_data(conn.target_node_id)
		if target.role == RS_LevelNode.Role.CORRIDOR:
			expected.append(conn.target_node_id)
	# Где двери: у комнаты с дверями в сцене — ровно стороны этих дверей, у
	# сборной — столько сокетов периметра, сколько разыграно, и только сокеты.
	var placed_right := true
	if room.socket_doors == 0:
		var scene_list: Array = []
		var room_cell: Vector3i = plan.cells[room.id]
		for side: int in RS_RoomLayout.door_sides_of_scene(room.room_scene_path):
			scene_list.append(plan.topology.rotate_side(room_cell, side, -room.turns))
		var keys: Array = []
		for face: Vector4i in faces:
			keys.append(face.w)
		scene_list.sort()
		keys.sort()
		placed_right = keys == scene_list
	else:
		var sockets := plan.topology.perimeter(plan.room_cells(room.id))
		placed_right = faces.size() == room.socket_doors
		for face: Vector4i in faces:
			placed_right = placed_right and sockets.has(face)
	planned.sort()
	expected.sort()
	if str(planned) != str(expected) or not placed_right:
		problems["двери — ровно двери сцены или сокеты, ветки — ровно рёбра графа"].append(
			"%s %s: %s vs %s" % [tag, room.id, faces, expected]
		)
	for face: Vector4i in faces:
		var inside := GridTopology.face_cell(face)
		var cell := plan.topology.neighbour(inside, face.w)
		var bit := 1 << plan.topology.back_side(inside, face.w)
		if plan.node_by_cell.get(cell, &"") != faces[face] or plan.corridor_tiles.get(cell, 0) & bit == 0:
			problems["перед каждой дверью — тайл её ветки с проёмом в комнату"].append(
				"%s %s:%s" % [tag, room.id, face]
			)


## Связность тайлов ветки по открытым проёмам — обход от первого тайла.
func _connected(plan: RS_LayerPlan, branch: StringName, floor_index: int) -> bool:
	var own: Array[Vector3i] = []
	for cell: Vector3i in plan.corridor_tiles:
		if cell.y == floor_index and plan.node_by_cell[cell] == branch:
			own.append(cell)
	if own.is_empty():
		return false
	var seen := {own[0]: true}
	var queue: Array[Vector3i] = [own[0]]
	while not queue.is_empty():
		var cell: Vector3i = queue.pop_back()
		for side in plan.topology.side_count(cell):
			if plan.corridor_tiles[cell] & (1 << side) == 0:
				continue
			var next := plan.topology.neighbour(cell, side)
			if plan.node_by_cell.get(next, &"") == branch and not seen.has(next):
				seen[next] = true
				queue.append(next)
	return seen.size() == own.size()


## Раскладка разыгрывается внутри генерации графа, из своего потока этажа, —
## поэтому сверяются два графа одного сида целиком, а не два плана одного графа.
func _check_determinism(library: RS_RoomPresetLibrary, config: RS_WorldGenConfig) -> void:
	var diverged: Array[int] = []
	for s in 5:
		var first := RS_LevelGraph.new().generate_run(s, library, config)
		var second := RS_LevelGraph.new().generate_run(s, library, config)
		for depth: int in RS_LevelGraph.DEPTHS:
			var a := first.layer_plan(depth)
			var b := second.layer_plan(depth)
			if str(a.corridor_tiles) != str(b.corridor_tiles) or str(a.door_faces) != str(b.door_faces) \
					or str(a.cells) != str(b.cells) or str(a.dead_ends) != str(b.dead_ends):
				diverged.append(s)
	_check("один сид — один граф и одна раскладка", diverged.is_empty(), str(diverged))
