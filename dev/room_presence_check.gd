extends Node
## Проверка «текущий узел меняется присутствием, а не дверью» — первого шага к
## коридорам (карточка «Процедурные коридоры между комнатами», §3).
##
## Ломается это тихо в обе стороны: узел, не сменившийся при входе, не даёт
## ошибки — просто контрольная точка, карта и счётчик комнат остаются в прошлой
## комнате; узел, сменившийся по нажатию двери, выглядит правильно ровно до
## появления коридоров, где между нажатием и входом идёт путь ногами.
##
## Две части: правило клетки на самом плане (RS_LayerPlan.node_at) по 10 сидам,
## без мира, и сквозной прогон настоящего RunManager с S_RoomPresence — игрок
## шагает из хаба на тайл его ветки коридора, и узел меняет следующий такт
## системы, а не сам шаг. Что дверь в коридор открывается на месте и никого не
## переносит, сверяет dev/corridor_spawn_check.
##
## Запускать: godot --headless dev/room_presence_check.tscn

const SEEDS := 10
const RUN_SEED := 424242

var _ok := 0
var _fail := 0
var _room_changes: Array[StringName] = []

## Настоящий сейв разработчика: прогон ставит контрольные точки, то есть пишет
## на диск, и чужой забег он ронять не должен (тот же приём, что run_stats_check).
var _save_backup := PackedByteArray()
var _had_save := false
var _save_object: RS_WorldSave


