extends "res://dev/check_harness.gd"
## Проверка коридорной раскладки (этап 3 карточки «Процедурные коридоры между
## комнатами»): комнаты на решётке, трассы веток по клеткам кита.
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
## Потолок доли комнат, которые коридор обволакивает своей же веткой
## (RS_LayoutMetrics), — по нынешнему генератору: 42.0 % на этих сидах на клетке
## 8 м (замер 27.09; до сборных комнат, с дверями, запечёнными в арт, было 55 %).
## Ловит правку ручек или раскладки, от которой стало хуже. Новая раскладка (п. 7
## карточки «Сетка уровня») обязана эту долю опустить — и порог опускается
## следом, иначе он перестаёт что-либо сторожить.
const MAX_ENVELOPED_SHARE := 0.43


func _ready() -> void:
	var library: RS_RoomPresetLibrary = GameConfig.config.room_preset_library
	var config := (load(CONFIG_PATH) as RS_WorldGenConfig).duplicate() as RS_WorldGenConfig

	var problems := {
		"все трассы проложены": [],
		"комнаты не делят клетку, тайлы не встают на комнаты": [],
		"двери — ровно двери сцены или сокеты, ветки — ровно рёбра графа": [],
		"перед каждой дверью — тайл её ветки с проёмом в комнату": [],
		"проёмы взаимны, в пустоту не ведёт ни один": [],
		"стык веток есть ровно там, где в графе ребро между ними": [],
		"тайлы ветки связны": [],
		"тайлов с одним проёмом (торца в ките нет) не бывает": [],
		"node_at узнаёт комнаты и коридоры": [],
	}
	var layout := RS_LayoutMetrics.new()
	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, library, config)
		for depth: int in RS_LevelGraph.DEPTHS:
			var layer := graph.get_nodes_by_depth(depth)
			var plan := RS_LayerPlan.build(layer, config)
			layout.add(RS_LayoutMetrics.of_plan(plan))
			_collect(graph, layer, plan, s, depth, problems)

	for what: String in problems:
		var list: Array = problems[what]
		_check("%s (%d сидов)" % [what, SEEDS], list.is_empty(), ", ".join(list.slice(0, 4)))

	print("  раскладка на %d сидах, %d этажей:" % [SEEDS, layout.floors])
	for line in layout.report_lines():
		print("    " + line)
	_check("обволакиваемых комнат не больше %d%%" % roundi(MAX_ENVELOPED_SHARE * 100.0),
		layout.enveloped_share() <= MAX_ENVELOPED_SHARE, "%.1f%%" % (layout.enveloped_share() * 100.0))

	_check_determinism(library, config)

	_finish()


func _collect(
	graph: RS_LevelGraph,
	layer: Array[RS_LevelNode],
	plan: RS_LayerPlan,
	s: int,
	depth: int,
	problems: Dictionary,
) -> void:
	var tag := "сид %d L%d" % [s, depth]
	for failure in plan.routing_failures:
		problems["все трассы проложены"].append("%s: %s" % [tag, failure])

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
		if RS_LayoutMetrics.piece_of(mask) == RS_LayoutMetrics.Piece.END:
			problems["тайлов с одним проёмом (торца в ките нет) не бывает"].append("%s %s" % [tag, cell])
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


func _check_determinism(library: RS_RoomPresetLibrary, config: RS_WorldGenConfig) -> void:
	var diverged: Array[int] = []
	for s in 5:
		var graph := RS_LevelGraph.new().generate_run(s, library, config)
		for depth: int in RS_LevelGraph.DEPTHS:
			var a := RS_LayerPlan.build(graph.get_nodes_by_depth(depth), config)
			var b := RS_LayerPlan.build(graph.get_nodes_by_depth(depth), config)
			if str(a.corridor_tiles) != str(b.corridor_tiles) or str(a.door_faces) != str(b.door_faces) \
					or str(a.cells) != str(b.cells):
				diverged.append(s)
	_check("один граф — одна раскладка", diverged.is_empty(), str(diverged))
