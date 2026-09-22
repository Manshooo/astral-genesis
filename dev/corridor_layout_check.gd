extends Node
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
## Сколько ассертов обязано отработать до сторожевого: SCRIPT ERROR внутри блока
## обрывает только блок, и без сверки числа сломанная раскладка выглядит зелёной.
const EXPECTED_ASSERTS := 12

var _ok := 0
var _fail := 0


func _ready() -> void:
	var library: RS_RoomPresetLibrary = GameConfig.config.room_preset_library
	var config := (load(CONFIG_PATH) as RS_WorldGenConfig).duplicate() as RS_WorldGenConfig
	config.corridors = true

	var problems := {
		"все трассы проложены": [],
		"комнаты не делят клетку, тайлы не встают на комнаты": [],
		"стороны дверей — ровно двери сцены, ветки — ровно рёбра графа": [],
		"перед каждой дверью — тайл её ветки с проёмом в комнату": [],
		"проёмы взаимны, в пустоту не ведёт ни один": [],
		"стык веток есть ровно там, где в графе ребро между ними": [],
		"тайлы ветки связны": [],
		"тайлов с одним проёмом (торца в ките нет) не бывает": [],
		"node_at узнаёт комнаты и коридоры": [],
	}
	var pieces := {"прямой": 0, "поворот": 0, "Т": 0, "крест": 0, "торец": 0}
	var floors := 0
	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, library, config)
		for depth: int in RS_LevelGraph.DEPTHS:
			var layer := graph.get_nodes_by_depth(depth)
			var plan := RS_LayerPlan.build(layer, config)
			floors += _floor_count(layer)
			_collect(graph, layer, plan, s, depth, problems, pieces)

	for what: String in problems:
		var list: Array = problems[what]
		_check("%s (%d сидов)" % [what, SEEDS], list.is_empty(), ", ".join(list.slice(0, 4)))

	var tiles := 0
	for kind: String in pieces:
		tiles += pieces[kind]
	print("  тайлов: %d на %d этажей (%.1f на этаж) — %s" % [tiles, floors, float(tiles) / floors, pieces])

	_check_determinism(library, config)
	_check_legacy(library)

	var ran := _ok + _fail
	_check("все блоки дошли до конца", ran == EXPECTED_ASSERTS,
		"ассертов %d из %d — какой-то блок упал на ошибке скрипта" % [ran, EXPECTED_ASSERTS])
	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _collect(
	graph: RS_LevelGraph,
	layer: Array[RS_LevelNode],
	plan: RS_LayerPlan,
	s: int,
	depth: int,
	problems: Dictionary,
	pieces: Dictionary,
) -> void:
	var tag := "сид %d L%d" % [s, depth]
	for failure in plan.routing_failures:
		problems["все трассы проложены"].append("%s: %s" % [tag, failure])

	var room_at: Dictionary[Vector3i, StringName] = {}
	for node in layer:
		if node.role != RS_LevelNode.Role.ROOM:
			continue
		var cell := Vector3i(plan.cells[node.id].x, node.floor_index, plan.cells[node.id].y)
		if room_at.has(cell) or plan.corridor_tiles.has(cell):
			problems["комнаты не делят клетку, тайлы не встают на комнаты"].append("%s %s" % [tag, node.id])
		room_at[cell] = node.id

	for node in layer:
		if node.role != RS_LevelNode.Role.ROOM:
			continue
		_check_room_doors(graph, node, plan, tag, problems)
		if plan.node_at(plan.positions[node.id] + Vector3(5.0, 1.7, -5.0)) != node.id:
			problems["node_at узнаёт комнаты и коридоры"].append("%s %s" % [tag, node.id])

	var adjacent_branches := {}  # "a|b" (a<b) -> есть ли открытый стык
	for cell: Vector3i in plan.corridor_tiles:
		var mask: int = plan.corridor_tiles[cell]
		var owner: StringName = plan.node_by_cell[cell]
		pieces[_piece(mask)] += 1
		if _bits(mask) == 1:
			problems["тайлов с одним проёмом (торца в ките нет) не бывает"].append("%s %s" % [tag, cell])
		if plan.node_at(plan.cell_position(Vector2i(cell.x, cell.z), cell.y) + Vector3(4.0, 1.7, 4.0)) != owner:
			problems["node_at узнаёт комнаты и коридоры"].append("%s тайл %s" % [tag, cell])
		for side: StringName in RS_LayerPlan.SIDE_BITS:
			if mask & RS_LayerPlan.SIDE_BITS[side] == 0:
				continue
			var offset: Vector2i = RS_RoomLayout.OFFSETS[side]
			var next := cell + Vector3i(offset.x, 0, offset.y)
			var back: int = RS_LayerPlan.SIDE_BITS[RS_RoomLayout.OPPOSITE[side]]
			if plan.corridor_tiles.has(next):
				if plan.corridor_tiles[next] & back == 0:
					problems["проёмы взаимны, в пустоту не ведёт ни один"].append("%s %s→%s" % [tag, cell, side])
				var other: StringName = plan.node_by_cell[next]
				if other != owner:
					var key := "%s|%s" % ([owner, other] if String(owner) < String(other) else [other, owner])
					adjacent_branches[key] = true
			elif room_at.has(next):
				var room: StringName = room_at[next]
				var facing: StringName = RS_RoomLayout.OPPOSITE[side]
				if plan.door_sides.get(room, {}).get(facing, &"") != owner:
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
	var sides: Dictionary = plan.door_sides.get(room.id, {})
	var scene_sides := RS_RoomLayout.door_directions_of_scene(room.room_scene_path)
	var planned: Array = sides.values()
	var expected: Array = []
	for conn: RS_LevelConnection in room.connections:
		var target := graph.get_node_data(conn.target_node_id)
		if target.role == RS_LevelNode.Role.CORRIDOR:
			expected.append(conn.target_node_id)
	var scene_list: Array = []
	for side in scene_sides:
		scene_list.append(String(side))
	var keys: Array = []
	for side in sides.keys():
		keys.append(String(side))
	for list: Array in [planned, expected, scene_list, keys]:
		list.sort()
	if str(planned) != str(expected) or keys != scene_list:
		problems["стороны дверей — ровно двери сцены, ветки — ровно рёбра графа"].append(
			"%s %s: %s vs %s" % [tag, room.id, sides, expected]
		)
	for side: StringName in sides:
		var offset: Vector2i = RS_RoomLayout.OFFSETS[side]
		var front: Vector2i = plan.cells[room.id] + offset
		var cell := Vector3i(front.x, room.floor_index, front.y)
		var bit: int = RS_LayerPlan.SIDE_BITS[RS_RoomLayout.OPPOSITE[side]]
		if plan.node_by_cell.get(cell, &"") != sides[side] or plan.corridor_tiles.get(cell, 0) & bit == 0:
			problems["перед каждой дверью — тайл её ветки с проёмом в комнату"].append(
				"%s %s:%s" % [tag, room.id, side]
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
		for side: StringName in RS_LayerPlan.SIDE_BITS:
			if plan.corridor_tiles[cell] & RS_LayerPlan.SIDE_BITS[side] == 0:
				continue
			var offset: Vector2i = RS_RoomLayout.OFFSETS[side]
			var next := cell + Vector3i(offset.x, 0, offset.y)
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
			if str(a.corridor_tiles) != str(b.corridor_tiles) or str(a.door_sides) != str(b.door_sides) \
					or str(a.positions) != str(b.positions):
				diverged.append(s)
	_check("один граф — одна раскладка", diverged.is_empty(), str(diverged))

	var graph := RS_LevelGraph.new().generate_run(0, library, config)
	var plan := RS_LayerPlan.build(graph.get_nodes_by_depth(RS_LevelGraph.DEPTHS[0]), config)
	_check("коридорный план на клетке кита", plan.cell_size == RS_LayerPlan.CELL_SIZE, str(plan.cell_size))


func _check_legacy(library: RS_RoomPresetLibrary) -> void:
	var graph := RS_LevelGraph.new().generate_run(0, library)
	var plan := RS_LayerPlan.build(graph.get_nodes_by_depth(RS_LevelGraph.HOME_DEPTH))
	_check("прежний граф раскладывается по-прежнему: шаг 60 м, без тайлов",
		plan.cell_size == RS_LayerPlan.ROOM_SPACING and plan.corridor_tiles.is_empty(), "")


func _floor_count(layer: Array[RS_LevelNode]) -> int:
	var floors := 0
	for node in layer:
		floors = maxi(floors, node.floor_index + 1)
	return floors


func _bits(mask: int) -> int:
	var n := 0
	for bit in [1, 2, 4, 8]:
		if mask & bit:
			n += 1
	return n


func _piece(mask: int) -> String:
	match _bits(mask):
		1:
			return "торец"
		2:
			return "прямой" if mask == 5 or mask == 10 else "поворот"
		3:
			return "Т"
		_:
			return "крест"


func _check(what: String, passed: bool, detail: String) -> void:
	if passed:
		_ok += 1
		print("  ok   %s" % what)
	else:
		_fail += 1
		print("  FAIL %s  (%s)" % [what, detail])