func _ready() -> void:
	_save_backup = FileAccess.get_file_as_bytes(WorldSave.SAVE_PATH)
	_had_save = not _save_backup.is_empty()
	_save_object = WorldSave.save

	_check_plan_rule()
	await _check_run()
	_restore_save()

	print("=== ИТОГ: ок=%d, провалов=%d ===" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


# ---------------------------------------------------------------------------
# Правило клетки на плане
# ---------------------------------------------------------------------------


func _check_plan_rule() -> void:
	var library := GameConfig.config.room_preset_library
	var misses: Array[String] = []
	var checked := 0
	for s in SEEDS:
		var graph := RS_LevelGraph.new().generate_run(s, library)
		for depth: int in RS_LevelGraph.DEPTHS:
			var plan := RS_LayerPlan.build(graph.get_nodes_by_depth(depth))
			for node_id: StringName in plan.positions:
				checked += 1
				var at: Vector3 = plan.positions[node_id]
				# Центр, угол комнаты (двери стоят в ~8 м от центра), рост игрока
				# над полом и точка чуть ниже пола — всё это «в этой комнате».
				for probe: Vector3 in [
					Vector3.ZERO, Vector3(8.0, 0.0, -8.0), Vector3(0.0, 1.7, 0.0),
					Vector3(0.0, 9.0, 0.0), Vector3(0.0, -1.0, 0.0),
				]:
					var got := plan.node_at(at + probe)
					if got != node_id:
						misses.append("сид %d %s +%s → '%s'" % [s, node_id, probe, got])
				# Этажом выше та же (x, z) — это уже не эта комната.
				if plan.node_at(at + Vector3(0.0, RS_LayerPlan.FLOOR_SPACING, 0.0)) == node_id:
					misses.append("сид %d %s: этажом выше всё ещё он" % [s, node_id])
	_check("каждая точка комнаты находит свой узел (%d узлов)" % checked,
		misses.is_empty(), ", ".join(misses.slice(0, 5)))

	var graph := RS_LevelGraph.new().generate_run(0, library)
	var plan := RS_LayerPlan.build(graph.get_nodes_by_depth(RS_LevelGraph.HOME_DEPTH))
	_check("точка далеко вне раскладки — ничья",
		plan.node_at(Vector3(10000.0, 0.0, 10000.0)) == &"", "")
	_check("провал под мир — ничей",
		plan.node_at(Vector3(0.0, GameConfig.config.void_fall_depth, 0.0)) == &"", "")


# ---------------------------------------------------------------------------
# Сквозной прогон RunManager
# ---------------------------------------------------------------------------


func _check_run() -> void:
	var world := World.new()
	add_child(world)
	ECS.world = world
	var presence := S_RoomPresence.new()
	presence.group = "gameplay"
	world.add_system(presence)

	# Свежий сейв без начатого забега: иначе вход пошёл бы с узла разработчика.
	var fresh := RS_WorldSave.new()
	fresh.world_seed = RUN_SEED
	WorldSave.save = fresh

	RunManager.room_changed.connect(_on_room_changed)
	RunManager.enter_complex(RUN_SEED)
	await get_tree().process_frame

	var entry := RunManager.current_graph.entry_node_id
	_check("вход в забег — входной узел", RunManager.current_node_id == entry,
		"текущий '%s'" % RunManager.current_node_id)

	_room_changes.clear()
	_tick()
	_check("стоя на месте, узел не меняется и сигнала нет",
		RunManager.current_node_id == entry and _room_changes.is_empty(), str(_room_changes))

	var neighbour := _same_layer_neighbour(entry)
	_check("у входного узла есть ветка коридора на том же слое", neighbour != &"", "")
	if neighbour == &"":
		return

	# Шаг из хаба на тайл его ветки — то, что делает игрок за открытой дверью.
	var plan := RunManager.plan_for_depth(RunManager.current_depth)
	_player().global_position = plan.positions[neighbour] + Vector3(0.0, 0.5, 0.0)
	_check("сам шаг узел НЕ меняет — его меняет такт присутствия",
		RunManager.current_node_id == entry, "текущий '%s'" % RunManager.current_node_id)
	_check("и игрок стоит в клетке ветки",
		plan.node_at(_player().global_position) == neighbour,
		"клетка игрока '%s'" % plan.node_at(_player().global_position))

	_tick()
	_check("следующий такт делает ветку текущей", RunManager.current_node_id == neighbour,
		"текущий '%s'" % RunManager.current_node_id)
	_check("room_changed ровно один раз и про ветку", _room_changes == [neighbour],
		str(_room_changes))
	_check("ветка записана в сейв как текущая и посещённая",
		WorldSave.save.current_node_id == neighbour
			and WorldSave.save.visited_node_ids.has(neighbour), "")

	_tick()
	_check("повторный такт на месте сигнала не шлёт", _room_changes.size() == 1,
		str(_room_changes))

	_player().global_position = Vector3(0.0, GameConfig.config.void_fall_depth + 10.0, 0.0)
	_tick()
	_check("пустота под миром узел не меняет", RunManager.current_node_id == neighbour,
		"текущий '%s'" % RunManager.current_node_id)

	_player().global_position = plan.positions[entry] + Vector3(0.0, 1.0, 0.0)
	_tick()
	_check("вернулся пешком — текущим снова стал вход", RunManager.current_node_id == entry,
		"текущий '%s'" % RunManager.current_node_id)

	var other_depth := _node_on_other_depth()
	RunManager.travel_to(other_depth)
	_check("переход на другой слой по-прежнему меняет узел сразу",
		RunManager.current_node_id == other_depth
			and RunManager.current_depth == RunManager.current_graph.get_node_data(other_depth).depth,
		"текущий '%s'" % RunManager.current_node_id)
	_tick()
	_check("и присутствие с ним согласно", RunManager.current_node_id == other_depth,
		"текущий '%s'" % RunManager.current_node_id)

	RunManager.room_changed.disconnect(_on_room_changed)
	RunManager._end_run()


func _same_layer_neighbour(node_id: StringName) -> StringName:
	var node := RunManager.current_graph.get_node_data(node_id)
	for conn: RS_LevelConnection in node.connections:
		var target := RunManager.current_graph.get_node_data(conn.target_node_id)
		if target and target.role == RS_LevelNode.Role.CORRIDOR:
			return target.id
	return &""


func _node_on_other_depth() -> StringName:
	var depth := RunManager.current_depth
	var other := RS_LevelGraph.DEPTHS[0] if depth != RS_LevelGraph.DEPTHS[0] else RS_LevelGraph.DEPTHS[1]
	return RunManager.current_graph.get_nodes_by_depth(other)[0].id


func _player() -> Node3D:
	return ECS.world.query.with_all([C_PlayerInput]).execute_one() as Node as Node3D


func _tick() -> void:
	ECS.process(0.016, "gameplay")


func _on_room_changed(node_id: StringName) -> void:
	_room_changes.append(node_id)


## Возвращает сейв разработчика ровно таким, каким он был до прогона — и на
## диске, и в памяти автолоада.
func _restore_save() -> void:
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
